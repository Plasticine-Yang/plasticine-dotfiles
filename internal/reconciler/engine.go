package reconciler

import (
	"archive/tar"
	"archive/zip"
	"bytes"
	"compress/gzip"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
	"syscall"
	"time"

	"github.com/Plasticine-Yang/plasticine-dotfiles/internal/platform"
	"github.com/Plasticine-Yang/plasticine-dotfiles/internal/release"
)

const preconditionAbsent = "absent"

type planSnapshot struct {
	Result         Result
	State          State
	ToolLockSHA256 string
	Desired        []desiredResource
	DesiredByPath  map[string]desiredResource
	ScopeChanged   bool
	SystemChange   bool
	Loaded         loadedState
	Active         map[ComponentID]bool
	Filtered       map[ComponentID]bool
	Secret         *SecretReference
	Adopt          bool
}

func (r Reconciler) buildPlan(ctx context.Context, req Request) (planSnapshot, error) {
	if err := ctx.Err(); err != nil {
		return planSnapshot{}, err
	}

	loaded, loadErr := loadState(req.Home)
	state := loaded.State
	result := Result{
		DesiredStateID: r.desiredStateID,
		Target:         req.Target,
		Support:        platform.ClassifySupport(req.Host),
	}
	snapshot := planSnapshot{
		Result:         result,
		State:          state,
		ToolLockSHA256: r.toolLockSHA256,
		DesiredByPath:  map[string]desiredResource{},
		Loaded:         loaded,
		Active:         map[ComponentID]bool{},
		Filtered:       map[ComponentID]bool{},
		Adopt:          req.Adopt,
	}

	if result.Support.Level == platform.SupportUnsupported {
		snapshot.block(BlockerUnsupportedTarget, result.Support.Reason)
		return snapshot, nil
	}
	if loadErr != nil {
		snapshot.block(BlockerStateUnreadable, loadErr.Error())
		return snapshot, nil
	}
	if len(state.PendingWork) > 0 {
		snapshot.block(BlockerPendingWork, "pending component work requires Apply recovery before planning")
		return snapshot, nil
	}
	if loaded.Migration != nil {
		snapshot.Result.StateMigration = loaded.Migration
		snapshot.Result.Changes = append(snapshot.Result.Changes, Change{
			Kind:         ChangeStateMigration,
			ResourceKind: ResourceManagedPath,
			Path:         StatePath(req.Home),
			Summary:      loaded.Migration.Message,
		})
	}

	catalog := defaultComponents()
	excluded := normalizedComponents(state.Scope.Excluded)
	if req.ReplaceScope {
		excluded = normalizedComponents(req.Exclude)
	}
	scopeExcluded := componentSet(excluded)
	activeCatalog := componentSet(catalog)
	for _, component := range catalog {
		if !scopeExcluded[component] {
			snapshot.Active[component] = true
		}
	}
	if len(req.Components) > 0 {
		filtered := componentSet(normalizedComponents(req.Components))
		snapshot.Filtered = filtered
		for component := range snapshot.Active {
			if !filtered[component] {
				delete(snapshot.Active, component)
			}
		}
		for component := range filtered {
			switch {
			case scopeExcluded[component]:
				snapshot.block(BlockerComponentExcluded, fmt.Sprintf("component %s is excluded by Workstation Scope", component))
			case !activeCatalog[component]:
				snapshot.block(BlockerUnknownComponent, fmt.Sprintf("component %s is not in the selected Desired State", component))
			}
		}
	}

	snapshot.Result.Scope = ScopeSummary{
		Excluded:  sortedComponentsFromSet(scopeExcluded),
		Active:    sortedComponentsFromSet(snapshot.Active),
		Suspended: suspendedComponents(state, scopeExcluded),
	}
	for _, component := range snapshot.Result.ActiveComponents() {
		snapshot.Result.Components = append(snapshot.Result.Components, ComponentResult{Component: component, Status: ComponentActive})
	}
	for _, component := range snapshot.Result.Scope.Suspended {
		snapshot.Result.Components = append(snapshot.Result.Components, ComponentResult{Component: component, Status: ComponentSuspended})
	}
	if req.ReplaceScope && !sameComponents(state.Scope.Excluded, excluded) {
		snapshot.ScopeChanged = true
		snapshot.Result.Changes = append(snapshot.Result.Changes, Change{
			Kind:         ChangeScopeReplacement,
			ResourceKind: ResourceManagedPath,
			Path:         StatePath(req.Home),
			Summary:      "persist Workstation Scope replacement before component effects",
		})
	}

	snapshot.validateComponentGraph()
	snapshot.validatePlatformComponentSupport(req)
	if err := snapshot.planSystemDependencies(ctx, req, r.system); err != nil {
		return planSnapshot{}, err
	}
	snapshot.planLoginShell(req)
	if req.RequireSystemChange {
		snapshot.planRequiredSystemChange(req)
	}

	secret, secretBlocker := resolveGitHubSecret(req, state, snapshot.Active[ComponentGitHubSSH])
	if secretBlocker != nil {
		snapshot.Result.Blockers = append(snapshot.Result.Blockers, *secretBlocker)
	} else if secret != nil {
		snapshot.Secret = secret
		if existing := state.SecretReferences[ComponentGitHubSSH]; existing != *secret {
			snapshot.Result.Changes = append(snapshot.Result.Changes, Change{
				Component:    ComponentGitHubSSH,
				Kind:         ChangeSecretReference,
				ResourceKind: ResourceSecretReference,
				Summary:      "persist non-secret GitHub SSH Secret Reference",
			})
		}
	}

	resourceReq := req
	resourceReq.ToolLockSHA256 = r.toolLockSHA256
	for _, component := range sortedComponentsFromSet(snapshot.Active) {
		if tool, ok := managedToolForComponent(component); ok {
			if _, hasArtifact := managedToolArtifact(r.toolLock, tool, req.Target); !hasArtifact {
				snapshot.block(BlockerUnsupportedTarget, fmt.Sprintf("Tool Lock is missing %s artifact for %s", tool, req.Target))
				continue
			}
		}
		for _, resource := range componentDesiredResources(resourceReq, component, snapshot.Secret, r.toolLock, snapshot.Active) {
			snapshot.Desired = append(snapshot.Desired, resource)
			snapshot.DesiredByPath[resource.Path] = resource
			snapshot.planResource(state, resource, req.Adopt)
		}
	}
	snapshot.planRetirements(state, req.Adopt)
	snapshot.planManagedToolCleanups(state, req.Adopt)
	snapshot.finishOutcome()
	return snapshot, nil
}

