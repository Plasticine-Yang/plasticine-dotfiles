#!/bin/sh

plasticine_managed_plugins_error() {
    printf 'plasticine-dotfiles: managed plugins: %s\n' "$1" >&2
}

plasticine_managed_plugins_scope_selected() {
    case $1:$2:$(uname -s) in
        neovim:neovim:*) return 0 ;;
        shell:shell:*) return 0 ;;
        shell:shell-linux:Linux) return 0 ;;
        *) return 1 ;;
    esac
}

plasticine_managed_plugins_validate_checkout() {
    plasticine_managed_plugins_checkout=$1
    plasticine_managed_plugins_origin=$2
    plasticine_managed_plugins_revision=$3
    [ -d "$plasticine_managed_plugins_checkout/.git" ] && [ ! -L "$plasticine_managed_plugins_checkout" ] || return 1
    [ "$(git -C "$plasticine_managed_plugins_checkout" remote get-url origin 2>/dev/null || true)" = "$plasticine_managed_plugins_origin" ] || return 1
    [ "$(git -C "$plasticine_managed_plugins_checkout" rev-parse HEAD 2>/dev/null || true)" = "$plasticine_managed_plugins_revision" ] || return 1
    [ -z "$(git -C "$plasticine_managed_plugins_checkout" status --porcelain --untracked-files=normal 2>/dev/null)" ]
}

