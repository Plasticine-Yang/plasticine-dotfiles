package reconciler_test

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/Plasticine-Yang/plasticine-dotfiles/internal/platform"
	"github.com/Plasticine-Yang/plasticine-dotfiles/internal/reconciler"
	"github.com/Plasticine-Yang/plasticine-dotfiles/internal/release"
)

func TestApplyMaterializesDesiredStateAndDoctorChecksOwnership(t *testing.T) {
	t.Parallel()

	r := contractReconciler()
	req := contractRequest(t.TempDir())

	plan, err := r.Plan(context.Background(), req)
	if err != nil {
		t.Fatalf("plan: %v", err)
	}
	if plan.Outcome != reconciler.OutcomeChangesPlanned {
		t.Fatalf("plan outcome = %s, want %s", plan.Outcome, reconciler.OutcomeChangesPlanned)
	}
	if pathExists(reconciler.StatePath(req.Home)) {
		t.Fatalf("plan wrote state at %s", reconciler.StatePath(req.Home))
	}
	if !hasChange(plan.Changes, reconciler.ComponentGitConfig, reconciler.ResourceManagedPath) {
		t.Fatalf("plan changes = %#v, want git-config managed path", plan.Changes)
	}

	req.Yes = true
	applied, err := r.Apply(context.Background(), req)
	if err != nil {
		t.Fatalf("apply: %v", err)
	}
	if applied.Outcome != reconciler.OutcomeApplied {
		t.Fatalf("apply outcome = %s, want %s", applied.Outcome, reconciler.OutcomeApplied)
	}
	if info, err := os.Stat(req.Home); err != nil || info.Mode().Perm() != 0o700 {
		t.Fatalf("home mode = %v, %v; want 0700", info, err)
	}
	gitConfig := filepath.Join(req.Home, "config", "git", "config")
	if content := readText(t, gitConfig); strings.Contains(content, "credential") || strings.Contains(content, "helper = store") {
		t.Fatalf("git Desired State contains plaintext credential helper:\n%s", content)
	}
	for _, path := range []string{
		gitConfig,
		filepath.Join(req.Home, "workstation", ".gitconfig"),
	} {
		if !pathExists(path) {
			t.Fatalf("expected materialized path %s", path)
		}
	}

	state, err := reconciler.ReadState(req.Home)
	if err != nil {
		t.Fatalf("read state: %v", err)
	}
	if state.SchemaVersion != reconciler.CurrentStateSchema {
		t.Fatalf("schema = %d, want %d", state.SchemaVersion, reconciler.CurrentStateSchema)
	}
	if _, ok := state.Ownership[gitConfig]; !ok {
		t.Fatalf("state ownership missing git config: %#v", state.Ownership)
	}

	second, err := r.Apply(context.Background(), req)
	if err != nil {
		t.Fatalf("second apply: %v", err)
	}
	if second.Outcome != reconciler.OutcomeNoChange {
		t.Fatalf("second apply outcome = %s, want %s", second.Outcome, reconciler.OutcomeNoChange)
	}

	doctor, err := r.Doctor(context.Background(), req)
	if err != nil {
		t.Fatalf("doctor: %v", err)
	}
	if doctor.Outcome != reconciler.OutcomeHealthy {
		t.Fatalf("doctor outcome = %s checks=%#v", doctor.Outcome, doctor.Checks)
	}
}