func (r Reconciler) executePlan(ctx context.Context, req Request, snapshot planSnapshot) (Result, error) {
	result := snapshot.Result
	if result.Outcome == OutcomeBlocked || result.Outcome == OutcomeNoChange {
		return result, nil
	}
	if !req.Yes && req.Authorize == nil {
		result.Outcome = OutcomeDenied
		return result, nil
	}
	if !req.Yes && !req.Authorize(result) {
		result.Outcome = OutcomeDenied
		return result, nil
	}
	if snapshot.SystemChange && !req.AllowSystem {
		result.Outcome = OutcomeBlocked
		result.Blockers = append(result.Blockers, Blocker{
			Code:    BlockerSystemChangeAuthorization,
			Message: "system changes require --allow-system",
		})
		return result, nil
	}

	state := snapshot.State
	state.SchemaVersion = CurrentStateSchema
	state.DesiredStateID = r.desiredStateID
	state.ToolLockSHA256 = r.toolLockSHA256
	state.Target = req.Target
	state.AppliedAt = r.clock().UTC().Format(time.RFC3339)
	ensureStateMaps(&state)

	if err := os.MkdirAll(req.Home, 0o700); err != nil {
		return Result{}, err
	}
	if err := os.Chmod(req.Home, 0o700); err != nil {
		return Result{}, err
	}
	if snapshot.ScopeChanged {
		state.Scope.Excluded = append([]ComponentID(nil), snapshot.Result.Scope.Excluded...)
		if err := writeState(req.Home, state); err != nil {
			return Result{}, err
		}
		result.DurableEffects = appendUnique(result.DurableEffects, StatePath(req.Home))
	}

	for _, conflict := range result.Conflicts {
		if !conflict.Adoptable {
			continue
		}
		backup, err := createBackup(req.Home, r.clock, conflict)
		if err != nil {
			return Result{}, err
		}
		if backup.Backup != "" {
			state.Backups = append(state.Backups, backup)
			result.DurableEffects = appendUnique(result.DurableEffects, backup.Backup)
		}
	}

	for _, retirement := range result.Retirements {
		change, ok, blocker := retirementChange(retirement, state)
		if blocker != nil {
			result.Outcome = OutcomeBlocked
			result.Blockers = append(result.Blockers, *blocker)
			return result, nil
		}
		if !ok {
			continue
		}
		stop, err := executeRemovalChange(req, &result, &state, change)
		if err != nil {
			return Result{}, err
		}
		if stop {
			return result, nil
		}
	}

	var failedCapabilities []Capability
	failedComponents := map[ComponentID]string{}
	awaitingOwnerAction := false
	var cleanupChanges []Change
	resourceChanges := map[ComponentID][]Change{}
	for _, change := range result.Changes {
		switch change.Kind {
		case ChangeScopeReplacement, ChangeStateMigration:
			continue
		case ChangeCleanupManagedTool:
			cleanupChanges = append(cleanupChanges, change)
			continue
		case ChangeSystemDependency:
			effects, err := r.applySystemDependency(ctx, req, change)
			for _, effect := range effects {
				result.DurableEffects = appendUnique(result.DurableEffects, effect)
			}
			remainingCapabilities := change.Capabilities
			if r.system != nil && len(change.Capabilities) > 0 {
				observed, observeErr := r.system.MissingCapabilities(ctx, req, sortedComponentsFromSet(snapshot.Active))
				if observeErr == nil {
					remainingCapabilities = intersectCapabilities(change.Capabilities, observed)
				} else if err == nil {
					err = observeErr
				}
			}
			if err != nil {
				result.Outcome = OutcomePartial
				code := BlockerOperationalFailure
				if errors.Is(err, ErrOwnerActionRequired) {
					code = BlockerOwnerActionRequired
					awaitingOwnerAction = true
				}
				result.Blockers = append(result.Blockers, Blocker{Code: code, Message: err.Error()})
				failedCapabilities = append(failedCapabilities, remainingCapabilities...)
				continue
			}
			if len(remainingCapabilities) > 0 {
				result.Outcome = OutcomePartial
				result.Blockers = append(result.Blockers, Blocker{
					Code:    BlockerOperationalFailure,
					Message: "system capabilities still missing after system change: " + capabilitiesSummary(remainingCapabilities),
				})
				failedCapabilities = append(failedCapabilities, remainingCapabilities...)
				continue
			}
			continue
		case ChangeLoginShell:
			if componentHasFailedCapability(change.Component, req, failedCapabilities) {
				continue
			}
			effects, err := applyLoginShellChange(ctx, req, change.Path)
			for _, effect := range effects {
				result.DurableEffects = appendUnique(result.DurableEffects, effect)
			}
			if err != nil {
				result.Outcome = OutcomePartial
				result.Blockers = append(result.Blockers, Blocker{Code: BlockerOperationalFailure, Message: err.Error()})
				failedComponents[change.Component] = err.Error()
			}
			continue
		case ChangeSecretReference:
			if snapshot.Secret != nil {
				state.SecretReferences[ComponentGitHubSSH] = *snapshot.Secret
			}
			continue
		}
		resourceChanges[change.Component] = append(resourceChanges[change.Component], change)
	}

	blockedBySystem := systemBlockedComponents(snapshot.Active, req, failedCapabilities)
	systemBlockedSet := systemBlockSet(blockedBySystem)
	for _, component := range sortedComponentsFromSet(systemBlockSet(blockedBySystem)) {
		block := blockedBySystem[component]
		status := ComponentBlocked
		message := "required system capability failed: " + capabilitiesSummary(failedCapabilities)
		if !block.Direct {
			status = ComponentSkipped
			message = "skipped because dependency " + string(block.Dependency) + " is blocked"
		} else if awaitingOwnerAction {
			status = ComponentAwaitingOwnerAction
			message = "awaiting Owner action for system capability: " + capabilitiesSummary(failedCapabilities)
		}
		result.Components = append(result.Components, ComponentResult{
			Component: component,
			Status:    status,
			Message:   message,
		})
	}
	blockedByComponent := componentBlockedComponents(snapshot.Active, failedComponents)
	reportedComponentBlocks := map[ComponentID]bool{}
	for _, component := range sortedComponentsFromSet(systemBlockSet(blockedByComponent)) {
		if systemBlockedSet[component] {
			continue
		}
		block := blockedByComponent[component]
		status := ComponentBlocked
		message := failedComponents[component]
		if !block.Direct {
			status = ComponentSkipped
			message = "skipped because dependency " + string(block.Dependency) + " is blocked"
		}
		result.Components = append(result.Components, ComponentResult{
			Component: component,
			Status:    status,
			Message:   message,
		})
		reportedComponentBlocks[component] = true
	}
	for _, component := range orderedComponentsFromSet(componentChangeSet(resourceChanges)) {
		if _, blocked := blockedBySystem[component]; blocked {
			continue
		}
		if block, blocked := componentBlockedComponents(snapshot.Active, failedComponents)[component]; blocked {
			if !reportedComponentBlocks[component] {
				status := ComponentBlocked
				message := failedComponents[component]
				if !block.Direct {
					status = ComponentSkipped
					message = "skipped because dependency " + string(block.Dependency) + " is blocked"
				}
				result.Components = append(result.Components, ComponentResult{
					Component: component,
					Status:    status,
					Message:   message,
				})
				reportedComponentBlocks[component] = true
			}
			continue
		}
		changes := resourceChanges[component]
		componentPending := journalEntriesFor(changes)
		state.PendingWork = append(state.PendingWork, componentPending...)
		if err := writeState(req.Home, state); err != nil {
			return Result{}, err
		}
		result.DurableEffects = appendUnique(result.DurableEffects, StatePath(req.Home))

		componentOwnership := map[string]Ownership{}
		componentFailed := false
		blockComponent := func(code BlockerCode, message string) {
			result.Outcome = OutcomePartial
			result.Blockers = append(result.Blockers, Blocker{Code: code, Message: message})
			result.Components = append(result.Components, ComponentResult{Component: component, Status: ComponentBlocked, Message: message})
			failedComponents[component] = message
			reportedComponentBlocks[component] = true
			componentFailed = true
		}
		for _, change := range changes {
			resource, ok := snapshot.DesiredByPath[change.Path]
			if !ok {
				continue
			}
			if req.BeforeMutation != nil {
				req.BeforeMutation(change)
			}
			if req.FailBeforeEffectPath == change.Path {
				blockComponent(BlockerOperationalFailure, "failure injected before materializing "+change.Path)
				break
			}
			if err := verifyPrecondition(change.Path, change.Precondition); err != nil {
				result.Outcome = OutcomeBlocked
				result.Blockers = append(result.Blockers, Blocker{Code: BlockerStalePlan, Message: err.Error()})
				return result, nil
			}
			if err := writeResource(ctx, req.Home, resource, r.httpClient); err != nil {
				blockComponent(BlockerOperationalFailure, err.Error())
				break
			}
			if resource.ResourceKind == ResourceUserService {
				effects, err := startUserService(ctx, req, resource.Path)
				if err != nil {
					blockComponent(BlockerOperationalFailure, err.Error())
					break
				}
				for _, effect := range effects {
					result.DurableEffects = appendUnique(result.DurableEffects, effect)
				}
			}
			componentOwnership[resource.Path] = Ownership{
				Component:    resource.Component,
				Path:         resource.Path,
				ResourceKind: resource.ResourceKind,
				Digest:       fileDigest(resource.Path),
				AcceptedAt:   state.AppliedAt,
			}
			result.DurableEffects = appendUnique(result.DurableEffects, resource.Path)
		}
		if componentFailed {
			continue
		}
		for path, ownership := range componentOwnership {
			state.Ownership[path] = ownership
		}
		state.PendingWork = removeJournalEntries(state.PendingWork, componentPending)
		if err := writeState(req.Home, state); err != nil {
			return Result{}, err
		}
		result.Components = append(result.Components, ComponentResult{Component: component, Status: ComponentSucceeded})
	}

	if result.Outcome != OutcomePartial {
		for _, change := range cleanupChanges {
			stop, err := executeRemovalChange(req, &result, &state, change)
			if err != nil {
				return Result{}, err
			}
			if stop {
				return result, nil
			}
			if result.Outcome == OutcomePartial {
				break
			}
		}
	}
	if result.Outcome != OutcomePartial {
		state.PendingWork = nil
	}
	if err := writeState(req.Home, state); err != nil {
		return Result{}, err
	}
	result.DurableEffects = appendUnique(result.DurableEffects, StatePath(req.Home))
	if result.Outcome != OutcomePartial {
		result.Outcome = OutcomeApplied
	}
	return result, nil
}

