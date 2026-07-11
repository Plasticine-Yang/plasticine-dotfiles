package reconciler

import (
	"path/filepath"
	"strings"

	desiredstate "github.com/Plasticine-Yang/plasticine-dotfiles/internal/desired"
	"github.com/Plasticine-Yang/plasticine-dotfiles/internal/platform"
	"github.com/Plasticine-Yang/plasticine-dotfiles/internal/release"
)

const (
	sshBlockStart = "# BEGIN PLASTICINE GITHUB SSH"
	sshBlockEnd   = "# END PLASTICINE GITHUB SSH"
)

type desiredResource struct {
	Component    ComponentID
	Path         string
	ResourceKind ResourceKind
	Content      string
	Summary      string
	ManagedTool  *managedToolInstall
}

type managedToolInstall struct {
	Tool        release.ManagedTool
	Entry       string
	Artifact    release.ToolArtifact
	CacheSHA256 string
}

func workstationRoot(req Request) string {
	if req.WorkstationRoot != "" {
		return req.WorkstationRoot
	}
	return filepath.Join(req.Home, "workstation")
}

func gitConfigPath(home string) string {
	return filepath.Join(home, "config", "git", "config")
}

func gitShimPath(req Request) string {
	return filepath.Join(workstationRoot(req), ".gitconfig")
}

func zshConfigPath(home string) string {
	return filepath.Join(home, "config", "zsh", ".zshrc")
}

func zshShimPath(req Request) string {
	return filepath.Join(workstationRoot(req), ".zshrc")
}

func sshConfigPath(req Request) string {
	return filepath.Join(workstationRoot(req), ".ssh", "config")
}

func githubSSHFragmentPath(home string) string {
	return filepath.Join(home, "config", "ssh", "github.conf")
}

func githubKnownHostsPath(home string) string {
	return filepath.Join(home, "config", "ssh", "github_known_hosts")
}

func githubAgentShellPath(home string) string {
	return filepath.Join(home, "config", "ssh", "github-agent.zsh")
}

func componentDesiredResources(req Request, component ComponentID, secret *SecretReference, toolLock release.ToolLock, active map[ComponentID]bool) []desiredResource {
	switch component {
	case ComponentShell:
		return []desiredResource{
			{
				Component:    component,
				Path:         zshConfigPath(req.Home),
				ResourceKind: ResourceManagedPath,
				Content:      zshConfigContent(req, active[ComponentGitHubSSH], active[ComponentFNM]),
				Summary:      "materialize centralized Zsh configuration",
			},
			{
				Component:    component,
				Path:         zshShimPath(req),
				ResourceKind: ResourceIntegrationShim,
				Content:      "source \"${PLASTICINE_HOME:-$HOME/.plasticine}/config/zsh/.zshrc\"\n",
				Summary:      "materialize minimal Zsh shim",
			},
		}
	case ComponentGitConfig:
		return []desiredResource{
			{
				Component:    component,
				Path:         gitConfigPath(req.Home),
				ResourceKind: ResourceManagedPath,
				Content:      gitConfigContent(active[ComponentGitHubSSH]),
				Summary:      "materialize centralized personal Git configuration",
			},
			{
				Component:    component,
				Path:         gitShimPath(req),
				ResourceKind: ResourceIntegrationShim,
				Content:      "[include]\n  path = ~/.plasticine/config/git/config\n",
				Summary:      "materialize minimal Git include shim",
			},
		}
	case ComponentNeovim:
		return append(neovimConfigResources(req.Home), managedToolResources(req, component, release.ManagedToolNeovim, []string{"nvim"}, toolLock)...)
	case ComponentLazygit:
		return managedToolResources(req, component, release.ManagedToolLazygit, []string{"lazygit"}, toolLock)
	case ComponentFNM:
		return managedToolResources(req, component, release.ManagedToolFNM, []string{"fnm"}, toolLock)
	case ComponentUV:
		return managedToolResources(req, component, release.ManagedToolUV, []string{"uv", "uvx"}, toolLock)
	case ComponentGitHubSSH:
		resources := []desiredResource{
			{
				Component:    component,
				Path:         githubSSHFragmentPath(req.Home),
				ResourceKind: ResourceManagedPath,
				Content:      githubSSHFragmentContent(req, secret),
				Summary:      "materialize GitHub SSH host fragment",
			},
			{
				Component:    component,
				Path:         githubKnownHostsPath(req.Home),
				ResourceKind: ResourceManagedPath,
				Content:      githubKnownHostsContent(),
				Summary:      "materialize pinned GitHub host keys",
			},
			{
				Component:    component,
				Path:         sshConfigPath(req),
				ResourceKind: ResourceManagedBlock,
				Content:      githubSSHManagedBlock(),
				Summary:      "materialize GitHub SSH managed block",
			},
		}
		if req.Target.OS == "darwin" {
			resources = append(resources, desiredResource{
				Component:    component,
				Path:         filepath.Join(req.Home, "config", "ssh", "macos-keychain"),
				ResourceKind: ResourceIntegrationShim,
				Content:      "UseKeychain yes\nAddKeysToAgent yes\n",
				Summary:      "configure macOS Keychain and AddKeysToAgent integration",
			})
		}
		if req.Target.OS == "linux" {
			resources = append(resources, desiredResource{
				Component:    component,
				Path:         filepath.Join(req.Home, "config", "systemd", "user", "ssh-agent.service"),
				ResourceKind: ResourceUserService,
				Content:      "[Service]\nExecStart=/usr/bin/ssh-agent -D -a %h/.plasticine/runtime/ssh-agent.sock\n",
				Summary:      "configure shared user-level Linux SSH agent",
			}, desiredResource{
				Component:    component,
				Path:         githubAgentShellPath(req.Home),
				ResourceKind: ResourceIntegrationShim,
				Content:      githubLinuxAgentShellContent(secret),
				Summary:      "configure Shell to use the shared Linux SSH agent",
			})
		}
		return resources
	default:
		return nil
	}
}

