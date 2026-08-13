package reconciler_test

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/Plasticine-Yang/plasticine-dotfiles/internal/platform"
	"github.com/Plasticine-Yang/plasticine-dotfiles/internal/reconciler"
)

func TestTSMBootstrapPlanApplyAndDoctorContract(t *testing.T) {
	workstationRoot := t.TempDir()
	plasticineHome := filepath.Join(workstationRoot, ".plasticine")
	primaryExecutable := filepath.Join(workstationRoot, ".local", "bin", "tsm")
	var downloads int
	var installedScriptPath string
	var installerStdout bytes.Buffer
	var installerStderr bytes.Buffer
	client := &http.Client{Transport: roundTripFunc(func(request *http.Request) (*http.Response, error) {
		downloads++
		return &http.Response{
			StatusCode: http.StatusOK,
			Status:     "200 OK",
			Body:       io.NopCloser(strings.NewReader("#!/bin/sh\n")),
			Header:     make(http.Header),
			Request:    request,
		}, nil
	})}
	runner := func(ctx context.Context, command reconciler.ExternalInstallerCommand) error {
		if command.Component != reconciler.ComponentTraexSessionManager {
			t.Fatalf("installer component = %s", command.Component)
		}
		if command.ScriptPath == "" || strings.Contains(command.ScriptPath, "://") {
			t.Fatalf("installer did not receive a downloaded file: %#v", command)
		}
		installedScriptPath = command.ScriptPath
		if command.Stdout == nil || command.Stderr == nil {
			t.Fatalf("installer output is not visible: %#v", command)
		}
		_, _ = fmt.Fprint(command.Stdout, "installer progress\n")
		_, _ = fmt.Fprint(command.Stderr, "installer warning\n")
		if command.Environment["HOME"] != workstationRoot {
			t.Fatalf("installer HOME = %q, want %q", command.Environment["HOME"], workstationRoot)
		}
		if err := os.MkdirAll(filepath.Dir(primaryExecutable), 0o700); err != nil {
			return err
		}
		return os.WriteFile(primaryExecutable, []byte("#!/bin/sh\nexit 0\n"), 0o755)
	}
	r := reconciler.New(reconciler.Options{
		DesiredStateID:  "self-managed-tool-contract",
		ToolLockSHA256:  strings.Repeat("d", 64),
		HTTPClient:      client,
		InstallerRunner: runner,
	})
	req := tsmOnlyRequest(plasticineHome, workstationRoot)
	req.InstallerStdout = &installerStdout
	req.InstallerStderr = &installerStderr

	plan, err := r.Plan(context.Background(), req)
	if err != nil {
		t.Fatalf("plan: %v", err)
	}
	if plan.Outcome != reconciler.OutcomeChangesPlanned {
		t.Fatalf("plan outcome = %s, blockers=%#v changes=%#v", plan.Outcome, plan.Blockers, plan.Changes)
	}
	if downloads != 0 {
		t.Fatalf("Plan made %d installer requests", downloads)
	}
	change := changeByKind(plan.Changes, reconciler.ChangeRunExternalInstaller)
	if change == nil {
		t.Fatalf("plan changes = %#v, want external installer", plan.Changes)
	}
	if change.Component != reconciler.ComponentTraexSessionManager ||
		change.ResourceKind != reconciler.ResourceSelfManagedTool ||
		change.Path != "https://raw.githubusercontent.com/Plasticine-Yang/traex-session-manager/main/install.sh" ||
		!strings.Contains(change.Summary, "external script") ||
		!strings.Contains(change.Summary, "opaque") {
		t.Fatalf("external installer change = %#v", change)
	}

	denied, err := r.Apply(context.Background(), req)
	if err != nil {
		t.Fatalf("denied apply: %v", err)
	}
	if denied.Outcome != reconciler.OutcomeDenied || downloads != 0 {
		t.Fatalf("denied outcome=%s downloads=%d", denied.Outcome, downloads)
	}

	req.Yes = true
	applied, err := r.Apply(context.Background(), req)
	if err != nil {
		t.Fatalf("apply: %v", err)
	}
	if applied.Outcome != reconciler.OutcomeApplied ||
		!hasComponentStatus(applied.Components, reconciler.ComponentTraexSessionManager, reconciler.ComponentSucceeded) {
		t.Fatalf("apply outcome=%s components=%#v blockers=%#v", applied.Outcome, applied.Components, applied.Blockers)
	}
	if downloads != 1 {
		t.Fatalf("installer downloads = %d, want 1", downloads)
	}
	if installedScriptPath == "" || pathExists(installedScriptPath) {
		t.Fatalf("successful installer temporary file was not removed: %q", installedScriptPath)
	}
	if installerStdout.String() != "installer progress\n" || installerStderr.String() != "installer warning\n" {
		t.Fatalf("installer output stdout=%q stderr=%q", installerStdout.String(), installerStderr.String())
	}
	state, err := reconciler.ReadState(plasticineHome)
	if err != nil {
		t.Fatalf("read state: %v", err)
	}
	if _, owned := state.Ownership[primaryExecutable]; owned {
		t.Fatalf("TSM executable entered Ownership: %#v", state.Ownership[primaryExecutable])
	}
	if len(state.PendingWork) != 0 {
		t.Fatalf("TSM bootstrap entered pending work: %#v", state.PendingWork)
	}

	second, err := r.Plan(context.Background(), req)
	if err != nil {
		t.Fatalf("second plan: %v", err)
	}
	if second.Outcome != reconciler.OutcomeNoChange || changeByKind(second.Changes, reconciler.ChangeRunExternalInstaller) != nil {
		t.Fatalf("second plan outcome=%s changes=%#v", second.Outcome, second.Changes)
	}
	doctor, err := r.Doctor(context.Background(), req)
	if err != nil {
		t.Fatalf("doctor: %v", err)
	}
	if doctor.Outcome != reconciler.OutcomeHealthy || !hasHealthyCheck(doctor.Checks, "self-managed:traex-session-manager") {
		t.Fatalf("doctor outcome=%s checks=%#v", doctor.Outcome, doctor.Checks)
	}
	if downloads != 1 {
		t.Fatalf("Doctor made an installer request; downloads=%d", downloads)
	}
}

