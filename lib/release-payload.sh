#!/bin/sh

# Verified Release assets are the only network seam used by a released
# installer for Plasticine source and managed plugin snapshots.

plasticine_release_error() {
    printf 'plasticine-dotfiles: release payload: %s\n' "$1" >&2
}

plasticine_release_sha256() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk 'NF == 2 {print tolower($1)}'
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$1" | awk 'NF == 2 {print tolower($1)}'
    else
        plasticine_release_error 'missing SHA-256 command (sha256sum or shasum).'
        return 1
    fi
}

plasticine_release_download() {
    plasticine_release_url=$1
    plasticine_release_expected=$2
    plasticine_release_destination=$3
    plasticine_release_parent=${plasticine_release_destination%/*}
    [ "$plasticine_release_parent" != "$plasticine_release_destination" ] || plasticine_release_parent=.
    mkdir -p "$plasticine_release_parent" || return 1
    [ -d "$plasticine_release_parent" ] && [ ! -L "$plasticine_release_parent" ] || {
        plasticine_release_error "asset parent is not a real directory: $plasticine_release_parent"
        return 1
    }
    plasticine_release_stage=$(mktemp "$plasticine_release_parent/.plasticine-release.XXXXXX") || return 1
    if ! curl --proto '=https' --proto-redir '=https' -fsSL \
        -o "$plasticine_release_stage" "$plasticine_release_url"; then
        rm -f "$plasticine_release_stage"
        plasticine_release_error "download failed: $plasticine_release_url"
        return 1
    fi
    plasticine_release_actual=$(plasticine_release_sha256 "$plasticine_release_stage") || {
        rm -f "$plasticine_release_stage"; return 1;
    }
    if [ "$plasticine_release_actual" != "$plasticine_release_expected" ]; then
        rm -f "$plasticine_release_stage"
        plasticine_release_error "SHA-256 mismatch: ${plasticine_release_url##*/}"
        return 1
    fi
    if ! mv -f "$plasticine_release_stage" "$plasticine_release_destination"; then
        rm -f "$plasticine_release_stage"
        plasticine_release_error "could not publish downloaded asset: $plasticine_release_destination"
        return 1
    fi
}