func TestScopeSuspendsGitConfigWithoutObservingCompanyGit(t *testing.T) {
	t.Parallel()

	r := contractReconciler()
	req := contractRequest(t.TempDir())
	req.Yes = true
	if _, err := r.Apply(context.Background(), req); err != nil {
		t.Fatalf("initial apply: %v", err)
	}
	gitShim := filepath.Join(req.Home, "workstation", ".gitconfig")

	req.ReplaceScope = true
	req.Exclude = []reconciler.ComponentID{
		reconciler.ComponentGitConfig,
		reconciler.ComponentGitHubSSH,
		reconciler.ComponentNeovim,
		reconciler.ComponentLazygit,
		reconciler.ComponentFNM,
		reconciler.ComponentUV,
	}
	scoped, err := r.Apply(context.Background(), req)
	if err != nil {
		t.Fatalf("scope apply: %v", err)
	}
	if scoped.Outcome != reconciler.OutcomeApplied {
		t.Fatalf("scope apply outcome = %s", scoped.Outcome)
	}
	writeText(t, gitShim, "[user]\n  name = Company Managed\n")

	req.ReplaceScope = false
	req.Exclude = nil
	plainPlan, err := r.Plan(context.Background(), req)
	if err != nil {
		t.Fatalf("plain plan: %v", err)
	}
	if plainPlan.Outcome != reconciler.OutcomeNoChange {
		t.Fatalf("plain plan outcome = %s conflicts=%#v", plainPlan.Outcome, plainPlan.Conflicts)
	}
	if len(plainPlan.Conflicts) != 0 {
		t.Fatalf("suspended git-config was observed: %#v", plainPlan.Conflicts)
	}

	req.ReplaceScope = true
	req.Exclude = []reconciler.ComponentID{
		reconciler.ComponentGitHubSSH,
		reconciler.ComponentNeovim,
		reconciler.ComponentLazygit,
		reconciler.ComponentFNM,
		reconciler.ComponentUV,
	}
	reenable, err := r.Plan(context.Background(), req)
	if err != nil {
		t.Fatalf("reenable plan: %v", err)
	}
	if reenable.Outcome != reconciler.OutcomeBlocked || !hasBlocker(reenable.Blockers, reconciler.BlockerConflict) {
		t.Fatalf("reenable outcome = %s blockers=%#v conflicts=%#v", reenable.Outcome, reenable.Blockers, reenable.Conflicts)
	}
}

func TestAdoptionCreatesUniqueBackupsBeforeReplacingHumanContent(t *testing.T) {
	t.Parallel()

	r := contractReconciler()
	req := contractRequest(t.TempDir())
	humanPath := filepath.Join(req.Home, "workstation", ".gitconfig")
	writeText(t, humanPath, "[user]\n  name = Human\n")

	blocked, err := r.Plan(context.Background(), req)
	if err != nil {
		t.Fatalf("plan: %v", err)
	}
	if blocked.Outcome != reconciler.OutcomeBlocked || !hasBlocker(blocked.Blockers, reconciler.BlockerConflict) {
		t.Fatalf("plan outcome=%s blockers=%#v conflicts=%#v", blocked.Outcome, blocked.Blockers, blocked.Conflicts)
	}
	if strings.Contains(blocked.Conflicts[0].Reason, "Human") {
		t.Fatalf("conflict leaked content: %#v", blocked.Conflicts[0])
	}

	req.Yes = true
	req.Adopt = true
	applied, err := r.Apply(context.Background(), req)
	if err != nil {
		t.Fatalf("apply adopt: %v", err)
	}
	if applied.Outcome != reconciler.OutcomeApplied {
		t.Fatalf("apply outcome = %s blockers=%#v", applied.Outcome, applied.Blockers)
	}
	state, err := reconciler.ReadState(req.Home)
	if err != nil {
		t.Fatalf("read state: %v", err)
	}
	if len(state.Backups) != 1 {
		t.Fatalf("backup count = %d, want 1", len(state.Backups))
	}
	if got := readText(t, state.Backups[0].Backup); !strings.Contains(got, "Human") {
		t.Fatalf("backup did not preserve human content: %q", got)
	}

	second, err := r.Apply(context.Background(), req)
	if err != nil {
		t.Fatalf("second apply: %v", err)
	}
	if second.Outcome != reconciler.OutcomeNoChange {
		t.Fatalf("second apply outcome = %s", second.Outcome)
	}
	state, err = reconciler.ReadState(req.Home)
	if err != nil {
		t.Fatalf("read state again: %v", err)
	}
	if len(state.Backups) != 1 {
		t.Fatalf("second apply created another backup: %#v", state.Backups)
	}
}