func (s *planSnapshot) validateComponentGraph() {
	if !s.Active[ComponentShell] {
		for _, dependent := range componentDependents(ComponentShell) {
			if s.Active[dependent] {
				s.block(BlockerMissingComponentDependency, fmt.Sprintf("%s requires active shell component", dependent))
			}
		}
	}
}

func (s *planSnapshot) validatePlatformComponentSupport(req Request) {
	if !s.Active[ComponentGitHubSSH] || req.Target.OS != platform.OSLinux {
		return
	}
	supportedFamily := req.Host.Family == platform.FamilyDebian || req.Host.Family == platform.FamilyUbuntu
	if !supportedFamily || s.Result.Support.Level != platform.SupportFull {
		s.block(BlockerUnsupportedSystemChange, "github-ssh Linux shared agent requires the Debian/Ubuntu support floor and a systemd user session")
	}
}

func (s *planSnapshot) planRequiredSystemChange(req Request) {
	switch s.Result.Support.Level {
	case platform.SupportFull:
		s.SystemChange = true
		s.Result.Changes = append(s.Result.Changes, Change{
			Kind:         ChangeSystemDependency,
			ResourceKind: ResourceSystemDependency,
			Summary:      "exercise explicit system-change authorization",
			SystemChange: true,
		})
	default:
		s.block(BlockerUnsupportedSystemChange, "host is outside the support floor for system changes")
	}
}

func (s *planSnapshot) planSystemDependencies(ctx context.Context, req Request, system SystemAdapter) error {
	missing, err := plannedMissingCapabilities(ctx, req, sortedComponentsFromSet(s.Active), system)
	if err != nil {
		return err
	}
	if containsCapability(missing, CapabilitySystemdUserSession) && s.Active[ComponentGitHubSSH] && req.Target.OS == platform.OSLinux {
		s.block(BlockerUnsupportedSystemChange, "github-ssh Linux shared agent requires an existing systemd user session")
		missing = removeCapability(missing, CapabilitySystemdUserSession)
	}
	if len(missing) == 0 {
		return nil
	}
	change := Change{
		Kind:         ChangeSystemDependency,
		ResourceKind: ResourceSystemDependency,
		Summary:      "satisfy missing system capabilities: " + capabilitiesSummary(missing),
		SystemChange: true,
		Capabilities: missing,
	}
	s.SystemChange = true
	s.Result.Changes = append(s.Result.Changes, change)
	if s.Result.Support.Level != platform.SupportFull {
		s.block(BlockerUnsupportedSystemChange, fmt.Sprintf("%s requires an unsupported system change on this host", capabilitiesSummary(missing)))
	}
	return nil
}

func (s *planSnapshot) planLoginShell(req Request) {
	if !s.Active[ComponentShell] {
		return
	}
	currentShell := strings.TrimSpace(req.LoginShell)
	desiredShell := strings.TrimSpace(req.ZshPath)
	if desiredShell == "" {
		return
	}
	if !req.LoginShellKnown || currentShell == "" {
		s.block(BlockerOperationalFailure, "current login shell could not be discovered")
		return
	}
	if loginShellSatisfied(currentShell, desiredShell) {
		return
	}
	s.SystemChange = true
	s.Result.Changes = append(s.Result.Changes, Change{
		Component:    ComponentShell,
		Kind:         ChangeLoginShell,
		ResourceKind: ResourceLoginShell,
		Path:         desiredShell,
		Summary:      "set login shell to Zsh; open a new terminal after Apply",
		SystemChange: true,
	})
	if s.Result.Support.Level != platform.SupportFull {
		s.block(BlockerUnsupportedSystemChange, "login-shell change requires a fully supported host")
	}
}

func loginShellSatisfied(currentShell string, desiredShell string) bool {
	if currentShell == desiredShell {
		return true
	}
	return filepath.Base(currentShell) == "zsh" && filepath.Base(desiredShell) == "zsh"
}