plasticine_release_asset() {
    plasticine_release_asset_home=$1
    plasticine_release_asset_base=$2
    plasticine_release_asset_version=$3
    plasticine_release_asset_name=$4
    plasticine_release_asset_digest=$5
    plasticine_release_asset_dir=$plasticine_release_asset_home/.cache/plasticine/releases/$plasticine_release_asset_version
    plasticine_release_asset_path=$plasticine_release_asset_dir/$plasticine_release_asset_name
    mkdir -p "$plasticine_release_asset_dir" || return 1
    [ -d "$plasticine_release_asset_dir" ] && [ ! -L "$plasticine_release_asset_dir" ] || {
        plasticine_release_error "asset directory is not a real directory: $plasticine_release_asset_dir"
        return 1
    }
    if [ -f "$plasticine_release_asset_path" ] && [ ! -L "$plasticine_release_asset_path" ] &&
        [ "$(plasticine_release_sha256 "$plasticine_release_asset_path" || true)" = "$plasticine_release_asset_digest" ]; then
        return 0
    fi
    [ ! -e "$plasticine_release_asset_path" ] && [ ! -L "$plasticine_release_asset_path" ] ||
        rm -f "$plasticine_release_asset_path"
    if [ -n "${PLASTICINE_RELEASE_ASSET_DIR:-}" ]; then
        case $PLASTICINE_RELEASE_ASSET_DIR in /*) ;;
            *) plasticine_release_error 'PLASTICINE_RELEASE_ASSET_DIR must be absolute.'; return 1 ;; esac
        plasticine_release_local_asset=$PLASTICINE_RELEASE_ASSET_DIR/$plasticine_release_asset_name
        [ -f "$plasticine_release_local_asset" ] && [ ! -L "$plasticine_release_local_asset" ] || {
            plasticine_release_error "local Release asset is unavailable: $plasticine_release_local_asset"
            return 1
        }
        plasticine_release_actual=$(plasticine_release_sha256 "$plasticine_release_local_asset") || return 1
        [ "$plasticine_release_actual" = "$plasticine_release_asset_digest" ] || {
            plasticine_release_error "SHA-256 mismatch: $plasticine_release_asset_name"
            return 1
        }
        plasticine_release_local_stage=$(mktemp "$plasticine_release_asset_dir/.plasticine-release.XXXXXX") || return 1
        if ! cp "$plasticine_release_local_asset" "$plasticine_release_local_stage" ||
            ! mv -f "$plasticine_release_local_stage" "$plasticine_release_asset_path"; then
            rm -f "$plasticine_release_local_stage"
            plasticine_release_error "could not publish local Release asset: $plasticine_release_asset_name"
            return 1
        fi
        return 0
    fi
    plasticine_release_download "$plasticine_release_asset_base/$plasticine_release_asset_name" \
        "$plasticine_release_asset_digest" "$plasticine_release_asset_path"
}

plasticine_release_acquire_source() {
    plasticine_release_home=$1
    plasticine_release_base=$2
    plasticine_release_version=$3
    plasticine_release_source_digest=$4
    plasticine_release_revision=$5
    plasticine_release_origin=$6
    plasticine_release_source_dir=$7

    plasticine_release_asset "$plasticine_release_home" "$plasticine_release_base" \
        "$plasticine_release_version" plasticine-source.bundle "$plasticine_release_source_digest" || return 1
    plasticine_release_source_bundle=$plasticine_release_asset_path
    git bundle verify "$plasticine_release_source_bundle" >/dev/null 2>&1 || {
        plasticine_release_error 'source Git bundle verification failed.'
        return 1
    }

    if [ -e "$plasticine_release_source_dir" ] || [ -L "$plasticine_release_source_dir" ]; then
        [ -d "$plasticine_release_source_dir/.git" ] && [ ! -L "$plasticine_release_source_dir" ] || {
            plasticine_release_error "existing chezmoi source is not a Git checkout: $plasticine_release_source_dir"
            return 1
        }
        plasticine_release_existing_origin=$(git -C "$plasticine_release_source_dir" remote get-url origin 2>/dev/null || true)
        [ "$plasticine_release_existing_origin" = "$plasticine_release_origin" ] || {
            plasticine_release_error "existing chezmoi source belongs to another repository: $plasticine_release_existing_origin"
            return 1
        }
        [ -z "$(git -C "$plasticine_release_source_dir" status --porcelain)" ] || {
            plasticine_release_error "existing chezmoi source has local changes: $plasticine_release_source_dir"
            return 1
        }
        GIT_TERMINAL_PROMPT=0 git -C "$plasticine_release_source_dir" fetch --no-tags \
            "$plasticine_release_source_bundle" HEAD || return 1
        [ "$(git -C "$plasticine_release_source_dir" rev-parse FETCH_HEAD)" = "$plasticine_release_revision" ] || {
            plasticine_release_error 'source bundle does not contain the released revision.'
            return 1
        }
        git -C "$plasticine_release_source_dir" checkout --detach "$plasticine_release_revision"
        return
    fi

    plasticine_release_source_parent=${plasticine_release_source_dir%/*}
    mkdir -p "$plasticine_release_source_parent" || return 1
    [ -d "$plasticine_release_source_parent" ] && [ ! -L "$plasticine_release_source_parent" ] || {
        plasticine_release_error "source parent is not a real directory: $plasticine_release_source_parent"
        return 1
    }
    plasticine_release_source_stage=$(mktemp -d "$plasticine_release_source_parent/.plasticine-source.XXXXXX") || return 1
    if ! GIT_TERMINAL_PROMPT=0 git clone -q --no-checkout "$plasticine_release_source_bundle" "$plasticine_release_source_stage"; then
        rm -rf "$plasticine_release_source_stage"
        plasticine_release_error 'could not restore the released source bundle.'
        return 1
    fi
    if ! git -C "$plasticine_release_source_stage" cat-file -e "$plasticine_release_revision^{commit}" 2>/dev/null ||
        ! git -C "$plasticine_release_source_stage" checkout -q --detach "$plasticine_release_revision" ||
        [ "$(git -C "$plasticine_release_source_stage" rev-parse HEAD)" != "$plasticine_release_revision" ]; then
        rm -rf "$plasticine_release_source_stage"
        plasticine_release_error 'restored source does not match the released revision.'
        return 1
    fi
    git -C "$plasticine_release_source_stage" remote set-url origin "$plasticine_release_origin" || {
        rm -rf "$plasticine_release_source_stage"; return 1;
    }
    if ! mv "$plasticine_release_source_stage" "$plasticine_release_source_dir"; then
        rm -rf "$plasticine_release_source_stage"
        plasticine_release_error 'could not publish the released source checkout.'
        return 1
    fi
}

plasticine_release_acquire_plugins() {
    plasticine_release_plugins_home=$1
    plasticine_release_plugins_base=$2
    plasticine_release_plugins_version=$3
    plasticine_release_plugins_digest=$4
    plasticine_release_asset "$plasticine_release_plugins_home" "$plasticine_release_plugins_base" \
        "$plasticine_release_plugins_version" plasticine-managed-plugins.tar.gz \
        "$plasticine_release_plugins_digest" || return 1
    # Public result consumed by the installer after the acquisition call.
    # shellcheck disable=SC2034
    plasticine_release_plugins_path=$plasticine_release_asset_path
}
