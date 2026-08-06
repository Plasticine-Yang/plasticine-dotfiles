package tui

import (
	"context"
	"strings"
	"testing"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"

	"github.com/Plasticine-Yang/plasticine-dotfiles/internal/reconciler"
	"github.com/Plasticine-Yang/plasticine-dotfiles/internal/workstation"
)

func TestDashboardStartsWithoutAPlan(t *testing.T) {
	t.Parallel()

	model := testModel(t, nil)
	model.width = 120
	model.height = 32
	view := model.View()
	for _, want := range []string{
		"PLASTICINE",
		"Dashboard",
		"No plan loaded",
		"Startup performs no Plan",
	} {
		if !strings.Contains(view, want) {
			t.Fatalf("dashboard missing %q:\n%s", want, view)
		}
	}
	if model.planResult != nil || model.doctorResult != nil || model.operation != "" {
		t.Fatalf("dashboard started an operation: %#v", model)
	}
}

func TestNavigationHelpAndResponsiveLayout(t *testing.T) {
	t.Parallel()

	state := testModel(t, nil)
	state.width = 90
	state.height = 28

	updated, _ := state.Update(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune("3")})
	state = updated.(model)
	if state.screen != screenComponents {
		t.Fatalf("screen = %d, want Components", state.screen)
	}

	updated, _ = state.Update(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune("?")})
	state = updated.(model)
	if state.dialog != dialogHelp || !strings.Contains(state.View(), "Keyboard help") {
		t.Fatalf("help did not open:\n%s", state.View())
	}

	state.width = 59
	state.height = 17
	if view := state.View(); !strings.Contains(view, "Terminal is too small") {
		t.Fatalf("small layout did not show resize prompt:\n%s", view)
	}
}

func TestMinimumSupportedSizeDoesNotOverflow(t *testing.T) {
	t.Parallel()

	state := testModel(t, map[string]string{"NO_COLOR": "1"})
	state.width = 60
	state.height = 18
	for _, target := range []screen{screenDashboard, screenPlan, screenComponents, screenDoctor} {
		state.screen = target
		if target == screenPlan {
			result := reconciler.Result{
				Outcome: reconciler.OutcomeChangesPlanned,
				Scope: reconciler.ScopeSummary{
					Active: []reconciler.ComponentID{
						reconciler.ComponentShell,
						reconciler.ComponentGitConfig,
						reconciler.ComponentGitHubSSH,
						reconciler.ComponentNeovim,
						reconciler.ComponentLazygit,
						reconciler.ComponentFNM,
						reconciler.ComponentUV,
						reconciler.ComponentZellij,
					},
				},
			}
			state.planResult = &result
		}
		if target == screenDoctor {
			result := reconciler.Result{
				Outcome: reconciler.OutcomeHealthy,
				Checks: []reconciler.Check{
					{Name: "artifact-target", Healthy: true, Message: "darwin/arm64"},
				},
			}
			state.doctorResult = &result
		}
		view := state.View()
		if got := lipgloss.Width(view); got > state.width {
			t.Fatalf("screen %d width = %d, want <= %d", target, got, state.width)
		}
		if got := lipgloss.Height(view); got > state.height {
			t.Fatalf("screen %d height = %d, want <= %d", target, got, state.height)
		}
	}
}

func TestNoColorThemeContainsNoANSIColorSequences(t *testing.T) {
	t.Parallel()

	model := testModel(t, map[string]string{"NO_COLOR": "1"})
	model.width = 120
	model.height = 32
	if view := model.View(); strings.Contains(view, "\x1b[") {
		t.Fatalf("NO_COLOR view contained ANSI color sequences: %q", view)
	}
}