func TestTSMComponentIsDefaultEnabledOnEveryArtifactTarget(t *testing.T) {
	catalog := reconciler.ComponentCatalog()
	if len(catalog) != 9 || catalog[len(catalog)-1].ID != reconciler.ComponentTraexSessionManager {
		t.Fatalf("catalog = %#v", catalog)
	}
	for _, target := range platform.SupportedArtifactTargets() {
		req := tsmOnlyRequest(filepath.Join(t.TempDir(), ".plasticine"), t.TempDir())
		req.Target = target
		req.Host.OS = target.OS
		req.Host.Arch = target.Arch
		if target.OS == platform.OSLinux {
			req.Host.Family = platform.FamilyUbuntu
			req.Host.Version = "24.04"
		}
		r := reconciler.New(reconciler.Options{
			DesiredStateID: "tsm-target-contract",
			ToolLockSHA256: strings.Repeat("e", 64),
		})
		plan, err := r.Plan(context.Background(), req)
		if err != nil {
			t.Fatalf("%s plan: %v", target, err)
		}
		if changeByKind(plan.Changes, reconciler.ChangeRunExternalInstaller) == nil {
			t.Fatalf("%s plan changes=%#v, want TSM installer", target, plan.Changes)
		}
	}
}

func TestTSMAcceptsOwnerManagedLifecycleAndScope(t *testing.T) {
	workstationRoot := t.TempDir()
	home := filepath.Join(workstationRoot, ".plasticine")
	primary := filepath.Join(workstationRoot, ".local", "bin", "tsm")
	alias := filepath.Join(workstationRoot, ".local", "bin", "traex-session-manager")
	outside := filepath.Join(workstationRoot, "bin", "tsm")
	writeMode(t, primary, "#!/bin/sh\nprintf 'tsm owner-build\\n'\n", 0o755)
	writeMode(t, outside, "#!/bin/sh\nexit 0\n", 0o755)
	if err := os.Symlink("missing-owner-alias", alias); err != nil {
		t.Fatalf("create broken alias: %v", err)
	}
	r := reconciler.New(reconciler.Options{
		DesiredStateID: "self-managed-lifecycle-contract",
		ToolLockSHA256: strings.Repeat("f", 64),
	})
	req := tsmOnlyRequest(home, workstationRoot)
	req.Yes = true

	applied, err := r.Apply(context.Background(), req)
	if err != nil {
		t.Fatalf("initial apply: %v", err)
	}
	if applied.Outcome != reconciler.OutcomeApplied {
		t.Fatalf("initial outcome=%s blockers=%#v", applied.Outcome, applied.Blockers)
	}
	replacement := "#!/bin/sh\nprintf 'tsm self-updated\\n'\n"
	writeMode(t, primary, replacement, 0o755)
	plan, err := r.Plan(context.Background(), req)
	if err != nil {
		t.Fatalf("self-updated plan: %v", err)
	}
	if plan.Outcome != reconciler.OutcomeNoChange || changeByKind(plan.Changes, reconciler.ChangeRunExternalInstaller) != nil {
		t.Fatalf("self-updated outcome=%s changes=%#v", plan.Outcome, plan.Changes)
	}

	req.ReplaceScope = true
	req.Exclude = append(req.Exclude, reconciler.ComponentTraexSessionManager)
	excluded, err := r.Apply(context.Background(), req)
	if err != nil {
		t.Fatalf("exclude apply: %v", err)
	}
	if excluded.Outcome != reconciler.OutcomeApplied || readText(t, primary) != replacement {
		t.Fatalf("exclude outcome=%s primary=%q", excluded.Outcome, readText(t, primary))
	}
	doctor, err := r.Doctor(context.Background(), req)
	if err != nil {
		t.Fatalf("excluded doctor: %v", err)
	}
	if checkByName(doctor.Checks, "self-managed:traex-session-manager") != nil {
		t.Fatalf("excluded Doctor observed TSM: %#v", doctor.Checks)
	}

	req.Exclude = req.Exclude[:len(req.Exclude)-1]
	reenabled, err := r.Plan(context.Background(), req)
	if err != nil {
		t.Fatalf("reenabled plan: %v", err)
	}
	if reenabled.Outcome != reconciler.OutcomeChangesPlanned {
		t.Fatalf("reenabled outcome=%s changes=%#v", reenabled.Outcome, reenabled.Changes)
	}
	if changeByKind(reenabled.Changes, reconciler.ChangeRunExternalInstaller) != nil {
		t.Fatalf("reenabled runnable TSM planned bootstrap: %#v", reenabled.Changes)
	}

	if err := os.Chmod(primary, 0o644); err != nil {
		t.Fatalf("make primary non-executable: %v", err)
	}
	repair, err := r.Plan(context.Background(), req)
	if err != nil {
		t.Fatalf("repair plan: %v", err)
	}
	if changeByKind(repair.Changes, reconciler.ChangeRunExternalInstaller) == nil {
		t.Fatalf("non-executable primary did not plan repair: %#v", repair.Changes)
	}
	writeMode(t, primary, "#!/bin/sh\nexit 1\n", 0o755)
	repair, err = r.Plan(context.Background(), req)
	if err != nil {
		t.Fatalf("failing-health plan: %v", err)
	}
	if changeByKind(repair.Changes, reconciler.ChangeRunExternalInstaller) == nil {
		t.Fatalf("failing health command did not plan repair: %#v", repair.Changes)
	}
	if err := os.Remove(primary); err != nil {
		t.Fatalf("remove primary: %v", err)
	}
	repair, err = r.Plan(context.Background(), req)
	if err != nil {
		t.Fatalf("missing-primary plan: %v", err)
	}
	if changeByKind(repair.Changes, reconciler.ChangeRunExternalInstaller) == nil {
		t.Fatalf("PATH/alias unexpectedly satisfied TSM: %#v", repair.Changes)
	}
}

