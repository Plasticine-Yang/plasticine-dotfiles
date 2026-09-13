#!/bin/sh

plasticine_fnm_error() {
    printf 'plasticine-dotfiles: fnm: %s\n' "$1" >&2
}

plasticine_fnm_log() {
    printf 'plasticine-dotfiles: %s\n' "$1"
}

plasticine_fnm_resolve() {
    command -v "$1" 2>/dev/null && return 0
    plasticine_fnm_path=$PATH
    while :; do
        plasticine_fnm_dir=${plasticine_fnm_path%%:*}
        [ -n "$plasticine_fnm_dir" ] || plasticine_fnm_dir=.
        if [ -e "$plasticine_fnm_dir/$1" ] || [ -L "$plasticine_fnm_dir/$1" ]; then
            printf '%s\n' "$plasticine_fnm_dir/$1"
            return 0
        fi
        case $plasticine_fnm_path in *:*) plasticine_fnm_path=${plasticine_fnm_path#*:} ;; *) return 1 ;; esac
    done
}

plasticine_fnm_version() {
    [ -x "$1" ] || return 1
    "$1" --version 2>/dev/null | awk '{
        for (i=1; i<=NF; i++) {
            value=$i; sub(/^v/, "", value); sub(/[,;]$/, "", value)
            if (value ~ /^[0-9]+\.[0-9]+\.[0-9]+$/) { seen++; version=value }
        }
    } END { if (seen == 1) print version; else exit 1 }'
}

plasticine_fnm_compare() {
    awk -v left="$1" -v right="$2" 'BEGIN {
        split(left,a,"."); split(right,b,".")
        for (i=1;i<=3;i++) { if (a[i]+0<b[i]+0) {print -1;exit}; if (a[i]+0>b[i]+0) {print 1;exit} }
        print 0
    }'
}

plasticine_fnm_hash() {
    cksum "$1" | awk 'NF >= 2 {print $1 ":" $2}'
}

plasticine_fnm_validate_destination() {
    for plasticine_fnm_parent in "$fnm_home" "$fnm_home/.local" "$fnm_install_dir"; do
        if [ -e "$plasticine_fnm_parent" ] || [ -L "$plasticine_fnm_parent" ]; then
            [ -d "$plasticine_fnm_parent" ] && [ ! -L "$plasticine_fnm_parent" ] || {
                plasticine_fnm_error "installation parent is not a real directory: $plasticine_fnm_parent"; return 1; }
        fi
    done
    if [ -e "$fnm_target" ] || [ -L "$fnm_target" ]; then
        [ -f "$fnm_target" ] && [ ! -L "$fnm_target" ] || {
            plasticine_fnm_error "installation target is not a regular file: $fnm_target; left untouched."; return 1; }
    fi
}

plasticine_fnm_conventional_brew() {
    case $fnm_arch in arm64|aarch64) printf '%s\n' "${PLASTICINE_FNM_HOMEBREW_ARM:-/opt/homebrew/bin/brew}" ;;
        *) printf '%s\n' "${PLASTICINE_FNM_HOMEBREW_INTEL:-/usr/local/bin/brew}" ;; esac
}

plasticine_fnm_terminal() {
    case ${PLASTICINE_FNM_TTY:-} in 1) return 0 ;; 0) return 1 ;;
        '') (test -r /dev/tty && test -w /dev/tty && : </dev/tty) 2>/dev/null ;; *) return 1 ;; esac
}

