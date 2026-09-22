#!/bin/sh

plasticine_neovim_error() {
    printf 'plasticine-dotfiles: neovim: %s\n' "$1" >&2
}

plasticine_neovim_resolve() {
    command -v nvim 2>/dev/null && return 0
    [ -n "${neovim_target_command:-}" ] && [ -e "$neovim_target_command" ] && printf '%s\n' "$neovim_target_command"
}

plasticine_neovim_version() {
    [ -x "$1" ] || return 1
    "$1" --version 2>/dev/null | sed -n '1{s/^NVIM v\([0-9][0-9.]*\)$/\1/p;}' | awk '
        /^[0-9]+\.[0-9]+\.[0-9]+$/ { seen++; value=$0 }
        END { if (seen == 1) print value; else exit 1 }'
}

plasticine_neovim_compare() {
    awk -v left="$1" -v right="$2" 'BEGIN {
        split(left, l, "."); split(right, r, ".")
        for (i=1; i<=3; i++) {
            if (l[i]+0 < r[i]+0) { print -1; exit }
            if (l[i]+0 > r[i]+0) { print 1; exit }
        }
        print 0
    }'
}

plasticine_neovim_checksum() {
    case $neovim_sha_command in
        sha256sum) sha256sum "$1" | awk 'NF == 2 {print tolower($1)}' ;;
        shasum) shasum -a 256 "$1" | awk 'NF == 2 {print tolower($1)}' ;;
        *) return 1 ;;
    esac
}

plasticine_neovim_identity() {
    plasticine_neovim_checksum "$1"
}

plasticine_neovim_validate_destination() {
    for plasticine_neovim_parent in "$neovim_home" "$neovim_home/.local" "$neovim_bin_dir" "$neovim_opt_dir"; do
        if [ -e "$plasticine_neovim_parent" ] || [ -L "$plasticine_neovim_parent" ]; then
            [ -d "$plasticine_neovim_parent" ] && [ ! -L "$plasticine_neovim_parent" ] || {
                plasticine_neovim_error "installation parent is not a real directory: $plasticine_neovim_parent"; return 1; }
        fi
    done
    if [ -e "$neovim_install_dir" ] || [ -L "$neovim_install_dir" ]; then
        neovim_distribution_link=$(readlink "$neovim_install_dir" 2>/dev/null || true)
        case $neovim_distribution_link in .neovim.plasticine-*) ;;
            *) plasticine_neovim_error "distribution target is not the managed release link: $neovim_install_dir; left untouched."; return 1 ;; esac
        [ -d "$neovim_opt_dir/$neovim_distribution_link" ] && [ ! -L "$neovim_opt_dir/$neovim_distribution_link" ] || {
            plasticine_neovim_error "managed distribution link is broken or unsafe: $neovim_install_dir; left untouched."; return 1; }
    fi
    if [ -e "$neovim_target_command" ] || [ -L "$neovim_target_command" ]; then
        [ -L "$neovim_target_command" ] && [ "$(readlink "$neovim_target_command")" = ../opt/neovim/bin/nvim ] || {
            plasticine_neovim_error "command entry is not the managed Neovim link: $neovim_target_command; left untouched."; return 1; }
    fi
}

