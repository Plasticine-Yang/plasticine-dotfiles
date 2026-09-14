#!/bin/sh
set -eu

repo_dir=$(cd -- "$(dirname -- "$0")/.." && pwd)
manifest=${1:-$repo_dir/release/managed-plugins.tsv}
output=${2:-}
[ -f "$manifest" ] && [ -n "$output" ] || {
    printf '%s\n' 'usage: scripts/build-managed-plugins.sh [manifest] <output.tar.gz>' >&2
    exit 2
}
[ ! -e "$output" ] || { printf 'output already exists: %s\n' "$output" >&2; exit 1; }

work_dir=$(mktemp -d "${TMPDIR:-/tmp}/plasticine-managed-plugins-build.XXXXXX")
trap 'rm -rf "$work_dir"' EXIT HUP INT TERM
payload=$work_dir/managed-plugins
mkdir -p "$payload"
: > "$payload/manifest.tsv"

while IFS='	' read -r scope plugin_path url revision probe extra ||
    [ -n "$scope$plugin_path$url$revision$probe" ]; do
    [ -n "$scope" ] && [ -n "$plugin_path" ] && [ -n "$url" ] && [ -n "$revision" ] &&
        [ -n "$probe" ] && [ -z "$extra" ] || {
        printf 'invalid managed plugin manifest row: %s\n' "$plugin_path" >&2
        exit 1
    }
    case $plugin_path in
        .antidote) ;;
        .local/share/nvim/lazy/*)
            plugin_leaf=${plugin_path#.local/share/nvim/lazy/}
            case $plugin_leaf in ''|.|..|*/*) printf 'invalid managed plugin path: %s\n' "$plugin_path" >&2; exit 1 ;; esac
            ;;
        .cache/antidote/github.com/*)
            plugin_leaf=${plugin_path#.cache/antidote/github.com/}
            case $plugin_leaf in */*) ;; *) printf 'invalid managed plugin path: %s\n' "$plugin_path" >&2; exit 1 ;; esac
            plugin_owner=${plugin_leaf%%/*}
            plugin_leaf=${plugin_leaf#*/}
            case $plugin_owner in ''|.|..) printf 'invalid managed plugin path: %s\n' "$plugin_path" >&2; exit 1 ;; esac
            case $plugin_leaf in ''|.|..|*/*) printf 'invalid managed plugin path: %s\n' "$plugin_path" >&2; exit 1 ;; esac
            ;;
        *) printf 'invalid managed plugin path: %s\n' "$plugin_path" >&2; exit 1 ;;
    esac
    case $revision in *[!0-9a-f]*|'') printf 'invalid plugin revision: %s\n' "$revision" >&2; exit 1 ;; esac
    [ "${#revision}" -eq 40 ] || { printf 'plugin revision must be full: %s\n' "$revision" >&2; exit 1; }
    destination=$payload/$plugin_path
    mkdir -p "${destination%/*}"
    git init -q "$destination"
    git -C "$destination" remote add origin "$url"
    printf 'snapshotting %s at %s\n' "$url" "$revision"
    GIT_TERMINAL_PROMPT=0 git -C "$destination" fetch -q --depth=1 origin "$revision"
    git -C "$destination" checkout -q --detach FETCH_HEAD
    [ "$(git -C "$destination" rev-parse HEAD)" = "$revision" ] || exit 1
    [ -e "$destination/$probe" ] && [ ! -L "$destination/$probe" ] || {
        printf 'managed plugin probe is unavailable: %s/%s\n' "$plugin_path" "$probe" >&2
        exit 1
    }
    printf '%s\t%s\t%s\t%s\n' "$scope" "$plugin_path" "$url" "$revision" >> "$payload/manifest.tsv"
done < "$manifest"

if ! find "$payload" -type l -exec sh -c '
    root=$1; shift
    root=$(cd "$root" && pwd -P) || exit 1
    for link do
        target=$(readlink "$link") || exit 1
        case $target in /*) exit 1 ;; esac
        parent=$(cd "${link%/*}" && pwd -P) || exit 1
        target_parent=$(cd "$parent/${target%/*}" 2>/dev/null && pwd -P) || exit 1
        case $target_parent/${target##*/} in "$root"/*) ;; *) exit 1 ;; esac
    done
' sh "$payload" {} +; then
    printf '%s\n' 'managed plugin payload contains an unsafe symbolic link' >&2
    exit 1
fi
output_parent=${output%/*}
[ "$output_parent" != "$output" ] || output_parent=.
mkdir -p "$output_parent"
COPYFILE_DISABLE=1 tar -czf "$output" -C "$work_dir" managed-plugins
printf 'built managed plugin snapshot: %s\n' "$output"
