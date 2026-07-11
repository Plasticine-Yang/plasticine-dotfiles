package reconciler_test

import (
	"context"
	"crypto/sha256"
	"crypto/x509"
	"encoding/hex"
	"encoding/json"
	"errors"
	"net"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"syscall"
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
	fragment := readText(t, filepath.Join(req.Home, "config", "ssh", "github.conf"))
	if !strings.Contains(fragment, "AddKeysToAgent yes") || !strings.Contains(fragment, "UseKeychain yes") {
		t.Fatalf("GitHub SSH fragment did not enable macOS Keychain integration:\n%s", fragment)
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

func TestGitHubSSHSecretReferenceCanBeSelectedInteractively(t *testing.T) {
	t.Parallel()

	r := contractReconciler()
	req := contractRequest(t.TempDir())
	req.Exclude = []reconciler.ComponentID{
		reconciler.ComponentNeovim,
		reconciler.ComponentLazygit,
		reconciler.ComponentFNM,
		reconciler.ComponentUV,
	}
	req.LoginShellKnown = true
	req.LoginShell = "/bin/zsh"
	req.ZshPath = "/bin/zsh"

	blocked, err := r.Plan(context.Background(), req)
	if err != nil {
		t.Fatalf("plan without secret: %v", err)
	}
	if blocked.Outcome != reconciler.OutcomeBlocked || !hasBlocker(blocked.Blockers, reconciler.BlockerSecretReferenceRequired) {
		t.Fatalf("plan without secret outcome=%s blockers=%#v", blocked.Outcome, blocked.Blockers)
	}

	key := filepath.Join(req.Home, "id_ed25519")
	generateSSHKey(t, key)
	selected := false
	req.GitHubKeySelector = func() (string, bool) {
		selected = true
		return key, true
	}
	plan, err := r.Plan(context.Background(), req)
	if err != nil {
		t.Fatalf("plan with selected secret: %v", err)
	}
	if !selected {
		t.Fatal("GitHub key selector was not called")
	}
	if hasBlocker(plan.Blockers, reconciler.BlockerSecretReferenceRequired) {
		t.Fatalf("selected key still produced secret blocker: %#v", plan.Blockers)
	}
	if !hasChange(plan.Changes, reconciler.ComponentGitHubSSH, reconciler.ResourceSecretReference) {
		t.Fatalf("plan changes = %#v, want Secret Reference change", plan.Changes)
	}
}

func TestGitHubSSHValidSecretReferenceDoesNotPromptAgain(t *testing.T) {
	t.Parallel()

	r := contractReconciler()
	req := contractRequest(t.TempDir())
	req.Exclude = []reconciler.ComponentID{
		reconciler.ComponentNeovim,
		reconciler.ComponentLazygit,
		reconciler.ComponentFNM,
		reconciler.ComponentUV,
	}
	req.LoginShellKnown = true
	req.LoginShell = "/bin/zsh"
	req.ZshPath = "/bin/zsh"
	key := filepath.Join(req.Home, "id_ed25519")
	generateSSHKey(t, key)
	req.GitHubKeyPath = key
	req.Yes = true
	applied, err := r.Apply(context.Background(), req)
	if err != nil {
		t.Fatalf("apply selected secret: %v", err)
	}
	if applied.Outcome != reconciler.OutcomeApplied {
		t.Fatalf("apply outcome=%s blockers=%#v", applied.Outcome, applied.Blockers)
	}

	req.GitHubKeyPath = ""
	req.Yes = false
	req.GitHubKeySelector = func() (string, bool) {
		t.Fatal("valid persisted Secret Reference should not prompt again")
		return "", false
	}
	plan, err := r.Plan(context.Background(), req)
	if err != nil {
		t.Fatalf("plan with persisted secret: %v", err)
	}
	if hasBlocker(plan.Blockers, reconciler.BlockerSecretReferenceRequired) {
		t.Fatalf("persisted secret produced blocker: %#v", plan.Blockers)
	}
}

func TestGitHubHTTPSRewriteRequiresGitConfigAndGitHubSSHActive(t *testing.T) {
	t.Parallel()

	r := contractReconciler()
	withoutSSH := contractRequest(t.TempDir())
	withoutSSH.Yes = true
	applied, err := r.Apply(context.Background(), withoutSSH)
	if err != nil {
		t.Fatalf("apply without github ssh: %v", err)
	}
	if applied.Outcome != reconciler.OutcomeApplied {
		t.Fatalf("apply without github ssh outcome=%s blockers=%#v", applied.Outcome, applied.Blockers)
	}
	gitConfig := readText(t, filepath.Join(withoutSSH.Home, "config", "git", "config"))
	if strings.Contains(gitConfig, "insteadOf = https://github.com/") {
		t.Fatalf("git config included GitHub rewrite while github-ssh was excluded:\n%s", gitConfig)
	}

	withSSH := contractRequest(t.TempDir())
	withSSH.Exclude = []reconciler.ComponentID{
		reconciler.ComponentNeovim,
		reconciler.ComponentLazygit,
		reconciler.ComponentFNM,
		reconciler.ComponentUV,
	}
	withSSH.LoginShellKnown = true
	withSSH.LoginShell = "/bin/zsh"
	withSSH.ZshPath = "/bin/zsh"
	key := filepath.Join(withSSH.Home, "id_ed25519")
	generateSSHKey(t, key)
	withSSH.GitHubKeyPath = key
	withSSH.Yes = true
	applied, err = r.Apply(context.Background(), withSSH)
	if err != nil {
		t.Fatalf("apply with github ssh: %v", err)
	}
	if applied.Outcome != reconciler.OutcomeApplied {
		t.Fatalf("apply with github ssh outcome=%s blockers=%#v", applied.Outcome, applied.Blockers)
	}
	gitConfig = readText(t, filepath.Join(withSSH.Home, "config", "git", "config"))
	if !strings.Contains(gitConfig, "[url \"git@github.com:\"]") || !strings.Contains(gitConfig, "insteadOf = https://github.com/") {
		t.Fatalf("git config did not include GitHub rewrite while git-config and github-ssh were active:\n%s", gitConfig)
	}
}

func TestLinuxGitHubSSHUsesSharedAgentSocket(t *testing.T) {
	t.Parallel()

	r := contractReconciler()
	req := contractRequest(t.TempDir())
	req.Target = platform.TargetLinuxAMD64
	req.Host = platform.Host{
		OS:      platform.OSLinux,
		Arch:    platform.ArchAMD64,
		Family:  platform.FamilyDebian,
		Version: "12",
	}
	req.Exclude = []reconciler.ComponentID{
		reconciler.ComponentNeovim,
		reconciler.ComponentLazygit,
		reconciler.ComponentFNM,
		reconciler.ComponentUV,
	}
	req.Capabilities = map[reconciler.Capability]bool{
		reconciler.CapabilityGit:                true,
		reconciler.CapabilityZsh:                true,
		reconciler.CapabilityOpenSSH:            true,
		reconciler.CapabilityCA:                 true,
		reconciler.CapabilitySystemdUserSession: true,
	}
	key := filepath.Join(req.Home, "id_ed25519")
	generateSSHKey(t, key)
	req.GitHubKeyPath = key
	req.Yes = true
	var startedServices []string
	req.UserServiceStarter = func(_ context.Context, servicePath string) ([]string, error) {
		startedServices = append(startedServices, servicePath)
		return []string{"systemctl --user link " + servicePath, "systemctl --user enable --now " + filepath.Base(servicePath)}, nil
	}

	applied, err := r.Apply(context.Background(), req)
	if err != nil {
		t.Fatalf("apply linux github ssh: %v", err)
	}
	if applied.Outcome != reconciler.OutcomeApplied {
		t.Fatalf("apply outcome=%s blockers=%#v", applied.Outcome, applied.Blockers)
	}
	fragment := readText(t, filepath.Join(req.Home, "config", "ssh", "github.conf"))
	if !strings.Contains(fragment, "IdentityAgent ~/.plasticine/runtime/ssh-agent.sock") {
		t.Fatalf("GitHub SSH fragment did not use shared Linux agent socket:\n%s", fragment)
	}
	shellConfig := readText(t, filepath.Join(req.Home, "config", "zsh", ".zshrc"))
	if !strings.Contains(shellConfig, "github-agent.zsh") {
		t.Fatalf("shell config did not source the shared agent fragment:\n%s", shellConfig)
	}
	agentShell := readText(t, filepath.Join(req.Home, "config", "ssh", "github-agent.zsh"))
	if !strings.Contains(agentShell, "export SSH_AUTH_SOCK") ||
		!strings.Contains(agentShell, "ssh-add -l") ||
		!strings.Contains(agentShell, "ssh-add '") {
		t.Fatalf("shared agent shell fragment did not conditionally load the key:\n%s", agentShell)
	}
	service := filepath.Join(req.Home, "config", "systemd", "user", "ssh-agent.service")
	if !pathExists(service) {
		t.Fatalf("shared user-level ssh-agent service was not materialized")
	}
	if len(startedServices) != 1 || startedServices[0] != service {
		t.Fatalf("started services=%#v, want %s", startedServices, service)
	}
	if !hasDurableEffect(applied.DurableEffects, "systemctl --user link "+service) {
		t.Fatalf("durable effects=%#v, want user service link", applied.DurableEffects)
	}
	if !hasDurableEffect(applied.DurableEffects, "systemctl --user enable --now ssh-agent.service") {
		t.Fatalf("durable effects=%#v, want user service start", applied.DurableEffects)
	}
}

func TestShellDoesNotSourceSuspendedGitHubAgent(t *testing.T) {
	t.Parallel()

	r := contractReconciler()
	req := contractRequest(t.TempDir())
	req.Target = platform.TargetLinuxAMD64
	req.Host = platform.Host{
		OS:      platform.OSLinux,
		Arch:    platform.ArchAMD64,
		Family:  platform.FamilyDebian,
		Version: "12",
	}
	req.Capabilities = map[reconciler.Capability]bool{
		reconciler.CapabilityGit: true,
		reconciler.CapabilityZsh: true,
		reconciler.CapabilityCA:  true,
	}
	req.Yes = true

	applied, err := r.Apply(context.Background(), req)
	if err != nil {
		t.Fatalf("apply shell without github ssh: %v", err)
	}
	if applied.Outcome != reconciler.OutcomeApplied {
		t.Fatalf("apply outcome=%s blockers=%#v", applied.Outcome, applied.Blockers)
	}
	shellConfig := readText(t, filepath.Join(req.Home, "config", "zsh", ".zshrc"))
	if strings.Contains(shellConfig, "github-agent.zsh") {
		t.Fatalf("shell config sourced suspended github-ssh artifact:\n%s", shellConfig)
	}
}

func TestLinuxGitHubSSHBlocksUnsupportedSharedAgentPlatform(t *testing.T) {
	t.Parallel()

	r := contractReconciler()
	req := contractRequest(t.TempDir())
	req.Target = platform.TargetLinuxAMD64
	req.Host = platform.Host{
		OS:      platform.OSLinux,
		Arch:    platform.ArchAMD64,
		Family:  platform.FamilyOtherLinux,
		Version: "39",
	}
	req.Exclude = []reconciler.ComponentID{
		reconciler.ComponentNeovim,
		reconciler.ComponentLazygit,
		reconciler.ComponentFNM,
		reconciler.ComponentUV,
	}
	req.Capabilities = map[reconciler.Capability]bool{
		reconciler.CapabilityGit:                true,
		reconciler.CapabilityZsh:                true,
		reconciler.CapabilityOpenSSH:            true,
		reconciler.CapabilityCA:                 true,
		reconciler.CapabilitySystemdUserSession: true,
	}
	key := filepath.Join(req.Home, "id_ed25519")
	generateSSHKey(t, key)
	req.GitHubKeyPath = key

	plan, err := r.Plan(context.Background(), req)
	if err != nil {
		t.Fatalf("plan unsupported linux github ssh: %v", err)
	}
	if plan.Outcome != reconciler.OutcomeBlocked || !hasBlocker(plan.Blockers, reconciler.BlockerUnsupportedSystemChange) {
		t.Fatalf("plan outcome=%s blockers=%#v", plan.Outcome, plan.Blockers)
	}
}

func TestLinuxGitHubSSHBlocksMissingSystemdUserSessionAsUnsupported(t *testing.T) {
	t.Parallel()

	r := contractReconciler()
	req := contractRequest(t.TempDir())
	req.Target = platform.TargetLinuxAMD64
	req.Host = platform.Host{
		OS:      platform.OSLinux,
		Arch:    platform.ArchAMD64,
		Family:  platform.FamilyDebian,
		Version: "12",
	}
	req.Exclude = []reconciler.ComponentID{
		reconciler.ComponentNeovim,
		reconciler.ComponentLazygit,
		reconciler.ComponentFNM,
		reconciler.ComponentUV,
	}
	req.Capabilities = map[reconciler.Capability]bool{
		reconciler.CapabilityGit:                true,
		reconciler.CapabilityZsh:                true,
		reconciler.CapabilityOpenSSH:            true,
		reconciler.CapabilityCA:                 true,
		reconciler.CapabilitySystemdUserSession: false,
	}
	key := filepath.Join(req.Home, "id_ed25519")
	generateSSHKey(t, key)
	req.GitHubKeyPath = key

	plan, err := r.Plan(context.Background(), req)
	if err != nil {
		t.Fatalf("plan missing systemd user session: %v", err)
	}
	if plan.Outcome != reconciler.OutcomeBlocked || !hasBlocker(plan.Blockers, reconciler.BlockerUnsupportedSystemChange) {
		t.Fatalf("plan outcome=%s blockers=%#v", plan.Outcome, plan.Blockers)
	}
	if hasSystemChange(plan.Changes) {
		t.Fatalf("missing systemd user session was planned as a system change: %#v", plan.Changes)
	}
}

func TestComponentOperationalFailureContinuesIndependentBranches(t *testing.T) {
	t.Parallel()

	r := contractReconciler()
	req := contractRequest(t.TempDir())
	req.Target = platform.TargetLinuxAMD64
	req.Host = platform.Host{
		OS:      platform.OSLinux,
		Arch:    platform.ArchAMD64,
		Family:  platform.FamilyDebian,
		Version: "12",
	}
	req.Exclude = []reconciler.ComponentID{
		reconciler.ComponentNeovim,
		reconciler.ComponentLazygit,
		reconciler.ComponentFNM,
		reconciler.ComponentUV,
	}
	req.Capabilities = map[reconciler.Capability]bool{
		reconciler.CapabilityGit:                true,
		reconciler.CapabilityZsh:                true,
		reconciler.CapabilityOpenSSH:            true,
		reconciler.CapabilityCA:                 true,
		reconciler.CapabilitySystemdUserSession: true,
	}
	key := filepath.Join(req.Home, "id_ed25519")
	generateSSHKey(t, key)
	req.GitHubKeyPath = key
	req.Yes = true
	req.UserServiceStarter = func(context.Context, string) ([]string, error) {
		return nil, errors.New("systemctl failed")
	}

	result, err := r.Apply(context.Background(), req)
	if err != nil {
		t.Fatalf("apply with service failure: %v", err)
	}
	if result.Outcome != reconciler.OutcomePartial || !hasBlocker(result.Blockers, reconciler.BlockerOperationalFailure) {
		t.Fatalf("outcome=%s blockers=%#v, want partial operational failure", result.Outcome, result.Blockers)
	}
	if !hasComponentStatus(result.Components, reconciler.ComponentShell, reconciler.ComponentSucceeded) ||
		!hasComponentStatus(result.Components, reconciler.ComponentGitConfig, reconciler.ComponentSucceeded) {
		t.Fatalf("independent components did not continue: %#v", result.Components)
	}
	if !hasComponentStatus(result.Components, reconciler.ComponentGitHubSSH, reconciler.ComponentBlocked) {
		t.Fatalf("github-ssh failure was not reported: %#v", result.Components)
	}
	state, err := reconciler.ReadState(req.Home)
	if err != nil {
		t.Fatalf("read state: %v", err)
	}
	if len(state.PendingWork) == 0 {
		t.Fatalf("github-ssh pending work was not preserved after component failure")
	}
}

func TestSystemDependenciesRequireIndependentAuthorization(t *testing.T) {
	t.Parallel()

	system := &recordingSystemAdapter{}
	r := reconciler.New(reconciler.Options{
		DesiredStateID: "desired-state-contract",
		ToolLockSHA256: strings.Repeat("c", 64),
		System:         system,
		ToolLock:       fnmLinuxToolLock(),
		Clock: func() time.Time {
			return time.Date(2026, 7, 11, 3, 0, 0, 0, time.UTC)
		},
	})
	req := contractRequest(t.TempDir())
	req.Exclude = []reconciler.ComponentID{
		reconciler.ComponentGitHubSSH,
		reconciler.ComponentNeovim,
		reconciler.ComponentLazygit,
		reconciler.ComponentFNM,
		reconciler.ComponentUV,
	}
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

func TestShellLoginShellChangeRequiresSystemAuthorizationAndDoesNotRepeat(t *testing.T) {
	t.Parallel()

	var shellChanges []string
	r := contractReconciler()
	req := contractRequest(t.TempDir())
	req.LoginShell = "/bin/bash"
	req.LoginShellKnown = true
	req.ZshPath = "/bin/zsh"
	req.ShellChangeExecutor = func(_ context.Context, desiredShell string) ([]string, error) {
		shellChanges = append(shellChanges, desiredShell)
		return []string{"chsh -s " + desiredShell}, nil
	}

	plan, err := r.Plan(context.Background(), req)
	if err != nil {
		t.Fatalf("plan login shell: %v", err)
	}
	if plan.Outcome != reconciler.OutcomeChangesPlanned || !hasChange(plan.Changes, reconciler.ComponentShell, reconciler.ResourceLoginShell) {
		t.Fatalf("plan outcome=%s changes=%#v, want login-shell system change", plan.Outcome, plan.Changes)
	}

	req.Yes = true
	denied, err := r.Apply(context.Background(), req)
	if err != nil {
		t.Fatalf("apply without allow-system: %v", err)
	}
	if denied.Outcome != reconciler.OutcomeBlocked || !hasBlocker(denied.Blockers, reconciler.BlockerSystemChangeAuthorization) {
		t.Fatalf("denied outcome=%s blockers=%#v", denied.Outcome, denied.Blockers)
	}
	if pathExists(reconciler.StatePath(req.Home)) {
		t.Fatalf("login-shell authorization denial wrote state")
	}

	req.AllowSystem = true
	applied, err := r.Apply(context.Background(), req)
	if err != nil {
		t.Fatalf("apply login shell: %v", err)
	}
	if applied.Outcome != reconciler.OutcomeApplied {
		t.Fatalf("apply outcome=%s blockers=%#v", applied.Outcome, applied.Blockers)
	}
	if len(shellChanges) != 1 || shellChanges[0] != "/bin/zsh" {
		t.Fatalf("shell changes=%#v, want one chsh to /bin/zsh", shellChanges)
	}
	if !hasDurableEffect(applied.DurableEffects, "chsh -s /bin/zsh") {
		t.Fatalf("durable effects=%#v, want chsh effect", applied.DurableEffects)
	}

	req.LoginShell = "/bin/zsh"
	req.LoginShellKnown = true
	second, err := r.Apply(context.Background(), req)
	if err != nil {
		t.Fatalf("second apply login shell: %v", err)
	}
	if second.Outcome != reconciler.OutcomeNoChange {
		t.Fatalf("second outcome=%s blockers=%#v", second.Outcome, second.Blockers)
	}
	if len(shellChanges) != 1 {
		t.Fatalf("login shell change repeated: %#v", shellChanges)
	}
}

func TestShellPlanIncludesLoginShellChangeWhenZshCapabilityIsMissing(t *testing.T) {
	t.Parallel()

	r := contractReconciler()
	req := contractRequest(t.TempDir())
	req.Target = platform.TargetLinuxAMD64
	req.Host = platform.Host{
		OS:      platform.OSLinux,
		Arch:    platform.ArchAMD64,
		Family:  platform.FamilyDebian,
		Version: "12",
	}
	req.Exclude = []reconciler.ComponentID{
		reconciler.ComponentGitHubSSH,
		reconciler.ComponentNeovim,
		reconciler.ComponentLazygit,
		reconciler.ComponentFNM,
		reconciler.ComponentUV,
	}
	req.Capabilities = map[reconciler.Capability]bool{
		reconciler.CapabilityGit: true,
		reconciler.CapabilityZsh: false,
		reconciler.CapabilityCA:  true,
	}
	req.LoginShell = "/bin/bash"
	req.LoginShellKnown = true
	req.ZshPath = "/usr/bin/zsh"

	plan, err := r.Plan(context.Background(), req)
	if err != nil {
		t.Fatalf("plan missing zsh login shell: %v", err)
	}
	if plan.Outcome != reconciler.OutcomeChangesPlanned || !hasSystemChange(plan.Changes) {
		t.Fatalf("plan outcome=%s changes=%#v, want system changes", plan.Outcome, plan.Changes)
	}
	if !hasChange(plan.Changes, reconciler.ComponentShell, reconciler.ResourceLoginShell) {
		t.Fatalf("plan changes=%#v, want login-shell change in same immutable plan", plan.Changes)
	}
}

func TestLoginShellChangeWaitsForSuccessfulZshCapability(t *testing.T) {
	t.Parallel()

	system := &recordingSystemAdapter{
		err:     errors.New("apt failed"),
		missing: []reconciler.Capability{reconciler.CapabilityZsh},
	}
	var shellChanges []string
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
	req.Exclude = []reconciler.ComponentID{
		reconciler.ComponentGitHubSSH,
		reconciler.ComponentNeovim,
		reconciler.ComponentLazygit,
		reconciler.ComponentFNM,
		reconciler.ComponentUV,
	}
	req.Capabilities = map[reconciler.Capability]bool{
		reconciler.CapabilityGit: true,
		reconciler.CapabilityZsh: false,
		reconciler.CapabilityCA:  true,
	}
	req.LoginShell = "/bin/bash"
	req.LoginShellKnown = true
	req.ZshPath = "/usr/bin/zsh"
	req.ShellChangeExecutor = func(_ context.Context, desiredShell string) ([]string, error) {
		shellChanges = append(shellChanges, desiredShell)
		return []string{"chsh -s " + desiredShell}, nil
	}
	req.Yes = true
	req.AllowSystem = true

	result, err := r.Apply(context.Background(), req)
	if err != nil {
		t.Fatalf("apply failed zsh install: %v", err)
	}
	if result.Outcome != reconciler.OutcomePartial || !hasBlocker(result.Blockers, reconciler.BlockerOperationalFailure) {
		t.Fatalf("outcome=%s blockers=%#v, want partial operational failure", result.Outcome, result.Blockers)
	}
	if len(shellChanges) != 0 {
		t.Fatalf("login shell changed before zsh capability succeeded: %#v", shellChanges)
	}
	if !hasComponentStatus(result.Components, reconciler.ComponentShell, reconciler.ComponentBlocked) {
		t.Fatalf("shell was not blocked by failed zsh capability: %#v", result.Components)
	}
}

func TestShellLoginShellDiscoveryFailureBlocksPlanning(t *testing.T) {
	t.Parallel()

	r := contractReconciler()
	req := contractRequest(t.TempDir())
	req.ZshPath = "/bin/zsh"

	plan, err := r.Plan(context.Background(), req)
	if err != nil {
		t.Fatalf("plan login shell discovery failure: %v", err)
	}
	if plan.Outcome != reconciler.OutcomeBlocked || !hasBlocker(plan.Blockers, reconciler.BlockerOperationalFailure) {
		t.Fatalf("plan outcome=%s blockers=%#v, want operational blocker", plan.Outcome, plan.Blockers)
	}
}

func TestShellLoginShellTreatsZshPathsAsSatisfied(t *testing.T) {
	t.Parallel()

	r := contractReconciler()
	req := contractRequest(t.TempDir())
	req.LoginShell = "/bin/zsh"
	req.LoginShellKnown = true
	req.ZshPath = "/usr/bin/zsh"

	plan, err := r.Plan(context.Background(), req)
	if err != nil {
		t.Fatalf("plan satisfied login shell: %v", err)
	}
	if hasChange(plan.Changes, reconciler.ComponentShell, reconciler.ResourceLoginShell) {
		t.Fatalf("plan repeated login-shell change for equivalent zsh paths: %#v", plan.Changes)
	}
}

func TestLoginShellFailureSkipsDependentsAndContinuesIndependentWork(t *testing.T) {
	t.Parallel()

	r := reconciler.New(reconciler.Options{
		DesiredStateID: "desired-state-contract",
		ToolLockSHA256: strings.Repeat("c", 64),
		ToolLock:       fnmLinuxToolLock(),
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
	req.Exclude = []reconciler.ComponentID{
		reconciler.ComponentGitHubSSH,
		reconciler.ComponentNeovim,
		reconciler.ComponentLazygit,
		reconciler.ComponentUV,
	}
	req.Capabilities = map[reconciler.Capability]bool{
		reconciler.CapabilityGit: true,
		reconciler.CapabilityZsh: true,
		reconciler.CapabilityCA:  true,
	}
	req.LoginShell = "/bin/bash"
	req.LoginShellKnown = true
	req.ZshPath = "/bin/zsh"
	req.ShellChangeExecutor = func(context.Context, string) ([]string, error) {
		return nil, errors.New("chsh failed")
	}
	req.Yes = true
	req.AllowSystem = true

	result, err := r.Apply(context.Background(), req)
	if err != nil {
		t.Fatalf("apply login shell failure: %v", err)
	}
	if result.Outcome != reconciler.OutcomePartial || !hasBlocker(result.Blockers, reconciler.BlockerOperationalFailure) {
		t.Fatalf("outcome=%s blockers=%#v, want partial operational failure", result.Outcome, result.Blockers)
	}
	if !hasComponentStatus(result.Components, reconciler.ComponentShell, reconciler.ComponentBlocked) {
		t.Fatalf("shell was not reported blocked: %#v", result.Components)
	}
	if !hasComponentStatus(result.Components, reconciler.ComponentFNM, reconciler.ComponentSkipped) {
		t.Fatalf("fnm was not skipped as shell dependent: %#v", result.Components)
	}
	if !hasComponentStatus(result.Components, reconciler.ComponentGitConfig, reconciler.ComponentSucceeded) {
		t.Fatalf("git-config did not continue independently: %#v", result.Components)
	}
	if !pathExists(filepath.Join(req.Home, "config", "git", "config")) {
		t.Fatalf("git-config was not materialized after shell chsh failure")
	}
	if pathExists(filepath.Join(req.Home, "bin", "fnm")) {
		t.Fatalf("fnm was materialized despite shell chsh failure")
	}
}

func TestShellResourceFailureSkipsDependentsAndContinuesIndependentWork(t *testing.T) {
	t.Parallel()

	r := reconciler.New(reconciler.Options{
		DesiredStateID: "desired-state-contract",
		ToolLockSHA256: strings.Repeat("c", 64),
		ToolLock:       fnmLinuxToolLock(),
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
	req.Exclude = []reconciler.ComponentID{
		reconciler.ComponentGitHubSSH,
		reconciler.ComponentNeovim,
		reconciler.ComponentLazygit,
		reconciler.ComponentUV,
	}
	req.Capabilities = map[reconciler.Capability]bool{
		reconciler.CapabilityGit: true,
		reconciler.CapabilityZsh: true,
		reconciler.CapabilityCA:  true,
	}
	req.LoginShell = "/bin/zsh"
	req.LoginShellKnown = true
	req.ZshPath = "/bin/zsh"
	req.FailBeforeEffectPath = filepath.Join(req.Home, "config", "zsh", ".zshrc")
	req.Yes = true

	result, err := r.Apply(context.Background(), req)
	if err != nil {
		t.Fatalf("apply shell resource failure: %v", err)
	}
	if result.Outcome != reconciler.OutcomePartial || !hasBlocker(result.Blockers, reconciler.BlockerOperationalFailure) {
		t.Fatalf("outcome=%s blockers=%#v, want partial operational failure", result.Outcome, result.Blockers)
	}
	if !hasComponentStatus(result.Components, reconciler.ComponentShell, reconciler.ComponentBlocked) {
		t.Fatalf("shell was not reported blocked: %#v", result.Components)
	}
	if !hasComponentStatus(result.Components, reconciler.ComponentFNM, reconciler.ComponentSkipped) {
		t.Fatalf("fnm was not skipped after shell resource failure: %#v", result.Components)
	}
	if !hasComponentStatus(result.Components, reconciler.ComponentGitConfig, reconciler.ComponentSucceeded) {
		t.Fatalf("git-config did not continue independently: %#v", result.Components)
	}
	if pathExists(filepath.Join(req.Home, "bin", "fnm")) {
		t.Fatalf("fnm was materialized despite shell resource failure")
	}
}

func TestApplyAuthorizesTheImmutablePlanBeforeMutation(t *testing.T) {
	t.Parallel()

	r := contractReconciler()
	req := contractRequest(t.TempDir())
	authorized := false
	req.Authorize = func(plan reconciler.Result) bool {
		authorized = true
		if plan.Outcome != reconciler.OutcomeChangesPlanned {
			t.Fatalf("authorized plan outcome = %s, want changes planned", plan.Outcome)
		}
		if !hasChange(plan.Changes, reconciler.ComponentGitConfig, reconciler.ResourceManagedPath) {
			t.Fatalf("authorized plan did not include git-config change: %#v", plan.Changes)
		}
		return true
	}

	applied, err := r.Apply(context.Background(), req)
	if err != nil {
		t.Fatalf("authorized apply: %v", err)
	}
	if !authorized {
		t.Fatalf("authorizer was not called")
	}
	if applied.Outcome != reconciler.OutcomeApplied {
		t.Fatalf("authorized apply outcome=%s blockers=%#v", applied.Outcome, applied.Blockers)
	}

	deniedHome := t.TempDir()
	deniedReq := contractRequest(deniedHome)
	deniedReq.Authorize = func(reconciler.Result) bool { return false }
	denied, err := r.Apply(context.Background(), deniedReq)
	if err != nil {
		t.Fatalf("denied apply: %v", err)
	}
	if denied.Outcome != reconciler.OutcomeDenied {
		t.Fatalf("denied outcome=%s", denied.Outcome)
	}
	if pathExists(reconciler.StatePath(deniedHome)) {
		t.Fatalf("denied authorization wrote state")
	}
}

func TestSystemDependencyFailureSkipsDependentComponentAndContinuesIndependentWork(t *testing.T) {
	t.Parallel()

	system := &recordingSystemAdapter{
		err:     errors.New("apt failed"),
		missing: []reconciler.Capability{reconciler.CapabilityZsh},
	}
	r := reconciler.New(reconciler.Options{
		DesiredStateID: "desired-state-contract",
		ToolLockSHA256: strings.Repeat("c", 64),
		System:         system,
		ToolLock:       fnmLinuxToolLock(),
		Clock: func() time.Time {
			return time.Date(2026, 7, 11, 3, 0, 0, 0, time.UTC)
		},
	})
	req := contractRequest(t.TempDir())
	req.Exclude = []reconciler.ComponentID{
		reconciler.ComponentGitHubSSH,
		reconciler.ComponentNeovim,
		reconciler.ComponentLazygit,
		reconciler.ComponentUV,
	}
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
		reconciler.CapabilityCA:  true,
	}
	req.Yes = true
	req.AllowSystem = true

	result, err := r.Apply(context.Background(), req)
	if err != nil {
		t.Fatalf("apply returned error: %v", err)
	}
	if result.Outcome != reconciler.OutcomePartial || !hasBlocker(result.Blockers, reconciler.BlockerOperationalFailure) {
		t.Fatalf("outcome=%s blockers=%#v, want partial operational failure", result.Outcome, result.Blockers)
	}
	gitConfig := filepath.Join(req.Home, "config", "git", "config")
	if !pathExists(gitConfig) {
		t.Fatalf("independent git-config did not continue after system failure")
	}
	if pathExists(filepath.Join(req.Home, "config", "zsh", ".zshrc")) {
		t.Fatalf("shell config was materialized despite missing zsh capability")
	}
	state, err := reconciler.ReadState(req.Home)
	if err != nil {
		t.Fatalf("read state: %v", err)
	}
	if _, ok := state.Ownership[gitConfig]; !ok {
		t.Fatalf("git-config ownership missing after independent continuation")
	}
	if _, ok := state.Ownership[filepath.Join(req.Home, "config", "zsh", ".zshrc")]; ok {
		t.Fatalf("shell ownership was accepted despite system failure")
	}
	if !hasComponentStatus(result.Components, reconciler.ComponentGitConfig, reconciler.ComponentSucceeded) {
		t.Fatalf("git-config was not reported as succeeded after independent continuation: %#v", result.Components)
	}
	if !hasComponentStatus(result.Components, reconciler.ComponentFNM, reconciler.ComponentSkipped) {
		t.Fatalf("fnm was not skipped as downstream of shell failure: %#v", result.Components)
	}
	if pathExists(filepath.Join(req.Home, "bin", "fnm")) {
		t.Fatalf("fnm launcher was materialized despite shell dependency failure")
	}
}

func TestMacOSCommandLineToolsLaunchLeavesDependentsAwaitingOwnerAction(t *testing.T) {
	t.Parallel()

	system := &recordingSystemAdapter{
		err:     reconciler.ErrOwnerActionRequired,
		effects: []string{"xcode-select --install"},
		missing: []reconciler.Capability{reconciler.CapabilityAppleDevelopmentTools},
	}
	r := reconciler.New(reconciler.Options{
		DesiredStateID: "desired-state-contract",
		ToolLockSHA256: strings.Repeat("c", 64),
		System:         system,
		Clock: func() time.Time {
			return time.Date(2026, 7, 11, 3, 0, 0, 0, time.UTC)
		},
	})
	req := contractRequest(t.TempDir())
	req.Exclude = []reconciler.ComponentID{
		reconciler.ComponentNeovim,
		reconciler.ComponentLazygit,
		reconciler.ComponentFNM,
		reconciler.ComponentUV,
	}
	key := filepath.Join(req.Home, "id_ed25519")
	generateSSHKey(t, key)
	req.GitHubKeyPath = key
	req.Capabilities = map[reconciler.Capability]bool{
		reconciler.CapabilityGit:                   true,
		reconciler.CapabilityZsh:                   true,
		reconciler.CapabilityOpenSSH:               true,
		reconciler.CapabilityCA:                    true,
		reconciler.CapabilityAppleDevelopmentTools: false,
	}
	req.Yes = true
	req.AllowSystem = true

	result, err := r.Apply(context.Background(), req)
	if err != nil {
		t.Fatalf("apply returned error: %v", err)
	}
	if result.Outcome != reconciler.OutcomePartial || !hasBlocker(result.Blockers, reconciler.BlockerOwnerActionRequired) {
		t.Fatalf("outcome=%s blockers=%#v, want partial owner action", result.Outcome, result.Blockers)
	}
	if !hasDurableEffect(result.DurableEffects, "xcode-select --install") {
		t.Fatalf("durable effects=%#v, want launched Apple installer", result.DurableEffects)
	}
	if !hasComponentStatus(result.Components, reconciler.ComponentGitHubSSH, reconciler.ComponentAwaitingOwnerAction) {
		t.Fatalf("github-ssh was not awaiting Owner action: %#v", result.Components)
	}
	if !hasComponentStatus(result.Components, reconciler.ComponentGitConfig, reconciler.ComponentSucceeded) {
		t.Fatalf("git-config was not reported as succeeded after Apple owner action: %#v", result.Components)
	}
	if !pathExists(filepath.Join(req.Home, "config", "git", "config")) {
		t.Fatalf("independent git-config did not continue after Apple owner action")
	}
	if pathExists(filepath.Join(req.Home, "config", "ssh", "github.conf")) {
		t.Fatalf("github-ssh fragment materialized before Apple owner action completed")
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

func TestRetirementRemovesManagedBlockWithoutDeletingOwnerContent(t *testing.T) {
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
	retiredPath := filepath.Join(req.WorkstationRoot, ".ssh", "config")
	body := strings.Join([]string{
		"Host internal",
		"  HostName git.internal",
		"# BEGIN PLASTICINE GITHUB SSH",
		"Host github.com",
		"  Include ~/.plasticine/config/ssh/github.conf",
		"# END PLASTICINE GITHUB SSH",
		"Host after",
		"  HostName after.internal",
		"",
	}, "\n")
	writeText(t, retiredPath, body)
	state.Ownership[retiredPath] = reconciler.Ownership{
		Component:    reconciler.ComponentGitConfig,
		Path:         retiredPath,
		ResourceKind: reconciler.ResourceManagedBlock,
		Digest:       testDigest(body),
		AcceptedAt:   state.AppliedAt,
	}
	writeStateJSON(t, req.Home, state)

	result, err := r.Apply(context.Background(), req)
	if err != nil {
		t.Fatalf("retirement apply: %v", err)
	}
	if result.Outcome != reconciler.OutcomeApplied {
		t.Fatalf("retirement apply outcome = %s", result.Outcome)
	}
	got := readText(t, retiredPath)
	if strings.Contains(got, "PLASTICINE GITHUB SSH") || strings.Contains(got, "Include ~/.plasticine") {
		t.Fatalf("managed block was not removed: %q", got)
	}
	if !strings.Contains(got, "Host internal") || !strings.Contains(got, "Host after") {
		t.Fatalf("owner content was not preserved: %q", got)
	}
	state, err = reconciler.ReadState(req.Home)
	if err != nil {
		t.Fatalf("read post-retirement state: %v", err)
	}
	if _, ok := state.Ownership[retiredPath]; ok {
		t.Fatalf("retired managed block ownership was not released")
	}
}

func TestRetirementDoesNotConflictOnManagedBlockOwnerEditsOutsideMarkers(t *testing.T) {
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
	retiredPath := filepath.Join(req.WorkstationRoot, ".ssh", "config")
	acceptedBody := strings.Join([]string{
		"Host internal",
		"  HostName old.internal",
		"# BEGIN PLASTICINE GITHUB SSH",
		"Host github.com",
		"  Include ~/.plasticine/config/ssh/github.conf",
		"# END PLASTICINE GITHUB SSH",
		"",
	}, "\n")
	currentBody := strings.Replace(acceptedBody, "old.internal", "new.internal", 1)
	writeText(t, retiredPath, currentBody)
	state.Ownership[retiredPath] = reconciler.Ownership{
		Component:    reconciler.ComponentGitConfig,
		Path:         retiredPath,
		ResourceKind: reconciler.ResourceManagedBlock,
		Digest:       testDigest(acceptedBody),
		AcceptedAt:   state.AppliedAt,
	}
	writeStateJSON(t, req.Home, state)

	plan, err := r.Plan(context.Background(), req)
	if err != nil {
		t.Fatalf("plan: %v", err)
	}
	if len(plan.Conflicts) != 0 || len(plan.Retirements) != 1 {
		t.Fatalf("plan conflicts=%#v retirements=%#v, want preservable managed block retirement", plan.Conflicts, plan.Retirements)
	}
	result, err := r.Apply(context.Background(), req)
	if err != nil {
		t.Fatalf("apply: %v", err)
	}
	if result.Outcome != reconciler.OutcomeApplied {
		t.Fatalf("apply outcome = %s blockers=%#v", result.Outcome, result.Blockers)
	}
	got := readText(t, retiredPath)
	if strings.Contains(got, "PLASTICINE GITHUB SSH") {
		t.Fatalf("managed block was not removed: %q", got)
	}
	if !strings.Contains(got, "new.internal") {
		t.Fatalf("owner edit outside markers was not preserved: %q", got)
	}
}

func TestRetirementAdoptionBacksUpDriftBeforeDeletion(t *testing.T) {
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
	retiredPath := filepath.Join(req.Home, "legacy", "drifted-git-shim")
	writeText(t, retiredPath, "owner drift")
	state.Ownership[retiredPath] = reconciler.Ownership{
		Component:    reconciler.ComponentGitConfig,
		Path:         retiredPath,
		ResourceKind: reconciler.ResourceManagedPath,
		Digest:       testDigest("old managed bytes"),
		AcceptedAt:   state.AppliedAt,
	}
	writeStateJSON(t, req.Home, state)

	req.Adopt = true
	plan, err := r.Plan(context.Background(), req)
	if err != nil {
		t.Fatalf("retirement plan: %v", err)
	}
	if len(plan.Conflicts) != 1 || len(plan.Retirements) != 1 {
		t.Fatalf("plan conflicts=%#v retirements=%#v, want adopted retirement drift", plan.Conflicts, plan.Retirements)
	}
	applied, err := r.Apply(context.Background(), req)
	if err != nil {
		t.Fatalf("retirement apply: %v", err)
	}
	if applied.Outcome != reconciler.OutcomeApplied {
		t.Fatalf("retirement apply outcome = %s blockers=%#v", applied.Outcome, applied.Blockers)
	}
	if pathExists(retiredPath) {
		t.Fatalf("adopted retirement drift was not deleted")
	}
	state, err = reconciler.ReadState(req.Home)
	if err != nil {
		t.Fatalf("read post-retirement state: %v", err)
	}
	if _, ok := state.Ownership[retiredPath]; ok {
		t.Fatalf("adopted retirement did not release ownership")
	}
	if len(state.Backups) == 0 {
		t.Fatalf("adopted retirement did not create a backup")
	}
	if got := readText(t, state.Backups[len(state.Backups)-1].Backup); got != "owner drift" {
		t.Fatalf("backup content = %q, want owner drift", got)
	}
}

func TestRetirementBlocksStaleExternalEditsBeforeDeletion(t *testing.T) {
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
	retiredPath := filepath.Join(req.Home, "legacy", "stale-git-shim")
	writeText(t, retiredPath, "old managed bytes")
	state.Ownership[retiredPath] = reconciler.Ownership{
		Component:    reconciler.ComponentGitConfig,
		Path:         retiredPath,
		ResourceKind: reconciler.ResourceManagedPath,
		Digest:       testDigest("old managed bytes"),
		AcceptedAt:   state.AppliedAt,
	}
	writeStateJSON(t, req.Home, state)

	req.Yes = false
	req.Authorize = func(reconciler.Result) bool {
		writeText(t, retiredPath, "owner edit after plan")
		return true
	}
	result, err := r.Apply(context.Background(), req)
	if err != nil {
		t.Fatalf("retirement apply: %v", err)
	}
	if result.Outcome != reconciler.OutcomeBlocked || !hasBlocker(result.Blockers, reconciler.BlockerStalePlan) {
		t.Fatalf("retirement outcome=%s blockers=%#v, want stale-plan block", result.Outcome, result.Blockers)
	}
	if got := readText(t, retiredPath); got != "owner edit after plan" {
		t.Fatalf("retirement deleted or rewrote stale path: %q", got)
	}
	state, err = reconciler.ReadState(req.Home)
	if err != nil {
		t.Fatalf("read post-retirement state: %v", err)
	}
	if len(state.PendingWork) != 0 {
		t.Fatalf("stale retirement wrote pending work: %#v", state.PendingWork)
	}
	if _, ok := state.Ownership[retiredPath]; !ok {
		t.Fatalf("stale retirement released ownership")
	}
}

func TestRetirementPreservesPendingJournalOnInterruptedDeletion(t *testing.T) {
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
	retiredPath := filepath.Join(req.Home, "legacy", "interrupted-git-shim")
	writeText(t, retiredPath, "old managed bytes")
	state.Ownership[retiredPath] = reconciler.Ownership{
		Component:    reconciler.ComponentGitConfig,
		Path:         retiredPath,
		ResourceKind: reconciler.ResourceManagedPath,
		Digest:       testDigest("old managed bytes"),
		AcceptedAt:   state.AppliedAt,
	}
	writeStateJSON(t, req.Home, state)

	req.FailBeforeEffectPath = retiredPath
	result, err := r.Apply(context.Background(), req)
	if err != nil {
		t.Fatalf("retirement apply: %v", err)
	}
	if result.Outcome != reconciler.OutcomePartial || !hasBlocker(result.Blockers, reconciler.BlockerOperationalFailure) {
		t.Fatalf("retirement outcome=%s blockers=%#v, want partial operational failure", result.Outcome, result.Blockers)
	}
	if !pathExists(retiredPath) {
		t.Fatalf("retirement deleted path despite injected interruption")
	}
	state, err = reconciler.ReadState(req.Home)
	if err != nil {
		t.Fatalf("read interrupted state: %v", err)
	}
	if len(state.PendingWork) != 1 {
		t.Fatalf("pending work = %#v, want one retirement journal entry", state.PendingWork)
	}
	pending := state.PendingWork[0]
	if pending.Path != retiredPath || pending.Intent != string(reconciler.ChangeRetireResource) {
		t.Fatalf("pending work = %#v, want retirement for %s", pending, retiredPath)
	}
	if _, ok := state.Ownership[retiredPath]; !ok {
		t.Fatalf("interrupted retirement released ownership")
	}
}

func TestRetirementRecoveryReleasesOwnershipAfterInterruptedDeletion(t *testing.T) {
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
	retiredPath := filepath.Join(req.Home, "legacy", "deleted-before-state-commit")
	state.Ownership[retiredPath] = reconciler.Ownership{
		Component:    reconciler.ComponentGitConfig,
		Path:         retiredPath,
		ResourceKind: reconciler.ResourceManagedPath,
		Digest:       testDigest("old managed bytes"),
		AcceptedAt:   state.AppliedAt,
	}
	state.PendingWork = []reconciler.JournalEntry{{
		Component:    reconciler.ComponentGitConfig,
		Path:         retiredPath,
		ResourceKind: reconciler.ResourceManagedPath,
		Intent:       string(reconciler.ChangeRetireResource),
		Precondition: testDigest("old managed bytes"),
	}}
	writeStateJSON(t, req.Home, state)

	result, err := r.Apply(context.Background(), req)
	if err != nil {
		t.Fatalf("recovery apply: %v", err)
	}
	if result.Outcome != reconciler.OutcomeNoChange && result.Outcome != reconciler.OutcomeApplied {
		t.Fatalf("recovery outcome = %s", result.Outcome)
	}
	state, err = reconciler.ReadState(req.Home)
	if err != nil {
		t.Fatalf("read recovered state: %v", err)
	}
	if len(state.PendingWork) != 0 {
		t.Fatalf("pending retirement was not cleared: %#v", state.PendingWork)
	}
	if _, ok := state.Ownership[retiredPath]; ok {
		t.Fatalf("retired ownership was not released during recovery")
	}
}

func TestRetirementDoesNotRunForOneShotFilteredOrSuspendedComponents(t *testing.T) {
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
	retiredPath := filepath.Join(req.Home, "legacy", "filtered-git-shim")
	writeText(t, retiredPath, "old managed bytes")
	state.Ownership[retiredPath] = reconciler.Ownership{
		Component:    reconciler.ComponentGitConfig,
		Path:         retiredPath,
		ResourceKind: reconciler.ResourceManagedPath,
		Digest:       testDigest("old managed bytes"),
		AcceptedAt:   state.AppliedAt,
	}
	writeStateJSON(t, req.Home, state)

	filteredReq := req
	filteredReq.Components = []reconciler.ComponentID{reconciler.ComponentShell}
	filteredPlan, err := r.Plan(context.Background(), filteredReq)
	if err != nil {
		t.Fatalf("filtered plan: %v", err)
	}
	if len(filteredPlan.Retirements) != 0 {
		t.Fatalf("one-shot component filter planned retirement: %#v", filteredPlan.Retirements)
	}

	state.Scope.Excluded = []reconciler.ComponentID{reconciler.ComponentGitConfig}
	writeStateJSON(t, req.Home, state)
	suspendedReq := req
	suspendedReq.ReplaceScope = false
	suspendedPlan, err := r.Plan(context.Background(), suspendedReq)
	if err != nil {
		t.Fatalf("suspended plan: %v", err)
	}
	if len(suspendedPlan.Retirements) != 0 {
		t.Fatalf("suspended component planned retirement: %#v", suspendedPlan.Retirements)
	}
	if !pathExists(retiredPath) {
		t.Fatalf("suspended retirement mutated content during plan")
	}
}

func TestRetirementNeverDeletesSystemDependenciesOrToolManagedState(t *testing.T) {
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
	systemPath := filepath.Join(req.Home, "system", "git")
	toolStatePath := filepath.Join(req.Home, "runtime", "node", "versions")
	writeText(t, systemPath, "system dependency marker")
	writeText(t, toolStatePath, "tool managed state")
	state.Ownership[systemPath] = reconciler.Ownership{
		Component:    reconciler.ComponentGitConfig,
		Path:         systemPath,
		ResourceKind: reconciler.ResourceSystemDependency,
		Digest:       testDigest("system dependency marker"),
		AcceptedAt:   state.AppliedAt,
	}
	state.Ownership[toolStatePath] = reconciler.Ownership{
		Component:    reconciler.ComponentGitConfig,
		Path:         toolStatePath,
		ResourceKind: reconciler.ResourceToolManagedState,
		Digest:       testDigest("tool managed state"),
		AcceptedAt:   state.AppliedAt,
	}
	writeStateJSON(t, req.Home, state)

	plan, err := r.Plan(context.Background(), req)
	if err != nil {
		t.Fatalf("plan: %v", err)
	}
	for _, retirement := range plan.Retirements {
		if retirement.Path == systemPath || retirement.Path == toolStatePath {
			t.Fatalf("planned forbidden retirement: %#v", retirement)
		}
	}
	applied, err := r.Apply(context.Background(), req)
	if err != nil {
		t.Fatalf("apply: %v", err)
	}
	if applied.Outcome != reconciler.OutcomeNoChange && applied.Outcome != reconciler.OutcomeApplied {
		t.Fatalf("apply outcome = %s", applied.Outcome)
	}
	if got := readText(t, systemPath); got != "system dependency marker" {
		t.Fatalf("system dependency was mutated: %q", got)
	}
	if got := readText(t, toolStatePath); got != "tool managed state" {
		t.Fatalf("tool managed state was mutated: %q", got)
	}
	state, err = reconciler.ReadState(req.Home)
	if err != nil {
		t.Fatalf("read post-apply state: %v", err)
	}
	if _, ok := state.Ownership[systemPath]; !ok {
		t.Fatalf("system dependency ownership was released")
	}
	if _, ok := state.Ownership[toolStatePath]; !ok {
		t.Fatalf("tool managed state ownership was released")
	}
}

func TestDoctorReportsSuspendedComponentWhoseCatalogDefinitionDisappeared(t *testing.T) {
	t.Parallel()

	r := contractReconciler()
	req := contractRequest(t.TempDir())
	legacyComponent := reconciler.ComponentID("legacy-component")
	legacyPath := filepath.Join(req.Home, "legacy", "owned")
	writeText(t, legacyPath, "legacy bytes")
	writeStateJSON(t, req.Home, reconciler.State{
		SchemaVersion:  reconciler.CurrentStateSchema,
		DesiredStateID: "older-release",
		Target:         req.Target,
		Scope: reconciler.WorkstationScope{
			Excluded: []reconciler.ComponentID{legacyComponent},
		},
		Ownership: map[string]reconciler.Ownership{
			legacyPath: {
				Component:    legacyComponent,
				Path:         legacyPath,
				ResourceKind: reconciler.ResourceManagedPath,
				Digest:       testDigest("legacy bytes"),
				AcceptedAt:   "2026-07-10T00:00:00Z",
			},
		},
	})

	doctor, err := r.Doctor(context.Background(), req)
	if err != nil {
		t.Fatalf("doctor: %v", err)
	}
	if doctor.Outcome != reconciler.OutcomeUnhealthy {
		t.Fatalf("doctor outcome = %s checks=%#v", doctor.Outcome, doctor.Checks)
	}
	if !hasUnhealthyCheck(doctor.Checks, "suspended-orphan:legacy-component") {
		t.Fatalf("doctor checks=%#v, want suspended orphan report", doctor.Checks)
	}
	if checkByName(doctor.Checks, "managed:legacy-component") != nil {
		t.Fatalf("doctor inspected suspended component ownership: %#v", doctor.Checks)
	}
	if got := readText(t, legacyPath); got != "legacy bytes" {
		t.Fatalf("doctor mutated suspended component content: %q", got)
	}
}

func TestManagedToolVersionSwitchCleansOldPayloadAfterSuccessfulInstallWithoutRetirement(t *testing.T) {
	t.Parallel()

	oldArtifact := []byte("#!/bin/sh\nprintf 'old lazygit\\n'\n")
	newArtifact := []byte("#!/bin/sh\nprintf 'new lazygit\\n'\n")
	oldSHA := testDigestBytes(oldArtifact)
	newSHA := testDigestBytes(newArtifact)
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/old":
			_, _ = w.Write(oldArtifact)
		case "/new":
			_, _ = w.Write(newArtifact)
		default:
			http.NotFound(w, r)
		}
	}))
	t.Cleanup(server.Close)

	oldReconciler := managedToolReconciler("managed-tool-old", oldSHA, "v-old", server.URL+"/old", oldSHA)
	newReconciler := managedToolReconciler("managed-tool-new", newSHA, "v-new", server.URL+"/new", newSHA)
	req := contractRequest(t.TempDir())
	req.Exclude = []reconciler.ComponentID{reconciler.ComponentGitHubSSH}
	req.Components = []reconciler.ComponentID{reconciler.ComponentLazygit}
	req.Yes = true

	if applied, err := oldReconciler.Apply(context.Background(), req); err != nil || applied.Outcome != reconciler.OutcomeApplied {
		t.Fatalf("old apply outcome=%s err=%v", applied.Outcome, err)
	}
	oldPayload := filepath.Join(req.Home, "tools", "lazygit", "v-old", "lazygit")
	newPayload := filepath.Join(req.Home, "tools", "lazygit", "v-new", "lazygit")
	plan, err := newReconciler.Plan(context.Background(), req)
	if err != nil {
		t.Fatalf("new plan: %v", err)
	}
	for _, retirement := range plan.Retirements {
		if retirement.Path == oldPayload {
			t.Fatalf("ordinary tool version switch reported old payload as retirement: %#v", retirement)
		}
	}
	if !hasChangeKindPath(plan.Changes, reconciler.ChangeCleanupManagedTool, oldPayload) {
		t.Fatalf("plan changes=%#v, want planned cleanup for old payload", plan.Changes)
	}
	applied, err := newReconciler.Apply(context.Background(), req)
	if err != nil {
		t.Fatalf("new apply: %v", err)
	}
	if applied.Outcome != reconciler.OutcomeApplied {
		t.Fatalf("new apply outcome = %s blockers=%#v", applied.Outcome, applied.Blockers)
	}
	if pathExists(oldPayload) {
		t.Fatalf("old managed tool payload still exists after successful switch")
	}
	if got := readText(t, newPayload); got != string(newArtifact) {
		t.Fatalf("new payload content = %q, want new artifact", got)
	}
	state, err := reconciler.ReadState(req.Home)
	if err != nil {
		t.Fatalf("read state: %v", err)
	}
	if _, ok := state.Ownership[oldPayload]; ok {
		t.Fatalf("old managed tool ownership was not released")
	}
	if _, ok := state.Ownership[newPayload]; !ok {
		t.Fatalf("new managed tool ownership was not recorded")
	}
}

func TestManagedToolCatalogRemovalStillReportsRetirementDuringToolLockChange(t *testing.T) {
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
	removedToolPath := filepath.Join(req.Home, "tools", "removed", "v-old", "removed")
	writeText(t, removedToolPath, "removed tool")
	state.ToolLockSHA256 = strings.Repeat("0", 64)
	state.Ownership[removedToolPath] = reconciler.Ownership{
		Component:    reconciler.ComponentGitConfig,
		Path:         removedToolPath,
		ResourceKind: reconciler.ResourceManagedTool,
		Digest:       testDigest("removed tool"),
		AcceptedAt:   state.AppliedAt,
	}
	writeStateJSON(t, req.Home, state)

	plan, err := r.Plan(context.Background(), req)
	if err != nil {
		t.Fatalf("plan: %v", err)
	}
	found := false
	for _, retirement := range plan.Retirements {
		if retirement.Path == removedToolPath {
			found = true
		}
	}
	if !found {
		t.Fatalf("plan retirements=%#v, want catalog-removed managed tool retirement", plan.Retirements)
	}
	if hasChangeKindPath(plan.Changes, reconciler.ChangeCleanupManagedTool, removedToolPath) {
		t.Fatalf("catalog-removed managed tool was planned as version-switch cleanup: %#v", plan.Changes)
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

func TestDoctorClassifiesHTTPSDiagnosticFailures(t *testing.T) {
	t.Parallel()

	for _, tc := range []struct {
		name string
		err  error
		want string
	}{
		{
			name: "dns",
			err: &url.Error{
				Op:  "Get",
				URL: "https://user:pass@example.invalid",
				Err: &net.DNSError{Name: "example.invalid", Err: "no such host"},
			},
			want: "dns: lookup example.invalid failed",
		},
		{
			name: "timeout",
			err:  context.DeadlineExceeded,
			want: "timeout: HTTPS diagnostic timed out",
		},
		{
			name: "canceled",
			err:  context.Canceled,
			want: "interrupted: HTTPS diagnostic canceled",
		},
		{
			name: "network unreachable",
			err: &url.Error{
				Op:  "Get",
				URL: "https://example.invalid",
				Err: &net.OpError{Err: syscall.ENETUNREACH},
			},
			want: "network-unreachable: HTTPS endpoint is unreachable",
		},
		{
			name: "tls",
			err: &url.Error{
				Op:  "Get",
				URL: "https://example.invalid",
				Err: x509.UnknownAuthorityError{},
			},
			want: "tls: HTTPS TLS verification failed",
		},
	} {
		tc := tc
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()

			r := reconciler.New(reconciler.Options{
				DesiredStateID: "doctor-classification-contract",
				ToolLockSHA256: strings.Repeat("d", 64),
				DiagnosticURLs: []string{"https://user:pass@example.invalid"},
				HTTPClient: &http.Client{Transport: roundTripFunc(func(*http.Request) (*http.Response, error) {
					return nil, tc.err
				})},
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
			if doctor.Outcome != reconciler.OutcomeUnhealthy {
				t.Fatalf("doctor outcome = %s checks=%#v", doctor.Outcome, doctor.Checks)
			}
			check := checkByName(doctor.Checks, "https-diagnostic")
			if check == nil {
				t.Fatalf("doctor checks = %#v, want https diagnostic", doctor.Checks)
			}
			if check.Message != tc.want {
				t.Fatalf("message = %q, want %q", check.Message, tc.want)
			}
			if strings.Contains(check.Message, "user:pass") {
				t.Fatalf("diagnostic leaked credentials: %#v", check)
			}
		})
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

func managedToolReconciler(desiredStateID string, toolLockSHA256 string, version string, artifactURL string, artifactSHA256 string) reconciler.Reconciler {
	return reconciler.New(reconciler.Options{
		DesiredStateID: desiredStateID,
		ToolLockSHA256: toolLockSHA256,
		ToolLock: release.ToolLock{Tools: map[release.ManagedTool]release.ToolVersion{
			release.ManagedToolLazygit: {
				Version: version,
				Targets: map[platform.ArtifactTarget]release.ToolArtifact{
					platform.TargetDarwinARM64: {
						URL:          artifactURL,
						ArtifactType: release.ArtifactTypeRawExecutable,
						SHA256:       artifactSHA256,
					},
				},
			},
		}},
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

func fnmLinuxToolLock() release.ToolLock {
	return release.ToolLock{Tools: map[release.ManagedTool]release.ToolVersion{
		release.ManagedToolFNM: {
			Version: "v-test",
			Targets: map[platform.ArtifactTarget]release.ToolArtifact{
				platform.TargetLinuxAMD64: {
					URL:          "https://example.invalid/fnm",
					ArtifactType: release.ArtifactTypeZip,
					SHA256:       strings.Repeat("f", 64),
				},
			},
		},
	}}
}

func hasChange(changes []reconciler.Change, component reconciler.ComponentID, kind reconciler.ResourceKind) bool {
	for _, change := range changes {
		if change.Component == component && change.ResourceKind == kind {
			return true
		}
	}
	return false
}

func hasChangeKindPath(changes []reconciler.Change, kind reconciler.ChangeKind, path string) bool {
	for _, change := range changes {
		if change.Kind == kind && change.Path == path {
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

func hasUnhealthyCheck(checks []reconciler.Check, name string) bool {
	for _, check := range checks {
		if check.Name == name && !check.Healthy {
			return true
		}
	}
	return false
}

func hasComponentStatus(results []reconciler.ComponentResult, component reconciler.ComponentID, status reconciler.ComponentStatus) bool {
	for _, result := range results {
		if result.Component == component && result.Status == status {
			return true
		}
	}
	return false
}

func hasDurableEffect(effects []string, want string) bool {
	for _, effect := range effects {
		if effect == want {
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
	if err := os.MkdirAll(filepath.Dir(reconciler.StatePath(home)), 0o700); err != nil {
		t.Fatalf("mkdir state dir: %v", err)
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
	err     error
	effects []string
	missing []reconciler.Capability
}

type roundTripFunc func(*http.Request) (*http.Response, error)

func (fn roundTripFunc) RoundTrip(request *http.Request) (*http.Response, error) {
	return fn(request)
}

func checkByName(checks []reconciler.Check, name string) *reconciler.Check {
	for index := range checks {
		if checks[index].Name == name {
			return &checks[index]
		}
	}
	return nil
}

func (adapter *recordingSystemAdapter) MissingCapabilities(context.Context, reconciler.Request, []reconciler.ComponentID) ([]reconciler.Capability, error) {
	return append([]reconciler.Capability(nil), adapter.missing...), nil
}

func (adapter *recordingSystemAdapter) ApplySystemDependencies(_ context.Context, _ reconciler.Request, missing []reconciler.Capability) ([]string, error) {
	adapter.applied = append(adapter.applied, append([]reconciler.Capability(nil), missing...))
	if adapter.err != nil {
		return adapter.effects, adapter.err
	}
	if len(adapter.effects) > 0 {
		return adapter.effects, nil
	}
	return []string{"system-adapter"}, nil
}
