package main

import (
	"bytes"
	"strings"
	"testing"

	"github.com/Plasticine-Yang/plasticine-dotfiles/internal/reconciler"
)

func TestPrintResultIncludesComponentStatuses(t *testing.T) {
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
	if !strings.Contains(text, "component: git-config succeeded") {
		t.Fatalf("output did not include succeeded component status:\n%s", text)
	}
	if !strings.Contains(text, "component: github-ssh awaiting-owner-action awaiting Owner action") {
		t.Fatalf("output did not include awaiting Owner action component status:\n%s", text)
	}
}

func TestPrintResultIncludesChangePath(t *testing.T) {
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
	if !strings.Contains(text, "change: shell login-shell system /usr/bin/zsh set login shell") {
		t.Fatalf("output did not include change path:\n%s", text)
	}
}
