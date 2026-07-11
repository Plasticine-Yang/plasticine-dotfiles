package reconciler

import (
	"context"
	"net/http"
	"os"
	"os/exec"
	"strings"
	"time"

	"github.com/Plasticine-Yang/plasticine-dotfiles/internal/platform"
	"github.com/Plasticine-Yang/plasticine-dotfiles/internal/release"
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
	BlockerOperationalFailure         BlockerCode = "operational-failure"
	BlockerOwnerActionRequired        BlockerCode = "owner-action-required"
)

type Options struct {
	DesiredStateID string
	ToolLockSHA256 string
	ToolLock       release.ToolLock
	HTTPClient     *http.Client
	DiagnosticURLs []string
	System         SystemAdapter
	Clock          func() time.Time
}

type Reconciler struct {
	desiredStateID string
	toolLockSHA256 string
	toolLock       release.ToolLock
	httpClient     *http.Client
	diagnosticURLs []string
	system         SystemAdapter
	clock          func() time.Time
}

func New(options Options) Reconciler {
	clock := options.Clock
	if clock == nil {
		clock = time.Now
	}
	httpClient := options.HTTPClient
	if httpClient == nil {
		httpClient = &http.Client{Timeout: 30 * time.Second}
	}
	return Reconciler{
		desiredStateID: options.DesiredStateID,
		toolLockSHA256: options.ToolLockSHA256,
		toolLock:       options.ToolLock,
		httpClient:     httpClient,
		diagnosticURLs: append([]string(nil), options.DiagnosticURLs...),
		system:         options.System,
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
	GitHubKeySelector    func() (string, bool)
	LoginShell           string
	LoginShellKnown      bool
	ZshPath              string
	ToolLockSHA256       string
	Capabilities         map[Capability]bool
	NetworkChecks        []Check
	Authorize            func(Result) bool
	UserServiceStarter   func(context.Context, string) ([]string, error)
	ShellChangeExecutor  func(context.Context, string) ([]string, error)
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
	} else if len(r.diagnosticURLs) > 0 {
		result.Checks = append(result.Checks, r.runOnlineDoctorChecks(ctx, req, loaded)...)
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

func (r Reconciler) runOnlineDoctorChecks(ctx context.Context, req Request, loaded loadedState) []Check {
	checks := make([]Check, 0, len(r.diagnosticURLs)+1)
	for _, target := range r.diagnosticURLs {
		checks = append(checks, r.runHTTPSDiagnostic(ctx, target))
	}
	if loaded.Exists && githubSSHActiveForDoctor(req, loaded.State) {
		if secret, ok := loaded.State.SecretReferences[ComponentGitHubSSH]; ok && secret.Path != "" {
			checks = append(checks, runGitHubSSHDiagnostic(ctx, req.Home, secret))
		} else {
			checks = append(checks, Check{Name: "github-ssh", Healthy: false, Message: "github-ssh is active but no Secret Reference is available"})
		}
	}
	return checks
}

func githubSSHActiveForDoctor(req Request, state State) bool {
	excluded := state.Scope.Excluded
	if req.ReplaceScope {
		excluded = req.Exclude
	}
	if componentSet(excluded)[ComponentGitHubSSH] {
		return false
	}
	if len(req.Components) > 0 && !componentSet(req.Components)[ComponentGitHubSSH] {
		return false
	}
	return true
}

func (r Reconciler) runHTTPSDiagnostic(ctx context.Context, target string) Check {
	checkCtx, cancel := context.WithTimeout(ctx, 3*time.Second)
	defer cancel()
	request, err := http.NewRequestWithContext(checkCtx, http.MethodGet, target, nil)
	if err != nil {
		return Check{Name: "https-diagnostic", Healthy: false, Message: redactCredentialURL(err.Error())}
	}
	response, err := r.httpClient.Do(request)
	if err != nil {
		return Check{Name: "https-diagnostic", Healthy: false, Message: redactCredentialURL(err.Error())}
	}
	defer response.Body.Close()
	if response.StatusCode < 200 || response.StatusCode >= 400 {
		return Check{Name: "https-diagnostic", Healthy: false, Message: redactCredentialURL(response.Status)}
	}
	return Check{Name: "https-diagnostic", Healthy: true, Message: redactCredentialURL(target)}
}

func runGitHubSSHDiagnostic(ctx context.Context, home string, secret SecretReference) Check {
	checkCtx, cancel := context.WithTimeout(ctx, 5*time.Second)
	defer cancel()
	command := exec.CommandContext(
		checkCtx,
		"ssh",
		"-T",
		"-o", "BatchMode=yes",
		"-o", "StrictHostKeyChecking=yes",
		"-o", "GlobalKnownHostsFile=/dev/null",
		"-o", "UserKnownHostsFile="+githubKnownHostsPath(home),
		"-o", "UpdateHostKeys=no",
		"-o", "CheckHostIP=no",
		"-o", "IdentitiesOnly=yes",
		"-i", secret.Path,
		"git@github.com",
	)
	output, err := command.CombinedOutput()
	message := strings.TrimSpace(string(output))
	if strings.Contains(message, "successfully authenticated") {
		return Check{Name: "github-ssh", Healthy: true, Message: "GitHub accepted the configured key"}
	}
	if err != nil {
		if message == "" {
			message = err.Error()
		}
		return Check{Name: "github-ssh", Healthy: false, Message: redactCredentialURL(message)}
	}
	return Check{Name: "github-ssh", Healthy: false, Message: "GitHub SSH authentication did not report success"}
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
