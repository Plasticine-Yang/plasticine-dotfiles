# 02 — Bootstrap the shell toolchain and login shell

Status: ready-for-agent

Blocked by: 01

## What to build

Extend the `shell` feature from configuring healthy existing tools to preparing a fresh supported workstation. Install only missing tools through reviewed native routes, recheck health before configuration, and attempt the native login-shell transition last.

## Acceptance criteria

- Supported macOS uses its system Zsh; an absent or unhealthy expected system Zsh fails with guidance.
- Supported Debian/Ubuntu uses an existing healthy Zsh or installs the missing package through the reviewed APT route.
- Existing healthy Antidote is retained. Missing Antidote uses Homebrew on macOS and its official Git checkout on supported Linux.
- Existing but unhealthy Zsh, Antidote, Git, Homebrew, or Powerlevel10k is left untouched and fails without switching installation owners.
- Missing Powerlevel10k is obtained through Antidote's plugin mechanism. Plasticine does not copy or own its checkout.
- Preview identifies the exact selected route, network need, package-manager mutation, privilege possibility, external-installer opacity, and proposed `chsh` command before confirmation.
- Only the reviewed APT child commands may invoke `sudo`; Homebrew, Git checkout, chezmoi, configuration writes, and `chsh` run as the invoking user.
- `--yes` does not answer Homebrew, sudo, or `chsh` credential prompts. A route requiring an unavailable terminal fails with useful guidance.
- The installer validates every shell configuration destination before the first tool mutation and revalidates tool health before applying configuration.
- Configuration is not applied when tool preparation fails. There is no automatic fallback route.
- The account login shell is read from the native account database rather than `$SHELL`. Equivalent merged-usr Zsh paths are treated as already configured.
- `chsh -s <absolute-zsh-path>` is attempted only after tools and configuration are usable. A failed transition retains them, returns failure, and is retryable without unnecessary rewrites.
- Tests use fake package managers, network commands, privilege commands, account databases, and `chsh`; they must never mutate the developer's real machine.

## Comments
