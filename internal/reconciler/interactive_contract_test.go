package reconciler_test

import (
	"context"
	"errors"
	"path/filepath"
	"strings"
	"testing"

	"github.com/Plasticine-Yang/plasticine-dotfiles/internal/platform"
	"github.com/Plasticine-Yang/plasticine-dotfiles/internal/reconciler"
)

func TestStructuredAuthorizationReceivesDefensiveImmutablePlan(t *testing.T) {
	t.Parallel()

	r := contractReconciler()
	req := contractRequest(t.TempDir())
	expectedPath := filepath.Join(req.Home, "config", "git", "config")
	req.Authorize = func(_ context.Context, plan reconciler.Result) reconciler.AuthorizationDecision {
		if len(plan.Changes) == 0 {
			t.Fatal("authorization received no changes")
		}
		plan.Changes[0].Path = filepath.Join(req.Home, "mutated-by-authorizer")
		plan.Scope.Excluded = nil
		return reconciler.AuthorizationDecision{
			Approved:           true,
			AllowSystemChanges: true,
			AllowAdoption:      true,
			AllowRetirements:   true,
		}
	}

	result, err := r.Apply(context.Background(), req)
	if err != nil {
		t.Fatalf("apply: %v", err)
	}
	if result.Outcome != reconciler.OutcomeApplied {
		t.Fatalf("outcome = %s blockers=%#v", result.Outcome, result.Blockers)
	}
	if !pathExists(expectedPath) {
		t.Fatalf("authorizer mutation changed the executed plan; missing %s", expectedPath)
	}
	if pathExists(filepath.Join(req.Home, "mutated-by-authorizer")) {
		t.Fatal("authorizer-controlled path was executed")
	}
}

func TestStructuredAuthorizationRequiresEachRiskClassBeforeMutation(t *testing.T) {
	t.Parallel()

	t.Run("system change", func(t *testing.T) {
		r := contractReconciler()
		req := contractRequest(t.TempDir())
		req.RequireSystemChange = true
		req.Authorize = approveOrdinaryOnly

		result, err := r.Apply(context.Background(), req)
		if err != nil {
			t.Fatalf("apply: %v", err)
		}
		if result.Outcome != reconciler.OutcomeBlocked || !hasBlocker(result.Blockers, reconciler.BlockerSystemChangeAuthorization) {
			t.Fatalf("outcome=%s blockers=%#v", result.Outcome, result.Blockers)
		}
		if pathExists(reconciler.StatePath(req.Home)) {
			t.Fatal("system authorization denial wrote state")
		}
	})

	t.Run("adoption", func(t *testing.T) {
		r := contractReconciler()
		req := contractRequest(t.TempDir())
		conflictPath := filepath.Join(req.WorkstationRoot, ".gitconfig")
		writeText(t, conflictPath, "[user]\n  name = Owner\n")
		req.Adopt = true
		req.Authorize = approveOrdinaryOnly

		result, err := r.Apply(context.Background(), req)
		if err != nil {
			t.Fatalf("apply: %v", err)
		}
		if result.Outcome != reconciler.OutcomeDenied {
			t.Fatalf("outcome=%s blockers=%#v", result.Outcome, result.Blockers)
		}
		if got := readText(t, conflictPath); !strings.Contains(got, "Owner") {
			t.Fatalf("adoption denial changed conflict: %q", got)
		}
		if pathExists(reconciler.StatePath(req.Home)) {
			t.Fatal("adoption denial wrote state")
		}
	})

	t.Run("retirement", func(t *testing.T) {
		r := contractReconciler()
		req := contractRequest(t.TempDir())
		req.Yes = true
		if _, err := r.Apply(context.Background(), req); err != nil {
			t.Fatalf("seed apply: %v", err)
		}
		state, err := reconciler.ReadState(req.Home)
		if err != nil {
			t.Fatalf("read state: %v", err)
		}
		retiredPath := filepath.Join(req.Home, "legacy", "retire-me")
		writeText(t, retiredPath, "managed")
		state.Ownership[retiredPath] = reconciler.Ownership{
			Component:    reconciler.ComponentGitConfig,
			Path:         retiredPath,
			ResourceKind: reconciler.ResourceManagedPath,
			Digest:       testDigest("managed"),
			AcceptedAt:   state.AppliedAt,
		}
		writeStateJSON(t, req.Home, state)

		req.Yes = false
		req.Authorize = approveOrdinaryOnly
		result, err := r.Apply(context.Background(), req)
		if err != nil {
			t.Fatalf("retirement apply: %v", err)
		}
		if result.Outcome != reconciler.OutcomeDenied {
			t.Fatalf("outcome=%s blockers=%#v", result.Outcome, result.Blockers)
		}
		if !pathExists(retiredPath) {
			t.Fatal("retirement denial deleted the managed path")
		}
	})
}