func TestStateMigrationAndPendingWorkRecoveryAreExplicit(t *testing.T) {
	t.Parallel()

	r := contractReconciler()
	req := contractRequest(t.TempDir())
	legacy := []byte(`{"desired_state_id":"legacy","tool_lock_sha256":"legacy","target":"darwin/arm64"}` + "\n")
	if err := os.MkdirAll(filepath.Dir(reconciler.StatePath(req.Home)), 0o700); err != nil {
		t.Fatalf("mkdir state: %v", err)
	}
	if err := os.WriteFile(reconciler.StatePath(req.Home), legacy, 0o600); err != nil {
		t.Fatalf("write legacy state: %v", err)
	}

	plan, err := r.Plan(context.Background(), req)
	if err != nil {
		t.Fatalf("plan migration: %v", err)
	}
	if plan.StateMigration == nil || plan.StateMigration.FromSchema != 0 {
		t.Fatalf("migration = %#v, want legacy migration", plan.StateMigration)
	}
	if got := readText(t, reconciler.StatePath(req.Home)); got != string(legacy) {
		t.Fatalf("plan mutated legacy state: %q", got)
	}

	req.Yes = true
	if _, err := r.Apply(context.Background(), req); err != nil {
		t.Fatalf("apply migration: %v", err)
	}
	state, err := reconciler.ReadState(req.Home)
	if err != nil {
		t.Fatalf("read migrated state: %v", err)
	}
	state.PendingWork = []reconciler.JournalEntry{{
		Component:    reconciler.ComponentGitConfig,
		Path:         filepath.Join(req.Home, "config", "git", "config"),
		ResourceKind: reconciler.ResourceManagedPath,
		Intent:       "interrupted-test",
	}}
	writeStateJSON(t, req.Home, state)

	pendingPlan, err := r.Plan(context.Background(), req)
	if err != nil {
		t.Fatalf("plan pending: %v", err)
	}
	if pendingPlan.Outcome != reconciler.OutcomeBlocked || !hasBlocker(pendingPlan.Blockers, reconciler.BlockerPendingWork) {
		t.Fatalf("pending plan outcome=%s blockers=%#v", pendingPlan.Outcome, pendingPlan.Blockers)
	}

	recovered, err := r.Apply(context.Background(), req)
	if err != nil {
		t.Fatalf("recover apply: %v", err)
	}
	if recovered.Outcome != reconciler.OutcomeNoChange {
		t.Fatalf("recover apply outcome = %s", recovered.Outcome)
	}
	state, err = reconciler.ReadState(req.Home)
	if err != nil {
		t.Fatalf("read recovered state: %v", err)
	}
	if len(state.PendingWork) != 0 {
		t.Fatalf("pending work was not cleared: %#v", state.PendingWork)
	}
}

func TestGitHubSSHSecretReferenceManagedBlockAndMacKeychain(t *testing.T) {
	t.Parallel()

	r := contractReconciler()
	req := contractRequest(t.TempDir())
	key := filepath.Join(req.Home, "id_ed25519")
	generateSSHKey(t, key)
	sshConfig := filepath.Join(req.Home, "workstation", ".ssh", "config")
	writeText(t, sshConfig, "Host internal\n  HostName git.internal\n")

	req.ReplaceScope = true
	req.Exclude = []reconciler.ComponentID{
		reconciler.ComponentNeovim,
		reconciler.ComponentLazygit,
		reconciler.ComponentFNM,
		reconciler.ComponentUV,
	}
	req.IncludeGitHubSSH = true
	req.GitHubKeyPath = key
	blocked, err := r.Plan(context.Background(), req)
	if err != nil {
		t.Fatalf("plan github ssh: %v", err)
	}
	if blocked.Outcome != reconciler.OutcomeBlocked || !hasBlocker(blocked.Blockers, reconciler.BlockerConflict) {
		t.Fatalf("plan outcome=%s blockers=%#v conflicts=%#v", blocked.Outcome, blocked.Blockers, blocked.Conflicts)
	}

	req.Yes = true
	req.Adopt = true
	applied, err := r.Apply(context.Background(), req)
	if err != nil {
		t.Fatalf("apply github ssh: %v", err)
	}
	if applied.Outcome != reconciler.OutcomeApplied {
		t.Fatalf("apply outcome = %s blockers=%#v", applied.Outcome, applied.Blockers)
	}
	config := readText(t, sshConfig)
	if !strings.Contains(config, "Host internal") || !strings.Contains(config, "BEGIN PLASTICINE GITHUB SSH") {
		t.Fatalf("ssh config did not preserve outside bytes and managed block:\n%s", config)
	}
	if !pathExists(filepath.Join(req.Home, "config", "ssh", "macos-keychain")) {
		t.Fatalf("macOS Keychain integration marker was not materialized")
	}
	stateBytes := readText(t, reconciler.StatePath(req.Home))
	if strings.Contains(stateBytes, readText(t, key)) {
		t.Fatalf("state leaked private key material:\n%s", stateBytes)
	}

	if err := os.Chmod(key, 0o644); err != nil {
		t.Fatalf("chmod key: %v", err)
	}
	req.GitHubKeyPath = ""
	req.Adopt = false
	invalid, err := r.Plan(context.Background(), req)
	if err != nil {
		t.Fatalf("plan invalid secret: %v", err)
	}
	if invalid.Outcome != reconciler.OutcomeBlocked || !hasBlocker(invalid.Blockers, reconciler.BlockerSecretReferenceRequired) {
		t.Fatalf("invalid secret outcome=%s blockers=%#v", invalid.Outcome, invalid.Blockers)
	}
}

