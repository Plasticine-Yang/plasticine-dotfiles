package main

import (
	"bytes"
	"errors"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/creack/pty"
)

func TestBareCommandTerminalContracts(t *testing.T) {
	binary := buildPlasticineTestBinary(t)

	t.Run("dashboard q restores terminal and exits zero", func(t *testing.T) {
		output, home := runBareCommandInPTY(t, binary, []byte("q"))
		for _, want := range []string{
			"PLASTICINE",
			"No plan loaded",
			"PLASTICINE_EXIT=0",
			"TERMINAL_RESTORED=yes",
		} {
			if !strings.Contains(output, want) {
				t.Fatalf("PTY output missing %q:\n%s", want, output)
			}
		}
		if _, err := os.Stat(home); !os.IsNotExist(err) {
			t.Fatalf("Dashboard startup created Plasticine Home %s: %v", home, err)
		}
	})

	t.Run("idle ctrl-c restores terminal and exits 130", func(t *testing.T) {
		output, home := runBareCommandInPTY(t, binary, []byte{3})
		for _, want := range []string{
			"No plan loaded",
			"PLASTICINE_EXIT=130",
			"TERMINAL_RESTORED=yes",
		} {
			if !strings.Contains(output, want) {
				t.Fatalf("PTY output missing %q:\n%s", want, output)
			}
		}
		if _, err := os.Stat(home); !os.IsNotExist(err) {
			t.Fatalf("Dashboard startup created Plasticine Home %s: %v", home, err)
		}
	})

	t.Run("non tty returns usage two", func(t *testing.T) {
		home := filepath.Join(t.TempDir(), "plasticine-home")
		command := exec.Command(binary)
		command.Env = append(os.Environ(),
			"PLASTICINE_HOME="+home,
			"PLASTICINE_WORKSTATION_ROOT="+t.TempDir(),
			"TERM=xterm-256color",
		)
		var stdout bytes.Buffer
		var stderr bytes.Buffer
		command.Stdout = &stdout
		command.Stderr = &stderr
		err := command.Run()
		var exitError *exec.ExitError
		if !errors.As(err, &exitError) || exitError.ExitCode() != 2 {
			t.Fatalf("non-TTY error = %v, want exit 2; stderr=%s", err, stderr.String())
		}
		for _, want := range []string{
			"interactive TUI requires a terminal",
			"usage: plasticine <plan|apply|doctor|upgrade|version>",
		} {
			if !strings.Contains(stderr.String(), want) {
				t.Fatalf("non-TTY stderr missing %q:\n%s", want, stderr.String())
			}
		}
		if stdout.Len() != 0 {
			t.Fatalf("non-TTY stdout = %q, want empty", stdout.String())
		}
	})

	t.Run("term dumb returns usage two", func(t *testing.T) {
		command := exec.Command(binary)
		command.Env = append(os.Environ(), "TERM=dumb")
		var stderr bytes.Buffer
		command.Stderr = &stderr
		err := command.Run()
		var exitError *exec.ExitError
		if !errors.As(err, &exitError) || exitError.ExitCode() != 2 {
			t.Fatalf("TERM=dumb error = %v, want exit 2", err)
		}
	})
}

func buildPlasticineTestBinary(t *testing.T) string {
	t.Helper()
	binary := filepath.Join(t.TempDir(), "plasticine")
	command := exec.Command("go", "build", "-o", binary, ".")
	command.Env = append(os.Environ(), "GOTOOLCHAIN=go1.26.5")
	output, err := command.CombinedOutput()
	if err != nil {
		t.Fatalf("build plasticine test binary: %v\n%s", err, output)
	}
	return binary
}

func runBareCommandInPTY(t *testing.T, binary string, input []byte) (string, string) {
	t.Helper()
	home := filepath.Join(t.TempDir(), "plasticine-home")
	workstationRoot := t.TempDir()
	script := `
"$1"
code=$?
if stty -a | grep -Eq '(^|[[:space:]])-(icanon|echo)([[:space:]]|$)'; then
  restored=no
else
  restored=yes
fi
printf '\nPLASTICINE_EXIT=%s TERMINAL_RESTORED=%s\n' "$code" "$restored"
`
	command := exec.Command("sh", "-c", script, "plasticine-pty", binary)
	command.Env = append(os.Environ(),
		"PLASTICINE_HOME="+home,
		"PLASTICINE_WORKSTATION_ROOT="+workstationRoot,
		"TERM=xterm-256color",
		"NO_COLOR=1",
	)
	terminal, err := pty.StartWithSize(command, &pty.Winsize{Rows: 32, Cols: 120})
	if err != nil {
		t.Fatalf("start PTY: %v", err)
	}
	defer terminal.Close()

	prefix := readPTYUntil(t, terminal, "No plan loaded", 8*time.Second)
	type suffixResult struct {
		data []byte
		err  error
	}
	suffixDone := make(chan suffixResult, 1)
	go func() {
		data, err := io.ReadAll(terminal)
		suffixDone <- suffixResult{data: data, err: err}
	}()
	if _, err := terminal.Write(input); err != nil {
		t.Fatalf("write PTY input: %v", err)
	}
	done := make(chan error, 1)
	go func() {
		done <- command.Wait()
	}()
	var waitErr error
	select {
	case waitErr = <-done:
	case <-time.After(8 * time.Second):
		_ = command.Process.Kill()
		t.Fatal("timed out waiting for PTY command")
	}
	suffix := <-suffixDone
	readErr := suffix.err
	if readErr != nil && !errors.Is(readErr, os.ErrClosed) && !strings.Contains(readErr.Error(), "input/output error") {
		t.Fatalf("read PTY suffix: %v", readErr)
	}
	if waitErr != nil {
		t.Fatalf("PTY wrapper failed: %v\n%s%s", waitErr, prefix, suffix.data)
	}
	return prefix + string(suffix.data), home
}

func readPTYUntil(t *testing.T, terminal *os.File, marker string, timeout time.Duration) string {
	t.Helper()
	type readResult struct {
		output string
		err    error
	}
	done := make(chan readResult, 1)
	go func() {
		var output bytes.Buffer
		buffer := make([]byte, 4096)
		backgroundAnswered := false
		cursorAnswered := false
		for {
			count, err := terminal.Read(buffer)
			if count > 0 {
				output.Write(buffer[:count])
				text := output.String()
				if !backgroundAnswered && strings.Contains(text, "\x1b]11;?\x1b\\") {
					backgroundAnswered = true
					_, _ = terminal.Write([]byte("\x1b]11;rgb:0000/0000/0000\x1b\\"))
				}
				if !cursorAnswered && strings.Contains(text, "\x1b[6n") {
					cursorAnswered = true
					_, _ = terminal.Write([]byte("\x1b[1;1R"))
				}
				if strings.Contains(text, marker) {
					done <- readResult{output: output.String()}
					return
				}
			}
			if err != nil {
				done <- readResult{output: output.String(), err: err}
				return
			}
		}
	}()

	select {
	case result := <-done:
		if result.err != nil {
			t.Fatalf("read PTY before %q: %v\n%s", marker, result.err, result.output)
		}
		return result.output
	case <-time.After(timeout):
		_ = terminal.Close()
		t.Fatalf("timed out reading PTY before %q", marker)
		return ""
	}
}