plasticine_fnm_plan() {
    fnm_home=$1
    case $fnm_home in /*) ;; *) plasticine_fnm_error 'destination must be absolute.'; return 1 ;; esac
    fnm_install_dir=$fnm_home/.local/bin
    fnm_target=$fnm_install_dir/fnm
    plasticine_fnm_validate_destination || return 1
    fnm_os=${PLASTICINE_FNM_OS:-$(uname -s)}
    fnm_arch=${PLASTICINE_FNM_ARCH:-$(uname -m)}
    case $fnm_os:$fnm_arch in Darwin:arm64|Darwin:aarch64|Darwin:x86_64|Linux:arm64|Linux:aarch64|Linux:x86_64|Linux:amd64) ;;
        *) plasticine_fnm_error "no reviewed route for $fnm_os/$fnm_arch."; return 1 ;; esac
    fnm_bin=$(plasticine_fnm_resolve fnm) || fnm_bin=''
    fnm_owner=missing
    fnm_observed=missing
    fnm_observed_hash=''
    if [ -n "$fnm_bin" ]; then
        case $fnm_bin in /*) ;; *) fnm_bin=$(cd -- "$(dirname -- "$fnm_bin")" && pwd -P)/${fnm_bin##*/} ;; esac
        fnm_observed=$(plasticine_fnm_version "$fnm_bin") || {
            plasticine_fnm_error "existing executable is unhealthy or has an unverifiable/prerelease/custom version: $fnm_bin; repair its owner. Left untouched."; return 1; }
        [ "$fnm_bin" = "$fnm_target" ] && fnm_owner=direct || fnm_owner=external
    elif [ -e "$fnm_target" ] || [ -L "$fnm_target" ]; then
        fnm_bin=$fnm_target; fnm_owner=direct
        fnm_observed=$(plasticine_fnm_version "$fnm_bin") || {
            plasticine_fnm_error "direct executable is unhealthy or has an unverifiable/prerelease/custom version: $fnm_bin; repair it. Left untouched."; return 1; }
    fi
    if [ "$fnm_owner" = direct ]; then fnm_observed_hash=$(plasticine_fnm_hash "$fnm_target") || return 1; fi
    fnm_brew=''
    fnm_brew_route=none
    if [ "$fnm_os" = Darwin ]; then
        fnm_brew=$(plasticine_fnm_resolve brew) || fnm_brew=''
        if [ -z "$fnm_brew" ]; then fnm_brew=$(plasticine_fnm_conventional_brew); [ -x "$fnm_brew" ] || fnm_brew=''; fi
        if [ -n "$fnm_brew" ]; then
            case $fnm_brew in /*) ;; *) plasticine_fnm_error 'Homebrew path must be absolute.'; return 1 ;; esac
            HOMEBREW_NO_ANALYTICS=1 "$fnm_brew" --version >/dev/null 2>&1 || { plasticine_fnm_error 'Homebrew is unhealthy; repair it. Left untouched.'; return 1; }
            fnm_brew_route=existing
        else
            fnm_brew_route=bootstrap
            if ! command -v curl >/dev/null 2>&1 || ! command -v bash >/dev/null 2>&1; then
                plasticine_fnm_error 'Homebrew bootstrap requires curl and bash.'; return 1
            fi
        fi
    else
        for plasticine_fnm_cmd in curl bash awk mktemp mkdir chmod cp ln mv cksum; do
            command -v "$plasticine_fnm_cmd" >/dev/null 2>&1 || { plasticine_fnm_error "missing official-script route command: $plasticine_fnm_cmd"; return 1; }
        done
    fi
}

plasticine_fnm_preview() {
    printf 'plasticine-dotfiles: fnm: platform %s/%s; observed=%s; owner=%s.\n' "$fnm_os" "$fnm_arch" "$fnm_observed" "$fnm_owner"
    if [ "$fnm_os" = Darwin ]; then
        [ "$fnm_brew_route" != bootstrap ] || printf '%s\n' \
            '  Homebrew missing: official bootstrap; HTTPS network; native terminal and possibly administrator credentials/Apple Command Line Tools.' \
            '  command: curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh; bash -c <downloaded installer>; never sudo bash.'
        printf '%s\n' \
            '  After confirmation: refresh Homebrew metadata, resolve the latest available fnm formula, and install/upgrade only fnm when needed.' \
            '  commands: HOMEBREW_NO_ANALYTICS=1 brew update; brew info --json=v2 fnm; brew install fnm or brew upgrade fnm.' \
            '  Homebrew may request native credentials; --yes never supplies them. Formula currency can lag upstream.'
    else
        printf '%s\n' \
            '  After confirmation: download https://fnm.vercel.app/install completely, then run bash <script> --skip-shell --install-dir <candidate>.' \
            "  Candidate is health-checked before atomic publication at $fnm_target; no --release selector or package-manager fallback." \
            '  The official script and its downloads share the upstream trust boundary; Plasticine adds no independent signature verification.'
    fi
    printf '%s\n' '  Node versions, defaults, project declarations, FNM_DIR, and native fnm runtime data are not inspected or changed.'
    [ "$fnm_os" != Linux ] || [ "$fnm_owner" != external ] || printf '%s\n' '  An external owner is accepted only if its version equals the resolved target; outdated external installations are left untouched with guidance.'
    printf '%s\n' "  Standalone selection does not edit shell startup; ensure $fnm_install_dir is on PATH and add native 'fnm env --shell zsh' activation if desired."
}

plasticine_fnm_brew_bootstrap() {
    plasticine_fnm_terminal || { plasticine_fnm_error 'Homebrew bootstrap needs a native terminal; install Homebrew interactively, then retry. --yes cannot supply credentials.'; return 1; }
    fnm_brew_installer=$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh) || { plasticine_fnm_error 'official Homebrew installer download failed; fnm was not changed.'; return 1; }
    ( unset NONINTERACTIVE CI; export HOMEBREW_NO_ANALYTICS=1; case ${PLASTICINE_FNM_TTY:-} in 1) bash -c "$fnm_brew_installer" ;; *) bash -c "$fnm_brew_installer" </dev/tty ;; esac ) || { plasticine_fnm_error 'official Homebrew installer failed; fnm was not changed.'; return 1; }
    fnm_brew=$(plasticine_fnm_resolve brew) || fnm_brew=$(plasticine_fnm_conventional_brew)
    if [ ! -x "$fnm_brew" ] || ! HOMEBREW_NO_ANALYTICS=1 "$fnm_brew" --version >/dev/null 2>&1; then
        plasticine_fnm_error 'Homebrew bootstrap did not produce usable brew.'; return 1
    fi
}

plasticine_fnm_brew_stable() {
    awk 'BEGIN { RS="[,{}]\n?" } /"stable"[[:space:]]*:/ { v=$0; sub(/^.*"stable"[[:space:]]*:[[:space:]]*"/,"",v); sub(/".*$/,"",v); if (v ~ /^[0-9]+\.[0-9]+\.[0-9]+$/) {n++; value=v} } END {if(n==1) print value; else exit 1}' "$1"
}

plasticine_fnm_prepare_macos() {
    [ "$fnm_brew_route" != bootstrap ] || plasticine_fnm_brew_bootstrap || return 1
    HOMEBREW_NO_ANALYTICS=1 "$fnm_brew" update || { plasticine_fnm_error 'Homebrew metadata refresh failed; an older fnm is not accepted as current.'; return 1; }
    fnm_info=$(mktemp "${TMPDIR:-/tmp}/plasticine-fnm-info.XXXXXX") || return 1
    HOMEBREW_NO_ANALYTICS=1 "$fnm_brew" info --json=v2 fnm >"$fnm_info" || { rm -f "$fnm_info"; plasticine_fnm_error 'Homebrew fnm formula lookup failed.'; return 1; }
    fnm_latest=$(plasticine_fnm_brew_stable "$fnm_info") || { rm -f "$fnm_info"; plasticine_fnm_error 'Homebrew returned no unambiguous stable fnm formula version.'; return 1; }
    rm -f "$fnm_info"
    fnm_brew_prefix=$(HOMEBREW_NO_ANALYTICS=1 "$fnm_brew" --prefix fnm 2>/dev/null || true)
    case $fnm_brew_prefix in /*) ;; *) fnm_brew_prefix='' ;; esac
    fnm_brew_bin=${fnm_brew_prefix:+$fnm_brew_prefix/bin/fnm}
    fnm_brew_observed=missing
    if [ -n "$fnm_brew_bin" ] && [ -x "$fnm_brew_bin" ]; then fnm_brew_observed=$(plasticine_fnm_version "$fnm_brew_bin") || { plasticine_fnm_error 'Homebrew-owned fnm is unhealthy; repair Homebrew.'; return 1; }; fi
    if [ "$fnm_brew_observed" = missing ]; then
        if [ "$fnm_owner" = external ] || [ "$fnm_owner" = direct ]; then
            [ "$(plasticine_fnm_compare "$fnm_observed" "$fnm_latest")" = 0 ] && { plasticine_fnm_log "fnm: external current version $fnm_observed equals Homebrew formula target $fnm_latest; left untouched."; return 0; }
            plasticine_fnm_error "$fnm_bin is not Homebrew-owned and does not match formula target $fnm_latest; update/remove it through its owner. No shadow copy installed."; return 1
        fi
        HOMEBREW_NO_ANALYTICS=1 "$fnm_brew" install fnm || { plasticine_fnm_error 'Homebrew fnm install failed; retry through Homebrew.'; return 1; }
        fnm_action=install
    else
        case $(plasticine_fnm_compare "$fnm_brew_observed" "$fnm_latest") in
            0) fnm_action=reuse ;; -1) HOMEBREW_NO_ANALYTICS=1 "$fnm_brew" upgrade fnm || { plasticine_fnm_error 'Homebrew fnm upgrade failed; retry through Homebrew.'; return 1; }; fnm_action=update ;;
            *) plasticine_fnm_error "Homebrew fnm $fnm_brew_observed is newer than formula target $fnm_latest; refusing downgrade/channel takeover."; return 1 ;; esac
    fi
    fnm_brew_prefix=$(HOMEBREW_NO_ANALYTICS=1 "$fnm_brew" --prefix fnm) || return 1
    fnm_brew_bin=$fnm_brew_prefix/bin/fnm
    [ "$(plasticine_fnm_version "$fnm_brew_bin" || true)" = "$fnm_latest" ] || { plasticine_fnm_error "Homebrew $fnm_action did not produce target $fnm_latest; native effects retained, retry after repairing Homebrew."; return 1; }
    fnm_effective=$(plasticine_fnm_resolve fnm) || fnm_effective=$fnm_brew_bin
    [ "$(plasticine_fnm_version "$fnm_effective" || true)" = "$fnm_latest" ] || {
        plasticine_fnm_error "Homebrew reached $fnm_latest, but PATH still selects a different fnm at $fnm_effective; repair the shadowing owner."
        return 1
    }
    plasticine_fnm_log "fnm: source=Homebrew latest available formula; target=$fnm_latest; action=$fnm_action; result=$fnm_brew_bin."
}

plasticine_fnm_prepare_linux() {
    fnm_work=$(mktemp -d "${TMPDIR:-/tmp}/plasticine-fnm.XXXXXX") || return 1
    fnm_script=$fnm_work/install.sh; fnm_candidate_dir=$fnm_work/candidate
    curl -fsSL -o "$fnm_script" https://fnm.vercel.app/install || { rm -rf "$fnm_work"; plasticine_fnm_error 'official installer download failed; existing fnm preserved.'; return 1; }
    mkdir "$fnm_candidate_dir" || { rm -rf "$fnm_work"; return 1; }
    bash "$fnm_script" --skip-shell --install-dir "$fnm_candidate_dir" || { rm -rf "$fnm_work"; plasticine_fnm_error 'official installer failed in candidate directory; existing fnm preserved.'; return 1; }
    fnm_candidate=$fnm_candidate_dir/fnm
    fnm_latest=$(plasticine_fnm_version "$fnm_candidate") || { rm -rf "$fnm_work"; plasticine_fnm_error 'official installer candidate is unhealthy or not stable; existing fnm preserved.'; return 1; }
    if [ "$fnm_observed" != missing ]; then
        case $(plasticine_fnm_compare "$fnm_observed" "$fnm_latest") in
            0) rm -rf "$fnm_work"; plasticine_fnm_log "fnm: source=official Linux installer; target=$fnm_latest; action=reuse; current executable left untouched."; return 0 ;;
            1) rm -rf "$fnm_work"; plasticine_fnm_error "installed $fnm_observed is newer than official stable $fnm_latest; refusing downgrade/channel takeover."; return 1 ;;
            -1) [ "$fnm_owner" = direct ] || { rm -rf "$fnm_work"; plasticine_fnm_error "outdated $fnm_bin is owned by an unsupported route; update it there to $fnm_latest. No shadow copy installed."; return 1; }; fnm_action=update ;; esac
    else fnm_action=install; fi
    plasticine_fnm_validate_destination || { rm -rf "$fnm_work"; return 1; }
    umask 077
    [ -e "$fnm_home/.local" ] || mkdir "$fnm_home/.local" || { rm -rf "$fnm_work"; return 1; }
    [ -e "$fnm_install_dir" ] || mkdir "$fnm_install_dir" || { rm -rf "$fnm_work"; return 1; }
    fnm_stage=$(mktemp "$fnm_install_dir/.fnm.plasticine.XXXXXX") || { rm -rf "$fnm_work"; return 1; }
    if ! cp "$fnm_candidate" "$fnm_stage" || ! chmod 755 "$fnm_stage"; then
        rm -f "$fnm_stage"; rm -rf "$fnm_work"; return 1
    fi
    if [ "$fnm_action" = install ]; then
        [ ! -e "$fnm_target" ] && [ ! -L "$fnm_target" ] || { rm -f "$fnm_stage"; rm -rf "$fnm_work"; plasticine_fnm_error 'target appeared during preparation; left untouched.'; return 1; }
        ln "$fnm_stage" "$fnm_target" || { rm -f "$fnm_stage"; rm -rf "$fnm_work"; plasticine_fnm_error 'atomic no-clobber publication failed.'; return 1; }; rm -f "$fnm_stage"
    else
        [ "$(plasticine_fnm_hash "$fnm_target" 2>/dev/null || true)" = "$fnm_observed_hash" ] || { rm -f "$fnm_stage"; rm -rf "$fnm_work"; plasticine_fnm_error 'target changed during preparation; update aborted.'; return 1; }
        mv -f "$fnm_stage" "$fnm_target" || { rm -f "$fnm_stage"; rm -rf "$fnm_work"; plasticine_fnm_error 'atomic replacement failed; existing destination state retained.'; return 1; }
    fi
    rm -rf "$fnm_work"
    [ "$(plasticine_fnm_version "$fnm_target" || true)" = "$fnm_latest" ] || { plasticine_fnm_error "published fnm failed final health check at $fnm_target; repair it and retry."; return 1; }
    plasticine_fnm_log "fnm: source=official Linux installer; target=$fnm_latest; action=$fnm_action; result=$fnm_target."
}

plasticine_fnm_prepare() {
    case $fnm_os in Darwin) plasticine_fnm_prepare_macos ;; Linux) plasticine_fnm_prepare_linux ;; *) return 1 ;; esac
}