func TestSystemDependenciesRequireIndependentAuthorization(t *testing.T) {
	t.Parallel()

	system := &recordingSystemAdapter{}
	r := reconciler.New(reconciler.Options{
		DesiredStateID: "desired-state-contract",
		ToolLockSHA256: strings.Repeat("c", 64),
		System:         system,
		Clock: func() time.Time {
			return time.Date(2026, 7, 11, 3, 0, 0, 0, time.UTC)
		},
	})
	req := contractRequest(t.TempDir())
	req.Target = platform.TargetLinuxAMD64
	req.Host = platform.Host{
		OS:      platform.OSLinux,
		Arch:    platform.ArchAMD64,
		Family:  platform.FamilyDebian,
		Version: "12",
	}
	req.Capabilities = map[reconciler.Capability]bool{
		reconciler.CapabilityGit: false,
		reconciler.CapabilityZsh: false,
		reconciler.CapabilityCA:  false,
	}

	plan, err := r.Plan(context.Background(), req)
	if err != nil {
		t.Fatalf("plan: %v", err)
	}
	if plan.Outcome != reconciler.OutcomeChangesPlanned || !hasSystemChange(plan.Changes) {
		t.Fatalf("plan outcome=%s changes=%#v", plan.Outcome, plan.Changes)
	}

	req.Yes = true
	denied, err := r.Apply(context.Background(), req)
	if err != nil {
		t.Fatalf("apply without allow-system: %v", err)
	}
	if denied.Outcome != reconciler.OutcomeBlocked || !hasBlocker(denied.Blockers, reconciler.BlockerSystemChangeAuthorization) {
		t.Fatalf("apply outcome=%s blockers=%#v", denied.Outcome, denied.Blockers)
	}
	if pathExists(reconciler.StatePath(req.Home)) {
		t.Fatalf("system-change denial wrote state")
	}

	req.AllowSystem = true
	applied, err := r.Apply(context.Background(), req)
	if err != nil {
		t.Fatalf("authorized apply: %v", err)
	}
	if applied.Outcome != reconciler.OutcomeApplied {
		t.Fatalf("authorized apply outcome = %s", applied.Outcome)
	}
	if len(system.applied) != 1 {
		t.Fatalf("system apply count = %d, want 1", len(system.applied))
	}

	unsupported := req
	unsupported.Home = t.TempDir()
	unsupported.Host.Family = platform.FamilyOtherLinux
	unsupported.Host.Version = "39"
	blocked, err := r.Plan(context.Background(), unsupported)
	if err != nil {
		t.Fatalf("unsupported plan: %v", err)
	}
	if blocked.Outcome != reconciler.OutcomeBlocked || !hasBlocker(blocked.Blockers, reconciler.BlockerUnsupportedSystemChange) {
		t.Fatalf("unsupported outcome=%s blockers=%#v", blocked.Outcome, blocked.Blockers)
	}
}