func TestScopeDraftAndOneRunFilterStaySeparate(t *testing.T) {
	t.Parallel()

	model := testModel(t, nil)
	model.scopeKnown = true
	model.screen = screenComponents
	model.componentCursor = 1
	model.column = columnScope
	model.toggleComponentRow()

	if !model.scopeExcluded[reconciler.ComponentGitConfig] || !model.scopeDirty {
		t.Fatalf("scope draft was not changed: %#v", model.scopeExcluded)
	}
	if !model.filterSelected[reconciler.ComponentGitConfig] {
		t.Fatal("scope draft unexpectedly changed one-run filter")
	}

	model.column = columnRun
	model.toggleComponentRow()
	if model.filterSelected[reconciler.ComponentGitConfig] {
		t.Fatal("one-run filter was not changed")
	}
	if !model.scopeExcluded[reconciler.ComponentGitConfig] {
		t.Fatal("one-run filter unexpectedly changed scope draft")
	}

	request := model.operationRequest()
	if !request.ReplaceScope || !containsComponent(request.Exclude, reconciler.ComponentGitConfig) {
		t.Fatalf("request scope = replace:%t exclude:%#v", request.ReplaceScope, request.Exclude)
	}
	if containsComponent(request.Components, reconciler.ComponentGitConfig) {
		t.Fatalf("request one-run filter includes disabled component: %#v", request.Components)
	}
}

func TestInvalidDependencySelectionsAreReportedInline(t *testing.T) {
	t.Parallel()

	model := testModel(t, nil)
	model.scopeKnown = true
	model.scopeExcluded[reconciler.ComponentShell] = true
	model.filterSelected[reconciler.ComponentShell] = false
	messages := strings.Join(model.validationMessages(), "\n")
	for _, want := range []string{
		"Scope: fnm requires active shell",
		"Scope: github-ssh requires active shell",
		"Run filter: fnm requires selected shell",
		"Run filter: github-ssh requires selected shell",
	} {
		if !strings.Contains(messages, want) {
			t.Fatalf("validation missing %q:\n%s", want, messages)
		}
	}
}

func TestAuthorizationRequiresEveryRiskClass(t *testing.T) {
	t.Parallel()

	result := reconciler.Result{
		Changes: []reconciler.Change{{
			Kind:         reconciler.ChangeLoginShell,
			SystemChange: true,
		}},
		Conflicts: []reconciler.Conflict{{
			Adoptable: true,
		}},
		Retirements: []reconciler.Retirement{{
			Path: "/managed/old",
		}},
	}
	items := authorizationItems(result, true)
	if len(items) != 4 {
		t.Fatalf("authorization items = %#v, want ordinary plus three risks", items)
	}
	model := testModel(t, nil)
	model.authItems = items
	if model.authorizationComplete() {
		t.Fatal("unchecked risks were accepted")
	}
	for index := range model.authItems {
		model.authItems[index].checked = true
	}
	if !model.authorizationComplete() {
		t.Fatal("all checked risks were not accepted")
	}
	decision := model.authorizationDecision()
	if !decision.Approved || !decision.AllowSystemChanges || !decision.AllowAdoption || !decision.AllowRetirements {
		t.Fatalf("decision = %#v", decision)
	}
	riskLines := strings.Join(authorizationRiskLines(result, 60), "\n")
	for _, want := range []string{"System Change", "Adoption", "Retirement", "/managed/old"} {
		if !strings.Contains(riskLines, want) {
			t.Fatalf("authorization risk details missing %q:\n%s", want, riskLines)
		}
	}
}

func TestAuthorizationRiskPaginationIsBounded(t *testing.T) {
	t.Parallel()

	state := testModel(t, map[string]string{"NO_COLOR": "1"})
	state.width = 60
	state.height = 18
	state.dialog = dialogAuthorization
	state.authItems = []authItem{
		{label: "Apply the exact reviewed plan", kind: "ordinary"},
		{label: "Back up and adopt listed Conflicts", kind: "adoption"},
	}
	for index := 0; index < 20; index++ {
		state.authResult.Conflicts = append(state.authResult.Conflicts, reconciler.Conflict{
			Component: reconciler.ComponentGitConfig,
			Path:      "/managed/conflict/" + strings.Repeat("x", index+1),
			Adoptable: true,
		})
	}
	view := state.View()
	if got := lipgloss.Height(view); got > state.height {
		t.Fatalf("authorization dialog height = %d, want <= %d", got, state.height)
	}
	if !strings.Contains(view, "1-3/20") {
		t.Fatalf("authorization pagination missing first page marker:\n%s", view)
	}

	updated, _ := state.Update(tea.KeyMsg{Type: tea.KeyPgDown})
	state = updated.(model)
	if !strings.Contains(state.View(), "6-8/20") {
		t.Fatalf("authorization pagination did not advance:\n%s", state.View())
	}
}