func (s *planSnapshot) planResource(state State, resource desiredResource, adopt bool) {
	if resource.ResourceKind == ResourceManagedBlock {
		s.planManagedBlock(state, resource, adopt)
		return
	}
	desiredDigest := digestResource(resource)
	currentDigest, exists := maybeFileDigest(resource.Path)
	ownership, owned := state.Ownership[resource.Path]
	precondition := preconditionAbsent
	if exists {
		precondition = currentDigest
	}
	if resource.ResourceKind == ResourceManagedTool {
		if exists && !owned {
			s.conflict(resource.Component, resource.Path, true, "unmanaged content exists at a managed tool path")
			if adopt {
				s.change(resource, ChangeInstallManagedTool, precondition)
			}
			return
		}
		if owned && exists && currentDigest != ownership.Digest {
			s.conflict(resource.Component, resource.Path, true, "managed tool payload has Owner drift")
			if adopt {
				s.change(resource, ChangeInstallManagedTool, precondition)
			}
			return
		}
		if !exists || state.ToolLockSHA256 != s.ToolLockSHA256 {
			s.change(resource, ChangeInstallManagedTool, precondition)
		}
		return
	}
	if exists && !owned {
		s.conflict(resource.Component, resource.Path, true, "unmanaged content exists at a managed path")
		if adopt {
			s.change(resource, ChangeUpdateManagedPath, precondition)
		}
		return
	}
	if owned && exists && currentDigest != ownership.Digest {
		s.conflict(resource.Component, resource.Path, true, "managed path has Owner drift")
		if adopt {
			s.change(resource, ChangeUpdateManagedPath, precondition)
		}
		return
	}
	if !exists {
		s.change(resource, ChangeCreateManagedPath, preconditionAbsent)
		return
	}
	if currentDigest != desiredDigest {
		s.change(resource, ChangeUpdateManagedPath, precondition)
	}
}

func (s *planSnapshot) planManagedBlock(state State, resource desiredResource, adopt bool) {
	data, err := os.ReadFile(resource.Path)
	if os.IsNotExist(err) {
		s.change(resource, ChangeCreateManagedBlock, preconditionAbsent)
		return
	}
	if err != nil {
		s.conflict(resource.Component, resource.Path, false, err.Error())
		return
	}
	text := string(data)
	digest := digestBytes(data)
	switch blockState(text) {
	case "empty":
		s.change(resource, ChangeCreateManagedBlock, digest)
	case "absent":
		s.conflict(resource.Component, resource.Path, true, "existing SSH config requires adoption before first managed block insertion")
		if adopt {
			s.change(resource, ChangeCreateManagedBlock, digest)
		}
	case "malformed":
		s.conflict(resource.Component, resource.Path, false, "SSH managed block markers are missing, duplicated, or malformed")
	case "healthy":
		ownership, owned := state.Ownership[resource.Path]
		if owned && ownership.Digest != digest {
			s.conflict(resource.Component, resource.Path, true, "managed SSH block has Owner drift")
			if adopt {
				s.change(resource, ChangeCreateManagedBlock, digest)
			}
			return
		}
		if !strings.Contains(text, resource.Content) {
			s.change(resource, ChangeCreateManagedBlock, digest)
		}
	}
}

func (s *planSnapshot) planRetirements(state State, adopt bool) {
	for path, ownership := range state.Ownership {
		if _, stillDesired := s.DesiredByPath[path]; stillDesired {
			continue
		}
		if !s.Active[ownership.Component] {
			continue
		}
		if ownership.ResourceKind == ResourceManagedTool &&
			state.ToolLockSHA256 != s.ToolLockSHA256 &&
			s.hasDesiredResourceKind(ownership.Component, ResourceManagedTool) {
			continue
		}
		if !retirableResourceKind(ownership.ResourceKind) {
			continue
		}
		precondition := preconditionAbsent
		currentDigest, exists := maybeFileDigest(path)
		if exists {
			precondition = currentDigest
		}
		if exists && currentDigest != ownership.Digest {
			if ownership.ResourceKind == ResourceManagedBlock && managedBlockRemovalPreservesOwnerContent(path) {
				retirement := Retirement{
					Component:    ownership.Component,
					Path:         path,
					ResourceKind: ownership.ResourceKind,
					Reason:       "owned resource is absent from the selected Desired State catalog",
					Precondition: precondition,
				}
				s.Result.Retirements = append(s.Result.Retirements, retirement)
				continue
			}
			s.conflict(ownership.Component, path, true, "retiring managed path has Owner drift")
			if !adopt {
				continue
			}
		}
		retirement := Retirement{
			Component:    ownership.Component,
			Path:         path,
			ResourceKind: ownership.ResourceKind,
			Reason:       "owned resource is absent from the selected Desired State catalog",
			Precondition: precondition,
		}
		s.Result.Retirements = append(s.Result.Retirements, retirement)
	}
}

func (s *planSnapshot) planManagedToolCleanups(state State, adopt bool) {
	if state.ToolLockSHA256 == s.ToolLockSHA256 {
		return
	}
	for path, ownership := range state.Ownership {
		if ownership.ResourceKind != ResourceManagedTool {
			continue
		}
		if !s.hasDesiredResourceKind(ownership.Component, ResourceManagedTool) {
			continue
		}
		if _, stillDesired := s.DesiredByPath[path]; stillDesired {
			continue
		}
		if !s.Active[ownership.Component] {
			continue
		}
		precondition := preconditionAbsent
		currentDigest, exists := maybeFileDigest(path)
		if exists {
			precondition = currentDigest
		}
		if exists && currentDigest != ownership.Digest {
			s.conflict(ownership.Component, path, true, "replaced managed tool payload has Owner drift")
			if !adopt {
				continue
			}
		}
		s.Result.Changes = append(s.Result.Changes, Change{
			Component:    ownership.Component,
			Kind:         ChangeCleanupManagedTool,
			ResourceKind: ownership.ResourceKind,
			Path:         path,
			Summary:      "remove old Managed Tool payload after successful Tool Lock switch",
			Precondition: precondition,
		})
	}
}

func (s *planSnapshot) hasDesiredResourceKind(component ComponentID, kind ResourceKind) bool {
	for _, resource := range s.Desired {
		if resource.Component == component && resource.ResourceKind == kind {
			return true
		}
	}
	return false
}

func (s *planSnapshot) finishOutcome() {
	if len(s.Result.Conflicts) > 0 {
		for _, conflict := range s.Result.Conflicts {
			if !conflict.Adoptable {
				s.Result.Blockers = append(s.Result.Blockers, Blocker{Code: BlockerConflict, Message: conflict.Reason})
				continue
			}
			if s.Adopt {
				continue
			}
			s.Result.Blockers = append(s.Result.Blockers, Blocker{Code: BlockerConflict, Message: "conflicts require --adopt"})
		}
	}
	if len(s.Result.Blockers) > 0 {
		s.Result.Outcome = OutcomeBlocked
		return
	}
	stateOutdated := !s.Loaded.Exists ||
		s.State.DesiredStateID != s.Result.DesiredStateID ||
		s.State.ToolLockSHA256 != s.ToolLockSHA256 ||
		s.State.Target != s.Result.Target
	if len(s.Result.Changes) == 0 && len(s.Result.Retirements) == 0 && !stateOutdated {
		s.Result.Outcome = OutcomeNoChange
		return
	}
	s.Result.Outcome = OutcomeChangesPlanned
}

func (s *planSnapshot) block(code BlockerCode, message string) {
	s.Result.Blockers = append(s.Result.Blockers, Blocker{Code: code, Message: message})
	s.Result.Outcome = OutcomeBlocked
}

func (s *planSnapshot) conflict(component ComponentID, path string, adoptable bool, reason string) {
	s.Result.Conflicts = append(s.Result.Conflicts, Conflict{
		Component: component,
		Path:      path,
		Adoptable: adoptable,
		Reason:    reason,
	})
}

