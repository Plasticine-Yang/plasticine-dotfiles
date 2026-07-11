package candidate_test

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"testing"

	"github.com/Plasticine-Yang/plasticine-dotfiles/internal/candidate"
)

func TestSelfInstallFailsFastWhenPlasticineLockIsHeld(t *testing.T) {
	t.Parallel()

	home := t.TempDir()
	next := writeFile(t, home, "candidate", "new")
	install := filepath.Join(home, "bin", "plasticine")
	copyFile(t, writeCompatibleCLI(t, home, "current"), install)
	want := readFile(t, install)
	if err := os.MkdirAll(filepath.Join(home, "locks"), 0o700); err != nil {
		t.Fatalf("mkdir locks: %v", err)
	}
	if err := os.WriteFile(candidate.LockPath(home), []byte("held"), 0o600); err != nil {
		t.Fatalf("hold lock: %v", err)
	}

	result, err := candidate.SelfInstall(context.Background(), candidate.Request{
		Home:                home,
		CandidateExecutable: next,
		InstallPath:         install,
		StateCompatible:     true,
		StateCompatibility: func() candidate.StateCompatibilityResult {
			t.Fatal("state compatibility should not run before the exclusive lock is acquired")
			return candidate.StateCompatibilityResult{}
		},
	})
	if err != nil {
		t.Fatalf("self install returned error: %v", err)
	}
	if result.Outcome != candidate.OutcomeLocked {
		t.Fatalf("outcome = %s, want %s", result.Outcome, candidate.OutcomeLocked)
	}
	if got := readFile(t, install); got != want {
		t.Fatalf("installed bytes = %q, want preserved current", got)
	}
}

func TestSelfInstallAtomicallyReplacesCompatibleCurrentCLI(t *testing.T) {
	t.Parallel()

	home := t.TempDir()
	next := writeFile(t, home, "candidate", "new")
	install := filepath.Join(home, "bin", "plasticine")
	copyFile(t, writeCompatibleCLI(t, home, "current"), install)

	result, err := candidate.SelfInstall(context.Background(), candidate.Request{
		Home:                home,
		CandidateExecutable: next,
		InstallPath:         install,
		StateCompatible:     true,
		FirstApply:          func(context.Context) error { return nil },
	})
	if err != nil {
		t.Fatalf("self install returned error: %v", err)
	}
	if result.Outcome != candidate.OutcomeInstalled {
		t.Fatalf("outcome = %s, want %s (%s)", result.Outcome, candidate.OutcomeInstalled, result.Message)
	}
	if got := readFile(t, install); got != "new" {
		t.Fatalf("installed bytes = %q, want new", got)
	}
	if pathExists(candidate.LockPath(home)) {
		t.Fatalf("lock was not released: %s", candidate.LockPath(home))
	}
}

func TestSelfInstallPreservesCurrentCLIWhenStateIsIncompatible(t *testing.T) {
	t.Parallel()

	home := t.TempDir()
	current := writeFile(t, home, "current", "old")
	next := writeFile(t, home, "candidate", "new")
	install := filepath.Join(home, "bin", "plasticine")
	copyFile(t, current, install)

	result, err := candidate.SelfInstall(context.Background(), candidate.Request{
		Home:                home,
		CandidateExecutable: next,
		InstallPath:         install,
		StateCompatible:     false,
	})
	if err != nil {
		t.Fatalf("self install returned error: %v", err)
	}
	if result.Outcome != candidate.OutcomeIncompatible {
		t.Fatalf("outcome = %s, want %s", result.Outcome, candidate.OutcomeIncompatible)
	}
	if got := readFile(t, install); got != "old" {
		t.Fatalf("installed bytes = %q, want old", got)
	}
}

func TestReadOnlyStateCompatibilityClassifiesMigrationPendingAndUnreadableState(t *testing.T) {
	t.Parallel()

	home := t.TempDir()
	result := candidate.ReadOnlyStateCompatibility(home)
	if result.Status != candidate.StateCompatibilityCompatible || !candidate.ReadOnlyStateCompatible(home) {
		t.Fatalf("missing state compatibility = %#v", result)
	}

	writeCandidateState(t, home, `{"schema_version":1,"desired_state_id":"old"}`)
	result = candidate.ReadOnlyStateCompatibility(home)
	if result.Status != candidate.StateCompatibilityMigrationRequired || !candidate.ReadOnlyStateCompatible(home) {
		t.Fatalf("old state compatibility = %#v", result)
	}

	writeCandidateState(t, home, `{"schema_version":2,"desired_state_id":"current","pending_work":[{"component":"git-config","path":"config","resource_kind":"managed-path","intent":"write"}]}`)
	result = candidate.ReadOnlyStateCompatibility(home)
	if result.Status != candidate.StateCompatibilityIncompatible || candidate.ReadOnlyStateCompatible(home) {
		t.Fatalf("pending state compatibility = %#v", result)
	}

	writeCandidateState(t, home, `{"schema_version":999,"desired_state_id":"future"}`)
	result = candidate.ReadOnlyStateCompatibility(home)
	if result.Status != candidate.StateCompatibilityIncompatible || candidate.ReadOnlyStateCompatible(home) {
		t.Fatalf("newer state compatibility = %#v", result)
	}

	writeCandidateState(t, home, `{`)
	result = candidate.ReadOnlyStateCompatibility(home)
	if result.Status != candidate.StateCompatibilityIncompatible || candidate.ReadOnlyStateCompatible(home) {
		t.Fatalf("malformed state compatibility = %#v", result)
	}
}