func TestManagedToolInstallDownloadsVerifiesCachesAndReusesArtifact(t *testing.T) {
	t.Parallel()

	artifact := []byte("#!/bin/sh\nprintf 'lazygit fixture\\n'\n")
	artifactSHA := testDigestBytes(artifact)
	hits := 0
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		hits++
		_, _ = w.Write(artifact)
	}))
	t.Cleanup(server.Close)

	r := reconciler.New(reconciler.Options{
		DesiredStateID: "managed-tool-contract",
		ToolLockSHA256: artifactSHA,
		ToolLock: release.ToolLock{Tools: map[release.ManagedTool]release.ToolVersion{
			release.ManagedToolLazygit: {
				Version: "v-test",
				Targets: map[platform.ArtifactTarget]release.ToolArtifact{
					platform.TargetDarwinARM64: {
						URL:          server.URL + "/lazygit",
						ArtifactType: release.ArtifactTypeRawExecutable,
						SHA256:       artifactSHA,
					},
				},
			},
		}},
		Clock: func() time.Time {
			return time.Date(2026, 7, 11, 3, 0, 0, 0, time.UTC)
		},
	})
	req := contractRequest(t.TempDir())
	req.Exclude = []reconciler.ComponentID{reconciler.ComponentGitHubSSH}
	req.Components = []reconciler.ComponentID{reconciler.ComponentLazygit}
	req.Yes = true

	applied, err := r.Apply(context.Background(), req)
	if err != nil {
		t.Fatalf("apply managed tool: %v", err)
	}
	if applied.Outcome != reconciler.OutcomeApplied {
		t.Fatalf("apply outcome = %s", applied.Outcome)
	}
	cachePath := filepath.Join(req.Home, "cache", "artifacts", artifactSHA)
	if got := readText(t, cachePath); got != string(artifact) {
		t.Fatalf("cache content = %q, want artifact", got)
	}
	payloadPath := filepath.Join(req.Home, "tools", "lazygit", "v-test", "lazygit")
	if got := readText(t, payloadPath); got != string(artifact) {
		t.Fatalf("payload content = %q, want artifact", got)
	}
	linkTarget, err := os.Readlink(filepath.Join(req.Home, "bin", "lg"))
	if err != nil {
		t.Fatalf("read lg symlink: %v", err)
	}
	if linkTarget != payloadPath {
		t.Fatalf("lg symlink = %q, want %q", linkTarget, payloadPath)
	}

	second, err := r.Apply(context.Background(), req)
	if err != nil {
		t.Fatalf("second apply: %v", err)
	}
	if second.Outcome != reconciler.OutcomeNoChange {
		t.Fatalf("second apply outcome = %s", second.Outcome)
	}
	if hits != 1 {
		t.Fatalf("artifact downloads = %d, want 1", hits)
	}
}

func TestManagedToolChecksumMismatchDoesNotPromoteArtifact(t *testing.T) {
	t.Parallel()

	artifact := []byte("tampered artifact")
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_, _ = w.Write(artifact)
	}))
	t.Cleanup(server.Close)
	wantSHA := strings.Repeat("0", 64)
	r := reconciler.New(reconciler.Options{
		DesiredStateID: "managed-tool-contract",
		ToolLockSHA256: wantSHA,
		ToolLock: release.ToolLock{Tools: map[release.ManagedTool]release.ToolVersion{
			release.ManagedToolLazygit: {
				Version: "v-test",
				Targets: map[platform.ArtifactTarget]release.ToolArtifact{
					platform.TargetDarwinARM64: {
						URL:          server.URL + "/lazygit",
						ArtifactType: release.ArtifactTypeRawExecutable,
						SHA256:       wantSHA,
					},
				},
			},
		}},
	})
	req := contractRequest(t.TempDir())
	req.Exclude = []reconciler.ComponentID{reconciler.ComponentGitHubSSH}
	req.Components = []reconciler.ComponentID{reconciler.ComponentLazygit}
	req.Yes = true

	result, err := r.Apply(context.Background(), req)
	if err != nil {
		t.Fatalf("apply returned error instead of structured partial: %v", err)
	}
	if result.Outcome != reconciler.OutcomePartial || !hasBlocker(result.Blockers, reconciler.BlockerOperationalFailure) {
		t.Fatalf("apply outcome=%s blockers=%#v, want partial operational failure", result.Outcome, result.Blockers)
	}
	if pathExists(filepath.Join(req.Home, "cache", "artifacts", wantSHA)) {
		t.Fatalf("checksum-mismatched artifact was promoted to cache")
	}
	if pathExists(filepath.Join(req.Home, "bin", "lazygit")) {
		t.Fatalf("launcher was materialized after checksum mismatch")
	}
}

