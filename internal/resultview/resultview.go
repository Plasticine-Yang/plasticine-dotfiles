package resultview

import (
	"sort"
	"strings"

	"github.com/Plasticine-Yang/plasticine-dotfiles/internal/reconciler"
)

type View struct {
	Components       []ComponentGroup
	ComponentDetails []reconciler.ComponentResult
	Risks            []Risk
	Changes          []ChangeGroup
	Checks           []CheckGroup
	UnhealthyChecks  []reconciler.Check
	HealthyCount     int
	UnhealthyCount   int
	NextActions      []string
}

type ComponentGroup struct {
	Status     string
	Components []reconciler.ComponentID
}

type RiskKind string

const (
	RiskSystemChange      RiskKind = "system-change"
	RiskConflict          RiskKind = "conflict"
	RiskRetirement        RiskKind = "retirement"
	RiskBlocker           RiskKind = "blocked"
	RiskExternalInstaller RiskKind = "external-installer"
)

type Risk struct {
	Kind        RiskKind
	Component   reconciler.ComponentID
	Path        string
	Summary     string
	Adoptable   bool
	BlockerCode reconciler.BlockerCode
}

type ChangeGroup struct {
	Component reconciler.ComponentID
	Kinds     []ChangeKindGroup
}

type ChangeKindGroup struct {
	Kind    string
	Changes []reconciler.Change
}

type CheckGroup struct {
	Category string
	Checks   []reconciler.Check
}

func Project(command string, result reconciler.Result) View {
	view := View{
		Components:       projectComponents(result),
		ComponentDetails: append([]reconciler.ComponentResult(nil), result.Components...),
		Risks:            projectRisks(result),
		Changes:          projectChanges(result.Changes),
		NextActions:      projectNextActions(command, result),
	}
	view.Checks, view.UnhealthyChecks, view.HealthyCount, view.UnhealthyCount = projectChecks(result.Checks)
	return view
}

func projectComponents(result reconciler.Result) []ComponentGroup {
	groups := map[string][]reconciler.ComponentID{}
	for _, change := range result.Changes {
		if change.Component != "" {
			groups["will-change"] = appendUniqueComponent(groups["will-change"], change.Component)
		}
	}
	for _, conflict := range result.Conflicts {
		groups["blocked"] = appendUniqueComponent(groups["blocked"], conflict.Component)
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
		groups[status] = appendUniqueComponent(groups[status], component.Component)
	}
	for _, component := range result.Scope.Suspended {
		groups["suspended"] = appendUniqueComponent(groups["suspended"], component)
	}
	var projected []ComponentGroup
	for _, status := range []string{"will-change", "blocked", "skipped", "suspended", "succeeded", "active"} {
		components := groups[status]
		if len(components) == 0 {
			continue
		}
		sort.Slice(components, func(i, j int) bool { return components[i] < components[j] })
		projected = append(projected, ComponentGroup{Status: status, Components: components})
	}
	return projected
}

func projectRisks(result reconciler.Result) []Risk {
	var risks []Risk
	for _, change := range result.Changes {
		if change.SystemChange {
			risks = append(risks, Risk{
				Kind:      RiskSystemChange,
				Component: change.Component,
				Path:      change.Path,
				Summary:   strings.TrimSpace(change.Summary),
			})
		}
		if change.Kind == reconciler.ChangeRunExternalInstaller {
			risks = append(risks, Risk{
				Kind:      RiskExternalInstaller,
				Component: change.Component,
				Path:      change.Path,
				Summary:   strings.TrimSpace(change.Summary),
			})
		}
	}
	for _, conflict := range result.Conflicts {
		risks = append(risks, Risk{
			Kind:      RiskConflict,
			Component: conflict.Component,
			Path:      conflict.Path,
			Summary:   conflict.Reason,
			Adoptable: conflict.Adoptable,
		})
	}
	for _, retirement := range result.Retirements {
		risks = append(risks, Risk{
			Kind:      RiskRetirement,
			Component: retirement.Component,
			Path:      retirement.Path,
			Summary:   retirement.Reason,
		})
	}
	for _, blocker := range result.Blockers {
		risks = append(risks, Risk{
			Kind:        RiskBlocker,
			Summary:     blocker.Message,
			BlockerCode: blocker.Code,
		})
	}
	return risks
}

func projectChanges(changes []reconciler.Change) []ChangeGroup {
	byComponent := map[reconciler.ComponentID][]reconciler.Change{}
	for _, change := range changes {
		byComponent[change.Component] = append(byComponent[change.Component], change)
	}
	components := make([]reconciler.ComponentID, 0, len(byComponent))
	for component := range byComponent {
		components = append(components, component)
	}
	sort.Slice(components, func(i, j int) bool { return components[i] < components[j] })

	groups := make([]ChangeGroup, 0, len(components))
	for _, component := range components {
		byKind := map[string][]reconciler.Change{}
		for _, change := range byComponent[component] {
			key := string(change.Kind) + "/" + string(change.ResourceKind)
			byKind[key] = append(byKind[key], change)
		}
		keys := make([]string, 0, len(byKind))
		for key := range byKind {
			keys = append(keys, key)
		}
		sort.Strings(keys)
		group := ChangeGroup{Component: component}
		for _, key := range keys {
			group.Kinds = append(group.Kinds, ChangeKindGroup{
				Kind:    key,
				Changes: append([]reconciler.Change(nil), byKind[key]...),
			})
		}
		groups = append(groups, group)
	}
	return groups
}

func projectChecks(checks []reconciler.Check) ([]CheckGroup, []reconciler.Check, int, int) {
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

	byCategory := map[string][]reconciler.Check{}
	var unhealthy []reconciler.Check
	healthyCount := 0
	for _, check := range ordered {
		if check.Healthy {
			healthyCount++
		} else {
			unhealthy = append(unhealthy, check)
		}
		category := CheckCategory(check.Name)
		byCategory[category] = append(byCategory[category], check)
	}
	var groups []CheckGroup
	for _, category := range []string{"Support", "Managed Resources", "Network Diagnostics", "GitHub SSH", "Other Checks"} {
		if len(byCategory[category]) == 0 {
			continue
		}
		groups = append(groups, CheckGroup{
			Category: category,
			Checks:   append([]reconciler.Check(nil), byCategory[category]...),
		})
	}
	return groups, unhealthy, healthyCount, len(unhealthy)
}

func CheckCategory(name string) string {
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

func projectNextActions(command string, result reconciler.Result) []string {
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

func checkPriority(name string) int {
	switch CheckCategory(name) {
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

func appendUniqueComponent(values []reconciler.ComponentID, value reconciler.ComponentID) []reconciler.ComponentID {
	for _, existing := range values {
		if existing == value {
			return values
		}
	}
	return append(values, value)
}