func TestTerminalRunnerReceivesSystemCommandsWithoutShellInterpolation(t *testing.T) {
	t.Parallel()

	r := reconciler.New(reconciler.Options{
		DesiredStateID: "terminal-runner-test",
		ToolLockSHA256: strings.Repeat("d", 64),
		System:         reconciler.LocalSystemAdapter{},
	})
	req := reconciler.Request{
		Home:            t.TempDir(),
		WorkstationRoot: t.TempDir(),
		Target:          platform.TargetLinuxAMD64,
		Host: platform.Host{
			OS:      platform.OSLinux,
			Arch:    platform.ArchAMD64,
			Family:  platform.FamilyDebian,
			Version: "12",
		},
		ReplaceScope: true,
		Exclude: []reconciler.ComponentID{
			reconciler.ComponentShell,
			reconciler.ComponentGitHubSSH,
			reconciler.ComponentNeovim,
			reconciler.ComponentLazygit,
			reconciler.ComponentFNM,
			reconciler.ComponentUV,
			reconciler.ComponentZellij,
		},
		Capabilities: map[reconciler.Capability]bool{
			reconciler.CapabilityGit: false,
		},
		Yes:         true,
		AllowSystem: true,
	}
	var commands []reconciler.TerminalCommand
	req.TerminalRunner = func(_ context.Context, command reconciler.TerminalCommand) error {
		commands = append(commands, command)
		return nil
	}

	if _, err := r.Apply(context.Background(), req); err != nil {
		t.Fatalf("apply: %v", err)
	}
	if len(commands) != 2 {
		t.Fatalf("terminal commands = %#v, want apt update and install", commands)
	}
	if commands[0].Name != "sudo" || strings.Join(commands[0].Args, " ") != "apt-get update" || !commands[0].RequiresTerminal {
		t.Fatalf("first terminal command = %#v", commands[0])
	}
	if commands[1].Name != "sudo" || strings.Join(commands[1].Args, " ") != "apt-get install -y --no-install-recommends git" {
		t.Fatalf("second terminal command = %#v", commands[1])
	}
}

func TestProgressRedactsSecretReferencePath(t *testing.T) {
	t.Parallel()

	r := contractReconciler()
	req := contractRequest(t.TempDir())
	req.Exclude = []reconciler.ComponentID{
		reconciler.ComponentNeovim,
		reconciler.ComponentLazygit,
		reconciler.ComponentFNM,
		reconciler.ComponentUV,
		reconciler.ComponentZellij,
	}
	req.LoginShellKnown = true
	req.LoginShell = "/bin/zsh"
	req.ZshPath = "/bin/zsh"
	keyPath := filepath.Join(req.Home, "private-owner-key")
	generateSSHKey(t, keyPath)
	req.GitHubKeyPath = keyPath
	req.Yes = true
	var events []reconciler.ProgressEvent
	req.Progress = func(event reconciler.ProgressEvent) {
		events = append(events, event)
	}

	if _, err := r.Apply(context.Background(), req); err != nil {
		t.Fatalf("apply: %v", err)
	}
	foundSecretReference := false
	for _, event := range events {
		if strings.Contains(event.Path, keyPath) || strings.Contains(event.Summary, keyPath) {
			t.Fatalf("progress leaked private key path: %#v", event)
		}
		if event.ChangeKind == reconciler.ChangeSecretReference {
			foundSecretReference = true
			if event.Path != "" || event.Summary != "update Secret Reference" {
				t.Fatalf("secret progress was not redacted: %#v", event)
			}
		}
	}
	if !foundSecretReference {
		t.Fatalf("progress events missing Secret Reference lifecycle: %#v", events)
	}
}

