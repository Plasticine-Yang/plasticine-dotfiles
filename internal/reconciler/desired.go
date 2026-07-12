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
	Tool            release.ManagedTool
	Entry           string
	Artifact        release.ToolArtifact
	CacheSHA256     string
	Directory       bool
	RequiredEntries []string
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

func zshPluginDeclarationPath(home string) string {
	return filepath.Join(home, "config", "zsh", ".zsh_plugins.txt")
}

func zshPromptConfigPath(home string) string {
	return filepath.Join(home, "config", "zsh", ".p10k.zsh")
}

func antidoteSourceShimPath(home string) string {
	return filepath.Join(home, "config", "zsh", "antidote.zsh")
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
		resources := []desiredResource{}
		if antidote := managedToolDirectoryResource(req, component, release.ManagedToolAntidote, toolLock, []string{"antidote.zsh", "functions"}); antidote.Path != "" {
			resources = append(resources, antidote, desiredResource{
				Component:    component,
				Path:         zshPluginDeclarationPath(req.Home),
				ResourceKind: ResourceManagedPath,
				Content:      zshPluginDeclarationContent(),
				Summary:      "materialize managed Zsh plugin declaration",
			}, desiredResource{
				Component:    component,
				Path:         zshPromptConfigPath(req.Home),
				ResourceKind: ResourceManagedPath,
				Content:      desiredstate.Powerlevel10kConfig(),
				Summary:      "materialize managed Powerlevel10k prompt configuration",
			}, desiredResource{
				Component:    component,
				Path:         antidoteSourceShimPath(req.Home),
				ResourceKind: ResourceManagedPath,
				Content:      antidoteSourceShimContent(toolLock, req.ToolLockSHA256),
				Summary:      "materialize stable Antidote source shim",
			})
		}
		resources = append(resources, desiredResource{
			Component:    component,
			Path:         zshConfigPath(req.Home),
			ResourceKind: ResourceManagedPath,
			Content:      zshConfigContent(req, active[ComponentGitHubSSH], active[ComponentFNM]),
			Summary:      "materialize centralized Zsh configuration",
		}, desiredResource{
			Component:    component,
			Path:         zshShimPath(req),
			ResourceKind: ResourceIntegrationShim,
			Content:      "source \"${PLASTICINE_HOME:-$HOME/.plasticine}/config/zsh/.zshrc\"\n",
			Summary:      "materialize minimal Zsh shim",
		})
		return compactDesiredResources(resources)
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
		return neovimResources(req, toolLock)
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

func neovimResources(req Request, toolLock release.ToolLock) []desiredResource {
	resources := neovimConfigResources(req.Home)
	payload := managedToolDirectoryResource(req, ComponentNeovim, release.ManagedToolNeovim, toolLock, []string{
		"bin/nvim",
		"share/nvim/runtime/lua/vim/deprecated/health.lua",
		"share/nvim/runtime/syntax/syntax.vim",
	})
	if payload.Path == "" {
		return resources
	}
	versionedRoot := filepath.Join(req.Home, "tools", string(release.ManagedToolNeovim), managedToolVersionSegment(toolLock, release.ManagedToolNeovim, req.ToolLockSHA256))
	resources = append(resources, payload, desiredResource{
		Component:    ComponentNeovim,
		Path:         filepath.Join(req.Home, "bin", "nvim"),
		ResourceKind: ResourceIntegrationShim,
		Content:      toolLauncher(versionedRoot, string(release.ManagedToolNeovim), "nvim"),
		Summary:      "materialize stable nvim launcher",
	})
	return resources
}

func zshConfigContent(req Request, githubSSHActive bool, fnmActive bool) string {
	lines := []string{
		"# Managed by Plasticine.",
		"export PLASTICINE_HOME=\"${PLASTICINE_HOME:-$HOME/.plasticine}\"",
		"export PATH=\"$PLASTICINE_HOME/bin:$PATH\"",
		"export ANTIDOTE_HOME=\"$PLASTICINE_HOME/runtime/antidote\"",
		"export ZDOTDIR=\"$ANTIDOTE_HOME/zsh\"",
		"zstyle ':antidote:bundle' use-friendly-names 'yes'",
		"zstyle ':antidote:bundle' file \"$ANTIDOTE_HOME/static.zsh\"",
		"zstyle ':compinit' dumpfile \"$ANTIDOTE_HOME/.zcompdump\"",
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
	lines = append(lines,
		"if [ -r \"$PLASTICINE_HOME/config/zsh/antidote.zsh\" ]; then",
		"  . \"$PLASTICINE_HOME/config/zsh/antidote.zsh\"",
		"  _plasticine_plugins=\"$PLASTICINE_HOME/config/zsh/.zsh_plugins.txt\"",
		"  _plasticine_bundle=\"$ANTIDOTE_HOME/static.zsh\"",
		"  _plasticine_p10k=\"$PLASTICINE_HOME/config/zsh/.p10k.zsh\"",
		"  ZVM_VI_INSERT_ESCAPE_BINDKEY=jk # jk -> <Esc>",
		"  ZVM_VI_EDITOR=nvim # vv -> nvim",
		"  if [ -r \"$_plasticine_plugins\" ]; then",
		"    if [ ! -r \"$_plasticine_bundle\" ] || [ \"$_plasticine_plugins\" -nt \"$_plasticine_bundle\" ]; then",
		"      mkdir -p \"$ANTIDOTE_HOME\" \"$ZDOTDIR\"",
		"      antidote bundle < \"$_plasticine_plugins\" >| \"$_plasticine_bundle\"",
		"    fi",
		"    [ -r \"$_plasticine_bundle\" ] && . \"$_plasticine_bundle\"",
		"    [ -r \"$_plasticine_p10k\" ] && . \"$_plasticine_p10k\"",
		"  fi",
		"  unset _plasticine_plugins _plasticine_bundle _plasticine_p10k",
		"fi",
		"",
	)
	return strings.Join(lines, "\n")
}

func zshPluginDeclarationContent() string {
	return strings.Join([]string{
		"# Zsh Completions",
		"zsh-users/zsh-completions",
		"",
		"# Vi-mode",
		"jeffreytse/zsh-vi-mode",
		"",
		"# Syntax Highlighting",
		"zsh-users/zsh-syntax-highlighting",
		"",
		"# History Substring Search",
		"zsh-users/zsh-history-substring-search",
		"",
		"# Autosuggestions",
		"zsh-users/zsh-autosuggestions",
		"",
		"# Prompt Theme - Powerlevel10k",
		"romkatv/powerlevel10k",
		"",
	}, "\n")
}

func antidoteSourceShimContent(toolLock release.ToolLock, fallbackSHA string) string {
	version := managedToolVersionSegment(toolLock, release.ManagedToolAntidote, fallbackSHA)
	return "source \"${PLASTICINE_HOME:-$HOME/.plasticine}/tools/antidote/" + version + "/antidote.zsh\"\n"
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

func managedToolDirectoryResource(req Request, component ComponentID, tool release.ManagedTool, toolLock release.ToolLock, requiredEntries []string) desiredResource {
	toolName := string(tool)
	version := managedToolVersionSegment(toolLock, tool, req.ToolLockSHA256)
	versionedRoot := filepath.Join(req.Home, "tools", toolName, version)
	artifact, hasArtifact := managedToolArtifact(toolLock, tool, req.Target)
	if !hasArtifact {
		return desiredResource{}
	}
	resource := desiredResource{
		Component:    component,
		Path:         versionedRoot,
		ResourceKind: ResourceManagedTool,
		Content:      "managed tool " + toolName + " directory selected by Tool Lock\n",
		Summary:      "install exact " + toolName + " directory payload selected by Tool Lock",
	}
	resource.ManagedTool = &managedToolInstall{
		Tool:            tool,
		Artifact:        artifact,
		CacheSHA256:     artifact.SHA256,
		Directory:       true,
		RequiredEntries: append([]string(nil), requiredEntries...),
	}
	return resource
}

func compactDesiredResources(resources []desiredResource) []desiredResource {
	compacted := resources[:0]
	for _, resource := range resources {
		if resource.Path == "" {
			continue
		}
		compacted = append(compacted, resource)
	}
	return compacted
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
	execPath := filepath.Join(versionedRoot, entry)
	switch tool {
	case "neovim":
		execPath = filepath.Join(versionedRoot, "bin", entry)
		lines = append(lines,
			"export XDG_CONFIG_HOME=\"${PLASTICINE_HOME:-$HOME/.plasticine}/config\"",
			"export XDG_STATE_HOME=\"${PLASTICINE_HOME:-$HOME/.plasticine}/runtime/nvim/state\"",
			"export XDG_DATA_HOME=\"${PLASTICINE_HOME:-$HOME/.plasticine}/runtime/nvim/data\"",
			"export XDG_CACHE_HOME=\"${PLASTICINE_HOME:-$HOME/.plasticine}/runtime/nvim/cache\"",
			"export VIMRUNTIME=\""+filepath.Join(versionedRoot, "share", "nvim", "runtime")+"\"",
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
	lines = append(lines, "exec \""+execPath+"\" \"$@\"", "")
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