plasticine_neovim_plan() {
    neovim_home=$1
    case $neovim_home in /*) ;; *) plasticine_neovim_error 'destination must be an absolute path.'; return 1 ;; esac
    neovim_opt_dir=$neovim_home/.local/opt
    neovim_install_dir=$neovim_opt_dir/neovim
    neovim_bin_dir=$neovim_home/.local/bin
    neovim_target_command=$neovim_bin_dir/nvim
    neovim_os=${PLASTICINE_NEOVIM_OS:-$(uname -s)}
    neovim_arch=${PLASTICINE_NEOVIM_ARCH:-$(uname -m)}
    case $neovim_os in Darwin) neovim_asset_os=macos ;; Linux) neovim_asset_os=linux ;;
        *) plasticine_neovim_error "unsupported platform: $neovim_os; no official archive route or fallback."; return 1 ;; esac
    case $neovim_arch in x86_64|amd64) neovim_asset_arch=x86_64 ;; arm64|aarch64) neovim_asset_arch=arm64 ;;
        *) plasticine_neovim_error "unsupported architecture: $neovim_arch; no official archive route or fallback."; return 1 ;; esac
    neovim_asset=nvim-$neovim_asset_os-$neovim_asset_arch.tar.gz
    neovim_archive_root=${neovim_asset%.tar.gz}
    neovim_version=0.12.5
    neovim_tag=v$neovim_version
    case $neovim_asset in
        nvim-macos-x86_64.tar.gz) neovim_expected=81f4518622cb059b450ee2e498c6a1082a222f6bd89589de5bbcf0c6a68aa3fd ;;
        nvim-macos-arm64.tar.gz) neovim_expected=65fb000099e47ca1b762584c484cc833f40e30851a0ec450d4174e16317c1f9b ;;
        nvim-linux-x86_64.tar.gz) neovim_expected=bce0f56eda1f1b1db6eee8f4133d7a38813ea07933837dd1777411ca384c6875 ;;
        nvim-linux-arm64.tar.gz) neovim_expected=1aa5ca085249580ae0f91eb14f27ec0919773ff2d99a163d03f3d6c21ac29725 ;;
        *) plasticine_neovim_error "no reviewed artifact tuple for $neovim_asset"; return 1 ;;
    esac
    for plasticine_neovim_command in curl tar awk sed env mktemp mkdir chmod ln mv rm readlink; do
        command -v "$plasticine_neovim_command" >/dev/null 2>&1 || {
            plasticine_neovim_error "missing command required by the official archive route: $plasticine_neovim_command"; return 1; }
    done
    if command -v sha256sum >/dev/null 2>&1; then neovim_sha_command=sha256sum
    elif command -v shasum >/dev/null 2>&1; then neovim_sha_command=shasum
    else plasticine_neovim_error 'missing SHA-256 command (sha256sum or shasum); no fallback.'; return 1; fi
    plasticine_neovim_validate_destination || return 1
}

plasticine_neovim_preview() {
    printf 'plasticine-dotfiles: neovim: observed %s/%s; official archive %s\n' "$neovim_os" "$neovim_arch" "$neovim_asset"
    printf '%s\n' \
        '  Fixed supported baseline: Neovim 0.12.5 from its exact official versioned GitHub Release asset.' \
        '  Missing Neovim is installed; an outdated managed distribution is safely replaced; a current installation is retained.' \
        '  Current external owners may be used without mutation; outdated, prerelease, custom, unhealthy, or ambiguous owners are refused.'
    if plasticine_neovim_uses_release_snapshot; then
        printf '%s\n' \
            '  network during apply: the pinned github.com/neovim/neovim archive only when needed; plugins come from the verified Plasticine Release snapshot without Git updates.' \
            '  effects after editor preparation: manage exactly twelve ~/.config/nvim Lua files, then verify the restored plugin runtime.'
    else
        printf '%s\n' \
            '  network during apply: the pinned github.com/neovim/neovim archive only when needed, plus lazy.nvim/plugin Git repositories.' \
            '  effects after editor preparation: manage exactly twelve ~/.config/nvim Lua files, then run native lazy.nvim update/synchronization.'
    fi
    printf '%s\n' \
        "  verification: reviewed pinned SHA-256, safe archive layout, candidate version and complete runtime; the digest shares GitHub's release trust boundary and is not an independent signature." \
        "  distribution: $neovim_install_dir; command link: $neovim_target_command; package manager/privilege: none."
}

plasticine_neovim_prepare() {
    neovim_work_dir=$(mktemp -d "${TMPDIR:-/tmp}/plasticine-neovim.XXXXXX") || return 1
    trap 'rm -rf "$neovim_work_dir"' EXIT
    trap 'rm -rf "$neovim_work_dir"; exit 1' HUP INT TERM
    neovim_archive=$neovim_work_dir/archive.tar.gz
    neovim_extract=$neovim_work_dir/extract
    neovim_url=https://github.com/neovim/neovim/releases/download/$neovim_tag/$neovim_asset

    neovim_bin=$(plasticine_neovim_resolve || true)
    neovim_owner=missing
    if [ -n "$neovim_bin" ]; then
        neovim_observed=$(plasticine_neovim_version "$neovim_bin") || { plasticine_neovim_error "existing editor is unhealthy or has a prerelease/custom/unverifiable version: $neovim_bin; repair its owner. Left untouched."; return 1; }
        [ "$neovim_bin" = "$neovim_target_command" ] && [ -L "$neovim_target_command" ] && [ "$(readlink "$neovim_target_command")" = ../opt/neovim/bin/nvim ] && [ -L "$neovim_install_dir" ] && neovim_owner=direct || neovim_owner=external
        neovim_comparison=$(plasticine_neovim_compare "$neovim_observed" "$neovim_version")
        case $neovim_comparison in
            0|1) printf 'plasticine-dotfiles: neovim: pinned baseline %s is satisfied by stable %s at %s; distribution retained without editor release traffic.\n' "$neovim_version" "$neovim_observed" "$neovim_bin"; return 0 ;;
            -1) [ "$neovim_owner" = direct ] || { plasticine_neovim_error "outdated Neovim $neovim_observed at unsupported owner path $neovim_bin; update it with its owner. No shadow installation was created."; return 1; }; neovim_publication=upgrade ;;
        esac
    else
        [ ! -e "$neovim_install_dir" ] && [ ! -L "$neovim_install_dir" ] && [ ! -e "$neovim_target_command" ] && [ ! -L "$neovim_target_command" ] || {
            plasticine_neovim_error 'an unowned distribution or command exists at the managed destination; remove or repair it explicitly. Left untouched.'; return 1; }
        neovim_publication=fresh
    fi
    if [ "$neovim_owner" = direct ]; then
        neovim_original_link=$(readlink "$neovim_install_dir") || return 1
        neovim_original_identity=$(plasticine_neovim_identity "$neovim_install_dir/bin/nvim") || return 1
    fi

    curl --proto '=https' --proto-redir '=https' -fsSL -o "$neovim_archive" "$neovim_url" || { plasticine_neovim_error 'official archive download failed; active installation was left untouched.'; return 1; }
    neovim_actual=$(plasticine_neovim_checksum "$neovim_archive") || return 1
    [ "$neovim_actual" = "$neovim_expected" ] || { plasticine_neovim_error 'GitHub Release asset SHA-256 digest mismatch; active installation was left untouched.'; return 1; }
    tar -tzf "$neovim_archive" > "$neovim_work_dir/members" 2>/dev/null || { plasticine_neovim_error 'archive listing failed; active installation was left untouched.'; return 1; }
    awk -v root="$neovim_archive_root/" 'NF == 0 || index($0, root) != 1 || $0 ~ /(^|\/)\.\.(\/|$)/ {bad=1} END {exit bad}' "$neovim_work_dir/members" || { plasticine_neovim_error 'archive contains an unsafe or unexpected member path; active installation was left untouched.'; return 1; }
    tar -tvzf "$neovim_archive" > "$neovim_work_dir/member-details" 2>/dev/null || { plasticine_neovim_error 'archive detail listing failed; active installation was left untouched.'; return 1; }
    awk 'substr($0, 1, 1) == "l" || substr($0, 1, 1) == "h" { unsafe=1 } END { exit unsafe }' \
        "$neovim_work_dir/member-details" || { plasticine_neovim_error 'archive contains a symbolic-link or hard-link member; active installation was left untouched.'; return 1; }
    if ! mkdir "$neovim_extract" || ! tar -xzf "$neovim_archive" -C "$neovim_extract"; then
        plasticine_neovim_error 'archive extraction failed; active installation was left untouched.'
        return 1
    fi
    neovim_candidate=$neovim_extract/$neovim_archive_root
    [ -x "$neovim_candidate/bin/nvim" ] && [ -d "$neovim_candidate/share/nvim/runtime" ] && [ -f "$neovim_candidate/share/nvim/runtime/filetype.lua" ] || { plasticine_neovim_error 'archive is not a complete Neovim distribution; active installation was left untouched.'; return 1; }
    neovim_candidate_version=$(plasticine_neovim_version "$neovim_candidate/bin/nvim") || { plasticine_neovim_error 'candidate editor failed its version health check; active installation was left untouched.'; return 1; }
    [ "$neovim_candidate_version" = "$neovim_version" ] || { plasticine_neovim_error "candidate version $neovim_candidate_version does not match target $neovim_version; active installation was left untouched."; return 1; }
    env -u VIMRUNTIME "$neovim_candidate/bin/nvim" --clean --headless '+lua assert(vim.fn.isdirectory(vim.env.VIMRUNTIME) == 1); assert(vim.fn.filereadable(vim.env.VIMRUNTIME .. "/filetype.lua") == 1)' '+qa' >/dev/null 2>&1 || { plasticine_neovim_error 'candidate could not load its packaged runtime; active installation was left untouched.'; return 1; }

    plasticine_neovim_validate_destination || return 1
    umask 077
    [ -e "$neovim_home/.local" ] || mkdir "$neovim_home/.local" || return 1
    [ -e "$neovim_opt_dir" ] || mkdir "$neovim_opt_dir" || return 1
    [ -e "$neovim_bin_dir" ] || mkdir "$neovim_bin_dir" || return 1
    plasticine_neovim_validate_destination || return 1
    neovim_release_dir=$neovim_opt_dir/.neovim.plasticine-$neovim_version-$$
    [ ! -e "$neovim_release_dir" ] && [ ! -L "$neovim_release_dir" ] || { plasticine_neovim_error 'private publication pathname unexpectedly exists.'; return 1; }
    mv "$neovim_candidate" "$neovim_release_dir" || { plasticine_neovim_error 'could not stage the complete distribution beside its destination.'; return 1; }
    case $neovim_publication in
        fresh)
            [ ! -e "$neovim_install_dir" ] && [ ! -L "$neovim_install_dir" ] && [ ! -e "$neovim_target_command" ] && [ ! -L "$neovim_target_command" ] || { plasticine_neovim_error 'managed destination appeared during preparation; publication aborted.'; return 1; }
            ln -s "${neovim_release_dir##*/}" "$neovim_install_dir" || { plasticine_neovim_error 'atomic no-clobber distribution publication failed.'; return 1; }
            ln -s ../opt/neovim/bin/nvim "$neovim_target_command" || { plasticine_neovim_error "distribution was published at $neovim_install_dir but command-link publication failed; inspect it and retry."; return 1; }
            ;;
        upgrade)
            plasticine_neovim_validate_destination || return 1
            [ "$(readlink "$neovim_install_dir")" = "$neovim_original_link" ] || { plasticine_neovim_error 'authorized distribution link changed during preparation; replacement aborted.'; return 1; }
            neovim_revalidated_identity=$(plasticine_neovim_identity "$neovim_install_dir/bin/nvim") || return 1
            [ "$neovim_revalidated_identity" = "$neovim_original_identity" ] || { plasticine_neovim_error 'authorized distribution changed during preparation; replacement aborted.'; return 1; }
            ln -sfn "${neovim_release_dir##*/}" "$neovim_install_dir" || { plasticine_neovim_error 'atomic authorized distribution switch failed; inspect the active link before retrying.'; return 1; }
            ;;
    esac
    neovim_result=$(plasticine_neovim_version "$neovim_target_command") || { plasticine_neovim_error 'published editor failed final health verification; configuration was not applied. Inspect the retained distribution.'; return 1; }
    [ "$neovim_result" = "$neovim_version" ] || { plasticine_neovim_error 'published editor does not match the resolved target; configuration was not applied.'; return 1; }
    if [ "$neovim_publication" = upgrade ] && [ "$neovim_original_link" != "${neovim_release_dir##*/}" ]; then
        case $neovim_original_link in .neovim.plasticine-*) rm -rf "${neovim_opt_dir:?}/$neovim_original_link" ;; esac
    fi
    printf 'plasticine-dotfiles: neovim: %s completed at stable target %s with complete runtime: %s\n' "$neovim_publication" "$neovim_version" "$neovim_install_dir"
}