func (s *planSnapshot) change(resource desiredResource, kind ChangeKind, precondition string) {
	s.Result.Changes = append(s.Result.Changes, Change{
		Component:    resource.Component,
		Kind:         kind,
		ResourceKind: resource.ResourceKind,
		Path:         resource.Path,
		Summary:      resource.Summary,
		Precondition: precondition,
	})
}

func resolveGitHubSecret(req Request, state State, active bool) (*SecretReference, *Blocker) {
	if !active {
		return nil, nil
	}
	if req.GitHubKeyPath != "" {
		ref, err := validateSecretReference(req.GitHubKeyPath, "")
		if err != nil {
			return nil, &Blocker{Code: BlockerSecretReferenceRequired, Message: err.Error()}
		}
		return &ref, nil
	}
	existing, ok := state.SecretReferences[ComponentGitHubSSH]
	var existingErr error
	if ok && existing.Path != "" {
		ref, err := validateSecretReference(existing.Path, existing.Fingerprint)
		if err == nil {
			return &ref, nil
		}
		existingErr = err
	}
	if req.GitHubKeySelector != nil {
		selectedPath, selected := req.GitHubKeySelector()
		if selected && strings.TrimSpace(selectedPath) != "" {
			ref, err := validateSecretReference(selectedPath, "")
			if err != nil {
				return nil, &Blocker{Code: BlockerSecretReferenceRequired, Message: err.Error()}
			}
			return &ref, nil
		}
	}
	if ok && existing.Path != "" {
		return nil, &Blocker{Code: BlockerSecretReferenceRequired, Message: existingErr.Error() + "; choose it explicitly again"}
	}
	return nil, &Blocker{Code: BlockerSecretReferenceRequired, Message: "github-ssh requires an explicit --github-key, an interactive key selection, or a valid persisted Secret Reference"}
}

func validateSecretReference(path string, expectedFingerprint string) (SecretReference, error) {
	info, err := os.Stat(path)
	if err != nil {
		return SecretReference{}, fmt.Errorf("validate GitHub SSH private key: %w", err)
	}
	if !info.Mode().IsRegular() {
		return SecretReference{}, fmt.Errorf("GitHub SSH key must be a regular file")
	}
	if stat, ok := info.Sys().(*syscall.Stat_t); ok && stat.Uid != uint32(os.Getuid()) {
		return SecretReference{}, fmt.Errorf("GitHub SSH key must be owned by the current user")
	}
	if info.Mode().Perm()&0o077 != 0 {
		return SecretReference{}, fmt.Errorf("GitHub SSH key permissions must not be readable by group or others")
	}
	publicKey, err := exec.Command("ssh-keygen", "-y", "-f", path).Output()
	if err != nil {
		return SecretReference{}, fmt.Errorf("validate GitHub SSH key readability: %w", err)
	}
	fingerprintCommand := exec.Command("ssh-keygen", "-lf", "-")
	fingerprintCommand.Stdin = bytes.NewReader(publicKey)
	fingerprintOutput, err := fingerprintCommand.Output()
	if err != nil {
		return SecretReference{}, fmt.Errorf("derive GitHub SSH public fingerprint: %w", err)
	}
	fields := strings.Fields(string(fingerprintOutput))
	if len(fields) < 2 {
		return SecretReference{}, fmt.Errorf("derive GitHub SSH public fingerprint: unexpected ssh-keygen output")
	}
	fingerprint := fields[1]
	if expectedFingerprint != "" && fingerprint != expectedFingerprint {
		return SecretReference{}, fmt.Errorf("GitHub SSH key fingerprint changed; choose it explicitly again")
	}
	abs, err := filepath.Abs(path)
	if err != nil {
		return SecretReference{}, err
	}
	return SecretReference{Component: ComponentGitHubSSH, Path: abs, Fingerprint: fingerprint}, nil
}

func writeResource(ctx context.Context, home string, resource desiredResource, client *http.Client) error {
	if err := os.MkdirAll(filepath.Dir(resource.Path), 0o700); err != nil {
		return err
	}
	if resource.ResourceKind == ResourceManagedTool && resource.ManagedTool != nil {
		return materializeManagedTool(ctx, home, resource, client)
	}
	if resource.ResourceKind == ResourceSymlink {
		tempPath := resource.Path + ".tmp"
		_ = os.Remove(tempPath)
		if err := os.Symlink(resource.Content, tempPath); err != nil {
			return err
		}
		return os.Rename(tempPath, resource.Path)
	}
	if resource.ResourceKind == ResourceManagedBlock {
		return writeManagedBlock(resource.Path, resource.Content)
	}
	mode := os.FileMode(0o644)
	if strings.Contains(filepath.ToSlash(resource.Path), "/bin/") {
		mode = 0o755
	}
	tempPath := resource.Path + ".tmp"
	if err := os.WriteFile(tempPath, []byte(resource.Content), mode); err != nil {
		return err
	}
	return os.Rename(tempPath, resource.Path)
}

func startUserService(ctx context.Context, req Request, servicePath string) ([]string, error) {
	if req.UserServiceStarter != nil {
		return req.UserServiceStarter(ctx, servicePath)
	}
	serviceName := filepath.Base(servicePath)
	if err := exec.CommandContext(ctx, "systemctl", "--user", "link", servicePath).Run(); err != nil {
		return nil, err
	}
	if err := exec.CommandContext(ctx, "systemctl", "--user", "daemon-reload").Run(); err != nil {
		return nil, err
	}
	if err := exec.CommandContext(ctx, "systemctl", "--user", "enable", "--now", serviceName).Run(); err != nil {
		return nil, err
	}
	return []string{"systemctl --user link " + servicePath, "systemctl --user daemon-reload", "systemctl --user enable --now " + serviceName}, nil
}

func applyLoginShellChange(ctx context.Context, req Request, desiredShell string) ([]string, error) {
	if req.ShellChangeExecutor != nil {
		return req.ShellChangeExecutor(ctx, desiredShell)
	}
	tty, err := os.OpenFile("/dev/tty", os.O_RDWR, 0)
	if err != nil {
		return nil, fmt.Errorf("login shell change requires a controlling terminal: %w", err)
	}
	defer tty.Close()
	command := exec.CommandContext(ctx, "chsh", "-s", desiredShell)
	command.Stdin = tty
	command.Stdout = tty
	command.Stderr = tty
	if err := command.Run(); err != nil {
		return nil, err
	}
	return []string{"chsh -s " + desiredShell}, nil
}

func materializeManagedTool(ctx context.Context, home string, resource desiredResource, client *http.Client) error {
	install := resource.ManagedTool
	cachePath, err := ensureArtifactCache(ctx, home, install.Artifact, client)
	if err != nil {
		return err
	}
	tempPath := resource.Path + ".tmp"
	_ = os.Remove(tempPath)
	switch install.Artifact.ArtifactType {
	case release.ArtifactTypeRawExecutable:
		if err := copyFile(cachePath, tempPath, 0o755); err != nil {
			return err
		}
	case release.ArtifactTypeTarGz:
		if err := extractTarGzExecutable(cachePath, install.Entry, tempPath); err != nil {
			return err
		}
	case release.ArtifactTypeZip:
		if err := extractZipExecutable(cachePath, install.Entry, tempPath); err != nil {
			return err
		}
	default:
		return fmt.Errorf("unsupported managed tool artifact type %q", install.Artifact.ArtifactType)
	}
	return os.Rename(tempPath, resource.Path)
}

