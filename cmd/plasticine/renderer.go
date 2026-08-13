package main

import (
	"fmt"
	"io"
	"os"
	"strings"

	"github.com/Plasticine-Yang/plasticine-dotfiles/internal/reconciler"
	"github.com/Plasticine-Yang/plasticine-dotfiles/internal/resultview"
)

type colorMode string

const (
	colorAuto   colorMode = "auto"
	colorAlways colorMode = "always"
	colorNever  colorMode = "never"
)

type outputCapabilities struct {
	Color colorMode
	TTY   bool
	Env   map[string]string
}

func parseColorMode(value string) (colorMode, error) {
	switch colorMode(value) {
	case colorAuto, colorAlways, colorNever:
		return colorMode(value), nil
	default:
		return "", fmt.Errorf("invalid --color %q; use auto, always, or never", value)
	}
}

func defaultOutputCapabilities() outputCapabilities {
	return outputCapabilities{
		Color: colorAuto,
		TTY:   stdoutIsTTY(),
		Env: map[string]string{
			"NO_COLOR": os.Getenv("NO_COLOR"),
		},
	}
}

func stdoutIsTTY() bool {
	info, err := os.Stdout.Stat()
	return err == nil && info.Mode()&os.ModeCharDevice != 0
}

func printResultTo(writer io.Writer, command string, result reconciler.Result) {
	renderResult(writer, command, result, outputCapabilities{Color: colorNever})
}

func renderResult(writer io.Writer, command string, result reconciler.Result, caps outputCapabilities) {
	style := newOutputStyle(caps)
	view := resultview.Project(command, result)
	fmt.Fprintf(writer, "%s %s\n", strings.ToUpper(command), style.outcome(result.Outcome))
	fmt.Fprintf(writer, "outcome: %s\n", result.Outcome)
	fmt.Fprintf(writer, "target: %s\n", result.Target)
	fmt.Fprintf(writer, "support: %s\n", result.Support.Level)
	if result.Support.Reason != "" {
		fmt.Fprintf(writer, "support_reason: %s\n", result.Support.Reason)
	}
	if result.DesiredStateID != "" {
		fmt.Fprintf(writer, "desired_state: %s\n", result.DesiredStateID)
	}
	fmt.Fprintf(writer, "scope: active=%d excluded=%d suspended=%d\n", len(result.Scope.Active), len(result.Scope.Excluded), len(result.Scope.Suspended))
	if len(result.Scope.Active) > 0 {
		fmt.Fprintf(writer, "active_components: %s\n", joinComponents(result.Scope.Active))
	}
	if len(result.Scope.Excluded) > 0 {
		fmt.Fprintf(writer, "excluded_components: %s\n", joinComponents(result.Scope.Excluded))
	}
	if len(result.Scope.Suspended) > 0 {
		fmt.Fprintf(writer, "suspended_components: %s\n", joinComponents(result.Scope.Suspended))
	}
	renderComponentSummary(writer, view, style)
	renderRisks(writer, view, style)
	renderChanges(writer, result, view)
	renderDurableEffects(writer, result)
	renderChecks(writer, view, style)
	renderNextActions(writer, view, style)
}

type outputStyle struct {
	enabled bool
}

func newOutputStyle(caps outputCapabilities) outputStyle {
	if caps.Env != nil && caps.Env["NO_COLOR"] != "" {
		return outputStyle{}
	}
	switch caps.Color {
	case colorAlways:
		return outputStyle{enabled: true}
	case colorAuto:
		return outputStyle{enabled: caps.TTY}
	default:
		return outputStyle{}
	}
}

func (s outputStyle) paint(code string, text string) string {
	if !s.enabled {
		return text
	}
	return "\x1b[" + code + "m" + text + "\x1b[0m"
}

func (s outputStyle) outcome(outcome reconciler.Outcome) string {
	switch outcome {
	case reconciler.OutcomeApplied, reconciler.OutcomeNoChange, reconciler.OutcomeHealthy:
		return s.paint("32;1", string(outcome))
	case reconciler.OutcomeChangesPlanned:
		return s.paint("36;1", string(outcome))
	case reconciler.OutcomeBlocked, reconciler.OutcomeDenied, reconciler.OutcomePartial, reconciler.OutcomeUnhealthy:
		return s.paint("31;1", string(outcome))
	default:
		return string(outcome)
	}
}

func (s outputStyle) status(status string) string {
	switch status {
	case "will-change":
		return s.paint("36", status)
	case "blocked", "conflict", "system-change", "unhealthy":
		return s.paint("31", status)
	case "succeeded", "healthy", "no-change":
		return s.paint("32", status)
	case "skipped", "suspended":
		return s.paint("33", status)
	default:
		return status
	}
}