func TestTSMPrerequisitesUseExistingSystemDependencyAuthorization(t *testing.T) {
	for _, test := range []struct {
		name    string
		missing []reconciler.Capability
	}{
		{name: "curl", missing: []reconciler.Capability{reconciler.CapabilityCurl}},
		{name: "tar", missing: []reconciler.Capability{reconciler.CapabilityTar}},
		{name: "sha256", missing: []reconciler.Capability{reconciler.CapabilitySHA256Verifier}},
	} {
		t.Run(test.name, func(t *testing.T) {
			system := &recordingSystemAdapter{missing: test.missing}
			workstationRoot := t.TempDir()
			r := reconciler.New(reconciler.Options{
				DesiredStateID:  "self-managed-prerequisite-contract",
				ToolLockSHA256:  strings.Repeat("1", 64),
				System:          system,
				InstallerRunner: func(context.Context, reconciler.ExternalInstallerCommand) error { return nil },
			})
			req := tsmOnlyRequest(filepath.Join(workstationRoot, ".plasticine"), workstationRoot)
			req.Target = platform.TargetLinuxAMD64
			req.Host = platform.Host{
				OS: platform.OSLinux, Arch: platform.ArchAMD64,
				Family: platform.FamilyDebian, Version: "12",
			}
			req.Capabilities = nil
			plan, err := r.Plan(context.Background(), req)
			if err != nil {
				t.Fatalf("plan: %v", err)
			}
			systemChange := changeByKind(plan.Changes, reconciler.ChangeSystemDependency)
			if systemChange == nil || !containsCapabilityForTest(systemChange.Capabilities, test.missing[0]) {
				t.Fatalf("changes=%#v, want prerequisite %s", plan.Changes, test.missing[0])
			}
			req.Yes = true
			blocked, err := r.Apply(context.Background(), req)
			if err != nil {
				t.Fatalf("apply without allow-system: %v", err)
			}
			if blocked.Outcome != reconciler.OutcomeBlocked ||
				!hasBlocker(blocked.Blockers, reconciler.BlockerSystemChangeAuthorization) {
				t.Fatalf("outcome=%s blockers=%#v", blocked.Outcome, blocked.Blockers)
			}
		})
	}

	workstationRoot := t.TempDir()
	primary := filepath.Join(workstationRoot, ".local", "bin", "tsm")
	writeMode(t, primary, "#!/bin/sh\nexit 0\n", 0o755)
	system := &recordingSystemAdapter{
		missing: []reconciler.Capability{
			reconciler.CapabilityCurl,
			reconciler.CapabilityTar,
			reconciler.CapabilitySHA256Verifier,
		},
	}
	r := reconciler.New(reconciler.Options{
		DesiredStateID: "self-managed-prerequisite-skip-contract",
		ToolLockSHA256: strings.Repeat("2", 64),
		System:         system,
	})
	req := tsmOnlyRequest(filepath.Join(workstationRoot, ".plasticine"), workstationRoot)
	req.Capabilities = nil
	plan, err := r.Plan(context.Background(), req)
	if err != nil {
		t.Fatalf("runnable plan: %v", err)
	}
	if changeByKind(plan.Changes, reconciler.ChangeSystemDependency) != nil {
		t.Fatalf("runnable TSM planned installer prerequisites: %#v", plan.Changes)
	}

	for _, verifier := range []string{"shasum", "sha256sum"} {
		t.Run(verifier+" satisfies verifier capability", func(t *testing.T) {
			binDir := t.TempDir()
			writeMode(t, filepath.Join(binDir, "curl"), "#!/bin/sh\nexit 0\n", 0o755)
			writeMode(t, filepath.Join(binDir, "tar"), "#!/bin/sh\nexit 0\n", 0o755)
			writeMode(t, filepath.Join(binDir, verifier), "#!/bin/sh\nexit 0\n", 0o755)
			t.Setenv("PATH", binDir)
			adapter := reconciler.LocalSystemAdapter{}
			req := tsmOnlyRequest(filepath.Join(t.TempDir(), ".plasticine"), t.TempDir())
			req.Capabilities = nil
			missing, err := adapter.MissingCapabilities(context.Background(), req, []reconciler.ComponentID{
				reconciler.ComponentTraexSessionManager,
			})
			if err != nil {
				t.Fatalf("missing capabilities: %v", err)
			}
			if containsCapabilityForTest(missing, reconciler.CapabilitySHA256Verifier) {
				t.Fatalf("%s did not satisfy SHA-256 verifier: %#v", verifier, missing)
			}
		})
	}
}

