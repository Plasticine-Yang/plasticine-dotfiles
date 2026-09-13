#!/bin/sh
# Existing-current-editor support. Ticket 13 owns archive installation/update.

plasticine_neovim_error() {
    printf 'plasticine-dotfiles: neovim: %s\n' "$1" >&2
}

plasticine_neovim_preview() {
    printf '%s\n' \
        'plasticine-dotfiles: Previewing Neovim...' \
        '  apply will query the official stable Neovim release and require the existing editor to match it' \
        '  route in this increment: existing current editor only; missing or outdated editors need ticket 13 archive installation' \
        '  network during apply: api.github.com and lazy.nvim/plugin Git repositories' \
        '  effects: manage exactly nine ~/.config/nvim Lua files, then run native lazy.nvim update/synchronization' \
        '  plugin checkout, cache, state, and lazy-lock.json remain owned by Neovim/lazy.nvim; no privilege required'
}

plasticine_neovim_release_url() {
    printf '%s\n' "${PLASTICINE_NEOVIM_RELEASE_API_URL:-https://api.github.com/repos/neovim/neovim/releases/latest}"
}

plasticine_neovim_stable_target() {
    plasticine_neovim_metadata=$(mktemp "${TMPDIR:-/tmp}/plasticine-neovim-release.XXXXXX") || return 1
    trap 'rm -f "$plasticine_neovim_metadata"' EXIT HUP INT TERM
    if ! curl --proto '=https' --proto-redir '=https' -fsSL \
        "$(plasticine_neovim_release_url)" > "$plasticine_neovim_metadata"; then
        plasticine_neovim_error 'official stable release lookup failed; managed configuration was not applied.'
        return 1
    fi
    plasticine_neovim_target=$(sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\(v[0-9][0-9.]*\)".*/\1/p' "$plasticine_neovim_metadata" | sed -n '1p')
    case $plasticine_neovim_target in
        v[0-9]*.*) ;;
        *) plasticine_neovim_error 'official stable release metadata did not contain a comparable tag; managed configuration was not applied.'; return 1 ;;
    esac
    rm -f "$plasticine_neovim_metadata"
    trap - EXIT HUP INT TERM
}

plasticine_neovim_observed_version() {
    plasticine_neovim_bin=$(command -v nvim 2>/dev/null || true)
    [ -n "$plasticine_neovim_bin" ] || {
        plasticine_neovim_error 'Neovim is missing; install the latest official stable archive with ticket 13, then retry.'
        return 1
    }
    plasticine_neovim_line=$("$plasticine_neovim_bin" --version 2>/dev/null | sed -n '1p') || {
        plasticine_neovim_error 'the existing editor is not healthy; repair or replace it through the official archive route, then retry.'
        return 1
    }
    case $plasticine_neovim_line in
        'NVIM v'[0-9]*.*) plasticine_neovim_observed=v${plasticine_neovim_line#NVIM v} ;;
        *) plasticine_neovim_error 'the existing editor version is unverifiable; install the latest official stable archive with ticket 13, then retry.'; return 1 ;;
    esac
    plasticine_neovim_observed=${plasticine_neovim_observed%% *}
    case $plasticine_neovim_observed in
        *-*) plasticine_neovim_error "the existing editor is a prerelease ($plasticine_neovim_observed), not the official stable target; use ticket 13 to install stable."; return 1 ;;
    esac
}

plasticine_neovim_prepare() {
    plasticine_neovim_stable_target || return 1
    plasticine_neovim_observed_version || return 1
    if [ "$plasticine_neovim_observed" != "$plasticine_neovim_target" ]; then
        plasticine_neovim_error "existing editor is $plasticine_neovim_observed but official stable is $plasticine_neovim_target; update through ticket 13's official archive route before applying configuration."
        return 1
    fi
    printf 'plasticine-dotfiles: neovim: existing editor %s matches official stable; configuration and native plugin update may proceed.\n' "$plasticine_neovim_observed"
}

plasticine_neovim_sync() {
    plasticine_neovim_dest=$1
    plasticine_neovim_observed_version || return 1
    printf '%s\n' 'plasticine-dotfiles: neovim: updating plugins through lazy.nvim...'
    HOME="$plasticine_neovim_dest" XDG_CONFIG_HOME="$plasticine_neovim_dest/.config" \
        XDG_DATA_HOME="$plasticine_neovim_dest/.local/share" \
        XDG_STATE_HOME="$plasticine_neovim_dest/.local/state" \
        XDG_CACHE_HOME="$plasticine_neovim_dest/.cache" \
        "$plasticine_neovim_bin" --headless '+Lazy! sync' '+lua vim.wait(1000)' '+qa' || {
        plasticine_neovim_error 'native plugin synchronization or startup failed after configuration application; configuration/backups and completed native effects remain. Fix the reported error and retry.'
        return 1
    }
    HOME="$plasticine_neovim_dest" XDG_CONFIG_HOME="$plasticine_neovim_dest/.config" \
        XDG_DATA_HOME="$plasticine_neovim_dest/.local/share" \
        XDG_STATE_HOME="$plasticine_neovim_dest/.local/state" \
        XDG_CACHE_HOME="$plasticine_neovim_dest/.cache" \
        "$plasticine_neovim_bin" --headless \
        '+lua local ok, err = pcall(function() assert(vim.fn.maparg("<C-n>", "n") ~= ""); assert(type(_FLOAT_TERM) == "function"); assert(vim.fn.exists(":NvimTreeToggle") == 2) end); if not ok then io.stderr:write(tostring(err) .. "\n"); vim.cmd("cquit") end' '+qa' || {
        plasticine_neovim_error 'runtime readiness check failed after plugin synchronization; retry after correcting the reported configuration/plugin error.'
        return 1
    }
    printf '%s\n' 'plasticine-dotfiles: neovim: managed configuration started and current plugins passed runtime readiness.'
}