func TestRetirementDeletesOnlyUnchangedOwnedResources(t *testing.T) {
	t.Parallel()

	r := contractReconciler()
	req := contractRequest(t.TempDir())
	req.Yes = true
	if _, err := r.Apply(context.Background(), req); err != nil {
		t.Fatalf("initial apply: %v", err)
	}
	state, err := reconciler.ReadState(req.Home)
	if err != nil {
		t.Fatalf("read state: %v", err)
	}
	retiredPath := filepath.Join(req.Home, "legacy", "old-git-shim")
	writeText(t, retiredPath, "old managed bytes")
	state.Ownership[retiredPath] = reconciler.Ownership{
		Component:    reconciler.ComponentGitConfig,
		Path:         retiredPath,
		ResourceKind: reconciler.ResourceManagedPath,
		Digest:       testDigest("old managed bytes"),
		AcceptedAt:   state.AppliedAt,
	}
	writeStateJSON(t, req.Home, state)

	plan, err := r.Plan(context.Background(), req)
	if err != nil {
		t.Fatalf("retirement plan: %v", err)
	}
	if plan.Outcome != reconciler.OutcomeChangesPlanned || len(plan.Retirements) != 1 {
		t.Fatalf("retirement plan outcome=%s retirements=%#v", plan.Outcome, plan.Retirements)
	}
	applied, err := r.Apply(context.Background(), req)
	if err != nil {
		t.Fatalf("retirement apply: %v", err)
	}
	if applied.Outcome != reconciler.OutcomeApplied {
		t.Fatalf("retirement apply outcome = %s", applied.Outcome)
	}
	if pathExists(retiredPath) {
		t.Fatalf("retired path still exists")
	}
	state, err = reconciler.ReadState(req.Home)
	if err != nil {
		t.Fatalf("read post-retirement state: %v", err)
	}
	if _, ok := state.Ownership[retiredPath]; ok {
		t.Fatalf("retired ownership was not released")
	}
}

func TestStalePlanPreconditionBlocksExternalEdits(t *testing.T) {
	t.Parallel()

	r := contractReconciler()
	req := contractRequest(t.TempDir())
	req.Yes = true
	called := false
	req.BeforeMutation = func(change reconciler.Change) {
		if called || change.Path == "" {
			return
		}
		called = true
		writeText(t, change.Path, "external edit wins")
	}

	result, err := r.Apply(context.Background(), req)
	if err != nil {
		t.Fatalf("apply: %v", err)
	}
	if result.Outcome != reconciler.OutcomeBlocked || !hasBlocker(result.Blockers, reconciler.BlockerStalePlan) {
		t.Fatalf("outcome=%s blockers=%#v", result.Outcome, result.Blockers)
	}
	if !called {
		t.Fatalf("test hook was not called")
	}
}

func TestDoctorAggregatesReadOnlyNetworkDiagnostics(t *testing.T) {
	t.Parallel()

	r := contractReconciler()
	req := contractRequest(t.TempDir())
	req.Yes = true
	if _, err := r.Apply(context.Background(), req); err != nil {
		t.Fatalf("apply: %v", err)
	}
	before := readText(t, reconciler.StatePath(req.Home))
	req.NetworkChecks = []reconciler.Check{
		{Name: "https-diagnostic", Healthy: false, Message: "timeout via https://user:pass@example.invalid"},
		{Name: "github-ssh", Healthy: true, Message: "skipped because github-ssh is inactive"},
	}
	doctor, err := r.Doctor(context.Background(), req)
	if err != nil {
		t.Fatalf("doctor: %v", err)
	}
	if doctor.Outcome != reconciler.OutcomeUnhealthy {
		t.Fatalf("doctor outcome = %s checks=%#v", doctor.Outcome, doctor.Checks)
	}
	for _, check := range doctor.Checks {
		if strings.Contains(check.Message, "user:pass") {
			t.Fatalf("doctor check leaked proxy credentials: %#v", check)
		}
	}
	if after := readText(t, reconciler.StatePath(req.Home)); after != before {
		t.Fatalf("doctor mutated state")
	}
}