func TestSelfInstallPreservesCurrentCLIWhenInstallationFails(t *testing.T) {
	t.Parallel()

	home := t.TempDir()
	current := writeCompatibleCLI(t, home, "current")
	install := filepath.Join(home, "bin", "plasticine")
	copyFile(t, current, install)
	want := readFile(t, install)

	result, err := candidate.SelfInstall(context.Background(), candidate.Request{
		Home:                home,
		CandidateExecutable: filepath.Join(home, "missing-candidate"),
		InstallPath:         install,
		StateCompatible:     true,
	})
	if err == nil {
		t.Fatalf("self install succeeded with missing candidate: %#v", result)
	}
	if result.Outcome != candidate.OutcomeInstallFailed {
		t.Fatalf("outcome = %s, want %s", result.Outcome, candidate.OutcomeInstallFailed)
	}
	if got := readFile(t, install); got != want {
		t.Fatalf("installed bytes = %q, want preserved current", got)
	}
}

func TestSelfInstallRetainsNewCLIWhenFirstApplyFails(t *testing.T) {
	t.Parallel()

	home := t.TempDir()
	current := writeCompatibleCLI(t, home, "current")
	next := writeFile(t, home, "candidate", "new")
	install := filepath.Join(home, "bin", "plasticine")
	copyFile(t, current, install)

	result, err := candidate.SelfInstall(context.Background(), candidate.Request{
		Home:                home,
		CandidateExecutable: next,
		InstallPath:         install,
		StateCompatible:     true,
		FirstApply:          func(context.Context) error { return errors.New("denied") },
	})
	if err == nil {
		t.Fatalf("self install succeeded despite first apply failure: %#v", result)
	}
	if result.Outcome != candidate.OutcomeFirstApplyFailed {
		t.Fatalf("outcome = %s, want %s", result.Outcome, candidate.OutcomeFirstApplyFailed)
	}
	if got := readFile(t, install); got != "new" {
		t.Fatalf("installed bytes = %q, want new", got)
	}
}

func TestSelfInstallPreservesUnknownCurrentExecutable(t *testing.T) {
	t.Parallel()

	home := t.TempDir()
	current := writeFile(t, home, "current", "old")
	next := writeFile(t, home, "candidate", "new")
	install := filepath.Join(home, "bin", "plasticine")
	copyFile(t, current, install)

	result, err := candidate.SelfInstall(context.Background(), candidate.Request{
		Home:                home,
		CandidateExecutable: next,
		InstallPath:         install,
		StateCompatible:     true,
	})
	if err != nil {
		t.Fatalf("self install returned error: %v", err)
	}
	if result.Outcome != candidate.OutcomeUnknownCurrent {
		t.Fatalf("outcome = %s, want %s", result.Outcome, candidate.OutcomeUnknownCurrent)
	}
	if got := readFile(t, install); got != "old" {
		t.Fatalf("installed bytes = %q, want old", got)
	}
}

func writeFile(t *testing.T, dir string, name string, body string) string {
	t.Helper()
	path := filepath.Join(dir, name)
	if err := os.WriteFile(path, []byte(body), 0o755); err != nil {
		t.Fatalf("write %s: %v", path, err)
	}
	return path
}

func writeCompatibleCLI(t *testing.T, dir string, name string) string {
	t.Helper()
	return writeFile(t, dir, name, "#!/bin/sh\nprintf '%s\\n' 'plasticine old commit=old commit_time=old'\n")
}

func copyFile(t *testing.T, source string, target string) {
	t.Helper()
	data, err := os.ReadFile(source)
	if err != nil {
		t.Fatalf("read %s: %v", source, err)
	}
	if err := os.MkdirAll(filepath.Dir(target), 0o700); err != nil {
		t.Fatalf("mkdir %s: %v", filepath.Dir(target), err)
	}
	if err := os.WriteFile(target, data, 0o755); err != nil {
		t.Fatalf("write %s: %v", target, err)
	}
}

func writeCandidateState(t *testing.T, home string, body string) {
	t.Helper()
	path := filepath.Join(home, "state", "reconciliation.json")
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		t.Fatalf("mkdir state: %v", err)
	}
	if err := os.WriteFile(path, []byte(body), 0o600); err != nil {
		t.Fatalf("write state: %v", err)
	}
}

func readFile(t *testing.T, path string) string {
	t.Helper()
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("read %s: %v", path, err)
	}
	return string(data)
}

func pathExists(path string) bool {
	_, err := os.Stat(path)
	return err == nil
}
