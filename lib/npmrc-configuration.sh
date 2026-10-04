# shellcheck shell=sh
# Only the script approval preference belongs to Plasticine. Never print the
# input: it may contain registry credentials. No Node/npm executable is needed.
plasticine_npmrc_validate() {
    plasticine_npmrc_dest=$1
    for plasticine_npmrc_dir in "$plasticine_npmrc_dest/.plasticine" \
        "$plasticine_npmrc_dest/.plasticine/backups" \
        "$plasticine_npmrc_dest/.plasticine/backups/npmrc"; do
        if [ -L "$plasticine_npmrc_dir" ] ||
            { [ -e "$plasticine_npmrc_dir" ] && [ ! -d "$plasticine_npmrc_dir" ]; }; then
            printf '%s\n' 'plasticine-dotfiles: npmrc: backup paths must be regular directories.' >&2
            return 1
        fi
    done
    if [ -L "$plasticine_npmrc_dest/.npmrc" ] ||
        { [ -e "$plasticine_npmrc_dest/.npmrc" ] && [ ! -f "$plasticine_npmrc_dest/.npmrc" ]; }; then
        printf '%s\n' 'plasticine-dotfiles: npmrc: ~/.npmrc must be a regular file.' >&2
        return 1
    fi
}

plasticine_npmrc_compose() {
    plasticine_npmrc_input=$1
    plasticine_npmrc_output=$2
    plasticine_npmrc_newline=1
    if [ -s "$plasticine_npmrc_input" ] && [ -n "$(tail -c 1 "$plasticine_npmrc_input")" ]; then
        plasticine_npmrc_newline=0
    fi
    # Retain unrelated bytes, including CRLF and a missing final newline.
    # Quoted keys and array spellings are also replaced rather than left as
    # conflicting npm/ini entries. Keep exactly one scalar preference.
    LC_ALL=C awk -v newline="$plasticine_npmrc_newline" '
        function emit(line) {
            if (count++) printf "\n"
            printf "%s", line
        }
        NR == 1 { cr = ($0 ~ /\r$/ ? "\r" : "") }
        /^[ \t]*\[.*\][ \t]*(;.*|#.*)?\r?$/ {
            if (!seen) { emit("dangerously-allow-all-scripts=true" cr); seen=1 }
            section=1
        }
        /^[ \t]*(dangerously-allow-all-scripts|"dangerously-allow-all-scripts"|\047dangerously-allow-all-scripts\047)(\[\])?[ \t]*(=|\r?$)/ {
            if (section) { emit($0); next }
            if (!seen++) emit("dangerously-allow-all-scripts=true" cr)
            next
        }
        { emit($0) }
        END {
            if (!seen) { emit("dangerously-allow-all-scripts=true" cr); newline=1 }
            if (newline) printf "\n"
        }
    ' "$plasticine_npmrc_input" > "$plasticine_npmrc_output"
}

plasticine_npmrc_preview() (
    set -eu
    plasticine_npmrc_validate "$1"
    umask 077
    work_dir=$(mktemp -d "${TMPDIR:-/tmp}/plasticine-npmrc-preview.XXXXXX")
    trap 'rm -rf "$work_dir"' EXIT HUP INT TERM
    if [ -f "$1/.npmrc" ]; then cat "$1/.npmrc" > "$work_dir/input"; else : > "$work_dir/input"; fi
    plasticine_npmrc_compose "$work_dir/input" "$work_dir/candidate"
    if cmp -s "$work_dir/input" "$work_dir/candidate"; then
        printf '%s\n' 'npmrc: ~/.npmrc already has dangerously-allow-all-scripts=true.'
    else
        printf '%s\n' 'npmrc: set dangerously-allow-all-scripts=true in ~/.npmrc; preserve all other settings.'
    fi
)

# Called after the shared selected-tool preparation stage. The sibling
# candidate is private and renamed atomically; existing Owner modes survive.
plasticine_npmrc_apply() (
    set -eu
    dest_dir=$1
    plasticine_npmrc_validate "$dest_dir"
    umask 077
    candidate=$(mktemp "$dest_dir/.npmrc.plasticine-XXXXXXXX")
    input=$(mktemp "${TMPDIR:-/tmp}/plasticine-npmrc-input.XXXXXX")
    trap 'rm -f "$candidate" "$input"' EXIT HUP INT TERM
    if [ -f "$dest_dir/.npmrc" ]; then cat "$dest_dir/.npmrc" > "$input"; else : > "$input"; fi
    plasticine_npmrc_compose "$input" "$candidate"
    if [ -f "$dest_dir/.npmrc" ] && cmp -s "$input" "$candidate"; then exit 0; fi
    plasticine_npmrc_validate "$dest_dir"
    if [ -f "$dest_dir/.npmrc" ]; then
        cmp -s "$input" "$dest_dir/.npmrc" || {
            printf '%s\n' 'plasticine-dotfiles: npmrc: ~/.npmrc changed during apply; retry.' >&2
            exit 1
        }
        mode=$(stat -c '%a' "$dest_dir/.npmrc" 2>/dev/null || stat -f '%Lp' "$dest_dir/.npmrc")
        plasticine_whole_file_backup_if_changed "$dest_dir/.npmrc" "$candidate" \
            "$dest_dir/.plasticine/backups/npmrc" .npmrc
        chmod "$mode" "$candidate"
        mv -f "$candidate" "$dest_dir/.npmrc"
    else
        # Fail rather than overwrite a file created since the initial read.
        ln "$candidate" "$dest_dir/.npmrc"
    fi
)