func ensureArtifactCache(ctx context.Context, home string, artifact release.ToolArtifact, client *http.Client) (string, error) {
	cachePath := filepath.Join(home, "cache", "artifacts", artifact.SHA256)
	if got, ok := maybeFileDigest(cachePath); ok && got == artifact.SHA256 {
		return cachePath, nil
	}
	if err := os.MkdirAll(filepath.Dir(cachePath), 0o700); err != nil {
		return "", err
	}
	partialPath := cachePath + ".partial"
	_ = os.Remove(partialPath)
	downloadCtx, cancel := context.WithTimeout(ctx, 30*time.Second)
	defer cancel()
	request, err := http.NewRequestWithContext(downloadCtx, http.MethodGet, artifact.URL, nil)
	if err != nil {
		return "", fmt.Errorf("%s", redactCredentialURL(err.Error()))
	}
	response, err := client.Do(request)
	if err != nil {
		return "", fmt.Errorf("%s", redactCredentialURL(err.Error()))
	}
	defer response.Body.Close()
	if response.StatusCode < 200 || response.StatusCode >= 300 {
		return "", fmt.Errorf("download %s: %s", redactCredentialURL(artifact.URL), response.Status)
	}
	partial, err := os.OpenFile(partialPath, os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0o600)
	if err != nil {
		return "", err
	}
	hash := sha256.New()
	_, copyErr := io.Copy(io.MultiWriter(partial, hash), response.Body)
	closeErr := partial.Close()
	if copyErr != nil {
		_ = os.Remove(partialPath)
		return "", copyErr
	}
	if closeErr != nil {
		_ = os.Remove(partialPath)
		return "", closeErr
	}
	got := hex.EncodeToString(hash.Sum(nil))
	if got != artifact.SHA256 {
		_ = os.Remove(partialPath)
		return "", fmt.Errorf("checksum mismatch for %s", redactCredentialURL(artifact.URL))
	}
	if err := os.Rename(partialPath, cachePath); err != nil {
		_ = os.Remove(partialPath)
		return "", err
	}
	return cachePath, nil
}

func copyFile(sourcePath string, targetPath string, mode os.FileMode) error {
	source, err := os.Open(sourcePath)
	if err != nil {
		return err
	}
	defer source.Close()
	target, err := os.OpenFile(targetPath, os.O_CREATE|os.O_TRUNC|os.O_WRONLY, mode)
	if err != nil {
		return err
	}
	_, copyErr := io.Copy(target, source)
	closeErr := target.Close()
	if copyErr != nil {
		_ = os.Remove(targetPath)
		return copyErr
	}
	if closeErr != nil {
		_ = os.Remove(targetPath)
		return closeErr
	}
	return nil
}

func extractTarGzExecutable(archivePath string, entryName string, targetPath string) error {
	file, err := os.Open(archivePath)
	if err != nil {
		return err
	}
	defer file.Close()
	gzipReader, err := gzip.NewReader(file)
	if err != nil {
		return err
	}
	defer gzipReader.Close()
	reader := tar.NewReader(gzipReader)
	for {
		header, err := reader.Next()
		if err == io.EOF {
			break
		}
		if err != nil {
			return err
		}
		if header.FileInfo().IsDir() || filepath.Base(header.Name) != entryName {
			continue
		}
		return writeExecutableFromReader(targetPath, reader)
	}
	return fmt.Errorf("artifact %s does not contain executable %s", archivePath, entryName)
}

func extractZipExecutable(archivePath string, entryName string, targetPath string) error {
	reader, err := zip.OpenReader(archivePath)
	if err != nil {
		return err
	}
	defer reader.Close()
	for _, file := range reader.File {
		if file.FileInfo().IsDir() || filepath.Base(file.Name) != entryName {
			continue
		}
		source, err := file.Open()
		if err != nil {
			return err
		}
		defer source.Close()
		return writeExecutableFromReader(targetPath, source)
	}
	return fmt.Errorf("artifact %s does not contain executable %s", archivePath, entryName)
}

func writeExecutableFromReader(targetPath string, source io.Reader) error {
	target, err := os.OpenFile(targetPath, os.O_CREATE|os.O_TRUNC|os.O_WRONLY, 0o755)
	if err != nil {
		return err
	}
	_, copyErr := io.Copy(target, source)
	closeErr := target.Close()
	if copyErr != nil {
		_ = os.Remove(targetPath)
		return copyErr
	}
	if closeErr != nil {
		_ = os.Remove(targetPath)
		return closeErr
	}
	return nil
}

func writeManagedBlock(path string, block string) error {
	data, err := os.ReadFile(path)
	if os.IsNotExist(err) {
		return os.WriteFile(path, []byte(block), 0o600)
	}
	if err != nil {
		return err
	}
	text := string(data)
	if strings.TrimSpace(text) == "" {
		return os.WriteFile(path, []byte(block), 0o600)
	}
	start := strings.Index(text, sshBlockStart)
	end := strings.Index(text, sshBlockEnd)
	if start < 0 && end < 0 {
		if !strings.HasSuffix(text, "\n") {
			text += "\n"
		}
		return os.WriteFile(path, []byte(text+block), 0o600)
	}
	start, end, ok := managedBlockSpan(text)
	if !ok {
		return fmt.Errorf("managed block markers are not replaceable")
	}
	next := text[:start] + block + text[end:]
	return os.WriteFile(path, []byte(next), 0o600)
}

func createBackup(home string, clock func() time.Time, conflict Conflict) (BackupMetadata, error) {
	data, err := os.ReadFile(conflict.Path)
	if os.IsNotExist(err) {
		return BackupMetadata{}, nil
	}
	if err != nil {
		return BackupMetadata{}, err
	}
	digest := digestBytes(data)
	dir := filepath.Join(home, "backups", clock().UTC().Format("20060102T150405Z"))
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return BackupMetadata{}, err
	}
	name := strings.ReplaceAll(strings.TrimPrefix(filepath.ToSlash(conflict.Path), "/"), "/", "_")
	if name == "" {
		name = "root"
	}
	backupPath := filepath.Join(dir, name+"-"+digest[:12])
	for index := 1; ; index++ {
		if _, err := os.Stat(backupPath); os.IsNotExist(err) {
			break
		}
		backupPath = filepath.Join(dir, fmt.Sprintf("%s-%s-%d", name, digest[:12], index))
	}
	if err := os.WriteFile(backupPath, data, 0o600); err != nil {
		return BackupMetadata{}, err
	}
	return BackupMetadata{
		Component: conflict.Component,
		Source:    conflict.Path,
		Backup:    backupPath,
		Digest:    digest,
		CreatedAt: clock().UTC().Format(time.RFC3339),
	}, nil
}