func TestProgressCoversScopeAdoptionAndManagedResources(t *testing.T) {
	t.Parallel()

	r := contractReconciler()
	req := contractRequest(t.TempDir())
	conflictPath := filepath.Join(req.WorkstationRoot, ".gitconfig")
	writeText(t, conflictPath, "[user]\n  name = Owner\n")
	req.Yes = true
	req.Adopt = true
	var events []reconciler.ProgressEvent
	req.Progress = func(event reconciler.ProgressEvent) {
		events = append(events, event)
	}

	result, err := r.Apply(context.Background(), req)
	if err != nil {
		t.Fatalf("apply: %v", err)
	}
	if result.Outcome != reconciler.OutcomeApplied {
		t.Fatalf("outcome=%s blockers=%#v", result.Outcome, result.Blockers)
	}
	for _, want := range []eventMatch{
		{kind: reconciler.ProgressOperation, status: reconciler.ProgressStarted, operation: "apply"},
		{kind: reconciler.ProgressChange, status: reconciler.ProgressStarted, changeKind: reconciler.ChangeScopeReplacement},
		{kind: reconciler.ProgressChange, status: reconciler.ProgressSucceeded, changeKind: reconciler.ChangeScopeReplacement},
		{kind: reconciler.ProgressChange, status: reconciler.ProgressStarted, changeKind: reconciler.ChangeAdoptConflict, path: conflictPath},
		{kind: reconciler.ProgressChange, status: reconciler.ProgressSucceeded, changeKind: reconciler.ChangeAdoptConflict, path: conflictPath},
		{kind: reconciler.ProgressChange, status: reconciler.ProgressSucceeded, resourceKind: reconciler.ResourceManagedPath},
		{kind: reconciler.ProgressComponent, status: reconciler.ProgressSucceeded, component: reconciler.ComponentGitConfig},
		{kind: reconciler.ProgressOperation, status: reconciler.ProgressSucceeded, operation: "apply"},
	} {
		if !hasProgressEvent(events, want) {
			t.Fatalf("events missing %#v:\n%#v", want, events)
		}
	}
}

func TestProgressCoversRetirementAndPartialFailure(t *testing.T) {
	t.Parallel()

	t.Run("retirement", func(t *testing.T) {
		r := contractReconciler()
		req := contractRequest(t.TempDir())
		req.Yes = true
		if _, err := r.Apply(context.Background(), req); err != nil {
			t.Fatalf("seed apply: %v", err)
		}
		state, err := reconciler.ReadState(req.Home)
		if err != nil {
			t.Fatalf("read state: %v", err)
		}
		retiredPath := filepath.Join(req.Home, "legacy", "retired-resource")
		writeText(t, retiredPath, "managed")
		state.Ownership[retiredPath] = reconciler.Ownership{
			Component:    reconciler.ComponentGitConfig,
			Path:         retiredPath,
			ResourceKind: reconciler.ResourceManagedPath,
			Digest:       testDigest("managed"),
			AcceptedAt:   state.AppliedAt,
		}
		writeStateJSON(t, req.Home, state)

		var events []reconciler.ProgressEvent
		req.Progress = func(event reconciler.ProgressEvent) {
			events = append(events, event)
		}
		result, err := r.Apply(context.Background(), req)
		if err != nil {
			t.Fatalf("retirement apply: %v", err)
		}
		if result.Outcome != reconciler.OutcomeApplied {
			t.Fatalf("outcome=%s blockers=%#v", result.Outcome, result.Blockers)
		}
		for _, status := range []reconciler.ProgressStatus{reconciler.ProgressStarted, reconciler.ProgressSucceeded} {
			if !hasProgressEvent(events, eventMatch{
				kind:       reconciler.ProgressChange,
				status:     status,
				changeKind: reconciler.ChangeRetireResource,
				path:       retiredPath,
			}) {
				t.Fatalf("retirement events missing %s:\n%#v", status, events)
			}
		}
	})

	t.Run("managed path partial failure", func(t *testing.T) {
		r := contractReconciler()
		req := contractRequest(t.TempDir())
		req.Yes = true
		failedPath := filepath.Join(req.Home, "config", "git", "config")
		req.FailBeforeEffectPath = failedPath
		var events []reconciler.ProgressEvent
		req.Progress = func(event reconciler.ProgressEvent) {
			events = append(events, event)
		}
		result, err := r.Apply(context.Background(), req)
		if err != nil {
			t.Fatalf("partial apply: %v", err)
		}
		if result.Outcome != reconciler.OutcomePartial {
			t.Fatalf("outcome=%s blockers=%#v", result.Outcome, result.Blockers)
		}
		for _, want := range []eventMatch{
			{kind: reconciler.ProgressChange, status: reconciler.ProgressFailed, path: failedPath},
			{kind: reconciler.ProgressComponent, status: reconciler.ProgressFailed, component: reconciler.ComponentGitConfig},
			{kind: reconciler.ProgressOperation, status: reconciler.ProgressFailed, operation: "apply"},
		} {
			if !hasProgressEvent(events, want) {
				t.Fatalf("partial events missing %#v:\n%#v", want, events)
			}
		}
	})
}