func TestDoctorRunsConfiguredHTTPSDiagnosticTarget(t *testing.T) {
	t.Parallel()

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusNoContent)
	}))
	t.Cleanup(server.Close)
	r := reconciler.New(reconciler.Options{
		DesiredStateID: "doctor-online-contract",
		ToolLockSHA256: strings.Repeat("d", 64),
		DiagnosticURLs: []string{server.URL},
		Clock: func() time.Time {
			return time.Date(2026, 7, 11, 3, 0, 0, 0, time.UTC)
		},
	})
	req := contractRequest(t.TempDir())
	req.Yes = true
	if _, err := r.Apply(context.Background(), req); err != nil {
		t.Fatalf("apply: %v", err)
	}

	doctor, err := r.Doctor(context.Background(), req)
	if err != nil {
		t.Fatalf("doctor: %v", err)
	}
	if doctor.Outcome != reconciler.OutcomeHealthy {
		t.Fatalf("doctor outcome = %s checks=%#v", doctor.Outcome, doctor.Checks)
	}
	if !hasHealthyCheck(doctor.Checks, "https-diagnostic") {
		t.Fatalf("doctor checks = %#v, want healthy https diagnostic", doctor.Checks)
	}
}

func TestComponentGraphBlocksMissingDependenciesAndScopeExpansion(t *testing.T) {
	t.Parallel()

	r := contractReconciler()
	req := contractRequest(t.TempDir())
	req.ReplaceScope = true
	req.Exclude = []reconciler.ComponentID{
		reconciler.ComponentShell,
		reconciler.ComponentGitHubSSH,
		reconciler.ComponentNeovim,
		reconciler.ComponentLazygit,
		reconciler.ComponentUV,
	}

	plan, err := r.Plan(context.Background(), req)
	if err != nil {
		t.Fatalf("plan: %v", err)
	}
	if plan.Outcome != reconciler.OutcomeBlocked || !hasBlocker(plan.Blockers, reconciler.BlockerMissingComponentDependency) {
		t.Fatalf("dependency outcome=%s blockers=%#v", plan.Outcome, plan.Blockers)
	}

	req.Components = []reconciler.ComponentID{reconciler.ComponentShell}
	expanded, err := r.Plan(context.Background(), req)
	if err != nil {
		t.Fatalf("component plan: %v", err)
	}
	if expanded.Outcome != reconciler.OutcomeBlocked || !hasBlocker(expanded.Blockers, reconciler.BlockerComponentExcluded) {
		t.Fatalf("expanded outcome=%s blockers=%#v", expanded.Outcome, expanded.Blockers)
	}
}

func TestReconciliationLocksBlockConflictingOperations(t *testing.T) {
	t.Parallel()

	r := contractReconciler()
	req := contractRequest(t.TempDir())
	lockPath := filepath.Join(req.Home, "locks", "plasticine.lock")
	writeText(t, lockPath, "pid=123 command=plasticine apply\n")

	plan, err := r.Plan(context.Background(), req)
	if err != nil {
		t.Fatalf("plan with held exclusive lock: %v", err)
	}
	if plan.Outcome != reconciler.OutcomeBlocked || !hasBlocker(plan.Blockers, reconciler.BlockerLockHeld) {
		t.Fatalf("plan outcome=%s blockers=%#v", plan.Outcome, plan.Blockers)
	}
	if err := os.Remove(lockPath); err != nil {
		t.Fatalf("remove exclusive lock: %v", err)
	}

	sharedPath := filepath.Join(req.Home, "locks", "plasticine.shared", "reader.lock")
	writeText(t, sharedPath, "pid=456 command=plasticine plan\n")
	req.Yes = true
	applied, err := r.Apply(context.Background(), req)
	if err != nil {
		t.Fatalf("apply with held shared lock: %v", err)
	}
	if applied.Outcome != reconciler.OutcomeBlocked || !hasBlocker(applied.Blockers, reconciler.BlockerLockHeld) {
		t.Fatalf("apply outcome=%s blockers=%#v", applied.Outcome, applied.Blockers)
	}
}