func TestTSMMissingMacOSPrerequisiteReportsOwnerAction(t *testing.T) {
	workstationRoot := t.TempDir()
	system := &recordingSystemAdapter{
		missing: []reconciler.Capability{reconciler.CapabilityCurl},
		err:     fmt.Errorf("%w: install curl and rerun apply", reconciler.ErrOwnerActionRequired),
	}
	r := reconciler.New(reconciler.Options{
		DesiredStateID: "self-managed-macos-prerequisite-contract",
		ToolLockSHA256: strings.Repeat("6", 64),
		System:         system,
	})
	req := tsmOnlyRequest(filepath.Join(workstationRoot, ".plasticine"), workstationRoot)
	req.Capabilities = nil
	req.Yes = true
	req.AllowSystem = true
	result, err := r.Apply(context.Background(), req)
	if err != nil {
		t.Fatalf("apply: %v", err)
	}
	if result.Outcome != reconciler.OutcomePartial ||
		!hasBlocker(result.Blockers, reconciler.BlockerOwnerActionRequired) ||
		!hasComponentStatus(result.Components, reconciler.ComponentTraexSessionManager, reconciler.ComponentAwaitingOwnerAction) {
		t.Fatalf("outcome=%s components=%#v blockers=%#v", result.Outcome, result.Components, result.Blockers)
	}
}

