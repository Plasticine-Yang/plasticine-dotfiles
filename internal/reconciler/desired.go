package reconciler

import (
	"path/filepath"
	"strings"
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

func componentDesiredResources(req Request, component ComponentID, secret *SecretReference) []desiredResource {
	switch component {
	case ComponentShell:
		return []desiredResource{
			{
				Component:    component,
				Path:         zshConfigPath(req.Home),
				ResourceKind: ResourceManagedPath,
				Content: strings.Join([]string{
					"# Managed by Plasticine.",
					"export PLASTICINE_HOME=\"${PLASTICINE_HOME:-$HOME/.plasticine}\"",
					"export PATH=\"$PLASTICINE_HOME/bin:$PATH\"",
					"export ANTIDOTE_HOME=\"$PLASTICINE_HOME/runtime/antidote\"",
					"",
				}, "\n"),
				Summary: "materialize centralized Zsh configuration",
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
				Content: strings.Join([]string{
					"[user]",
					"  email = 975036719@qq.com",
					"  name = plasticine",
					"[init]",
					"  defaultBranch = main",
					"[pull]",
					"  rebase = true",
					"",
				}, "\n"),
				Summary: "materialize centralized personal Git configuration",
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
		return managedToolResources(req, component, "neovim", []string{"nvim"})
	case ComponentLazygit:
		return managedToolResources(req, component, "lazygit", []string{"lazygit", "lg"})
	case ComponentFNM:
		return managedToolResources(req, component, "fnm", []string{"fnm"})
	case ComponentUV:
		return managedToolResources(req, component, "uv", []string{"uv", "uvx"})
	case ComponentGitHubSSH:
		resources := []desiredResource{
			{
				Component:    component,
				Path:         githubSSHFragmentPath(req.Home),
				ResourceKind: ResourceManagedPath,
				Content:      githubSSHFragmentContent(secret),
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
				ResourceKind: ResourceIntegrationShim,
				Content:      "[Service]\nExecStart=/usr/bin/ssh-agent -D -a %h/.plasticine/runtime/ssh-agent.sock\n",
				Summary:      "configure shared user-level Linux SSH agent",
			})
		}
		return resources
	default:
		return nil
	}
}

func managedToolResources(req Request, component ComponentID, tool string, entries []string) []desiredResource {
	home := req.Home
	version := toolLockVersionSegment(req.ToolLockSHA256)
	versionedRoot := filepath.Join(home, "tools", tool, version)
	resources := make([]desiredResource, 0, len(entries)*2)
	seenPayloads := map[string]bool{}
	for _, entry := range entries {
		payloadName := entry
		if tool == "lazygit" {
			payloadName = "lazygit"
		}
		payloadPath := filepath.Join(versionedRoot, payloadName)
		if !seenPayloads[payloadPath] {
			seenPayloads[payloadPath] = true
			resources = append(resources, desiredResource{
				Component:    component,
				Path:         payloadPath,
				ResourceKind: ResourceManagedTool,
				Content:      "managed tool " + tool + " executable " + payloadName + " selected by Tool Lock\n",
				Summary:      "install exact " + tool + " payload selected by Tool Lock",
			})
		}
	}
	for _, entry := range entries {
		if tool == "lazygit" {
			resources = append(resources, desiredResource{
				Component:    component,
				Path:         filepath.Join(home, "bin", entry),
				ResourceKind: ResourceSymlink,
				Content:      filepath.Join(versionedRoot, "lazygit"),
				Summary:      "materialize stable " + entry + " symlink",
			})
			continue
		}
		launcher := toolLauncher(versionedRoot, tool, entry)
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

func toolLockVersionSegment(sha256 string) string {
	if len(sha256) >= 12 {
		return sha256[:12]
	}
	if sha256 != "" {
		return sha256
	}
	return "unknown-tool-lock"
}

func toolLauncher(versionedRoot string, tool string, entry string) string {
	lines := []string{"#!/bin/sh"}
	switch tool {
	case "neovim":
		lines = append(lines,
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

func githubSSHFragmentContent(secret *SecretReference) string {
	keyPath := ""
	if secret != nil {
		keyPath = secret.Path
	}
	return strings.Join([]string{
		"Host github.com",
		"  HostName github.com",
		"  User git",
		"  IdentitiesOnly yes",
		"  IdentityFile " + keyPath,
		"  UserKnownHostsFile ~/.plasticine/config/ssh/github_known_hosts",
		"  StrictHostKeyChecking yes",
		"",
	}, "\n")
}

func githubKnownHostsContent() string {
	return strings.Join([]string{
		"github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl",
		"github.com ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBEmKSENjQEezOmxkZMy7opKgwFB9nkt5YRrYMjNuG5N87uRgg6CLrbo5wAdT/y6v0mKV0U2w0WZ2YB/++Tpockg=",
		"github.com ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCj7ndNxQowgcQnjshcLrqPEiiphnt+VTTvDP6mHBL9j1aNUkY4Ue1gvwnGLVlOhGeYrnZaMgRK6+PKCUXaDbC7qtbW8gIkhL7aGCsOr/C56SJMy/BCZfxd1nWzAOxSDPgVsmerOBYfNqltV9/hWCqBywINIR+5dIg6JTJ72pcEpEjcYgXkE2YEFXV1JHnsKgbLWNlhScqb2UmyRkQyytRLtL+38TGxkxCflmO+5Z8CSSNY7GidjMIZ7Q4zMjA2n1nGrlTDkzwDCsw+wqFPGQA179cnfGWOWRVruj16z6XyvxvjJwbz0wQZ75XK5tKSb7FNyeIEs4TT4jk+S4dhPeAUC5y+bDYirYgM4GC7uEnztnZyaVWQ7B381AK4Qdrwt51ZqExKbQpTUNn+EjqoTwvqNj4kqx5QUCI0ThS/YkOxJCXmPUWZbhjpCg56i+2aB6CmK2JGhn57K5mj0MNdBXA4/WnwH6XoPWJzK5Nyu2zB3nAZp+S5hpQs+p1vN1/wsjk=",
		"",
	}, "\n")
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
