package tui

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
	"time"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/creack/pty"

	"github.com/Plasticine-Yang/plasticine-dotfiles/internal/reconciler"
	"github.com/Plasticine-Yang/plasticine-dotfiles/internal/workstation"
)

func TestTerminalCommandReleasesAndRestoresTUI(t *testing.T) {
	if os.Getenv("PLASTICINE_TUI_TERMINAL_HELPER") == "1" {
		runTerminalCommandHelper(t)
		return
	}

	home := filepath.Join(t.TempDir(), "plasticine-home")
	workstationRoot := t.TempDir()
	script := `
"$1" -test.run '^TestTerminalCommandReleasesAndRestoresTUI$'
code=$?
if stty -a | grep -Eq '(^|[[:space:]])-(icanon|echo)([[:space:]]|$)'; then
  restored=no
else
  restored=yes
fi
printf '\nHELPER_EXIT=%s TERMINAL_RESTORED=%s\n' "$code" "$restored"
`
	command := exec.Command("sh", "-c", script, "terminal-pty", os.Args[0])
	command.Env = append(os.Environ(),
		"PLASTICINE_TUI_TERMINAL_HELPER=1",
		"PLASTICINE_HOME="+home,
		"PLASTICINE_WORKSTATION_ROOT="+workstationRoot,
		"TERM=xterm-256color",
		"NO_COLOR=1",
	)
	terminal, err := pty.StartWithSize(command, &pty.Winsize{Rows: 32, Cols: 120})
	if err != nil {
		t.Fatalf("start helper PTY: %v", err)
	}
	defer terminal.Close()

	outputDone := make(chan []byte, 1)
	go func() {
		outputDone <- readTerminalOutput(terminal)
	}()
	waitDone := make(chan error, 1)
	go func() {
		waitDone <- command.Wait()
	}()

	select {
	case err := <-waitDone:
		if err != nil {
			output := <-outputDone
			t.Fatalf("terminal helper failed: %v\n%s", err, output)
		}
	case <-time.After(10 * time.Second):
		_ = command.Process.Kill()
		t.Fatal("terminal helper timed out")
	}
	output := string(<-outputDone)
	for _, want := range []string{
		"HARMLESS_TERMINAL_COMMAND",
		"COMMAND_FAILURE_RETURNED=yes",
		"HELPER_EXIT=0 TERMINAL_RESTORED=yes",
		"\x1b[?1049l",
	} {
		if !strings.Contains(output, want) {
			t.Fatalf("terminal helper output missing %q:\n%s", want, output)
		}
	}
}

func runTerminalCommandHelper(t *testing.T) {
	runtime, err := workstation.New(workstation.Options{
		Home:            os.Getenv("PLASTICINE_HOME"),
		WorkstationRoot: os.Getenv("PLASTICINE_WORKSTATION_ROOT"),
		DiagnosticURLs:  []string{},
	})
	if err != nil {
		t.Fatalf("new runtime: %v", err)
	}
	ctx := context.Background()
	bridge := &operationBridge{ctx: ctx}
	initialModel := newModel(runtime, map[string]string{"NO_COLOR": "1"}, bridge)
	program := tea.NewProgram(
		initialModel,
		tea.WithInput(os.Stdin),
		tea.WithOutput(os.Stdout),
		tea.WithAltScreen(),
	)
	bridge.setProgram(program)

	commandResult := make(chan error, 1)
	go func() {
		response := make(chan error, 1)
		program.Send(terminalRequestMsg{
			ctx: ctx,
			command: reconciler.TerminalCommand{
				Name:             "sh",
				Args:             []string{"-c", "printf 'HARMLESS_TERMINAL_COMMAND\\n'; exit 7"},
				RequiresTerminal: true,
			},
			response: response,
		})
		commandResult <- <-response
		program.Quit()
	}()

	if _, err := program.Run(); err != nil {
		t.Fatalf("run helper program: %v", err)
	}
	commandErr := <-commandResult
	if commandErr == nil {
		t.Fatal("harmless failing command returned nil")
	}
	fmt.Println("COMMAND_FAILURE_RETURNED=yes")
}

func readTerminalOutput(terminal *os.File) []byte {
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
		}
		if err != nil {
			if errors.Is(err, io.EOF) ||
				errors.Is(err, os.ErrClosed) ||
				strings.Contains(err.Error(), "input/output error") {
				return output.Bytes()
			}
			return append(output.Bytes(), []byte("\nREAD_ERROR="+err.Error())...)
		}
	}
}