func TestTSMPrerequisiteFailureContinuesIndependentComponent(t *testing.T) {
	workstationRoot := t.TempDir()
	system := &recordingSystemAdapter{
		missing: []reconciler.Capability{reconciler.CapabilityCurl},
		err:     errors.New("apt fixture failed"),
	}
	r := reconciler.New(reconciler.Options{
		DesiredStateID: "self-managed-prerequisite-failure-contract",
		ToolLockSHA256: strings.Repeat("7", 64),
		System:         system,
	})
	req := tsmAndGitConfigRequest(filepath.Join(workstationRoot, ".plasticine"), workstationRoot)
	req.Target = platform.TargetLinuxAMD64
	req.Host = platform.Host{
		OS: platform.OSLinux, Arch: platform.ArchAMD64,
		Family: platform.FamilyUbuntu, Version: "24.04",
	}
	req.Capabilities = nil
	req.Yes = true
	req.AllowSystem = true
	result, err := r.Apply(context.Background(), req)
	if err != nil {
		t.Fatalf("apply: %v", err)
	}
	if result.Outcome != reconciler.OutcomePartial ||
		!hasComponentStatus(result.Components, reconciler.ComponentTraexSessionManager, reconciler.ComponentBlocked) ||
		!hasComponentStatus(result.Components, reconciler.ComponentGitConfig, reconciler.ComponentSucceeded) {
		t.Fatalf("outcome=%s components=%#v blockers=%#v", result.Outcome, result.Components, result.Blockers)
	}
	if !pathExists(filepath.Join(req.Home, "config", "git", "config")) {
		t.Fatalf("independent git-config did not continue")
	}
}

