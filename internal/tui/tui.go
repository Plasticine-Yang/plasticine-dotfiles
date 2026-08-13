package tui

import (
	"context"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"sync"
	"syscall"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/x/term"

	"github.com/Plasticine-Yang/plasticine-dotfiles/internal/reconciler"
	"github.com/Plasticine-Yang/plasticine-dotfiles/internal/workstation"
)

type ExitReason int

const (
	ExitOwnerQuit ExitReason = iota
	ExitInterrupted
)

func (reason ExitReason) Code() int {
	if reason == ExitInterrupted {
		return 130
	}
	return 0
}

type IO struct {
	In  io.Reader
	Out io.Writer
	Err io.Writer
	Env map[string]string
}

func Run(ctx context.Context, runtime workstation.Runtime, terminal IO) (ExitReason, error) {
	if terminal.In == nil {
		terminal.In = os.Stdin
	}
	if terminal.Out == nil {
		terminal.Out = os.Stdout
	}
	if terminal.Err == nil {
		terminal.Err = os.Stderr
	}
	states := captureTerminalStates(terminal.In, terminal.Out)
	bridge := &operationBridge{ctx: ctx, out: terminal.Out, err: terminal.Err}
	initialModel := newModel(runtime, terminal.Env, bridge)
	program := tea.NewProgram(
		initialModel,
		tea.WithContext(ctx),
		tea.WithInput(terminal.In),
		tea.WithOutput(terminal.Out),
		tea.WithAltScreen(),
		tea.WithMouseCellMotion(),
	)
	bridge.setProgram(program)
	final, err := program.Run()
	bridge.cancelOperation()
	restoreErr := restoreTerminalStates(states)
	if err != nil {
		if ctx.Err() != nil {
			return ExitInterrupted, restoreErr
		}
		if restoreErr != nil {
			return ExitOwnerQuit, fmt.Errorf("%w; restore terminal: %v", err, restoreErr)
		}
		return ExitOwnerQuit, err
	}
	if restoreErr != nil {
		return ExitOwnerQuit, fmt.Errorf("restore terminal: %w", restoreErr)
	}
	finished, ok := final.(model)
	if !ok {
		return ExitOwnerQuit, fmt.Errorf("unexpected TUI model %T", final)
	}
	return finished.exitReason, nil
}

type terminalState struct {
	fd    uintptr
	state *term.State
}

func captureTerminalStates(streams ...any) []terminalState {
	seen := map[uintptr]bool{}
	var states []terminalState
	for _, stream := range streams {
		provider, ok := stream.(interface{ Fd() uintptr })
		if !ok || seen[provider.Fd()] || !term.IsTerminal(provider.Fd()) {
			continue
		}
		state, err := term.GetState(provider.Fd())
		if err != nil {
			continue
		}
		seen[provider.Fd()] = true
		states = append(states, terminalState{fd: provider.Fd(), state: state})
	}
	return states
}

func restoreTerminalStates(states []terminalState) error {
	var restoreErr error
	for _, saved := range states {
		if err := term.Restore(saved.fd, saved.state); err != nil && restoreErr == nil {
			restoreErr = err
		}
	}
	return restoreErr
}

type operationBridge struct {
	ctx context.Context
	out io.Writer
	err io.Writer

	mu        sync.Mutex
	program   *tea.Program
	cancel    context.CancelFunc
	operation string
}

func (bridge *operationBridge) setProgram(program *tea.Program) {
	bridge.mu.Lock()
	defer bridge.mu.Unlock()
	bridge.program = program
}

func (bridge *operationBridge) send(message tea.Msg) {
	bridge.mu.Lock()
	program := bridge.program
	bridge.mu.Unlock()
	if program != nil {
		program.Send(message)
	}
}

func (bridge *operationBridge) start(operation string, run func(context.Context) (reconciler.Result, error)) {
	bridge.cancelOperation()
	operationCtx, cancel := context.WithCancel(bridge.ctx)
	bridge.mu.Lock()
	bridge.cancel = cancel
	bridge.operation = operation
	bridge.mu.Unlock()
	go func() {
		result, err := run(operationCtx)
		bridge.send(operationDoneMsg{operation: operation, result: result, err: err})
		bridge.mu.Lock()
		if bridge.operation == operation {
			bridge.cancel = nil
			bridge.operation = ""
		}
		bridge.mu.Unlock()
	}()
}

func (bridge *operationBridge) cancelOperation() {
	bridge.mu.Lock()
	cancel := bridge.cancel
	bridge.mu.Unlock()
	if cancel != nil {
		cancel()
	}
}

func (bridge *operationBridge) authorize(ctx context.Context, result reconciler.Result) reconciler.AuthorizationDecision {
	response := make(chan reconciler.AuthorizationDecision, 1)
	bridge.send(authorizationRequestMsg{result: result, response: response})
	select {
	case decision := <-response:
		return decision
	case <-ctx.Done():
		return reconciler.AuthorizationDecision{}
	}
}

func (bridge *operationBridge) selectGitHubKey(ctx context.Context) (string, bool) {
	response := make(chan keySelection, 1)
	bridge.send(keyRequestMsg{response: response})
	select {
	case selection := <-response:
		return selection.path, selection.selected
	case <-ctx.Done():
		return "", false
	}
}

func (bridge *operationBridge) runTerminal(ctx context.Context, command reconciler.TerminalCommand) error {
	if !command.RequiresTerminal {
		return exec.CommandContext(ctx, command.Name, command.Args...).Run()
	}
	response := make(chan error, 1)
	bridge.send(terminalRequestMsg{ctx: ctx, command: command, response: response})
	select {
	case err := <-response:
		return err
	case <-ctx.Done():
		return ctx.Err()
	}
}

type operationDoneMsg struct {
	operation string
	result    reconciler.Result
	err       error
}

type authorizationRequestMsg struct {
	result   reconciler.Result
	response chan<- reconciler.AuthorizationDecision
}

type keySelection struct {
	path     string
	selected bool
}

type keyRequestMsg struct {
	response chan<- keySelection
}

type terminalRequestMsg struct {
	ctx      context.Context
	command  reconciler.TerminalCommand
	response chan<- error
}

type terminalDoneMsg struct {
	response    chan<- error
	err         error
	interrupted bool
}

type progressMsg reconciler.ProgressEvent

func terminalInterrupted(err error) bool {
	if err == nil || errors.Is(err, context.Canceled) {
		return errors.Is(err, context.Canceled)
	}
	var exitError *exec.ExitError
	if !errors.As(err, &exitError) {
		return false
	}
	status, ok := exitError.Sys().(syscall.WaitStatus)
	return ok && status.Signaled() && status.Signal() == syscall.SIGINT
}