plasticine_neovim_observed_version() {
    plasticine_neovim_bin=$(plasticine_neovim_resolve || true)
    [ -n "$plasticine_neovim_bin" ] || { plasticine_neovim_error 'Neovim is missing after preparation.'; return 1; }
    plasticine_neovim_version "$plasticine_neovim_bin" >/dev/null || { plasticine_neovim_error 'the selected editor is not healthy after preparation.'; return 1; }
}

plasticine_neovim_uses_release_snapshot() {
    [ -n "${PLASTICINE_MANAGED_PLUGINS_ARCHIVE:-}" ] ||
        [ -f "$neovim_home/.local/share/nvim/lazy/lazy.nvim/.git/plasticine-release-snapshot" ]
}

plasticine_neovim_fnm_node_bin() {
    printf '%s\n' "$1" |
        grep -E '(^|[[:space:]])PATH=' |
        sed -e 's/^[^=]*=//' -e 's/[$]PATH//g' |
        tr -d '"' |
        tr -d "'" |
        tr ':' '\n' |
        while IFS= read -r plasticine_neovim_fnm_entry; do
            [ -n "$plasticine_neovim_fnm_entry" ] || continue
            if [ -x "$plasticine_neovim_fnm_entry/node" ] && [ -x "$plasticine_neovim_fnm_entry/npm" ]; then
                printf '%s\n' "$plasticine_neovim_fnm_entry"
                break
            fi
        done
}