func renderComponentSummary(writer io.Writer, view resultview.View, style outputStyle) {
	if len(view.Components) == 0 {
		return
	}
	fmt.Fprintln(writer, "\nComponents")
	for _, group := range view.Components {
		fmt.Fprintf(writer, "- %s: %s\n", style.status(group.Status), joinComponents(group.Components))
	}
	for _, component := range view.ComponentDetails {
		if strings.TrimSpace(component.Message) != "" {
			fmt.Fprintf(writer, "  detail: %s %s %s\n", component.Component, component.Status, strings.TrimSpace(component.Message))
		}
	}
}

func renderRisks(writer io.Writer, view resultview.View, style outputStyle) {
	if len(view.Risks) == 0 {
		return
	}
	fmt.Fprintln(writer, "\nRisks And Blockers")
	for _, risk := range view.Risks {
		switch risk.Kind {
		case resultview.RiskSystemChange:
			fmt.Fprintf(writer, "- %s: %s %s\n", style.status(string(risk.Kind)), risk.Component, risk.Summary)
		case resultview.RiskExternalInstaller:
			fmt.Fprintf(writer, "- %s: %s url=%s %s\n", style.status(string(risk.Kind)), risk.Component, risk.Path, risk.Summary)
		case resultview.RiskConflict:
			fmt.Fprintf(writer, "- %s: %s adoptable=%t path=%s reason=%s\n", style.status(string(risk.Kind)), risk.Component, risk.Adoptable, risk.Path, risk.Summary)
		case resultview.RiskRetirement:
			fmt.Fprintf(writer, "- retirement: %s %s %s\n", risk.Component, risk.Path, risk.Summary)
		case resultview.RiskBlocker:
			fmt.Fprintf(writer, "- blocked: %s %s\n", risk.BlockerCode, risk.Summary)
		}
	}
}

func renderChanges(writer io.Writer, result reconciler.Result, view resultview.View) {
	if result.StateMigration != nil {
		fmt.Fprintf(writer, "\nState Migration\n- %d->%d %s\n", result.StateMigration.FromSchema, result.StateMigration.ToSchema, result.StateMigration.Message)
	}
	if len(view.Changes) == 0 {
		return
	}
	fmt.Fprintln(writer, "\nChanges")
	for _, group := range view.Changes {
		name := string(group.Component)
		if name == "" {
			name = "global"
		}
		fmt.Fprintf(writer, "[%s]\n", name)
		for _, kind := range group.Kinds {
			fmt.Fprintf(writer, "  %s\n", kind.Kind)
			for _, change := range kind.Changes {
				scope := "user"
				if change.SystemChange {
					scope = "system"
				}
				path := change.Path
				if path == "" {
					path = "(no path)"
				}
				fmt.Fprintf(writer, "  - %s %s :: %s\n", scope, path, strings.TrimSpace(change.Summary))
			}
		}
	}
}

func renderDurableEffects(writer io.Writer, result reconciler.Result) {
	if len(result.DurableEffects) == 0 {
		return
	}
	fmt.Fprintln(writer, "\nDurable Effects")
	for _, effect := range result.DurableEffects {
		fmt.Fprintf(writer, "- %s\n", effect)
	}
}

func renderChecks(writer io.Writer, view resultview.View, style outputStyle) {
	if len(view.Checks) == 0 {
		return
	}
	fmt.Fprintf(writer, "\nChecks: healthy=%d unhealthy=%d\n", view.HealthyCount, view.UnhealthyCount)
	if len(view.UnhealthyChecks) > 0 {
		primary := view.UnhealthyChecks[0]
		fmt.Fprintf(writer, "primary_failure: %s %s\n", primary.Name, strings.TrimSpace(primary.Message))
		fmt.Fprintln(writer, "Unhealthy Checks")
		for _, check := range view.UnhealthyChecks {
			fmt.Fprintf(writer, "- %s %s %s\n", style.status("unhealthy"), check.Name, strings.TrimSpace(check.Message))
		}
	}
	fmt.Fprintln(writer, "Grouped Checks")
	for _, group := range view.Checks {
		fmt.Fprintf(writer, "%s\n", group.Category)
		for _, check := range group.Checks {
			status := "healthy"
			if !check.Healthy {
				status = "unhealthy"
			}
			fmt.Fprintf(writer, "- %s %s %s\n", style.status(status), check.Name, strings.TrimSpace(check.Message))
		}
	}
}

func renderNextActions(writer io.Writer, view resultview.View, style outputStyle) {
	if len(view.NextActions) == 0 {
		return
	}
	fmt.Fprintf(writer, "\nNext Actions\n")
	for _, action := range view.NextActions {
		fmt.Fprintf(writer, "- %s %s\n", style.paint("1", "next:"), action)
	}
}

func joinComponents(components []reconciler.ComponentID) string {
	parts := make([]string, 0, len(components))
	for _, component := range components {
		parts = append(parts, string(component))
	}
	return strings.Join(parts, ", ")
}