func neovimConfigResources(home string) []desiredResource {
	configRoot := filepath.Join(home, "config", "nvim")
	files := desiredstate.NeovimConfigFiles()
	resources := make([]desiredResource, 0, len(files))
	for _, file := range files {
		resources = append(resources, desiredResource{
			Component:    ComponentNeovim,
			Path:         filepath.Join(configRoot, file.Path),
			ResourceKind: ResourceManagedPath,
			Content:      file.Content,
			Summary:      "materialize centralized Neovim configuration",
		})
	}
	return resources
}

func zshConfigContent(req Request, githubSSHActive bool, fnmActive bool) string {
	lines := []string{
		"# Managed by Plasticine.",
		"export PLASTICINE_HOME=\"${PLASTICINE_HOME:-$HOME/.plasticine}\"",
		"export PATH=\"$PLASTICINE_HOME/bin:$PATH\"",
		"export ANTIDOTE_HOME=\"$PLASTICINE_HOME/runtime/antidote\"",
	}
	if fnmActive {
		lines = append(lines,
			"export FNM_DIR=\"$PLASTICINE_HOME/runtime/fnm\"",
			"if [ -x \"$PLASTICINE_HOME/bin/fnm\" ]; then",
			"  eval \"$(\"$PLASTICINE_HOME/bin/fnm\" env --use-on-cd --shell zsh)\"",
			"fi",
		)
	}
	if req.Target.OS == platform.OSLinux && githubSSHActive {
		lines = append(lines,
			"if [ -r \"$PLASTICINE_HOME/config/ssh/github-agent.zsh\" ]; then",
			"  . \"$PLASTICINE_HOME/config/ssh/github-agent.zsh\"",
			"fi",
		)
	}
	lines = append(lines, "")
	return strings.Join(lines, "\n")
}

func gitConfigContent(githubSSHActive bool) string {
	lines := []string{
		"[user]",
		"  email = 975036719@qq.com",
		"  name = plasticine",
		"[init]",
		"  defaultBranch = main",
		"[pull]",
		"  rebase = true",
	}
	if githubSSHActive {
		lines = append(lines,
			"[url \"git@github.com:\"]",
			"  insteadOf = https://github.com/",
		)
	}
	lines = append(lines, "")
	return strings.Join(lines, "\n")
}