func TestTSMInstallerFailureIsIsolatedAndTemporaryFileIsRemoved(t *testing.T) {
	workstationRoot := t.TempDir()
	var scriptPath string
	r := reconciler.New(reconciler.Options{
		DesiredStateID: "self-managed-failure-contract",
		ToolLockSHA256: strings.Repeat("3", 64),
		HTTPClient: &http.Client{Transport: roundTripFunc(func(request *http.Request) (*http.Response, error) {
			return &http.Response{
				StatusCode: http.StatusOK,
				Status:     "200 OK",
				Body:       io.NopCloser(strings.NewReader("#!/bin/sh\n")),
				Header:     make(http.Header),
				Request:    request,
			}, nil
		})},
		InstallerRunner: func(_ context.Context, command reconciler.ExternalInstallerCommand) error {
			scriptPath = command.ScriptPath
			partial := filepath.Join(workstationRoot, ".local", "bin", "partial-owner-state")
			writeText(t, partial, "preserve me")
			return os.ErrPermission
		},
	})
	req := tsmAndGitConfigRequest(filepath.Join(workstationRoot, ".plasticine"), workstationRoot)
	req.Yes = true
	result, err := r.Apply(context.Background(), req)
	if err != nil {
		t.Fatalf("apply: %v", err)
	}
	if result.Outcome != reconciler.OutcomePartial ||
		!hasComponentStatus(result.Components, reconciler.ComponentTraexSessionManager, reconciler.ComponentBlocked) ||
		!hasComponentStatus(result.Components, reconciler.ComponentGitConfig, reconciler.ComponentSucceeded) {
		t.Fatalf("outcome=%s components=%#v blockers=%#v", result.Outcome, result.Components, result.Blockers)
	}
	if scriptPath == "" || pathExists(scriptPath) {
		t.Fatalf("temporary installer was not removed: %q", scriptPath)
	}
	partial := filepath.Join(workstationRoot, ".local", "bin", "partial-owner-state")
	if readText(t, partial) != "preserve me" {
		t.Fatalf("partial upstream state was rolled back")
	}
	retry, err := r.Plan(context.Background(), req)
	if err != nil {
		t.Fatalf("retry plan: %v", err)
	}
	if changeByKind(retry.Changes, reconciler.ChangeRunExternalInstaller) == nil {
		t.Fatalf("failed bootstrap was remembered instead of reobserved: %#v", retry.Changes)
	}
}

func TestTSMInstallerCancellationPropagatesAndCleansTemporaryFile(t *testing.T) {
	workstationRoot := t.TempDir()
	started := make(chan string, 1)
	r := reconciler.New(reconciler.Options{
		DesiredStateID: "self-managed-cancellation-contract",
		ToolLockSHA256: strings.Repeat("4", 64),
		HTTPClient: &http.Client{Transport: roundTripFunc(func(request *http.Request) (*http.Response, error) {
			return &http.Response{
				StatusCode: http.StatusOK,
				Status:     "200 OK",
				Body:       io.NopCloser(strings.NewReader("#!/bin/sh\n")),
				Header:     make(http.Header),
				Request:    request,
			}, nil
		})},
		InstallerRunner: func(ctx context.Context, command reconciler.ExternalInstallerCommand) error {
			started <- command.ScriptPath
			<-ctx.Done()
			return ctx.Err()
		},
	})
	req := tsmOnlyRequest(filepath.Join(workstationRoot, ".plasticine"), workstationRoot)
	req.Yes = true
	ctx, cancel := context.WithCancel(context.Background())
	resultCh := make(chan error, 1)
	go func() {
		_, err := r.Apply(ctx, req)
		resultCh <- err
	}()
	scriptPath := <-started
	cancel()
	if err := <-resultCh; err != context.Canceled {
		t.Fatalf("cancellation error=%v, want context.Canceled", err)
	}
	if pathExists(scriptPath) {
		t.Fatalf("temporary installer remained after cancellation: %s", scriptPath)
	}
}

