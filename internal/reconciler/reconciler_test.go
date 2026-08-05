package reconciler_test

import (
	"context"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/Plasticine-Yang/plasticine-dotfiles/internal/platform"
	"github.com/Plasticine-Yang/plasticine-dotfiles/internal/reconciler"
)

func TestPlanApplyDoctorContractUsesOnlyObservableEffects(t *testing.T) {
	t.Parallel()

	home := t.TempDir()
	r := reconciler.New(reconciler.Options{
		DesiredStateID: "desired-state-test",
		ToolLockSHA256: strings.Repeat("a", 64),
	})
	req := reconciler.Request{
		Home:   home,
		Target: platform.TargetDarwinARM64,
		Host: platform.Host{
			OS:      platform.OSDarwin,
			Arch:    platform.ArchARM64,
			Family:  platform.FamilyMacOS,
			Version: "13.0",
		},
		ReplaceScope: true,
		Exclude: []reconciler.ComponentID{
			reconciler.ComponentGitHubSSH,
			reconciler.ComponentNeovim,
			reconciler.ComponentLazygit,
			reconciler.ComponentFNM,
			reconciler.ComponentUV,
			reconciler.ComponentZellij,
		},
	}

	plan, err := r.Plan(context.Background(), req)
	if err != nil {
		t.Fatalf("plan failed: %v", err)
	}
	if plan.Outcome != reconciler.OutcomeChangesPlanned {
		t.Fatalf("plan outcome = %s, want %s", plan.Outcome, reconciler.OutcomeChangesPlanned)
	}
	if len(plan.DurableEffects) != 0 {
		t.Fatalf("plan reported durable effects: %v", plan.DurableEffects)
	}
	if pathExists(reconciler.StatePath(home)) {
		t.Fatalf("plan wrote reconciliation state at %s", reconciler.StatePath(home))
	}

	denied, err := r.Apply(context.Background(), req)
	if err != nil {
		t.Fatalf("apply without consent failed unexpectedly: %v", err)
	}
	if denied.Outcome != reconciler.OutcomeDenied {
		t.Fatalf("apply without --yes outcome = %s, want %s", denied.Outcome, reconciler.OutcomeDenied)
	}
	if pathExists(reconciler.StatePath(home)) {
		t.Fatalf("denied apply wrote reconciliation state at %s", reconciler.StatePath(home))
	}

	req.Yes = true
	applied, err := r.Apply(context.Background(), req)
	if err != nil {
		t.Fatalf("apply with consent failed: %v", err)
	}
	if applied.Outcome != reconciler.OutcomeApplied {
		t.Fatalf("apply outcome = %s, want %s", applied.Outcome, reconciler.OutcomeApplied)
	}
	if !contains(applied.DurableEffects, reconciler.StatePath(home)) {
		t.Fatalf("apply durable effects = %v, want state path", applied.DurableEffects)
	}

	state, err := reconciler.ReadState(home)
	if err != nil {
		t.Fatalf("read state: %v", err)
	}
	if state.DesiredStateID != "desired-state-test" {
		t.Fatalf("state desired id = %q", state.DesiredStateID)
	}
	if state.ToolLockSHA256 != strings.Repeat("a", 64) {
		t.Fatalf("state tool lock sha = %q", state.ToolLockSHA256)
	}
	if state.Target != platform.TargetDarwinARM64 {
		t.Fatalf("state target = %s, want %s", state.Target, platform.TargetDarwinARM64)
	}

	second, err := r.Apply(context.Background(), req)
	if err != nil {
		t.Fatalf("second apply failed: %v", err)
	}
	if second.Outcome != reconciler.OutcomeNoChange {
		t.Fatalf("second apply outcome = %s, want %s", second.Outcome, reconciler.OutcomeNoChange)
	}

	doctor, err := r.Doctor(context.Background(), req)
	if err != nil {
		t.Fatalf("doctor failed: %v", err)
	}
	if doctor.Outcome != reconciler.OutcomeHealthy {
		t.Fatalf("doctor outcome = %s, want %s", doctor.Outcome, reconciler.OutcomeHealthy)
	}
	if len(doctor.DurableEffects) != 0 {
		t.Fatalf("doctor reported durable effects: %v", doctor.DurableEffects)
	}
}

func TestUnsupportedSystemChangesAreDeterministicAndNonMutating(t *testing.T) {
	t.Parallel()

	home := t.TempDir()
	r := reconciler.New(reconciler.Options{
		DesiredStateID: "desired-state-test",
		ToolLockSHA256: strings.Repeat("b", 64),
	})
	req := reconciler.Request{
		Home: home,
		Target: platform.ArtifactTarget{
			OS:   platform.OSLinux,
			Arch: platform.ArchAMD64,
		},
		Host: platform.Host{
			OS:      platform.OSLinux,
			Arch:    platform.ArchAMD64,
			Family:  platform.FamilyOtherLinux,
			Version: "39",
		},
		RequireSystemChange: true,
		Yes:                 true,
		AllowSystem:         true,
	}

	plan, err := r.Plan(context.Background(), req)
	if err != nil {
		t.Fatalf("plan failed: %v", err)
	}
	if plan.Outcome != reconciler.OutcomeBlocked {
		t.Fatalf("plan outcome = %s, want %s", plan.Outcome, reconciler.OutcomeBlocked)
	}
	if !hasBlocker(plan.Blockers, reconciler.BlockerUnsupportedSystemChange) {
		t.Fatalf("blockers = %#v, want unsupported system change", plan.Blockers)
	}
	if len(plan.DurableEffects) != 0 {
		t.Fatalf("unsupported plan reported durable effects: %v", plan.DurableEffects)
	}

	applied, err := r.Apply(context.Background(), req)
	if err != nil {
		t.Fatalf("apply failed: %v", err)
	}
	if applied.Outcome != reconciler.OutcomeBlocked {
		t.Fatalf("apply outcome = %s, want %s", applied.Outcome, reconciler.OutcomeBlocked)
	}
	if pathExists(reconciler.StatePath(home)) {
		t.Fatalf("blocked apply wrote reconciliation state at %s", reconciler.StatePath(home))
	}
}

func TestDefaultPlasticineHomeUsesAnIsolatedHOME(t *testing.T) {
	hostHome := t.TempDir()
	isolatedHome := t.TempDir()
	t.Setenv("PLASTICINE_HOME", "")
	t.Setenv("HOME", isolatedHome)

	got, err := reconciler.DefaultPlasticineHome()
	if err != nil {
		t.Fatalf("default home: %v", err)
	}
	want := filepath.Join(isolatedHome, ".plasticine")
	if got != want {
		t.Fatalf("default home = %q, want %q", got, want)
	}
	if strings.Contains(got, hostHome) {
		t.Fatalf("default home unexpectedly used host home %q", hostHome)
	}
}

func TestDefaultPlasticineHomeHonorsExplicitEnvironment(t *testing.T) {
	explicitHome := t.TempDir()
	t.Setenv("PLASTICINE_HOME", explicitHome)

	got, err := reconciler.DefaultPlasticineHome()
	if err != nil {
		t.Fatalf("default home: %v", err)
	}
	if got != explicitHome {
		t.Fatalf("default home = %q, want %q", got, explicitHome)
	}
}

func pathExists(path string) bool {
	_, err := os.Stat(path)
	return err == nil
}

func contains(values []string, want string) bool {
	for _, value := range values {
		if value == want {
			return true
		}
	}
	return false
}

func hasBlocker(blockers []reconciler.Blocker, want reconciler.BlockerCode) bool {
	for _, blocker := range blockers {
		if blocker.Code == want {
			return true
		}
	}
	return false
}