func retirementChange(retirement Retirement, state State) (Change, bool, *Blocker) {
	ownership, owned := state.Ownership[retirement.Path]
	if !owned {
		return Change{}, false, nil
	}
	resourceKind := retirement.ResourceKind
	if resourceKind == "" {
		resourceKind = ownership.ResourceKind
	}
	if !retirableResourceKind(resourceKind) {
		return Change{}, false, &Blocker{
			Code:    BlockerOperationalFailure,
			Message: "refusing to retire non-retirable resource kind " + string(resourceKind),
		}
	}
	return Change{
		Component:    retirement.Component,
		Kind:         ChangeRetireResource,
		ResourceKind: resourceKind,
		Path:         retirement.Path,
		Summary:      retirement.Reason,
		Precondition: retirement.Precondition,
	}, true, nil
}

func retirableResourceKind(kind ResourceKind) bool {
	switch kind {
	case ResourceManagedPath, ResourceManagedBlock, ResourceManagedTool, ResourceIntegrationShim, ResourceSymlink:
		return true
	default:
		return false
	}
}

func executeRemovalChange(req Request, result *Result, state *State, change Change) (bool, error) {
	if err := verifyPrecondition(change.Path, change.Precondition); err != nil {
		result.Outcome = OutcomeBlocked
		result.Blockers = append(result.Blockers, Blocker{Code: BlockerStalePlan, Message: err.Error()})
		return true, nil
	}
	pending := journalEntriesFor([]Change{change})
	state.PendingWork = append(state.PendingWork, pending...)
	if err := writeState(req.Home, *state); err != nil {
		return false, err
	}
	result.DurableEffects = appendUnique(result.DurableEffects, StatePath(req.Home))
	if req.BeforeMutation != nil {
		req.BeforeMutation(change)
	}
	if err := verifyPrecondition(change.Path, change.Precondition); err != nil {
		state.PendingWork = removeJournalEntries(state.PendingWork, pending)
		if writeErr := writeState(req.Home, *state); writeErr != nil {
			return false, writeErr
		}
		result.Outcome = OutcomeBlocked
		result.Blockers = append(result.Blockers, Blocker{Code: BlockerStalePlan, Message: err.Error()})
		return true, nil
	}
	if req.FailBeforeEffectPath == change.Path {
		result.Outcome = OutcomePartial
		result.Blockers = append(result.Blockers, Blocker{
			Code:    BlockerOperationalFailure,
			Message: "failure injected before removing " + change.Path,
		})
		return false, nil
	}
	if err := applyRemovalChange(change, state); err != nil {
		result.Outcome = OutcomePartial
		result.Blockers = append(result.Blockers, Blocker{Code: BlockerOperationalFailure, Message: err.Error()})
		return false, nil
	}
	state.PendingWork = removeJournalEntries(state.PendingWork, pending)
	if err := writeState(req.Home, *state); err != nil {
		return false, err
	}
	result.DurableEffects = appendUnique(result.DurableEffects, change.Path)
	return false, nil
}

func applyRemovalChange(change Change, state *State) error {
	if !retirableResourceKind(change.ResourceKind) {
		return fmt.Errorf("refusing to retire non-retirable resource kind %s", change.ResourceKind)
	}
	if change.ResourceKind == ResourceManagedBlock {
		if err := removeManagedBlock(change.Path); err != nil {
			return err
		}
		delete(state.Ownership, change.Path)
		return nil
	}
	if err := os.Remove(change.Path); err != nil && !os.IsNotExist(err) {
		return err
	}
	delete(state.Ownership, change.Path)
	return nil
}

func removeManagedBlock(path string) error {
	data, err := os.ReadFile(path)
	if os.IsNotExist(err) {
		return nil
	}
	if err != nil {
		return err
	}
	text := string(data)
	start := strings.Index(text, sshBlockStart)
	end := strings.Index(text, sshBlockEnd)
	if start < 0 && end < 0 {
		return nil
	}
	start, end, ok := managedBlockSpan(text)
	if !ok {
		return fmt.Errorf("managed block markers are not removable")
	}
	next := text[:start] + text[end:]
	if strings.TrimSpace(next) == "" {
		return os.Remove(path)
	}
	return os.WriteFile(path, []byte(next), 0o600)
}

func managedBlockSpan(text string) (int, int, bool) {
	start := strings.Index(text, sshBlockStart)
	end := strings.Index(text, sshBlockEnd)
	if start < 0 || end < start {
		return 0, 0, false
	}
	end += len(sshBlockEnd)
	if end < len(text) && text[end] == '\n' {
		end++
	}
	return start, end, true
}

func managedBlockRemoved(path string) bool {
	data, err := os.ReadFile(path)
	if os.IsNotExist(err) {
		return true
	}
	if err != nil {
		return false
	}
	return blockState(string(data)) == "absent" || blockState(string(data)) == "empty"
}

func managedBlockRemovalPreservesOwnerContent(path string) bool {
	data, err := os.ReadFile(path)
	if err != nil {
		return false
	}
	start, end, ok := managedBlockSpan(string(data))
	if !ok {
		return false
	}
	return string(data[start:end]) == githubSSHManagedBlock()
}

func (r Reconciler) applySystemDependency(ctx context.Context, req Request, change Change) ([]string, error) {
	if r.system != nil {
		return r.system.ApplySystemDependencies(ctx, req, change.Capabilities)
	}
	return nil, fmt.Errorf("no system adapter configured for authorized System Change")
}

func plannedMissingCapabilities(ctx context.Context, req Request, active []ComponentID, system SystemAdapter) ([]Capability, error) {
	if req.Capabilities != nil {
		var missing []Capability
		for _, capability := range requiredCapabilities(active, req) {
			if present, explicitlySet := req.Capabilities[capability]; explicitlySet && !present {
				missing = append(missing, capability)
			}
		}
		return missing, nil
	}
	if system == nil {
		return nil, nil
	}
	return system.MissingCapabilities(ctx, req, active)
}

func capabilitiesSummary(capabilities []Capability) string {
	parts := make([]string, 0, len(capabilities))
	for _, capability := range capabilities {
		parts = append(parts, string(capability))
	}
	return strings.Join(parts, ", ")
}

func intersectCapabilities(left []Capability, right []Capability) []Capability {
	rightSet := map[Capability]bool{}
	for _, capability := range right {
		rightSet[capability] = true
	}
	var intersection []Capability
	for _, capability := range left {
		if rightSet[capability] {
			intersection = append(intersection, capability)
		}
	}
	return intersection
}

func componentHasFailedCapability(component ComponentID, req Request, failed []Capability) bool {
	if len(failed) == 0 {
		return false
	}
	failedSet := map[Capability]bool{}
	for _, capability := range failed {
		failedSet[capability] = true
	}
	for _, required := range requiredCapabilities([]ComponentID{component}, req) {
		if failedSet[required] {
			return true
		}
	}
	return false
}

func removeCapability(values []Capability, remove Capability) []Capability {
	filtered := values[:0]
	for _, capability := range values {
		if capability != remove {
			filtered = append(filtered, capability)
		}
	}
	return filtered
}

type systemBlock struct {
	Direct     bool
	Dependency ComponentID
}