plasticine_neovim_node_available() {
    if command -v node >/dev/null 2>&1 && command -v npm >/dev/null 2>&1; then
        return 0
    fi
    # fnm may own Node without it being on the current PATH. Resolve the
    # managed bin directory and front-load it before deciding, so an installed
    # but inactive Node is not mistaken for a missing one.
    command -v fnm >/dev/null 2>&1 || return 1
    plasticine_neovim_fnm_env=$(fnm env 2>/dev/null || true)
    [ -n "$plasticine_neovim_fnm_env" ] || return 1
    plasticine_neovim_fnm_bin=$(plasticine_neovim_fnm_node_bin "$plasticine_neovim_fnm_env")
    [ -n "$plasticine_neovim_fnm_bin" ] || return 1
    PATH=$plasticine_neovim_fnm_bin:$PATH
    export PATH
    command -v node >/dev/null 2>&1 && command -v npm >/dev/null 2>&1
}

plasticine_neovim_supply_tools() {
    plasticine_neovim_supply_home=$1
    plasticine_neovim_supply_bin=$2
    if plasticine_neovim_node_available; then
        printf '%s\n' 'plasticine-dotfiles: neovim: Node toolchain detected; installing LSP and formatter tools through mason.'
    else
        printf '%s\n' 'plasticine-dotfiles: neovim: warning: Node toolchain was not found; skipping Node-dependent LSP and formatter tools (typescript-language-server, vscode-langservers-extracted, prettier) for javascript/typescript and json. Markdown LSP (marksman) and shell formatting (shfmt) stay available. Install fnm and a Node version, then re-run --neovim to complete the tool set.' >&2
    fi
    HOME="$plasticine_neovim_supply_home" XDG_CONFIG_HOME="$plasticine_neovim_supply_home/.config" \
        XDG_DATA_HOME="$plasticine_neovim_supply_home/.local/share" \
        XDG_STATE_HOME="$plasticine_neovim_supply_home/.local/state" \
        XDG_CACHE_HOME="$plasticine_neovim_supply_home/.cache" GIT_TERMINAL_PROMPT=0 \
        "$plasticine_neovim_supply_bin" --headless '+MasonToolsInstallSync' '+qa' || {
        plasticine_neovim_error 'mason tool installation failed; fix the reported error and retry.'
        return 1
    }
}