plasticine_managed_plugins_validate_path() {
    case $1 in
        .antidote) return 0 ;;
        .local/share/nvim/lazy/*)
            plasticine_managed_plugins_leaf=${1#.local/share/nvim/lazy/}
            ;;
        .cache/antidote/github.com/*)
            plasticine_managed_plugins_leaf=${1#.cache/antidote/github.com/}
            case $plasticine_managed_plugins_leaf in */*) ;; *) return 1 ;; esac
            plasticine_managed_plugins_owner=${plasticine_managed_plugins_leaf%%/*}
            plasticine_managed_plugins_leaf=${plasticine_managed_plugins_leaf#*/}
            case $plasticine_managed_plugins_owner in ''|.|..) return 1 ;; esac
            ;;
        *) return 1 ;;
    esac
    case $plasticine_managed_plugins_leaf in ''|.|..|*/*) return 1 ;; *) return 0 ;; esac
}

plasticine_managed_plugins_snapshot_owned() {
    plasticine_managed_plugins_owned_checkout=$1
    plasticine_managed_plugins_owned_origin=$2
    plasticine_managed_plugins_owned_marker=$plasticine_managed_plugins_owned_checkout/.git/plasticine-release-snapshot
    [ -d "$plasticine_managed_plugins_owned_checkout/.git" ] &&
        [ ! -L "$plasticine_managed_plugins_owned_checkout" ] &&
        [ -f "$plasticine_managed_plugins_owned_marker" ] &&
        [ ! -L "$plasticine_managed_plugins_owned_marker" ] || return 1
    plasticine_managed_plugins_owned_revision=$(sed -n '1p' "$plasticine_managed_plugins_owned_marker")
    case $plasticine_managed_plugins_owned_revision in *[!0-9a-f]*|'') return 1 ;; esac
    [ "${#plasticine_managed_plugins_owned_revision}" -eq 40 ] &&
        [ "$(git -C "$plasticine_managed_plugins_owned_checkout" remote get-url origin 2>/dev/null || true)" = "$plasticine_managed_plugins_owned_origin" ] &&
        [ "$(git -C "$plasticine_managed_plugins_owned_checkout" rev-parse HEAD 2>/dev/null || true)" = "$plasticine_managed_plugins_owned_revision" ] &&
        [ -z "$(git -C "$plasticine_managed_plugins_owned_checkout" status --porcelain --untracked-files=normal 2>/dev/null)" ]
}

plasticine_managed_plugins_restore() {
    plasticine_managed_plugins_archive=$1
    plasticine_managed_plugins_home=$2
    plasticine_managed_plugins_feature=$3
    [ -f "$plasticine_managed_plugins_archive" ] && [ ! -L "$plasticine_managed_plugins_archive" ] || {
        plasticine_managed_plugins_error 'verified snapshot archive is unavailable.'
        return 1
    }
    plasticine_managed_plugins_work=$(mktemp -d "${TMPDIR:-/tmp}/plasticine-managed-plugins.XXXXXX") || return 1
    if ! tar -tzf "$plasticine_managed_plugins_archive" > "$plasticine_managed_plugins_work/members" 2>/dev/null; then
        rm -rf "$plasticine_managed_plugins_work"
        plasticine_managed_plugins_error 'snapshot archive listing failed.'
        return 1
    fi
    if ! awk 'NF == 0 || $0 !~ /^managed-plugins\// || $0 ~ /(^|\/)\.\.(\/|$)/ || $0 ~ /^\// { bad=1 } END { exit bad }' \
        "$plasticine_managed_plugins_work/members"; then
        rm -rf "$plasticine_managed_plugins_work"
        plasticine_managed_plugins_error 'snapshot archive contains an unsafe member path.'
        return 1
    fi
    if ! tar -xzf "$plasticine_managed_plugins_archive" -C "$plasticine_managed_plugins_work"; then
        rm -rf "$plasticine_managed_plugins_work"
        plasticine_managed_plugins_error 'snapshot archive extraction failed.'
        return 1
    fi
    plasticine_managed_plugins_root=$plasticine_managed_plugins_work/managed-plugins
    plasticine_managed_plugins_manifest=$plasticine_managed_plugins_root/manifest.tsv
    [ -f "$plasticine_managed_plugins_manifest" ] || {
        rm -rf "$plasticine_managed_plugins_work"
        plasticine_managed_plugins_error 'snapshot manifest is missing.'
        return 1
    }

    plasticine_managed_plugins_selected=0
    while IFS='	' read -r plasticine_managed_plugins_scope plasticine_managed_plugins_path \
        plasticine_managed_plugins_origin plasticine_managed_plugins_revision plasticine_managed_plugins_extra ||
        [ -n "$plasticine_managed_plugins_scope$plasticine_managed_plugins_path$plasticine_managed_plugins_origin$plasticine_managed_plugins_revision" ]; do
        [ -z "$plasticine_managed_plugins_extra" ] || { rm -rf "$plasticine_managed_plugins_work"; plasticine_managed_plugins_error 'snapshot manifest has extra fields.'; return 1; }
        plasticine_managed_plugins_validate_path "$plasticine_managed_plugins_path" || {
            rm -rf "$plasticine_managed_plugins_work"
            plasticine_managed_plugins_error "invalid snapshot path: $plasticine_managed_plugins_path"
            return 1
        }
        case $plasticine_managed_plugins_revision in
            *[!0-9a-f]*|'') rm -rf "$plasticine_managed_plugins_work"; plasticine_managed_plugins_error 'invalid snapshot revision.'; return 1 ;;
        esac
        [ "${#plasticine_managed_plugins_revision}" -eq 40 ] || { rm -rf "$plasticine_managed_plugins_work"; plasticine_managed_plugins_error 'snapshot revision is not a full commit ID.'; return 1; }
        plasticine_managed_plugins_source=$plasticine_managed_plugins_root/$plasticine_managed_plugins_path
        plasticine_managed_plugins_validate_checkout "$plasticine_managed_plugins_source" \
            "$plasticine_managed_plugins_origin" "$plasticine_managed_plugins_revision" || {
            rm -rf "$plasticine_managed_plugins_work"
            plasticine_managed_plugins_error "snapshot checkout validation failed: $plasticine_managed_plugins_path"
            return 1
        }
        plasticine_managed_plugins_scope_selected "$plasticine_managed_plugins_feature" "$plasticine_managed_plugins_scope" || continue
        plasticine_managed_plugins_selected=$((plasticine_managed_plugins_selected + 1))
        plasticine_managed_plugins_destination=$plasticine_managed_plugins_home/$plasticine_managed_plugins_path
        plasticine_managed_plugins_parent=${plasticine_managed_plugins_destination%/*}
        mkdir -p "$plasticine_managed_plugins_parent" || { rm -rf "$plasticine_managed_plugins_work"; return 1; }
        if [ -e "$plasticine_managed_plugins_destination" ] || [ -L "$plasticine_managed_plugins_destination" ]; then
            if plasticine_managed_plugins_validate_checkout "$plasticine_managed_plugins_destination" \
                "$plasticine_managed_plugins_origin" "$plasticine_managed_plugins_revision"; then
                continue
            fi
            if ! plasticine_managed_plugins_snapshot_owned "$plasticine_managed_plugins_destination" \
                "$plasticine_managed_plugins_origin"; then
                if [ -d "$plasticine_managed_plugins_destination/.git" ] &&
                    [ "$(git -C "$plasticine_managed_plugins_destination" remote get-url origin 2>/dev/null || true)" = "$plasticine_managed_plugins_origin" ]; then
                    # Native plugin managers own pre-existing or modified
                    # checkouts. A Release only advances an unchanged prior
                    # snapshot; it never takes over Owner state.
                    continue
                fi
                rm -rf "$plasticine_managed_plugins_work"
                plasticine_managed_plugins_error "existing checkout is not an owned Release snapshot and was left untouched: $plasticine_managed_plugins_destination"
                return 1
            fi
            plasticine_managed_plugins_old=$plasticine_managed_plugins_destination.plasticine-old-$$
            mv "$plasticine_managed_plugins_destination" "$plasticine_managed_plugins_old" || { rm -rf "$plasticine_managed_plugins_work"; return 1; }
            if ! mv "$plasticine_managed_plugins_source" "$plasticine_managed_plugins_destination"; then
                mv "$plasticine_managed_plugins_old" "$plasticine_managed_plugins_destination" 2>/dev/null || true
                rm -rf "$plasticine_managed_plugins_work"
                return 1
            fi
            rm -rf "$plasticine_managed_plugins_old"
        else
            mv "$plasticine_managed_plugins_source" "$plasticine_managed_plugins_destination" || { rm -rf "$plasticine_managed_plugins_work"; return 1; }
        fi
        printf '%s\n' "$plasticine_managed_plugins_revision" > "$plasticine_managed_plugins_destination/.git/plasticine-release-snapshot"
    done < "$plasticine_managed_plugins_manifest"
    rm -rf "$plasticine_managed_plugins_work"
    [ "$plasticine_managed_plugins_selected" -gt 0 ] || {
        plasticine_managed_plugins_error "snapshot contains no entries for $plasticine_managed_plugins_feature."
        return 1
    }
}