func managedToolResources(req Request, component ComponentID, tool release.ManagedTool, entries []string, toolLock release.ToolLock) []desiredResource {
	home := req.Home
	toolName := string(tool)
	version := managedToolVersionSegment(toolLock, tool, req.ToolLockSHA256)
	versionedRoot := filepath.Join(home, "tools", toolName, version)
	artifact, hasArtifact := managedToolArtifact(toolLock, tool, req.Target)
	resources := make([]desiredResource, 0, len(entries)*2)
	seenPayloads := map[string]bool{}
	for _, entry := range entries {
		payloadName := entry
		if tool == release.ManagedToolLazygit {
			payloadName = "lazygit"
		}
		payloadPath := filepath.Join(versionedRoot, payloadName)
		if !seenPayloads[payloadPath] {
			seenPayloads[payloadPath] = true
			resources = append(resources, desiredResource{
				Component:    component,
				Path:         payloadPath,
				ResourceKind: ResourceManagedTool,
				Content:      "managed tool " + toolName + " executable " + payloadName + " selected by Tool Lock\n",
				Summary:      "install exact " + toolName + " payload selected by Tool Lock",
			})
			if hasArtifact {
				resources[len(resources)-1].ManagedTool = &managedToolInstall{
					Tool:        tool,
					Entry:       payloadName,
					Artifact:    artifact,
					CacheSHA256: artifact.SHA256,
				}
			}
		}
	}
	launcherEntries := entries
	if tool == release.ManagedToolLazygit {
		launcherEntries = []string{"lazygit", "lg"}
	}
	for _, entry := range launcherEntries {
		if tool == release.ManagedToolLazygit {
			resources = append(resources, desiredResource{
				Component:    component,
				Path:         filepath.Join(home, "bin", entry),
				ResourceKind: ResourceSymlink,
				Content:      filepath.Join(versionedRoot, "lazygit"),
				Summary:      "materialize stable " + entry + " symlink",
			})
			continue
		}
		launcher := toolLauncher(versionedRoot, toolName, entry)
		resources = append(resources, desiredResource{
			Component:    component,
			Path:         filepath.Join(home, "bin", entry),
			ResourceKind: ResourceIntegrationShim,
			Content:      launcher,
			Summary:      "materialize stable " + entry + " launcher",
		})
	}
	return resources
}

func managedToolArtifact(toolLock release.ToolLock, tool release.ManagedTool, target platform.ArtifactTarget) (release.ToolArtifact, bool) {
	version, ok := toolLock.Tools[tool]
	if !ok {
		return release.ToolArtifact{}, false
	}
	artifact, ok := version.Targets[target]
	return artifact, ok
}

func managedToolForComponent(component ComponentID) (release.ManagedTool, bool) {
	switch component {
	case ComponentNeovim:
		return release.ManagedToolNeovim, true
	case ComponentLazygit:
		return release.ManagedToolLazygit, true
	case ComponentFNM:
		return release.ManagedToolFNM, true
	case ComponentUV:
		return release.ManagedToolUV, true
	default:
		return "", false
	}
}

func managedToolVersionSegment(toolLock release.ToolLock, tool release.ManagedTool, fallbackSHA string) string {
	if version, ok := toolLock.Tools[tool]; ok && version.Version != "" {
		return sanitizePathSegment(version.Version)
	}
	if len(fallbackSHA) >= 12 {
		return fallbackSHA[:12]
	}
	if fallbackSHA != "" {
		return fallbackSHA
	}
	return "unknown-tool-version"
}

func sanitizePathSegment(value string) string {
	return strings.NewReplacer("/", "_", "\\", "_", ":", "_").Replace(value)
}

func toolLauncher(versionedRoot string, tool string, entry string) string {
	lines := []string{"#!/bin/sh"}
	switch tool {
	case "neovim":
		lines = append(lines,
			"export XDG_CONFIG_HOME=\"${PLASTICINE_HOME:-$HOME/.plasticine}/config\"",
			"export XDG_STATE_HOME=\"${PLASTICINE_HOME:-$HOME/.plasticine}/runtime/nvim/state\"",
			"export XDG_DATA_HOME=\"${PLASTICINE_HOME:-$HOME/.plasticine}/runtime/nvim/data\"",
			"export XDG_CACHE_HOME=\"${PLASTICINE_HOME:-$HOME/.plasticine}/runtime/nvim/cache\"",
		)
	case "fnm":
		lines = append(lines, "export FNM_DIR=\"${PLASTICINE_HOME:-$HOME/.plasticine}/runtime/fnm\"")
	case "uv":
		lines = append(lines,
			"export UV_CACHE_DIR=\"${PLASTICINE_HOME:-$HOME/.plasticine}/runtime/uv/cache\"",
			"export UV_TOOL_DIR=\"${PLASTICINE_HOME:-$HOME/.plasticine}/runtime/uv/tools\"",
			"export UV_PYTHON_INSTALL_DIR=\"${PLASTICINE_HOME:-$HOME/.plasticine}/runtime/uv/python\"",
		)
	}
	lines = append(lines, "exec \""+filepath.Join(versionedRoot, entry)+"\" \"$@\"", "")
	return strings.Join(lines, "\n")
}

