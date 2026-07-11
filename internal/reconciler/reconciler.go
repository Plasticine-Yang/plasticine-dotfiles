package reconciler

import (
	"context"
	"os"
	"strings"
	"time"

	"github.com/Plasticine-Yang/plasticine-dotfiles/internal/platform"
)

type Outcome string

const (
	OutcomeChangesPlanned Outcome = "changes-planned"
	OutcomeApplied        Outcome = "applied"
	OutcomeNoChange       Outcome = "no-change"
	OutcomeDenied         Outcome = "denied"
	OutcomeBlocked        Outcome = "blocked"
	OutcomePartial        Outcome = "partial"
	OutcomeHealthy        Outcome = "healthy"
	OutcomeUnhealthy      Outcome = "unhealthy"
)

type BlockerCode string

const (
	BlockerSystemChangeAuthorization  BlockerCode = "system-change-authorization-required"
	BlockerUnsupportedSystemChange    BlockerCode = "unsupported-system-change"
	BlockerUnsupportedTarget          BlockerCode = "unsupported-target"
	BlockerMissingState               BlockerCode = "missing-state"
	BlockerStateUnreadable            BlockerCode = "state-unreadable"
	BlockerPendingWork                BlockerCode = "pending-work"
	BlockerComponentExcluded          BlockerCode = "component-excluded"
	BlockerUnknownComponent           BlockerCode = "unknown-component"
	BlockerMissingComponentDependency BlockerCode = "missing-component-dependency"
	BlockerConflict                   BlockerCode = "conflict"
	BlockerSecretReferenceRequired    BlockerCode = "secret-reference-required"
	BlockerStalePlan                  BlockerCode = "stale-plan"
	BlockerLockHeld                   BlockerCode = "lock-held"
)

type Options struct {
	DesiredStateID string
	ToolLockSHA256 string
	Clock          func() time.Time
}

type Reconciler struct {
	desiredStateID string
	toolLockSHA256 string
	clock          func() time.Time
}

func New(options Options) Reconciler {
	clock := options.Clock
	if clock == nil {
		clock = time.Now
	}
	return Reconciler{
		desiredStateID: options.DesiredStateID,
		toolLockSHA256: options.ToolLockSHA256,
		clock:          clock,
	}
}

type Request struct {
	Home                 string
	WorkstationRoot      string
	Target               platform.ArtifactTarget
	Host                 platform.Host
	Yes                  bool
	AllowSystem          bool
	RequireSystemChange  bool
	ReplaceScope         bool
	Exclude              []ComponentID
	Components           []ComponentID
	Adopt                bool
	IncludeGitHubSSH     bool
	GitHubKeyPath        string
	ToolLockSHA256       string
	Capabilities         map[Capability]bool
	NetworkChecks        []Check
	BeforeMutation       func(Change)
	FailBeforeEffectPath string
	SkipLock             bool
}

type Result struct {
	Outcome        Outcome
	DesiredStateID string
	Target         platform.ArtifactTarget
	Support        platform.SupportClassification
	DurableEffects []string
	Blockers       []Blocker
	Changes        []Change
	Conflicts      []Conflict
	Retirements    []Retirement
	Scope          ScopeSummary
	Components     []ComponentResult
	Checks         []Check
	StateMigration *StateMigration
}

type Blocker struct {
	Code    BlockerCode
	Message string
}

type Check struct {
	Name    string
	Healthy bool
	Message string
}

func (r Reconciler) Plan(ctx context.Context, req Request) (Result, error) {
	release, blocked, err := acquireReconciliationLock(req.Home, sharedLock, req.SkipLock)
	if err != nil || blocked != nil {
		return lockResult(r, req, blocked), err
	}
	defer release()
	snapshot, err := r.buildPlan(ctx, req)
	if err != nil {
		return Result{}, err
	}
	return snapshot.Result, nil
}

func (r Reconciler) Apply(ctx context.Context, req Request) (Result, error) {
	release, blocked, err := acquireReconciliationLock(req.Home, exclusiveLock, req.SkipLock)
	if err != nil || blocked != nil {
		return lockResult(r, req, blocked), err
	}
	defer release()
	if req.Yes {
		if err := recoverPendingWork(req.Home); err != nil {
			return Result{}, err
		}
	}
	snapshot, err := r.buildPlan(ctx, req)
	if err != nil {
		return Result{}, err
	}
	return r.executePlan(ctx, req, snapshot)
}

