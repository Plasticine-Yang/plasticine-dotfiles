package candidate

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"
)

type Outcome string

const (
	OutcomeInstalled        Outcome = "installed"
	OutcomeLocked           Outcome = "locked"
	OutcomeIncompatible     Outcome = "incompatible"
	OutcomeInstallFailed    Outcome = "install-failed"
	OutcomeFirstApplyFailed Outcome = "first-apply-failed"
	OutcomeUnknownCurrent   Outcome = "unknown-current"
)

type Request struct {
	Home                string
	CurrentExecutable   string
	CandidateExecutable string
	InstallPath         string
	StateCompatible     bool
	FirstApply          func(context.Context) error
}

type Result struct {
	Outcome Outcome
	Message string
}

func SelfInstall(ctx context.Context, req Request) (Result, error) {
	if err := ctx.Err(); err != nil {
		return Result{}, err
	}
	release, err := acquireLock(req.Home)
	if err != nil {
		return Result{Outcome: OutcomeLocked, Message: err.Error()}, nil
	}
	defer release()

	if !req.StateCompatible {
		return Result{Outcome: OutcomeIncompatible, Message: "state compatibility check failed"}, nil
	}
	current := req.CurrentExecutable
	if current == "" {
		current = req.InstallPath
	}
	compatible, err := currentExecutableIsCompatible(ctx, current)
	if err != nil {
		return Result{Outcome: OutcomeInstallFailed, Message: err.Error()}, err
	}
	if !compatible {
		return Result{Outcome: OutcomeUnknownCurrent, Message: "current executable is not a compatible Plasticine CLI"}, nil
	}
	if err := replaceExecutable(req.CandidateExecutable, req.InstallPath); err != nil {
		return Result{Outcome: OutcomeInstallFailed, Message: err.Error()}, err
	}
	if req.FirstApply != nil {
		if err := req.FirstApply(ctx); err != nil {
			return Result{Outcome: OutcomeFirstApplyFailed, Message: err.Error()}, err
		}
	}
	return Result{Outcome: OutcomeInstalled}, nil
}

func LockPath(home string) string {
	return filepath.Join(home, "locks", "plasticine.lock")
}

func ReadOnlyStateCompatible(home string) bool {
	data, err := os.ReadFile(filepath.Join(home, "state", "reconciliation.json"))
	if os.IsNotExist(err) {
		return true
	}
	if err != nil {
		return false
	}
	var state struct {
		DesiredStateID string `json:"desired_state_id"`
	}
	if err := json.Unmarshal(data, &state); err != nil {
		return false
	}
	return state.DesiredStateID != ""
}

func acquireLock(home string) (func(), error) {
	path := LockPath(home)
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		return nil, err
	}
	file, err := os.OpenFile(path, os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0o600)
	if err != nil {
		return nil, fmt.Errorf("plasticine lock is held at %s", path)
	}
	if _, err := fmt.Fprintf(file, "%d\n", os.Getpid()); err != nil {
		_ = file.Close()
		_ = os.Remove(path)
		return nil, err
	}
	return func() {
		_ = file.Close()
		_ = os.Remove(path)
	}, nil
}

func currentExecutableIsCompatible(ctx context.Context, path string) (bool, error) {
	if _, err := os.Stat(path); os.IsNotExist(err) {
		return true, nil
	} else if err != nil {
		return false, err
	}
	checkCtx, cancel := context.WithTimeout(ctx, 2*time.Second)
	defer cancel()
	output, err := exec.CommandContext(checkCtx, path, "version").CombinedOutput()
	if err != nil {
		return false, nil
	}
	return strings.HasPrefix(string(output), "plasticine "), nil
}

func replaceExecutable(candidatePath string, installPath string) error {
	source, err := os.Open(candidatePath)
	if err != nil {
		return err
	}
	defer source.Close()

	if err := os.MkdirAll(filepath.Dir(installPath), 0o700); err != nil {
		return err
	}
	tempPath := installPath + ".candidate"
	target, err := os.OpenFile(tempPath, os.O_CREATE|os.O_TRUNC|os.O_WRONLY, 0o755)
	if err != nil {
		return err
	}
	if _, err := io.Copy(target, source); err != nil {
		_ = target.Close()
		_ = os.Remove(tempPath)
		return err
	}
	if err := target.Close(); err != nil {
		_ = os.Remove(tempPath)
		return err
	}
	return os.Rename(tempPath, installPath)
}
