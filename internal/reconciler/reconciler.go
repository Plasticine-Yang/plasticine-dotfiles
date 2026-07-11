package reconciler

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
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
	OutcomeHealthy        Outcome = "healthy"
	OutcomeUnhealthy      Outcome = "unhealthy"
)

type BlockerCode string

const (
	BlockerSystemChangeAuthorization BlockerCode = "system-change-authorization-required"
	BlockerUnsupportedSystemChange   BlockerCode = "unsupported-system-change"
	BlockerUnsupportedTarget         BlockerCode = "unsupported-target"
	BlockerMissingState              BlockerCode = "missing-state"
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
	Home                string
	Target              platform.ArtifactTarget
	Host                platform.Host
	Yes                 bool
	AllowSystem         bool
	RequireSystemChange bool
}

type Result struct {
	Outcome        Outcome
	DesiredStateID string
	Target         platform.ArtifactTarget
	Support        platform.SupportClassification
	DurableEffects []string
	Blockers       []Blocker
	Checks         []Check
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

type State struct {
	DesiredStateID string                  `json:"desired_state_id"`
	ToolLockSHA256 string                  `json:"tool_lock_sha256"`
	Target         platform.ArtifactTarget `json:"target"`
	AppliedAt      string                  `json:"applied_at"`
}

func (r Reconciler) Plan(ctx context.Context, req Request) (Result, error) {
	if err := ctx.Err(); err != nil {
		return Result{}, err
	}
	result := Result{
		DesiredStateID: r.desiredStateID,
		Target:         req.Target,
		Support:        platform.ClassifySupport(req.Host),
	}
	if result.Support.Level == platform.SupportUnsupported {
		result.Outcome = OutcomeBlocked
		result.Blockers = append(result.Blockers, Blocker{
			Code:    BlockerUnsupportedTarget,
			Message: result.Support.Reason,
		})
		return result, nil
	}
	if req.RequireSystemChange {
		switch result.Support.Level {
		case platform.SupportFull:
			if !req.AllowSystem {
				result.Outcome = OutcomeBlocked
				result.Blockers = append(result.Blockers, Blocker{
					Code:    BlockerSystemChangeAuthorization,
					Message: "system changes require --allow-system",
				})
				return result, nil
			}
		default:
			result.Outcome = OutcomeBlocked
			result.Blockers = append(result.Blockers, Blocker{
				Code:    BlockerUnsupportedSystemChange,
				Message: "host is outside the support floor for system changes",
			})
			return result, nil
		}
	}
	state, err := ReadState(req.Home)
	if err == nil && state.DesiredStateID == r.desiredStateID && state.ToolLockSHA256 == r.toolLockSHA256 && state.Target == req.Target {
		result.Outcome = OutcomeNoChange
		return result, nil
	}
	if err != nil && !os.IsNotExist(err) {
		return Result{}, err
	}
	result.Outcome = OutcomeChangesPlanned
	return result, nil
}

func (r Reconciler) Apply(ctx context.Context, req Request) (Result, error) {
	plan, err := r.Plan(ctx, req)
	if err != nil {
		return Result{}, err
	}
	if plan.Outcome == OutcomeBlocked || plan.Outcome == OutcomeNoChange {
		return plan, nil
	}
	if !req.Yes {
		plan.Outcome = OutcomeDenied
		return plan, nil
	}
	if err := os.MkdirAll(filepath.Dir(StatePath(req.Home)), 0o700); err != nil {
		return Result{}, err
	}
	state := State{
		DesiredStateID: r.desiredStateID,
		ToolLockSHA256: r.toolLockSHA256,
		Target:         req.Target,
		AppliedAt:      r.clock().UTC().Format(time.RFC3339),
	}
	if err := writeState(req.Home, state); err != nil {
		return Result{}, err
	}
	plan.Outcome = OutcomeApplied
	plan.DurableEffects = []string{StatePath(req.Home)}
	return plan, nil
}

func (r Reconciler) Doctor(ctx context.Context, req Request) (Result, error) {
	if err := ctx.Err(); err != nil {
		return Result{}, err
	}
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
	for _, check := range result.Checks {
		if !check.Healthy {
			result.Outcome = OutcomeUnhealthy
			break
		}
	}
	return result, nil
}

func StatePath(home string) string {
	return filepath.Join(home, "state", "reconciliation.json")
}

func DefaultPlasticineHome() (string, error) {
	if home := os.Getenv("PLASTICINE_HOME"); home != "" {
		return home, nil
	}
	home, err := os.UserHomeDir()
	if err != nil {
		return "", err
	}
	return filepath.Join(home, ".plasticine"), nil
}

func ReadState(home string) (State, error) {
	data, err := os.ReadFile(StatePath(home))
	if err != nil {
		return State{}, err
	}
	var state State
	if err := json.Unmarshal(data, &state); err != nil {
		return State{}, fmt.Errorf("decode reconciliation state: %w", err)
	}
	return state, nil
}

func writeState(home string, state State) error {
	path := StatePath(home)
	data, err := json.MarshalIndent(state, "", "  ")
	if err != nil {
		return err
	}
	tempPath := path + ".tmp"
	if err := os.WriteFile(tempPath, append(data, '\n'), 0o600); err != nil {
		return err
	}
	return os.Rename(tempPath, path)
}
