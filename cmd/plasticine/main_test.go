package main

import (
	"bytes"
	"strings"
	"testing"

	"github.com/Plasticine-Yang/plasticine-dotfiles/internal/reconciler"
)

func TestRenderResultGroupsComponentStatuses(t *testing.T) {
	t.Parallel()

	var output bytes.Buffer
	printResultTo(&output, "apply", reconciler.Result{
		Outcome: reconciler.OutcomePartial,
		Components: []reconciler.ComponentResult{
			{
				Component: reconciler.ComponentGitConfig,
				Status:    reconciler.ComponentSucceeded,
			},
			{
				Component: reconciler.ComponentGitHubSSH,
				Status:    reconciler.ComponentAwaitingOwnerAction,
				Message:   "awaiting Owner action for system capability: apple-development-tools",
			},
		},
	})

	text := output.String()
	if !strings.Contains(text, "Components") || !strings.Contains(text, "succeeded: git-config") {
		t.Fatalf("output did not include succeeded component status:\n%s", text)
	}
	if !strings.Contains(text, "detail: github-ssh awaiting-owner-action awaiting Owner action") {
		t.Fatalf("output did not include awaiting Owner action component status:\n%s", text)
	}
}

func TestRenderResultGroupsRiskyChangePathAndNextAction(t *testing.T) {
	t.Parallel()

	var output bytes.Buffer
	printResultTo(&output, "plan", reconciler.Result{
		Outcome: reconciler.OutcomeChangesPlanned,
		Changes: []reconciler.Change{
			{
				Component:    reconciler.ComponentShell,
				Kind:         reconciler.ChangeLoginShell,
				ResourceKind: reconciler.ResourceLoginShell,
				Path:         "/usr/bin/zsh",
				Summary:      "set login shell to Zsh; open a new terminal after Apply",
				SystemChange: true,
			},
		},
	})

	text := output.String()
	for _, want := range []string{
		"Risks And Blockers",
		"system-change: shell set login shell",
		"[shell]",
		"login-shell/login-shell",
		"- system /usr/bin/zsh :: set login shell",
		"next: review changes, then run apply",
	} {
		if !strings.Contains(text, want) {
			t.Fatalf("output missing %q:\n%s", want, text)
		}
	}
}

func TestRenderResultAddsFailureNextActions(t *testing.T) {
	t.Parallel()

	var output bytes.Buffer
	printResultTo(&output, "apply", reconciler.Result{
		Outcome: reconciler.OutcomeBlocked,
		Blockers: []reconciler.Blocker{
			{
				Code:    reconciler.BlockerSystemChangeAuthorization,
				Message: "system changes require --allow-system",
			},
		},
		Conflicts: []reconciler.Conflict{
			{
				Component: reconciler.ComponentGitConfig,
				Path:      "/tmp/.gitconfig",
				Adoptable: true,
				Reason:    "unmanaged content exists at a managed path",
			},
		},
	})

	text := output.String()
	for _, want := range []string{
		"review planned system changes, then rerun with --allow-system",
		"review conflicting paths, then rerun with --adopt",
	} {
		if !strings.Contains(text, want) {
			t.Fatalf("output missing next action %q:\n%s", want, text)
		}
	}
}

func TestRenderResultColorPolicy(t *testing.T) {
	t.Parallel()

	result := reconciler.Result{Outcome: reconciler.OutcomeUnhealthy}
	var forced bytes.Buffer
	renderResult(&forced, "doctor", result, outputCapabilities{Color: colorAlways, TTY: false})
	if !strings.Contains(forced.String(), "\x1b[") {
		t.Fatalf("forced color output did not contain ANSI escapes:\n%q", forced.String())
	}

	var noColor bytes.Buffer
	renderResult(&noColor, "doctor", result, outputCapabilities{
		Color: colorAlways,
		TTY:   true,
		Env: map[string]string{
			"NO_COLOR": "1",
		},
	})
	if strings.Contains(noColor.String(), "\x1b[") {
		t.Fatalf("NO_COLOR output contained ANSI escapes:\n%q", noColor.String())
	}
}

func TestParseColorModeRejectsInvalidValue(t *testing.T) {
	t.Parallel()

	if _, err := parseColorMode("sometimes"); err == nil {
		t.Fatal("invalid color mode was accepted")
	}
	if _, err := parseColorMode("always"); err != nil {
		t.Fatalf("valid color mode rejected: %v", err)
	}
}

func TestRenderDoctorGroupsChecks(t *testing.T) {
	t.Parallel()

	var output bytes.Buffer
	printResultTo(&output, "doctor", reconciler.Result{
		Outcome: reconciler.OutcomeUnhealthy,
		Checks: []reconciler.Check{
			{Name: "managed:shell", Healthy: true, Message: "/tmp/.zshrc"},
			{Name: "https-diagnostic", Healthy: false, Message: "timeout: HTTPS diagnostic timed out"},
			{Name: "github-ssh", Healthy: true, Message: "skipped because github-ssh is inactive"},
		},
	})

	text := output.String()
	for _, want := range []string{
		"Checks: healthy=2 unhealthy=1",
		"primary_failure: https-diagnostic timeout",
		"Unhealthy Checks",
		"Grouped Checks",
		"Managed Resources",
		"Network Diagnostics",
		"GitHub SSH",
		"unhealthy https-diagnostic timeout",
		"healthy github-ssh skipped",
		"next: fix unhealthy checks, then rerun doctor",
	} {
		if !strings.Contains(text, want) {
			t.Fatalf("doctor output missing %q:\n%s", want, text)
		}
	}
	if strings.Contains(text, "user:pass") {
		t.Fatalf("doctor output leaked credentials:\n%s", text)
	}
}