func (r Reconciler) Doctor(ctx context.Context, req Request) (Result, error) {
	if err := ctx.Err(); err != nil {
		return Result{}, err
	}
	release, blocked, err := acquireReconciliationLock(req.Home, sharedLock, req.SkipLock)
	if err != nil || blocked != nil {
		return lockResult(r, req, blocked), err
	}
	defer release()
	result := Result{
		Outcome:        OutcomeHealthy,
		DesiredStateID: r.desiredStateID,
		Target:         req.Target,
		Support:        platform.ClassifySupport(req.Host),
		Checks: []Check{
			{Name: "artifact-target", Healthy: req.Target == platform.TargetDarwinAMD64 || req.Target == platform.TargetDarwinARM64 || req.Target == platform.TargetLinuxAMD64 || req.Target == platform.TargetLinuxARM64, Message: req.Target.String()},
			{Name: "support-floor", Healthy: platform.ClassifySupport(req.Host).Level != platform.SupportUnsupported, Message: platform.ClassifySupport(req.Host).Reason},
		},
	}
	loaded, err := loadState(req.Home)
	if err != nil {
		result.Checks = append(result.Checks, Check{Name: "reconciliation-state", Healthy: false, Message: err.Error()})
	} else if loaded.Exists {
		for path, ownership := range loaded.State.Ownership {
			got, exists := maybeFileDigest(path)
			healthy := exists && got == ownership.Digest
			result.Checks = append(result.Checks, Check{
				Name:    "managed:" + string(ownership.Component),
				Healthy: healthy,
				Message: path,
			})
		}
	} else {
		result.Checks = append(result.Checks, Check{Name: "reconciliation-state", Healthy: false, Message: "state has not been applied"})
	}
	if req.NetworkChecks != nil {
		for _, check := range req.NetworkChecks {
			check.Message = redactCredentialURL(check.Message)
			result.Checks = append(result.Checks, check)
		}
	} else {
		result.Checks = append(result.Checks, Check{Name: "https-diagnostic", Healthy: true, Message: "bounded diagnostic not configured in this run"})
	}
	for _, check := range result.Checks {
		if !check.Healthy {
			result.Outcome = OutcomeUnhealthy
			break
		}
	}
	return result, nil
}

func lockResult(r Reconciler, req Request, blocker *Blocker) Result {
	result := Result{
		Outcome:        OutcomeBlocked,
		DesiredStateID: r.desiredStateID,
		Target:         req.Target,
		Support:        platform.ClassifySupport(req.Host),
	}
	if blocker != nil {
		result.Blockers = append(result.Blockers, *blocker)
	}
	return result
}

func recoverPendingWork(home string) error {
	loaded, err := loadState(home)
	if os.IsNotExist(err) || !loaded.Exists {
		return nil
	}
	if err != nil {
		return err
	}
	if len(loaded.State.PendingWork) == 0 {
		return nil
	}
	for _, pending := range loaded.State.PendingWork {
		currentDigest, exists := maybeFileDigest(pending.Path)
		ownership, owned := loaded.State.Ownership[pending.Path]
		switch {
		case owned && exists && currentDigest == ownership.Digest:
			continue
		case pending.Precondition == preconditionAbsent && !exists:
			continue
		case pending.Precondition != "" && exists && currentDigest == pending.Precondition:
			continue
		default:
			return nil
		}
	}
	loaded.State.PendingWork = nil
	return writeState(home, loaded.State)
}

func redactCredentialURL(message string) string {
	const marker = "://"
	start := strings.Index(message, marker)
	if start < 0 {
		return message
	}
	authorityStart := start + len(marker)
	authorityEnd := len(message)
	if slash := strings.Index(message[authorityStart:], "/"); slash >= 0 {
		authorityEnd = authorityStart + slash
	}
	authority := message[authorityStart:authorityEnd]
	if at := strings.LastIndex(authority, "@"); at >= 0 {
		return message[:authorityStart] + "[redacted]@" + authority[at+1:] + message[authorityEnd:]
	}
	return message
}
