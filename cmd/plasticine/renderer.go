package main

import (
	"fmt"
	"io"
	"os"
	"sort"
	"strings"

	"github.com/Plasticine-Yang/plasticine-dotfiles/internal/reconciler"
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
	renderComponentSummary(writer, result, style)
	renderRisks(writer, result, style)
	renderChanges(writer, result)
	renderDurableEffects(writer, result)
	renderChecks(writer, result, style)
	renderNextActions(writer, command, result, style)
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

func renderComponentSummary(writer io.Writer, result reconciler.Result, style outputStyle) {
	groups := map[string][]string{}
	for _, change := range result.Changes {
		if change.Component != "" {
			groups["will-change"] = appendUniqueString(groups["will-change"], string(change.Component))
		}
	}
	for _, conflict := range result.Conflicts {
		groups["blocked"] = appendUniqueString(groups["blocked"], string(conflict.Component))
	}
	for _, component := range result.Components {
		status := string(component.Status)
		switch component.Status {
		case reconciler.ComponentBlocked, reconciler.ComponentAwaitingOwnerAction:
			status = "blocked"
		case reconciler.ComponentSkipped:
			status = "skipped"
		case reconciler.ComponentSuspended:
			status = "suspended"
		case reconciler.ComponentSucceeded:
			status = "succeeded"
		}
		groups[status] = appendUniqueString(groups[status], string(component.Component))
	}
	for _, component := range result.Scope.Suspended {
		groups["suspended"] = appendUniqueString(groups["suspended"], string(component))
	}
	if len(groups) == 0 {
		return
	}
	fmt.Fprintln(writer, "\nComponents")
	for _, status := range []string{"will-change", "blocked", "skipped", "suspended", "succeeded", "active"} {
		values := groups[status]
		if len(values) == 0 {
			continue
		}
		sort.Strings(values)
		fmt.Fprintf(writer, "- %s: %s\n", style.status(status), strings.Join(values, ", "))
	}
	for _, component := range result.Components {
		if strings.TrimSpace(component.Message) != "" {
			fmt.Fprintf(writer, "  detail: %s %s %s\n", component.Component, component.Status, strings.TrimSpace(component.Message))
		}
	}
}

func renderRisks(writer io.Writer, result reconciler.Result, style outputStyle) {
	if len(result.Blockers) == 0 && len(result.Conflicts) == 0 && len(result.Retirements) == 0 && !hasSystemChanges(result.Changes) {
		return
	}
	fmt.Fprintln(writer, "\nRisks And Blockers")
	for _, change := range result.Changes {
		if change.SystemChange {
			fmt.Fprintf(writer, "- %s: %s %s\n", style.status("system-change"), change.Component, strings.TrimSpace(change.Summary))
		}
	}
	for _, conflict := range result.Conflicts {
		fmt.Fprintf(writer, "- %s: %s adoptable=%t path=%s reason=%s\n", style.status("conflict"), conflict.Component, conflict.Adoptable, conflict.Path, conflict.Reason)
	}
	for _, retirement := range result.Retirements {
		fmt.Fprintf(writer, "- retirement: %s %s %s\n", retirement.Component, retirement.Path, retirement.Reason)
	}
	for _, blocker := range result.Blockers {
		fmt.Fprintf(writer, "- blocked: %s %s\n", blocker.Code, blocker.Message)
	}
}

func renderChanges(writer io.Writer, result reconciler.Result) {
	if result.StateMigration != nil {
		fmt.Fprintf(writer, "\nState Migration\n- %d->%d %s\n", result.StateMigration.FromSchema, result.StateMigration.ToSchema, result.StateMigration.Message)
	}
	if len(result.Changes) == 0 {
		return
	}
	byComponent := map[reconciler.ComponentID][]reconciler.Change{}
	for _, change := range result.Changes {
		byComponent[change.Component] = append(byComponent[change.Component], change)
	}
	fmt.Fprintln(writer, "\nChanges")
	for _, component := range sortedChangeComponents(byComponent) {
		name := string(component)
		if name == "" {
			name = "global"
		}
		fmt.Fprintf(writer, "[%s]\n", name)
		byKind := map[string][]reconciler.Change{}
		for _, change := range byComponent[component] {
			key := string(change.Kind) + "/" + string(change.ResourceKind)
			byKind[key] = append(byKind[key], change)
		}
		for _, key := range sortedChangeGroupKeys(byKind) {
			fmt.Fprintf(writer, "  %s\n", key)
			for _, change := range byKind[key] {
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

func renderChecks(writer io.Writer, result reconciler.Result, style outputStyle) {
	if len(result.Checks) == 0 {
		return
	}
	healthyCount := 0
	unhealthyCount := 0
	groups := map[string][]reconciler.Check{}
	var unhealthy []reconciler.Check
	for _, check := range sortedChecks(result.Checks) {
		if check.Healthy {
			healthyCount++
		} else {
			unhealthyCount++
			unhealthy = append(unhealthy, check)
		}
		category := checkCategory(check.Name)
		groups[category] = append(groups[category], check)
	}
	fmt.Fprintf(writer, "\nChecks: healthy=%d unhealthy=%d\n", healthyCount, unhealthyCount)
	if len(unhealthy) > 0 {
		primary := unhealthy[0]
		fmt.Fprintf(writer, "primary_failure: %s %s\n", primary.Name, strings.TrimSpace(primary.Message))
		fmt.Fprintln(writer, "Unhealthy Checks")
		for _, check := range unhealthy {
			fmt.Fprintf(writer, "- %s %s %s\n", style.status("unhealthy"), check.Name, strings.TrimSpace(check.Message))
		}
	}
	fmt.Fprintln(writer, "Grouped Checks")
	for _, category := range []string{"Support", "Managed Resources", "Network Diagnostics", "GitHub SSH", "Other Checks"} {
		checks := groups[category]
		if len(checks) == 0 {
			continue
		}
		fmt.Fprintf(writer, "%s\n", category)
		for _, check := range checksByHealth(checks, false) {
			status := "healthy"
			if !check.Healthy {
				status = "unhealthy"
			}
			fmt.Fprintf(writer, "- %s %s %s\n", style.status(status), check.Name, strings.TrimSpace(check.Message))
		}
	}
}

func checksByHealth(checks []reconciler.Check, healthyFirst bool) []reconciler.Check {
	ordered := make([]reconciler.Check, 0, len(checks))
	for _, wantHealthy := range []bool{false, true} {
		if healthyFirst {
			wantHealthy = !wantHealthy
		}
		for _, check := range checks {
			if check.Healthy == wantHealthy {
				ordered = append(ordered, check)
			}
		}
	}
	return ordered
}

func checkCategory(name string) string {
	switch {
	case name == "artifact-target" || name == "support-floor":
		return "Support"
	case strings.HasPrefix(name, "managed:") || strings.HasPrefix(name, "suspended-orphan:"):
		return "Managed Resources"
	case name == "https-diagnostic":
		return "Network Diagnostics"
	case name == "github-ssh":
		return "GitHub SSH"
	default:
		return "Other Checks"
	}
}

func renderNextActions(writer io.Writer, command string, result reconciler.Result, style outputStyle) {
	actions := nextActions(command, result)
	if len(actions) == 0 {
		return
	}
	fmt.Fprintf(writer, "\nNext Actions\n")
	for _, action := range actions {
		fmt.Fprintf(writer, "- %s %s\n", style.paint("1", "next:"), action)
	}
}

func nextActions(command string, result reconciler.Result) []string {
	actions := map[string]bool{}
	add := func(action string) {
		if action != "" {
			actions[action] = true
		}
	}
	if result.Outcome == reconciler.OutcomeDenied {
		add("review the plan, then rerun apply interactively or with --yes")
	}
	for _, conflict := range result.Conflicts {
		if conflict.Adoptable {
			add("review conflicting paths, then rerun with --adopt if Plasticine should take ownership")
		} else {
			add("repair the non-adoptable conflict manually, then rerun plan")
		}
	}
	for _, blocker := range result.Blockers {
		switch blocker.Code {
		case reconciler.BlockerSystemChangeAuthorization:
			add("review planned system changes, then rerun with --allow-system")
		case reconciler.BlockerSecretReferenceRequired:
			add("provide --github-key <path> or choose a key interactively")
		case reconciler.BlockerStalePlan:
			add("rerun plan or apply because local state changed after planning")
		case reconciler.BlockerPendingWork:
			add("rerun apply --yes to recover or complete pending work")
		case reconciler.BlockerOwnerActionRequired:
			add("complete the external Owner action, then rerun apply")
		case reconciler.BlockerConflict:
			add("resolve conflicts or rerun with --adopt for adoptable paths")
		}
	}
	if result.Outcome == reconciler.OutcomePartial {
		add("run doctor, then rerun apply or apply --component <id> for the failed component")
	}
	if result.Outcome == reconciler.OutcomeUnhealthy {
		add("fix unhealthy checks, then rerun doctor")
	}
	if command == "plan" && result.Outcome == reconciler.OutcomeChangesPlanned {
		add("review changes, then run apply")
	}
	list := make([]string, 0, len(actions))
	for action := range actions {
		list = append(list, action)
	}
	sort.Strings(list)
	return list
}

func sortedChangeComponents(values map[reconciler.ComponentID][]reconciler.Change) []reconciler.ComponentID {
	components := make([]reconciler.ComponentID, 0, len(values))
	for component := range values {
		components = append(components, component)
	}
	sort.Slice(components, func(i, j int) bool {
		return components[i] < components[j]
	})
	return components
}

func sortedChangeGroupKeys(values map[string][]reconciler.Change) []string {
	keys := make([]string, 0, len(values))
	for key := range values {
		keys = append(keys, key)
	}
	sort.Strings(keys)
	return keys
}

func sortedChecks(checks []reconciler.Check) []reconciler.Check {
	ordered := append([]reconciler.Check(nil), checks...)
	sort.SliceStable(ordered, func(i, j int) bool {
		left := ordered[i]
		right := ordered[j]
		if left.Healthy != right.Healthy {
			return !left.Healthy
		}
		if checkPriority(left.Name) != checkPriority(right.Name) {
			return checkPriority(left.Name) < checkPriority(right.Name)
		}
		if left.Name != right.Name {
			return left.Name < right.Name
		}
		return left.Message < right.Message
	})
	return ordered
}

func checkPriority(name string) int {
	switch checkCategory(name) {
	case "Support":
		return 10
	case "Managed Resources":
		return 20
	case "Network Diagnostics":
		return 30
	case "GitHub SSH":
		return 40
	default:
		return 50
	}
}

func hasSystemChanges(changes []reconciler.Change) bool {
	for _, change := range changes {
		if change.SystemChange {
			return true
		}
	}
	return false
}

func joinComponents(components []reconciler.ComponentID) string {
	parts := make([]string, 0, len(components))
	for _, component := range components {
		parts = append(parts, string(component))
	}
	return strings.Join(parts, ", ")
}

func appendUniqueString(values []string, value string) []string {
	for _, existing := range values {
		if existing == value {
			return values
		}
	}
	return append(values, value)
}