func systemBlockedComponents(active map[ComponentID]bool, req Request, failed []Capability) map[ComponentID]systemBlock {
	blocked := map[ComponentID]systemBlock{}
	if len(failed) == 0 {
		return blocked
	}
	failedSet := map[Capability]bool{}
	for _, capability := range failed {
		failedSet[capability] = true
	}
	for component := range active {
		for _, required := range requiredCapabilities([]ComponentID{component}, req) {
			if failedSet[required] {
				blocked[component] = systemBlock{Direct: true}
			}
		}
	}
	for changed := true; changed; {
		changed = false
		for component := range active {
			if _, ok := blocked[component]; ok {
				continue
			}
			for _, dependency := range componentDependencies(component) {
				if _, ok := blocked[dependency]; ok {
					blocked[component] = systemBlock{Dependency: dependency}
					changed = true
					break
				}
			}
		}
	}
	return blocked
}

func componentBlockedComponents(active map[ComponentID]bool, failed map[ComponentID]string) map[ComponentID]systemBlock {
	blocked := map[ComponentID]systemBlock{}
	for component := range failed {
		if active[component] {
			blocked[component] = systemBlock{Direct: true}
		}
	}
	for changed := true; changed; {
		changed = false
		for component := range active {
			if _, ok := blocked[component]; ok {
				continue
			}
			for _, dependency := range componentDependencies(component) {
				if _, ok := blocked[dependency]; ok {
					blocked[component] = systemBlock{Dependency: dependency}
					changed = true
					break
				}
			}
		}
	}
	return blocked
}

func systemBlockSet(blocked map[ComponentID]systemBlock) map[ComponentID]bool {
	values := map[ComponentID]bool{}
	for component := range blocked {
		values[component] = true
	}
	return values
}

func componentDependencies(component ComponentID) []ComponentID {
	switch component {
	case ComponentFNM, ComponentGitHubSSH:
		return []ComponentID{ComponentShell}
	default:
		return nil
	}
}

func componentDependents(dependency ComponentID) []ComponentID {
	var dependents []ComponentID
	for _, component := range defaultComponents() {
		for _, candidateDependency := range componentDependencies(component) {
			if candidateDependency == dependency {
				dependents = append(dependents, component)
				break
			}
		}
	}
	return dependents
}

func orderedComponentsFromSet(components map[ComponentID]bool) []ComponentID {
	visited := map[ComponentID]bool{}
	var ordered []ComponentID
	var visit func(ComponentID)
	visit = func(component ComponentID) {
		if visited[component] {
			return
		}
		visited[component] = true
		for _, dependency := range componentDependencies(component) {
			if components[dependency] {
				visit(dependency)
			}
		}
		if components[component] {
			ordered = append(ordered, component)
		}
	}
	for _, component := range defaultComponents() {
		visit(component)
	}
	for _, component := range sortedComponentsFromSet(components) {
		visit(component)
	}
	return ordered
}

func verifyPrecondition(path string, precondition string) error {
	current, exists := maybeFileDigest(path)
	if precondition == preconditionAbsent {
		if exists {
			return fmt.Errorf("stale plan for %s: expected absence", path)
		}
		return nil
	}
	if !exists {
		return fmt.Errorf("stale plan for %s: expected digest %s but path is absent", path, precondition)
	}
	if current != precondition {
		return fmt.Errorf("stale plan for %s: expected digest %s", path, precondition)
	}
	return nil
}

func maybeFileDigest(path string) (string, bool) {
	info, err := os.Lstat(path)
	if err != nil {
		return "", false
	}
	if info.Mode()&os.ModeSymlink != 0 {
		target, err := os.Readlink(path)
		if err != nil {
			return "", false
		}
		return digestString("symlink:" + target), true
	}
	data, err := os.ReadFile(path)
	if err != nil {
		return "", false
	}
	return digestBytes(data), true
}

func fileDigest(path string) string {
	digest, _ := maybeFileDigest(path)
	return digest
}

func digestString(value string) string {
	return digestBytes([]byte(value))
}

func digestResource(resource desiredResource) string {
	if resource.ResourceKind == ResourceSymlink {
		return digestString("symlink:" + resource.Content)
	}
	return digestString(resource.Content)
}

func digestBytes(data []byte) string {
	sum := sha256.Sum256(data)
	return hex.EncodeToString(sum[:])
}

func blockState(text string) string {
	if strings.TrimSpace(text) == "" {
		return "empty"
	}
	startCount := strings.Count(text, sshBlockStart)
	endCount := strings.Count(text, sshBlockEnd)
	if startCount == 0 && endCount == 0 {
		return "absent"
	}
	if startCount != 1 || endCount != 1 || strings.Index(text, sshBlockStart) > strings.Index(text, sshBlockEnd) {
		return "malformed"
	}
	return "healthy"
}

func suspendedComponents(state State, excluded map[ComponentID]bool) []ComponentID {
	suspended := map[ComponentID]bool{}
	for _, ownership := range state.Ownership {
		if excluded[ownership.Component] {
			suspended[ownership.Component] = true
		}
	}
	return sortedComponentsFromSet(suspended)
}

func normalizedComponents(values []ComponentID) []ComponentID {
	seen := map[ComponentID]bool{}
	var normalized []ComponentID
	for _, value := range values {
		if value == "" || seen[value] {
			continue
		}
		seen[value] = true
		normalized = append(normalized, value)
	}
	sort.Slice(normalized, func(i int, j int) bool { return normalized[i] < normalized[j] })
	return normalized
}

func componentSet(values []ComponentID) map[ComponentID]bool {
	set := map[ComponentID]bool{}
	for _, value := range values {
		set[value] = true
	}
	return set
}

func sortedComponentsFromSet(set map[ComponentID]bool) []ComponentID {
	values := make([]ComponentID, 0, len(set))
	for value := range set {
		values = append(values, value)
	}
	sort.Slice(values, func(i int, j int) bool { return values[i] < values[j] })
	return values
}

func sameComponents(left []ComponentID, right []ComponentID) bool {
	left = normalizedComponents(left)
	right = normalizedComponents(right)
	if len(left) != len(right) {
		return false
	}
	for index := range left {
		if left[index] != right[index] {
			return false
		}
	}
	return true
}

func appendUnique(values []string, value string) []string {
	for _, existing := range values {
		if existing == value {
			return values
		}
	}
	return append(values, value)
}

func componentChangeSet(changes map[ComponentID][]Change) map[ComponentID]bool {
	set := map[ComponentID]bool{}
	for component := range changes {
		set[component] = true
	}
	return set
}

func journalEntriesFor(changes []Change) []JournalEntry {
	entries := make([]JournalEntry, 0, len(changes))
	for _, change := range changes {
		entries = append(entries, JournalEntry{
			Component:    change.Component,
			Path:         change.Path,
			ResourceKind: change.ResourceKind,
			Intent:       string(change.Kind),
			Precondition: change.Precondition,
		})
	}
	return entries
}

func removeJournalEntries(entries []JournalEntry, remove []JournalEntry) []JournalEntry {
	removeSet := map[string]bool{}
	for _, entry := range remove {
		removeSet[entry.Path+"|"+entry.Intent] = true
	}
	kept := entries[:0]
	for _, entry := range entries {
		if !removeSet[entry.Path+"|"+entry.Intent] {
			kept = append(kept, entry)
		}
	}
	return kept
}

func sanitizeName(value string) string {
	replacer := strings.NewReplacer(" ", "-", "/", "-", ":", "", "--", "-")
	return replacer.Replace(strings.ToLower(value))
}

func (result Result) ActiveComponents() []ComponentID {
	return append([]ComponentID(nil), result.Scope.Active...)
}
