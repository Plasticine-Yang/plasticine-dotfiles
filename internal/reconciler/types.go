package reconciler

import "github.com/Plasticine-Yang/plasticine-dotfiles/internal/platform"

const CurrentStateSchema = 2

type ComponentID string

const (
	ComponentShell     ComponentID = "shell"
	ComponentGitConfig ComponentID = "git-config"
	ComponentGitHubSSH ComponentID = "github-ssh"
	ComponentNeovim    ComponentID = "neovim"
	ComponentLazygit   ComponentID = "lazygit"
	ComponentFNM       ComponentID = "fnm"
	ComponentUV        ComponentID = "uv"
	ComponentZellij    ComponentID = "zellij"
)

type ComponentStatus string

const (
	ComponentActive              ComponentStatus = "active"
	ComponentSuspended           ComponentStatus = "suspended"
	ComponentSkipped             ComponentStatus = "skipped"
	ComponentBlocked             ComponentStatus = "blocked"
	ComponentAwaitingOwnerAction ComponentStatus = "awaiting-owner-action"
	ComponentSucceeded           ComponentStatus = "succeeded"
)

type Capability string

const (
	CapabilityGit                   Capability = "git"
	CapabilityZsh                   Capability = "zsh"
	CapabilityOpenSSH               Capability = "openssh"
	CapabilityCA                    Capability = "ca-certificates"
	CapabilityAppleDevelopmentTools Capability = "apple-development-tools"
	CapabilitySystemdUserSession    Capability = "systemd-user-session"
)

type ChangeKind string

const (
	ChangeCreateManagedPath  ChangeKind = "create-managed-path"
	ChangeUpdateManagedPath  ChangeKind = "update-managed-path"
	ChangeCreateManagedBlock ChangeKind = "create-managed-block"
	ChangeInstallManagedTool ChangeKind = "install-managed-tool"
	ChangeSystemDependency   ChangeKind = "system-dependency"
	ChangeSecretReference    ChangeKind = "secret-reference"
	ChangeStateMigration     ChangeKind = "state-migration"
	ChangeScopeReplacement   ChangeKind = "scope-replacement"
	ChangeLoginShell         ChangeKind = "login-shell"
	ChangeRetireResource     ChangeKind = "retire-resource"
	ChangeCleanupManagedTool ChangeKind = "cleanup-managed-tool"
)

type ResourceKind string

const (
	ResourceManagedPath      ResourceKind = "managed-path"
	ResourceManagedBlock     ResourceKind = "managed-block"
	ResourceManagedTool      ResourceKind = "managed-tool"
	ResourceSystemDependency ResourceKind = "system-dependency"
	ResourceSecretReference  ResourceKind = "secret-reference"
	ResourceLoginShell       ResourceKind = "login-shell"
	ResourceUserService      ResourceKind = "user-service"
	ResourceIntegrationShim  ResourceKind = "integration-shim"
	ResourceSymlink          ResourceKind = "symlink"
	ResourceToolManagedState ResourceKind = "tool-managed-state"
)

type Change struct {
	Component    ComponentID  `json:"component"`
	Kind         ChangeKind   `json:"kind"`
	ResourceKind ResourceKind `json:"resource_kind"`
	Path         string       `json:"path,omitempty"`
	Summary      string       `json:"summary"`
	SystemChange bool         `json:"system_change,omitempty"`
	Precondition string       `json:"precondition,omitempty"`
	Capabilities []Capability `json:"capabilities,omitempty"`
}

type Conflict struct {
	Component ComponentID `json:"component"`
	Path      string      `json:"path"`
	Adoptable bool        `json:"adoptable"`
	Reason    string      `json:"reason"`
}

type Retirement struct {
	Component    ComponentID  `json:"component"`
	Path         string       `json:"path"`
	ResourceKind ResourceKind `json:"resource_kind"`
	Reason       string       `json:"reason"`
	Precondition string       `json:"precondition,omitempty"`
}

type ScopeSummary struct {
	Excluded  []ComponentID `json:"excluded,omitempty"`
	Active    []ComponentID `json:"active,omitempty"`
	Suspended []ComponentID `json:"suspended,omitempty"`
}

type ComponentResult struct {
	Component ComponentID     `json:"component"`
	Status    ComponentStatus `json:"status"`
	Message   string          `json:"message,omitempty"`
}

type StateMigration struct {
	FromSchema int    `json:"from_schema"`
	ToSchema   int    `json:"to_schema"`
	Message    string `json:"message"`
}

type WorkstationScope struct {
	Excluded []ComponentID `json:"excluded,omitempty"`
}

type Ownership struct {
	Component    ComponentID  `json:"component"`
	Path         string       `json:"path"`
	ResourceKind ResourceKind `json:"resource_kind"`
	Digest       string       `json:"digest"`
	AcceptedAt   string       `json:"accepted_at"`
}

type BackupMetadata struct {
	Component ComponentID `json:"component"`
	Source    string      `json:"source"`
	Backup    string      `json:"backup"`
	Digest    string      `json:"digest"`
	CreatedAt string      `json:"created_at"`
}

type SecretReference struct {
	Component   ComponentID `json:"component"`
	Path        string      `json:"path"`
	Fingerprint string      `json:"fingerprint"`
}

type JournalEntry struct {
	Component    ComponentID  `json:"component"`
	Path         string       `json:"path"`
	ResourceKind ResourceKind `json:"resource_kind"`
	Intent       string       `json:"intent"`
	Precondition string       `json:"precondition"`
}

type State struct {
	SchemaVersion    int                             `json:"schema_version"`
	DesiredStateID   string                          `json:"desired_state_id"`
	ToolLockSHA256   string                          `json:"tool_lock_sha256"`
	Target           platform.ArtifactTarget         `json:"target"`
	AppliedAt        string                          `json:"applied_at"`
	Scope            WorkstationScope                `json:"scope,omitempty"`
	Ownership        map[string]Ownership            `json:"ownership,omitempty"`
	Backups          []BackupMetadata                `json:"backups,omitempty"`
	SecretReferences map[ComponentID]SecretReference `json:"secret_references,omitempty"`
	PendingWork      []JournalEntry                  `json:"pending_work,omitempty"`
}

func defaultComponents() []ComponentID {
	return []ComponentID{
		ComponentShell,
		ComponentGitConfig,
		ComponentGitHubSSH,
		ComponentNeovim,
		ComponentLazygit,
		ComponentFNM,
		ComponentUV,
		ComponentZellij,
	}
}