func githubSSHFragmentContent(req Request, secret *SecretReference) string {
	keyPath := ""
	if secret != nil {
		keyPath = secret.Path
	}
	lines := []string{
		"Host github.com",
		"  HostName github.com",
		"  User git",
		"  IdentitiesOnly yes",
		"  IdentityFile " + keyPath,
		"  UserKnownHostsFile ~/.plasticine/config/ssh/github_known_hosts",
		"  StrictHostKeyChecking yes",
	}
	switch req.Target.OS {
	case platform.OSDarwin:
		lines = append(lines, "  AddKeysToAgent yes", "  UseKeychain yes")
	case platform.OSLinux:
		lines = append(lines, "  IdentityAgent ~/.plasticine/runtime/ssh-agent.sock")
	}
	lines = append(lines, "")
	return strings.Join(lines, "\n")
}

func githubKnownHostsContent() string {
	return strings.Join([]string{
		"github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl",
		"github.com ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBEmKSENjQEezOmxkZMy7opKgwFB9nkt5YRrYMjNuG5N87uRgg6CLrbo5wAdT/y6v0mKV0U2w0WZ2YB/++Tpockg=",
		"github.com ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCj7ndNxQowgcQnjshcLrqPEiiphnt+VTTvDP6mHBL9j1aNUkY4Ue1gvwnGLVlOhGeYrnZaMgRK6+PKCUXaDbC7qtbW8gIkhL7aGCsOr/C56SJMy/BCZfxd1nWzAOxSDPgVsmerOBYfNqltV9/hWCqBywINIR+5dIg6JTJ72pcEpEjcYgXkE2YEFXV1JHnsKgbLWNlhScqb2UmyRkQyytRLtL+38TGxkxCflmO+5Z8CSSNY7GidjMIZ7Q4zMjA2n1nGrlTDkzwDCsw+wqFPGQA179cnfGWOWRVruj16z6XyvxvjJwbz0wQZ75XK5tKSb7FNyeIEs4TT4jk+S4dhPeAUC5y+bDYirYgM4GC7uEnztnZyaVWQ7B381AK4Qdrwt51ZqExKbQpTUNn+EjqoTwvqNj4kqx5QUCI0ThS/YkOxJCXmPUWZbhjpCg56i+2aB6CmK2JGhn57K5mj0MNdBXA4/WnwH6XoPWJzK5Nyu2zB3nAZp+S5hpQs+p1vN1/wsjk=",
		"",
	}, "\n")
}

func githubLinuxAgentShellContent(secret *SecretReference) string {
	keyPath := ""
	fingerprint := ""
	if secret != nil {
		keyPath = secret.Path
		fingerprint = secret.Fingerprint
	}
	quotedKeyPath := shellSingleQuote(keyPath)
	quotedFingerprint := shellSingleQuote(fingerprint)
	return strings.Join([]string{
		"export SSH_AUTH_SOCK=\"${PLASTICINE_HOME:-$HOME/.plasticine}/runtime/ssh-agent.sock\"",
		"if [ -n " + quotedFingerprint + " ] && [ -r " + quotedKeyPath + " ] && command -v ssh-add >/dev/null 2>&1; then",
		"  if ! ssh-add -l 2>/dev/null | grep -Fq " + quotedFingerprint + "; then",
		"    ssh-add " + quotedKeyPath + " >/dev/null",
		"  fi",
		"fi",
		"",
	}, "\n")
}

func shellSingleQuote(value string) string {
	return "'" + strings.ReplaceAll(value, "'", "'\"'\"'") + "'"
}

func githubSSHManagedBlock() string {
	return strings.Join([]string{
		sshBlockStart,
		"Host github.com",
		"  Include ~/.plasticine/config/ssh/github.conf",
		sshBlockEnd,
		"",
	}, "\n")
}