plasticine_neovim_sync() {
    neovim_home=$1; neovim_target_command=$neovim_home/.local/bin/nvim
    if [ -L "$neovim_target_command" ] && [ "$(readlink "$neovim_target_command")" = ../opt/neovim/bin/nvim ] && [ -x "$neovim_target_command" ]; then
        plasticine_neovim_bin=$neovim_target_command
    else
        plasticine_neovim_observed_version || return 1
    fi
    if ! plasticine_neovim_uses_release_snapshot; then
        printf '%s\n' 'plasticine-dotfiles: neovim: updating plugins through lazy.nvim...'
        HOME="$neovim_home" XDG_CONFIG_HOME="$neovim_home/.config" XDG_DATA_HOME="$neovim_home/.local/share" XDG_STATE_HOME="$neovim_home/.local/state" XDG_CACHE_HOME="$neovim_home/.cache" GIT_TERMINAL_PROMPT=0 \
            "$plasticine_neovim_bin" --headless '+Lazy! sync' '+lua local p=require("lazy.core.plugin"); for _,x in pairs(require("lazy.core.config").plugins) do if p.has_errors(x) then vim.cmd("cquit") end end' '+qa' || { plasticine_neovim_error 'native plugin synchronization or startup failed after configuration application; configuration/backups, editor publication, and completed native effects remain. Fix the reported error and retry.'; return 1; }
    else
        printf '%s\n' 'plasticine-dotfiles: neovim: using the verified Release plugin snapshot; no Git update during installation.'
    fi
    plasticine_neovim_supply_tools "$neovim_home" "$plasticine_neovim_bin" || return 1
    if plasticine_neovim_uses_release_snapshot; then
        HOME="$neovim_home" XDG_CONFIG_HOME="$neovim_home/.config" XDG_DATA_HOME="$neovim_home/.local/share" XDG_STATE_HOME="$neovim_home/.local/state" XDG_CACHE_HOME="$neovim_home/.cache" \
            PLASTICINE_MANAGED_PLUGINS_ARCHIVE=release-snapshot \
            "$plasticine_neovim_bin" --headless '+lua local ok, err = pcall(function() assert(vim.fn.maparg("<C-n>", "n") ~= ""); assert(type(_FLOAT_TERM) == "function"); assert(vim.fn.exists(":NvimTreeToggle") == 2) end); if not ok then io.stderr:write(tostring(err) .. "\n"); vim.cmd("cquit") end' '+qa' || { plasticine_neovim_error 'runtime readiness check failed after plugin synchronization; retry after correcting the reported configuration/plugin error.'; return 1; }
    else
        HOME="$neovim_home" XDG_CONFIG_HOME="$neovim_home/.config" XDG_DATA_HOME="$neovim_home/.local/share" XDG_STATE_HOME="$neovim_home/.local/state" XDG_CACHE_HOME="$neovim_home/.cache" \
            "$plasticine_neovim_bin" --headless '+lua local ok, err = pcall(function() assert(vim.fn.maparg("<C-n>", "n") ~= ""); assert(type(_FLOAT_TERM) == "function"); assert(vim.fn.exists(":NvimTreeToggle") == 2) end); if not ok then io.stderr:write(tostring(err) .. "\n"); vim.cmd("cquit") end' '+qa' || { plasticine_neovim_error 'runtime readiness check failed after plugin synchronization; retry after correcting the reported configuration/plugin error.'; return 1; }
    fi
    printf '%s\n' 'plasticine-dotfiles: neovim: complete distribution, managed configuration, and current plugins passed runtime readiness.'
}