func contractReconciler() reconciler.Reconciler {
	return reconciler.New(reconciler.Options{
		DesiredStateID: "desired-state-contract",
		ToolLockSHA256: strings.Repeat("c", 64),
		Clock: func() time.Time {
			return time.Date(2026, 7, 11, 3, 0, 0, 0, time.UTC)
		},
	})
}

func contractRequest(home string) reconciler.Request {
	return reconciler.Request{
		Home:            home,
		WorkstationRoot: filepath.Join(home, "workstation"),
		Target:          platform.TargetDarwinARM64,
		ReplaceScope:    true,
		Exclude: []reconciler.ComponentID{
			reconciler.ComponentGitHubSSH,
			reconciler.ComponentNeovim,
			reconciler.ComponentLazygit,
			reconciler.ComponentFNM,
			reconciler.ComponentUV,
		},
		Host: platform.Host{
			OS:      platform.OSDarwin,
			Arch:    platform.ArchARM64,
			Family:  platform.FamilyMacOS,
			Version: "13.0",
		},
	}
}

func hasChange(changes []reconciler.Change, component reconciler.ComponentID, kind reconciler.ResourceKind) bool {
	for _, change := range changes {
		if change.Component == component && change.ResourceKind == kind {
			return true
		}
	}
	return false
}

func hasSystemChange(changes []reconciler.Change) bool {
	for _, change := range changes {
		if change.SystemChange {
			return true
		}
	}
	return false
}

func hasHealthyCheck(checks []reconciler.Check, name string) bool {
	for _, check := range checks {
		if check.Name == name && check.Healthy {
			return true
		}
	}
	return false
}

func testDigest(value string) string {
	return testDigestBytes([]byte(value))
}

func testDigestBytes(value []byte) string {
	sum := sha256.Sum256(value)
	return hex.EncodeToString(sum[:])
}

func writeText(t *testing.T, path string, body string) {
	t.Helper()
	writeMode(t, path, body, 0o644)
}

func writeMode(t *testing.T, path string, body string, mode os.FileMode) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		t.Fatalf("mkdir %s: %v", filepath.Dir(path), err)
	}
	if err := os.WriteFile(path, []byte(body), mode); err != nil {
		t.Fatalf("write %s: %v", path, err)
	}
}

func readText(t *testing.T, path string) string {
	t.Helper()
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("read %s: %v", path, err)
	}
	return string(data)
}

func writeStateJSON(t *testing.T, home string, state reconciler.State) {
	t.Helper()
	data, err := json.MarshalIndent(state, "", "  ")
	if err != nil {
		t.Fatalf("marshal state: %v", err)
	}
	if err := os.WriteFile(reconciler.StatePath(home), append(data, '\n'), 0o600); err != nil {
		t.Fatalf("write state: %v", err)
	}
}

func generateSSHKey(t *testing.T, path string) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		t.Fatalf("mkdir key dir: %v", err)
	}
	cmd := exec.Command("ssh-keygen", "-t", "ed25519", "-N", "", "-f", path)
	output, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("generate ssh key: %v\n%s", err, output)
	}
	if err := os.Chmod(path, 0o600); err != nil {
		t.Fatalf("chmod generated key: %v", err)
	}
}

type recordingSystemAdapter struct {
	applied [][]reconciler.Capability
}

func (adapter *recordingSystemAdapter) MissingCapabilities(context.Context, reconciler.Request, []reconciler.ComponentID) ([]reconciler.Capability, error) {
	return nil, nil
}

func (adapter *recordingSystemAdapter) ApplySystemDependencies(_ context.Context, _ reconciler.Request, missing []reconciler.Capability) ([]string, error) {
	adapter.applied = append(adapter.applied, append([]reconciler.Capability(nil), missing...))
	return []string{"system-adapter"}, nil
}