func TestOperationResultsAndCancellationUpdateScreens(t *testing.T) {
	t.Parallel()

	state := testModel(t, nil)
	state.operation = "plan"
	result := reconciler.Result{
		Outcome: reconciler.OutcomeChangesPlanned,
		Scope: reconciler.ScopeSummary{
			Excluded: []reconciler.ComponentID{reconciler.ComponentGitConfig},
		},
	}
	updated, _ := state.Update(operationDoneMsg{operation: "plan", result: result})
	state = updated.(model)
	if state.screen != screenPlan || state.planResult == nil {
		t.Fatalf("plan result did not open Plan screen: %#v", state)
	}
	if !state.scopeKnown || !state.scopeExcluded[reconciler.ComponentGitConfig] {
		t.Fatalf("plan result did not load scope: %#v", state.scopeExcluded)
	}

	state.operation = "doctor"
	state.interruptPending = true
	updated, command := state.Update(operationDoneMsg{operation: "doctor", err: context.Canceled})
	state = updated.(model)
	if command == nil || state.exitReason != ExitOwnerQuit {
		t.Fatalf("canceled operation did not request quit: reason=%d command=%v", state.exitReason, command)
	}
}

func TestBlockedPlanWithoutScopeDoesNotReviewDraft(t *testing.T) {
	t.Parallel()

	state := testModel(t, nil)
	state.operation = "plan"
	state.scopeKnown = true
	state.scopeDirty = true
	state.scopeReviewed = false
	result := reconciler.Result{
		Outcome: reconciler.OutcomeBlocked,
		Blockers: []reconciler.Blocker{{
			Code:    reconciler.BlockerStateUnreadable,
			Message: "state is unreadable",
		}},
	}
	updated, _ := state.Update(operationDoneMsg{operation: "plan", result: result})
	state = updated.(model)
	if state.scopeReviewed {
		t.Fatal("blocked Plan without an observable Scope reviewed the draft")
	}
	if !strings.Contains(state.status, "could not validate") {
		t.Fatalf("status = %q, want Scope validation failure", state.status)
	}
}

func TestViewportScrollsPlanDetails(t *testing.T) {
	t.Parallel()

	state := testModel(t, nil)
	state.width = 80
	state.height = 20
	state.screen = screenPlan
	state.detailFocused = true
	changes := make([]reconciler.Change, 40)
	for index := range changes {
		changes[index] = reconciler.Change{
			Component:    reconciler.ComponentGitConfig,
			Kind:         reconciler.ChangeUpdateManagedPath,
			ResourceKind: reconciler.ResourceManagedPath,
			Path:         "/a/very/long/path/to/config/" + strings.Repeat("x", index+1),
			Summary:      "materialize configuration",
		}
	}
	result := reconciler.Result{
		Outcome: reconciler.OutcomeChangesPlanned,
		Scope: reconciler.ScopeSummary{
			Active: []reconciler.ComponentID{reconciler.ComponentGitConfig},
		},
		Changes: changes,
	}
	state.planResult = &result
	state.planCursor = 1
	state.resizeViewport()
	if state.viewport.YOffset != 0 {
		t.Fatalf("initial viewport offset = %d", state.viewport.YOffset)
	}

	updated, _ := state.Update(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune("j")})
	state = updated.(model)
	if state.viewport.YOffset == 0 {
		t.Fatal("detail viewport did not scroll")
	}
}

func TestLongPathTruncationPreservesBothEnds(t *testing.T) {
	t.Parallel()

	got := truncateMiddle("/Users/owner/.plasticine/very/long/path/to/config/file.toml", 24)
	if len([]rune(got)) > 24 || !strings.HasPrefix(got, "/Users/owner") || !strings.HasSuffix(got, "file.toml") {
		t.Fatalf("truncateMiddle = %q", got)
	}
}

func testModel(t *testing.T, env map[string]string) model {
	t.Helper()
	runtime, err := workstation.New(workstation.Options{
		Home:            t.TempDir(),
		WorkstationRoot: t.TempDir(),
		DiagnosticURLs:  []string{},
	})
	if err != nil {
		t.Fatalf("new runtime: %v", err)
	}
	return newModel(runtime, env, &operationBridge{ctx: context.Background()})
}

func containsComponent(components []reconciler.ComponentID, want reconciler.ComponentID) bool {
	for _, component := range components {
		if component == want {
			return true
		}
	}
	return false
}