func TestProgressCoversSystemOwnerAction(t *testing.T) {
	t.Parallel()

	system := &recordingSystemAdapter{
		err:     errors.Join(reconciler.ErrOwnerActionRequired, errors.New("complete installer")),
		missing: []reconciler.Capability{reconciler.CapabilityGit},
	}
	r := reconciler.New(reconciler.Options{
		DesiredStateID: "owner-action-progress",
		ToolLockSHA256: strings.Repeat("e", 64),
		System:         system,
	})
	req := contractRequest(t.TempDir())
	req.RequireSystemChange = true
	req.Yes = true
	req.AllowSystem = true
	var events []reconciler.ProgressEvent
	req.Progress = func(event reconciler.ProgressEvent) {
		events = append(events, event)
	}

	result, err := r.Apply(context.Background(), req)
	if err != nil {
		t.Fatalf("apply: %v", err)
	}
	if result.Outcome != reconciler.OutcomePartial || !hasBlocker(result.Blockers, reconciler.BlockerOwnerActionRequired) {
		t.Fatalf("outcome=%s blockers=%#v", result.Outcome, result.Blockers)
	}
	if !hasProgressEvent(events, eventMatch{
		kind:       reconciler.ProgressChange,
		status:     reconciler.ProgressAwaitingOwnerAction,
		changeKind: reconciler.ChangeSystemDependency,
	}) {
		t.Fatalf("owner action event missing:\n%#v", events)
	}
	if !hasProgressEvent(events, eventMatch{
		kind:      reconciler.ProgressComponent,
		status:    reconciler.ProgressAwaitingOwnerAction,
		component: reconciler.ComponentShell,
	}) {
		t.Fatalf("Owner action Component event missing:\n%#v", events)
	}
}

type eventMatch struct {
	kind         reconciler.ProgressKind
	status       reconciler.ProgressStatus
	operation    string
	component    reconciler.ComponentID
	changeKind   reconciler.ChangeKind
	resourceKind reconciler.ResourceKind
	path         string
}

func hasProgressEvent(events []reconciler.ProgressEvent, want eventMatch) bool {
	for _, event := range events {
		if event.Kind != want.kind || event.Status != want.status {
			continue
		}
		if want.operation != "" && event.Operation != want.operation {
			continue
		}
		if want.component != "" && event.Component != want.component {
			continue
		}
		if want.changeKind != "" && event.ChangeKind != want.changeKind {
			continue
		}
		if want.resourceKind != "" && event.ResourceKind != want.resourceKind {
			continue
		}
		if want.path != "" && event.Path != want.path {
			continue
		}
		return true
	}
	return false
}

func approveOrdinaryOnly(context.Context, reconciler.Result) reconciler.AuthorizationDecision {
	return reconciler.AuthorizationDecision{Approved: true}
}