func TestTSMInstallerTimeoutIsAttributedAndCleansTemporaryFile(t *testing.T) {
	workstationRoot := t.TempDir()
	var scriptPath string
	r := reconciler.New(reconciler.Options{
		DesiredStateID: "self-managed-timeout-contract",
		ToolLockSHA256: strings.Repeat("8", 64),
		HTTPClient: &http.Client{Transport: roundTripFunc(func(request *http.Request) (*http.Response, error) {
			return &http.Response{
				StatusCode: http.StatusOK,
				Status:     "200 OK",
				Body:       io.NopCloser(strings.NewReader("#!/bin/sh\n")),
				Header:     make(http.Header),
				Request:    request,
			}, nil
		})},
		InstallerRunner: func(_ context.Context, command reconciler.ExternalInstallerCommand) error {
			scriptPath = command.ScriptPath
			return context.DeadlineExceeded
		},
	})
	req := tsmOnlyRequest(filepath.Join(workstationRoot, ".plasticine"), workstationRoot)
	req.Yes = true
	result, err := r.Apply(context.Background(), req)
	if err != nil {
		t.Fatalf("timeout apply returned error: %v", err)
	}
	if result.Outcome != reconciler.OutcomePartial ||
		!hasComponentStatus(result.Components, reconciler.ComponentTraexSessionManager, reconciler.ComponentBlocked) ||
		!blockerContains(result.Blockers, "timed out") {
		t.Fatalf("outcome=%s components=%#v blockers=%#v", result.Outcome, result.Components, result.Blockers)
	}
	if pathExists(scriptPath) {
		t.Fatalf("temporary installer remained after timeout: %s", scriptPath)
	}
}

func TestTSMCatalogRemovalCannotRetireUnownedPaths(t *testing.T) {
	workstationRoot := t.TempDir()
	primary := filepath.Join(workstationRoot, ".local", "bin", "tsm")
	writeMode(t, primary, "#!/bin/sh\nexit 0\n", 0o755)
	home := filepath.Join(workstationRoot, ".plasticine")
	r := reconciler.New(reconciler.Options{
		DesiredStateID: "self-managed-catalog-removal-contract",
		ToolLockSHA256: strings.Repeat("9", 64),
	})
	req := tsmOnlyRequest(home, workstationRoot)
	req.Yes = true
	if _, err := r.Apply(context.Background(), req); err != nil {
		t.Fatalf("initial apply: %v", err)
	}
	state, err := reconciler.ReadState(home)
	if err != nil {
		t.Fatalf("read state: %v", err)
	}
	if _, owned := state.Ownership[primary]; owned {
		t.Fatalf("primary unexpectedly owned before catalog removal")
	}
	for _, ownership := range state.Ownership {
		if ownership.Component == reconciler.ComponentTraexSessionManager {
			t.Fatalf("TSM ownership unexpectedly persisted: %#v", ownership)
		}
	}
	if _, err := os.Stat(primary); err != nil {
		t.Fatalf("catalog-removal precondition lost primary: %v", err)
	}
}

func TestTSMInstallerDownloadAndPostHealthFailuresCleanTemporaryFiles(t *testing.T) {
	for _, test := range []struct {
		name      string
		transport http.RoundTripper
		runner    reconciler.ExternalInstallerRunner
	}{
		{
			name: "download",
			transport: roundTripFunc(func(*http.Request) (*http.Response, error) {
				return nil, errors.New("fixture download unavailable")
			}),
		},
		{
			name: "post-install-health",
			transport: roundTripFunc(func(request *http.Request) (*http.Response, error) {
				return &http.Response{
					StatusCode: http.StatusOK,
					Status:     "200 OK",
					Body:       io.NopCloser(strings.NewReader("#!/bin/sh\n")),
					Header:     make(http.Header),
					Request:    request,
				}, nil
			}),
			runner: func(context.Context, reconciler.ExternalInstallerCommand) error {
				return nil
			},
		},
	} {
		t.Run(test.name, func(t *testing.T) {
			before, err := filepath.Glob(filepath.Join(os.TempDir(), "plasticine-external-installer-*"))
			if err != nil {
				t.Fatalf("glob before: %v", err)
			}
			workstationRoot := t.TempDir()
			r := reconciler.New(reconciler.Options{
				DesiredStateID:  "self-managed-" + test.name + "-contract",
				ToolLockSHA256:  strings.Repeat("5", 64),
				HTTPClient:      &http.Client{Transport: test.transport},
				InstallerRunner: test.runner,
			})
			req := tsmOnlyRequest(filepath.Join(workstationRoot, ".plasticine"), workstationRoot)
			req.Yes = true
			result, err := r.Apply(context.Background(), req)
			if err != nil {
				t.Fatalf("apply: %v", err)
			}
			if result.Outcome != reconciler.OutcomePartial ||
				!hasComponentStatus(result.Components, reconciler.ComponentTraexSessionManager, reconciler.ComponentBlocked) {
				t.Fatalf("outcome=%s components=%#v blockers=%#v", result.Outcome, result.Components, result.Blockers)
			}
			after, err := filepath.Glob(filepath.Join(os.TempDir(), "plasticine-external-installer-*"))
			if err != nil {
				t.Fatalf("glob after: %v", err)
			}
			if len(after) != len(before) {
				t.Fatalf("temporary installer directories before=%#v after=%#v", before, after)
			}
		})
	}
}

func tsmOnlyRequest(home string, workstationRoot string) reconciler.Request {
	excluded := make([]reconciler.ComponentID, 0)
	for _, definition := range reconciler.ComponentCatalog() {
		if definition.ID != reconciler.ComponentTraexSessionManager {
			excluded = append(excluded, definition.ID)
		}
	}
	return reconciler.Request{
		Home:            home,
		WorkstationRoot: workstationRoot,
		Target:          platform.TargetDarwinARM64,
		Host: platform.Host{
			OS:      platform.OSDarwin,
			Arch:    platform.ArchARM64,
			Family:  platform.FamilyMacOS,
			Version: "13.0",
		},
		ReplaceScope: true,
		Exclude:      excluded,
		Capabilities: map[reconciler.Capability]bool{
			reconciler.CapabilityCurl:           true,
			reconciler.CapabilityTar:            true,
			reconciler.CapabilitySHA256Verifier: true,
		},
		InstallerStdout: io.Discard,
		InstallerStderr: io.Discard,
	}
}

func tsmAndGitConfigRequest(home string, workstationRoot string) reconciler.Request {
	req := tsmOnlyRequest(home, workstationRoot)
	for index, component := range req.Exclude {
		if component == reconciler.ComponentGitConfig {
			req.Exclude = append(req.Exclude[:index], req.Exclude[index+1:]...)
			break
		}
	}
	return req
}

func containsCapabilityForTest(capabilities []reconciler.Capability, want reconciler.Capability) bool {
	for _, capability := range capabilities {
		if capability == want {
			return true
		}
	}
	return false
}

func blockerContains(blockers []reconciler.Blocker, want string) bool {
	for _, blocker := range blockers {
		if strings.Contains(blocker.Message, want) {
			return true
		}
	}
	return false
}

func changeByKind(changes []reconciler.Change, kind reconciler.ChangeKind) *reconciler.Change {
	for index := range changes {
		if changes[index].Kind == kind {
			return &changes[index]
		}
	}
	return nil
}
