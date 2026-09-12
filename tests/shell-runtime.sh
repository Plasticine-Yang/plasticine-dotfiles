#!/bin/sh
set -eu

# Interface-level runtime verification of the managed Zsh fragment with a real
# Zsh. Installation, composition and ownership are covered by tests/shell.sh and
# tests/integration.sh; this suite starts a real shell against the artifacts the
# repository actually ships and observes what the shell ends up with.

repo_dir=$(cd -- "$(dirname -- "$0")/.." && pwd)

if ! command -v zsh >/dev/null 2>&1; then
    printf '%s\n' 'shell 运行时测试需要真实的 zsh。' >&2
    exit 1
fi
zsh_bin=$(command -v zsh)

test_root=$(mktemp -d "${TMPDIR:-/tmp}/plasticine-shell-runtime.XXXXXX")
# Physical paths keep zsh path expansion ($file:a) comparable with the fixtures.
test_root=$(cd "$test_root" && pwd -P)
trap 'rm -rf "$test_root"' EXIT HUP INT TERM

# The canonical composer and marker block, evaluated exactly as the rendered
# chezmoi source modifier and the shell `.chezmoiscripts` use them, so the runtime
# sees the real artifact.
# shellcheck disable=SC1091
. "$repo_dir/.chezmoitemplates/shell-zshrc-block"

fail() {
    printf '%s\n' "shell runtime tests: $1" >&2
    exit 1
}

expect_status() {
    [ "$1" -eq 0 ] || fail "$2 (status $1)"
}

expect_line() {
    grep -Fxq "$2" "$1" || {
        printf '%s\n' "--- $1" >&2
        cat "$1" >&2
        fail "$3"
    }
}

reject_line() {
    if grep -Fxq "$2" "$1"; then
        printf '%s\n' "--- $1" >&2
        cat "$1" >&2
        fail "$3"
    fi
}

expect_order() {
    expect_first=$(grep -n -F -m1 "$2" "$1" | cut -d: -f1)
    expect_second=$(grep -n -F -m1 "$3" "$1" | cut -d: -f1)
    if [ -z "$expect_first" ] || [ -z "$expect_second" ]; then
        fail "$4 (missing entries)"
    fi
    [ "$expect_first" -lt "$expect_second" ] || fail "$4"
}

expect_error() {
    grep -Fq "$2" "$1" || {
        printf '%s\n' "--- $1" >&2
        cat "$1" >&2
        fail "$3"
    }
}

reject_error() {
    if grep -Fq "$2" "$1"; then
        printf '%s\n' "--- $1" >&2
        cat "$1" >&2
        fail "$3"
    fi
}

expect_warning() {
    expect_error "$1" "plasticine: $2 unavailable; continuing shell startup" "$3"
}

# A healthy or non-interactive shell must be completely quiet.
reject_warnings() {
    reject_error "$1" 'plasticine:' "$2"
}

hash_tree() {
    find "$1" -type f -exec shasum -a 256 {} + | LC_ALL=C sort | shasum -a 256 | awk '{ print $1 }'
}

# ---------------------------------------------------------------- fixtures ---

# Controlled PATH: a fixture Homebrew plus the real system binaries. Nothing else
# on the developer's machine (real brew, real fnm, real antidote) is reachable.
# The fixture prefix lives inside the disposable HOME, so a scenario that wants
# Antidote present or absent controls the Homebrew route as well.
runtime_os=$(uname -s)
runtime_bin=$test_root/bin
brew_calls=$test_root/brew-calls
mkdir -p "$runtime_bin"
: > "$brew_calls"
cat > "$runtime_bin/brew" <<EOF
#!/bin/sh
printf 'brew %s\\n' "\$*" >> '$brew_calls'
case \$* in
    '--prefix antidote' | '--prefix')
        printf '%s\\n' "\$HOME/brew-prefix"
        ;;
    *)
        printf '%s\\n' "plasticine shell runtime tests: host brew blocked: \$*" >&2
        exit 99
        ;;
esac
EOF
chmod +x "$runtime_bin/brew"
runtime_path=$runtime_bin:/usr/bin:/bin

# A fixture fnm that prints shell code and then fails, or succeeds on demand.
fnm_bin=$test_root/fnm-bin
fnm_calls=$test_root/fnm-calls
mkdir -p "$fnm_bin"
: > "$fnm_calls"
cat > "$fnm_bin/fnm" <<'EOF'
#!/bin/sh
printf 'fnm %s\n' "$*" >> "${PLASTICINE_RUNTIME_FNM_CALLS:-/dev/null}"
case ${PLASTICINE_RUNTIME_FNM_MODE:-fail} in
    fail)
        printf '%s\n' 'PLASTICINE_FNM_EVALUATED=1'
        exit 1
        ;;
    ok)
        printf '%s\n' 'typeset -g PLASTICINE_FNM_OK=1'
        exit 0
        ;;
esac
exit 99
EOF
chmod +x "$fnm_bin/fnm"

# The Antidote entry point the host's fragment resolves. macOS resolves it
# through Homebrew and Linux through ~/.antidote, so the fixture goes on the
# native route and a poisoned stand-in goes on the other one: reaching the
# poisoned copy means the fragment ignored its native route.
native_antidote_path() {
    case $runtime_os in
        Darwin) printf '%s\n' "$1/brew-prefix/share/antidote/antidote.zsh" ;;
        *) printf '%s\n' "$1/.antidote/antidote.zsh" ;;
    esac
}

foreign_antidote_path() {
    case $runtime_os in
        Darwin) printf '%s\n' "$1/.antidote/antidote.zsh" ;;
        *) printf '%s\n' "$1/brew-prefix/share/antidote/antidote.zsh" ;;
    esac
}

write_antidote() {
    fixture_home=$1
    antidote_target=$(native_antidote_path "$fixture_home")
    mkdir -p "${antidote_target%/*}"
    # Records every declaration the managed fragment loads and contributes fpath
    # the way `kind:fpath` does.
    cat > "$antidote_target" <<'PLASTICINE_ANTIDOTE'
antidote() {
    case $1 in
        --version)
            print -r -- 'plasticine shell runtime antidote'
            return 0
            ;;
        load)
            if [[ -n ${PLASTICINE_RUNTIME_LOG:-} ]]; then
                print -r -- "antidote-load $2" >> "$PLASTICINE_RUNTIME_LOG"
            fi
            if [[ -n ${PLASTICINE_RUNTIME_FAIL_LOAD:-} && $2 == *${PLASTICINE_RUNTIME_FAIL_LOAD}* ]]; then
                return 1
            fi
            case $2 in
                "$HOME/.zsh_plugins.txt")
                    fpath=("$PLASTICINE_RUNTIME_COMPLETIONS" $fpath)
                    if [[ -n ${PLASTICINE_RUNTIME_LOG:-} ]]; then
                        print -r -- 'managed-plugins-active' >> "$PLASTICINE_RUNTIME_LOG"
                    fi
                    ;;
                "$HOME/.zsh_plugins.local.txt")
                    if [[ -n ${PLASTICINE_RUNTIME_LOG:-} ]]; then
                        print -r -- 'owner-plugins-active' >> "$PLASTICINE_RUNTIME_LOG"
                    fi
                    ;;
            esac
            return 0
            ;;
        path)
            print -r -- "$HOME/.cache/antidote/github.com/romkatv/powerlevel10k"
            return 0
            ;;
    esac
    return 1
}
PLASTICINE_ANTIDOTE
    write_foreign_antidote "$fixture_home"
}

write_foreign_antidote() {
    foreign_target=$(foreign_antidote_path "$1")
    mkdir -p "${foreign_target%/*}"
    cat > "$foreign_target" <<'PLASTICINE_FOREIGN_ANTIDOTE'
if [[ -n ${PLASTICINE_RUNTIME_LOG:-} ]]; then
    print -r -- 'foreign-antidote-route' >> "$PLASTICINE_RUNTIME_LOG"
fi
antidote() {
    if [[ -n ${PLASTICINE_RUNTIME_LOG:-} ]]; then
        print -r -- "foreign-antidote-load $2" >> "$PLASTICINE_RUNTIME_LOG"
    fi
    return 0
}
PLASTICINE_FOREIGN_ANTIDOTE
}

completions_dir=$test_root/plasticine-completions
mkdir -p "$completions_dir"
cat > "$completions_dir/_plasticine-runtime" <<'EOF'
#compdef plasticine-runtime
_plasticine-runtime() {
    _message 'plasticine runtime completion'
}
EOF

# Owner content that follows the managed block in the Owner-controlled .zshrc.
owner_trailer=$test_root/owner-trailer
cat > "$owner_trailer" <<'EOF'
if [ -n "${PLASTICINE_RUNTIME_LOG:-}" ]; then
    print -r -- 'owner-trailer-active' >> "$PLASTICINE_RUNTIME_LOG"
fi
plasticine_runtime_owner_active() { return 0 }
path=("$HOME/owner-bin" "${path[@]}")
export PATH
EOF

# Observations are appended after `.zshrc` finished, so they only exist when the
# managed block returned control to the later Owner content.
probe_script=$test_root/probe.zsh
cat > "$probe_script" <<'EOF'
{
    print -r -- "probe-interactive=${options[interactive]}"
    print -r -- "probe-comp=${+_comps[plasticine-runtime]}"
    print -r -- "probe-fpath=${fpath[(Ie)$PLASTICINE_RUNTIME_COMPLETIONS]}"
    print -r -- "probe-completion=${+functions[_plasticine-runtime]}"
    print -r -- "probe-brew-prefix-bin=${path[(Ie)$HOME/brew-prefix/bin]}"
    print -r -- "probe-owner-function=${+functions[plasticine_runtime_owner_active]}"
    print -r -- "probe-p10k-instant=${POWERLEVEL9K_INSTANT_PROMPT:-unset}"
    print -r -- "probe-p10k-config=${POWERLEVEL9K_CONFIG_FILE:-unset}"
    print -r -- "probe-path-first=${path[1]}"
    print -r -- "probe-local-bin=${path[(Ie)$HOME/.local/bin]}"
    print -r -- "probe-fnm-evaluated=${+PLASTICINE_FNM_EVALUATED}"
    print -r -- "probe-fnm-ok=${PLASTICINE_FNM_OK:-unset}"
} >> "$PLASTICINE_RUNTIME_LOG"
EOF

# ---------------------------------------------------------------- harness ----

# Sets home/log/out/err for the scenario and composes the real `.zshrc`.
new_home() {
    scenario_dir=$test_root/$1
    home=$scenario_dir/home
    log=$scenario_dir/log
    out=$scenario_dir/stdout
    err=$scenario_dir/stderr
    mkdir -p "$home/.plasticine/zsh"
    cp "$repo_dir/dot_plasticine/zsh/shared.zsh" "$home/.plasticine/zsh/shared.zsh"
    cp "$repo_dir/dot_zsh_plugins.txt" "$home/.zsh_plugins.txt"
    cp "$repo_dir/dot_p10k.zsh" "$home/.p10k.zsh"
    plasticine_shell_compose "$owner_trailer" > "$home/.zshrc"
    : > "$log"
}

# `interactive` starts a real interactive shell. `sourced` evaluates the managed
# fragment the way a non-interactive shell would. Extra `NAME=value` arguments are
# exported for that shell only. Every probe starts a fresh log so observations
# always describe exactly one shell startup.
probe() {
    probe_mode=$1
    shift
    : > "$log"
    : > "$brew_calls"
    probe_status=0
    # A subshell owns every exported knob, so the test shell keeps its own HOME,
    # PATH and environment no matter how the probed shell ends.
    (
        # The absolute shell and the explicit environment keep the developer's own
        # brew, fnm and antidote unreachable while the shell starts.
        export HOME="$home" ZDOTDIR="$home" TERM_PROGRAM=plasticine-runtime-test \
            PLASTICINE_RUNTIME_LOG="$log" PLASTICINE_RUNTIME_PROBE="$probe_script" \
            PLASTICINE_RUNTIME_COMPLETIONS="$completions_dir" \
            PLASTICINE_RUNTIME_FAIL_LOAD='' PLASTICINE_RUNTIME_FNM_MODE='' \
            PLASTICINE_RUNTIME_FNM_CALLS='/dev/null'
        export PATH="$runtime_path"
        for probe_assignment in "$@"; do
            # The name is dynamic on purpose; SC2163 warns about the literal name.
            # shellcheck disable=SC2163
            export "$probe_assignment"
        done
        # The single-quoted zsh snippets must evaluate in the probed shell.
        # shellcheck disable=SC2016
        if [ "$probe_mode" = interactive ]; then
            set -- -i -c 'source "$PLASTICINE_RUNTIME_PROBE"'
        else
            set -- -c '. "$ZDOTDIR/.zshrc"; source "$PLASTICINE_RUNTIME_PROBE"'
        fi
        "$zsh_bin" "$@"
    ) >"$out" 2>"$err" || probe_status=$?
    # The status is reported through $probe_status so scenarios can assert it.
    return 0
}

# ------------------------------------------------------- healthy runtime -----

new_home healthy-interactive
write_antidote "$home"
printf '%s\n' '# Owner plugin declaration' 'owner/plugin' > "$home/.zsh_plugins.local.txt"
probe interactive
expect_status "$probe_status" 'a healthy interactive shell exited non-zero'
reject_warnings "$err" 'the healthy interactive stack warned'
reject_line "$log" 'foreign-antidote-route' 'Antidote was loaded from the wrong native route'
expect_line "$log" "antidote-load $home/.zsh_plugins.txt" 'the managed plugin declaration was not loaded'
expect_line "$log" "antidote-load $home/.zsh_plugins.local.txt" 'the Owner plugin declaration was not loaded'
expect_line "$log" 'managed-plugins-active' 'managed plugins were not activated'
expect_line "$log" 'owner-plugins-active' 'Owner plugins were not activated'
expect_order "$log" "antidote-load $home/.zsh_plugins.txt" \
    "antidote-load $home/.zsh_plugins.local.txt" 'the managed declaration did not load before the Owner declaration'
expect_line "$log" 'owner-trailer-active' 'later Owner .zshrc content never ran'
expect_line "$log" 'probe-interactive=on' 'the probe did not run in an interactive shell'
expect_line "$log" 'probe-comp=1' 'completions contributed through the declaration were not initialized'
expect_line "$log" 'probe-completion=1' 'the completion contributed through the declaration is not available'
case $(sed -n 's/^probe-fpath=//p' "$log") in
    0 | '') fail 'the fpath entry contributed through the declaration did not survive into the interactive shell' ;;
esac

expect_line "$log" 'probe-owner-function=1' 'the managed block did not return control to later Owner .zshrc content'
expect_line "$log" 'probe-p10k-instant=quiet' 'Powerlevel10k preferences were not applied'
expect_line "$log" "probe-p10k-config=$home/.p10k.zsh" 'Powerlevel10k preferences were not applied from the managed path'
expect_line "$log" "probe-path-first=$home/owner-bin" 'later Owner .zshrc content could not override the managed PATH default'
case $(sed -n 's/^probe-local-bin=//p' "$log") in
    0 | '') fail 'the managed ~/.local/bin PATH default is missing' ;;
esac

# The same artifacts must behave in a non-interactive shell, without completion
# initialization and without warnings.
new_home healthy-noninteractive
write_antidote "$home"
printf '%s\n' 'owner/plugin' > "$home/.zsh_plugins.local.txt"
probe sourced
expect_status "$probe_status" 'a healthy non-interactive shell exited non-zero'
reject_warnings "$err" 'the healthy non-interactive stack warned'
expect_line "$log" "antidote-load $home/.zsh_plugins.txt" 'the managed declaration was not loaded without a terminal'
expect_line "$log" "antidote-load $home/.zsh_plugins.local.txt" 'the Owner declaration was not loaded without a terminal'
expect_line "$log" 'probe-interactive=off' 'the probe did not run in a non-interactive shell'
expect_line "$log" 'probe-comp=0' 'completions were initialized outside an interactive shell'
expect_line "$log" 'probe-owner-function=1' 'the managed block did not return control to later Owner content'
reject_line "$log" 'foreign-antidote-route' 'Antidote was loaded from the wrong native route'

# ------------------------------------------- optional layers degrade safely ---

# An absent Owner plugin declaration is optional: no load, no warning, and Owner
# content after the block still runs.
new_home owner-declaration-absent
write_antidote "$home"
probe interactive
expect_status "$probe_status" 'a shell without the Owner plugin declaration exited non-zero'
reject_warnings "$err" 'the absent Owner declaration warned'
reject_line "$log" "antidote-load $home/.zsh_plugins.local.txt" 'an absent Owner declaration was loaded anyway'
expect_line "$log" "antidote-load $home/.zsh_plugins.txt" 'the managed declaration was not loaded'
expect_line "$log" 'probe-owner-function=1' 'the managed block did not return control to later Owner content'

# A present but unusable Owner declaration warns interactively and is never
# replaced or removed.
new_home owner-declaration-unusable
write_antidote "$home"
mkdir "$home/.zsh_plugins.local.txt"
probe interactive
expect_warning "$err" 'Owner plugin declaration' 'an unusable Owner declaration did not warn'
expect_line "$log" "antidote-load $home/.zsh_plugins.txt" 'a broken Owner declaration stopped the managed declaration'
expect_line "$log" 'probe-owner-function=1' 'a broken Owner declaration aborted later Owner content'
test -d "$home/.zsh_plugins.local.txt" || fail 'the unusable Owner declaration was replaced'
probe sourced
reject_warnings "$err" 'an unusable Owner declaration warned without a terminal'
expect_line "$log" 'probe-owner-function=1' 'later Owner content was aborted'

# Missing Antidote warns interactively, installs nothing, and returns control.
new_home antidote-missing
probe interactive
expect_status "$probe_status" 'a shell without Antidote exited non-zero'
expect_warning "$err" 'Antidote' 'a missing Antidote did not warn interactively'
reject_line "$log" 'managed-plugins-active' 'plugins were activated without Antidote'
expect_line "$log" 'probe-owner-function=1' 'a missing Antidote aborted later Owner content'
test ! -e "$home/.antidote" || fail 'a missing Antidote was installed into the destination'
test ! -e "$home/.cache" || fail 'a missing Antidote created a cache'
probe sourced
reject_warnings "$err" 'a missing Antidote warned without a terminal'
expect_line "$log" 'probe-owner-function=1' 'a missing Antidote aborted later Owner content'
test ! -e "$home/.antidote" || fail 'a missing Antidote was installed without a terminal'

# Antidote that exists but cannot provide its function warns interactively.
new_home antidote-unusable
unusable_antidote=$(native_antidote_path "$home")
mkdir -p "${unusable_antidote%/*}"
printf '%s\n' 'return 0' > "$unusable_antidote"
probe interactive
expect_warning "$err" 'Antidote' 'an unusable Antidote did not warn'
expect_line "$log" 'probe-owner-function=1' 'an unusable Antidote aborted later Owner content'
probe sourced
reject_warnings "$err" 'an unusable Antidote warned without a terminal'
expect_line "$log" 'probe-owner-function=1' 'later Owner content was aborted'

# A failing managed declaration warns interactively, does not load stale plugins
# and does not stop the Owner declaration or later Owner content.
new_home managed-declaration-fails
write_antidote "$home"
printf '%s\n' 'owner/plugin' > "$home/.zsh_plugins.local.txt"
probe interactive PLASTICINE_RUNTIME_FAIL_LOAD=zsh_plugins.txt
expect_warning "$err" 'managed plugins' 'a failing managed declaration did not warn'
reject_line "$log" 'managed-plugins-active' 'a failed managed declaration reported active plugins'
expect_line "$log" "antidote-load $home/.zsh_plugins.local.txt" 'a failed managed declaration stopped the Owner declaration'
expect_line "$log" 'owner-plugins-active' 'Owner plugins were skipped after a managed failure'
expect_line "$log" 'probe-owner-function=1' 'a failed managed declaration aborted later Owner content'
probe sourced PLASTICINE_RUNTIME_FAIL_LOAD=zsh_plugins.txt
reject_warnings "$err" 'a failing managed declaration warned without a terminal'
expect_line "$log" 'probe-owner-function=1' 'a failed managed declaration aborted later Owner content'

# A failing Owner declaration warns interactively without stopping Owner content.
new_home owner-declaration-fails
write_antidote "$home"
printf '%s\n' 'owner/plugin' > "$home/.zsh_plugins.local.txt"
probe interactive PLASTICINE_RUNTIME_FAIL_LOAD=.zsh_plugins.local.txt
expect_warning "$err" 'Owner plugins' 'a failing Owner declaration did not warn'
expect_line "$log" 'managed-plugins-active' 'a failed Owner declaration stopped the managed declaration'
expect_line "$log" 'probe-owner-function=1' 'a failed Owner declaration aborted later Owner content'
probe sourced PLASTICINE_RUNTIME_FAIL_LOAD=.zsh_plugins.local.txt
reject_warnings "$err" 'a failing Owner declaration warned without a terminal'
expect_line "$log" 'probe-owner-function=1' 'later Owner content was aborted'

# Missing managed declaration: interactive warning, no plugin state, Owner content
# still runs.
new_home managed-declaration-absent
write_antidote "$home"
rm "$home/.zsh_plugins.txt"
probe interactive
expect_warning "$err" 'managed plugin declaration' 'a missing managed declaration did not warn'
reject_line "$log" 'managed-plugins-active' 'plugins were activated without a declaration'
expect_line "$log" 'probe-owner-function=1' 'a missing managed declaration aborted later Owner content'
test ! -e "$home/.zsh_plugins.txt" || fail 'a missing managed declaration was created at runtime'

# Completion initialization that cannot run warns interactively only. An empty
# function path makes Zsh's own compinit unavailable without touching state.
new_home completions-unavailable
write_antidote "$home"
mkdir -p "$home/no-functions"
printf '%s\n' "fpath=(\"\$HOME/no-functions\")" > "$home/.zshenv"
probe interactive
expect_warning "$err" 'completions' 'unavailable completions did not warn'
expect_line "$log" 'probe-owner-function=1' 'unavailable completions aborted later Owner content'
probe sourced
reject_warnings "$err" 'unavailable completions warned without a terminal'
expect_line "$log" 'probe-owner-function=1' 'later Owner content was aborted'
rm "$home/.zshenv"

# Missing Powerlevel10k preferences warn interactively and are never recreated.
new_home prompt-absent
write_antidote "$home"
rm "$home/.p10k.zsh"
probe interactive
expect_warning "$err" 'Powerlevel10k preferences' 'missing Powerlevel10k preferences did not warn'
expect_line "$log" 'probe-owner-function=1' 'missing Powerlevel10k preferences aborted later Owner content'
test ! -e "$home/.p10k.zsh" || fail 'missing Powerlevel10k preferences were recreated at runtime'
probe sourced
reject_warnings "$err" 'missing Powerlevel10k preferences warned without a terminal'
expect_line "$log" 'probe-owner-function=1' 'later Owner content was aborted'

# Failing Powerlevel10k preferences warn interactively and apply nothing.
new_home prompt-fails
write_antidote "$home"
printf '%s\n' 'POWERLEVEL9K_MODE=broken' 'return 1' > "$home/.p10k.zsh"
probe interactive
expect_warning "$err" 'Powerlevel10k preferences' 'failing Powerlevel10k preferences did not warn'
expect_line "$log" 'probe-p10k-instant=unset' 'failing Powerlevel10k preferences were treated as applied'
expect_line "$log" 'probe-p10k-config=unset' 'failing Powerlevel10k preferences were treated as applied'
expect_line "$log" 'probe-owner-function=1' 'failing Powerlevel10k preferences aborted later Owner content'
probe sourced
reject_warnings "$err" 'failing Powerlevel10k preferences warned without a terminal'
expect_line "$log" 'probe-owner-function=1' 'later Owner content was aborted'

# --------------------------------------------------------------- fnm layer ---

fnm_probe_path=$fnm_bin:$runtime_path

# fnm is not installed by this feature: its absence stays silent, and existing
# fnm state is neither installed, moved nor rewritten.
new_home fnm-absent
write_antidote "$home"
mkdir -p "$home/.local/share/fnm/node-versions/v20.11.0/installation/bin" "$home/.fnm"
printf '%s\n' 'fnm' > "$home/.local/share/fnm/node-versions/v20.11.0/installation/bin/fnm"
printf '%s\n' 'owner fnm state' > "$home/.fnm/marker"
fnm_state_hash=$(hash_tree "$home/.local/share/fnm" "$home/.fnm")
probe interactive
expect_status "$probe_status" 'a shell without fnm exited non-zero'
reject_warnings "$err" 'an absent fnm warned'
expect_line "$log" 'probe-owner-function=1' 'an absent fnm aborted later Owner content'
test ! -s "$fnm_calls" || fail 'an absent fnm was invoked'
test "$(hash_tree "$home/.local/share/fnm" "$home/.fnm")" = "$fnm_state_hash" ||
    fail 'an absent fnm relocated or rewrote existing fnm state'
if grep -Evq '^brew --prefix( antidote)?$' "$brew_calls"; then
    cat "$brew_calls" >&2
    fail 'an absent fnm made Homebrew perform something other than a prefix lookup'
fi

# A failing `fnm env --shell zsh` must warn interactively, must not be evaluated
# and must not stop Owner content or run any other fnm subcommand.
new_home fnm-fails
write_antidote "$home"
mkdir -p "$home/.local/share/fnm"
printf '%s\n' 'owner fnm state' > "$home/.local/share/fnm/marker"
fnm_state_hash=$(hash_tree "$home/.local/share/fnm")
probe interactive PATH="$fnm_probe_path" PLASTICINE_RUNTIME_FNM_CALLS="$fnm_calls"
expect_warning "$err" 'fnm activation' 'a failing fnm activation did not warn'
expect_line "$log" 'probe-fnm-evaluated=0' 'code printed by a failing fnm was evaluated'
expect_line "$log" 'probe-owner-function=1' 'a failing fnm activation aborted later Owner content'
expect_line "$fnm_calls" 'fnm env --shell zsh' 'the failing fnm activation was never attempted'
test "$(grep -c . "$fnm_calls" | tr -d ' ')" = 1 ||
    fail 'a failing fnm activation ran commands beyond the documented fnm call'
test "$(hash_tree "$home/.local/share/fnm")" = "$fnm_state_hash" ||
    fail 'a failing fnm activation rewrote existing fnm state'
probe sourced PATH="$fnm_probe_path" PLASTICINE_RUNTIME_FNM_CALLS="$fnm_calls"
reject_warnings "$err" 'a failing fnm activation warned without a terminal'
expect_line "$log" 'probe-fnm-evaluated=0' 'code printed by a failing fnm was evaluated'
reject_line "$log" 'probe-fnm-evaluated=1' 'code printed by a failing fnm was evaluated'
expect_line "$log" 'probe-owner-function=1' 'a failing fnm activation aborted later Owner content'

# A successful `fnm env --shell zsh` is evaluated, which is what the failing case
# above is observed against.
new_home fnm-succeeds
write_antidote "$home"
: > "$fnm_calls"
probe interactive PATH="$fnm_probe_path" PLASTICINE_RUNTIME_FNM_CALLS="$fnm_calls" \
    PLASTICINE_RUNTIME_FNM_MODE=ok
expect_status "$probe_status" 'a shell with a healthy fnm exited non-zero'
reject_warnings "$err" 'a healthy fnm activation warned'
expect_line "$log" 'probe-fnm-ok=1' 'a successful fnm activation was not evaluated'
expect_line "$log" 'probe-owner-function=1' 'a healthy fnm activation aborted later Owner content'

# On macOS the fragment exposes an already installed Homebrew executable
# directory only when fnm is missing from PATH, then activates it.
if [ "$runtime_os" = Darwin ]; then
    new_home fnm-homebrew-prefix
    write_antidote "$home"
    mkdir -p "$home/brew-prefix/bin"
    cp "$fnm_bin/fnm" "$home/brew-prefix/bin/fnm"
    : > "$fnm_calls"
    probe interactive PLASTICINE_RUNTIME_FNM_CALLS="$fnm_calls" PLASTICINE_RUNTIME_FNM_MODE=ok
    expect_status "$probe_status" 'a shell with a prefix-only fnm exited non-zero'
    reject_warnings "$err" 'a prefix-only fnm activation warned'
    expect_line "$log" 'probe-fnm-ok=1' 'a prefix-only fnm activation was not evaluated'
    case $(sed -n 's/^probe-brew-prefix-bin=//p' "$log") in
        0 | '') fail 'the Homebrew executable directory of an installed fnm was not exposed' ;;
    esac
    expect_line "$fnm_calls" 'fnm env --shell zsh' 'the prefix-only fnm was never activated'
    test ! -e "$home/.local/share/fnm" || fail 'activating fnm relocated its state'
    test "$(find "$home/brew-prefix" -type f | LC_ALL=C sort)" = \
        "$(printf '%s\n' "$home/brew-prefix/bin/fnm" "$(native_antidote_path "$home")" | LC_ALL=C sort)" ||
        fail 'activating fnm rewrote the Homebrew prefix'
fi

# ---------------------------------------------- managed fragment failure -----

# The `.zshrc` block itself must contain a broken managed fragment.
new_home fragment-broken
write_antidote "$home"
printf '%s\n' 'if [ ; then' > "$home/.plasticine/zsh/shared.zsh"
probe interactive
expect_error "$err" 'plasticine: shared shell configuration unavailable' \
    'a broken managed fragment did not report unavailability'
expect_line "$log" 'probe-owner-function=1' 'a broken managed fragment aborted later Owner content'
probe sourced
reject_error "$err" 'plasticine:' 'a broken managed fragment warned without a terminal'
expect_line "$log" 'probe-owner-function=1' 'a broken managed fragment aborted later Owner content'

# ------------------------------------------- runtime state stays untouched ---

# Antidote-owned runtime state and the Owner plugin list are read-only inputs for
# the fragment: nothing is generated, replaced, compiled or removed.
new_home runtime-state
write_antidote "$home"
mkdir -p "$home/.cache/antidote/github.com/zsh-users/zsh-autosuggestions"
printf '%s\n' 'plugin declaration' > "$home/.zsh_plugins.local.txt"
printf '%s\n' 'generated managed bundle' > "$home/.zsh_plugins.zsh"
printf '%s\n' 'generated Owner bundle' > "$home/.zsh_plugins.local.zsh"
printf '%s\n' 'plugin checkout' \
    > "$home/.cache/antidote/github.com/zsh-users/zsh-autosuggestions/zsh-autosuggestions.zsh"
printf '%s\n' 'compiled plugin' \
    > "$home/.cache/antidote/github.com/zsh-users/zsh-autosuggestions/zsh-autosuggestions.zsh.zwc"
printf '%s\n' 'compiled bundle' > "$home/.zsh_plugins.zsh.zwc"
runtime_state_hash=$(hash_tree "$home/.zsh_plugins.zsh" "$home/.zsh_plugins.local.zsh" \
    "$home/.zsh_plugins.local.txt" "$home/.cache" "$home/.zsh_plugins.zsh.zwc")
find "$home" -mindepth 1 -type d | LC_ALL=C sort > "$scenario_dir/directories-before"
probe interactive
expect_status "$probe_status" 'the runtime-state shell exited non-zero'
reject_warnings "$err" 'the runtime-state shell warned'
test "$(hash_tree "$home/.zsh_plugins.zsh" "$home/.zsh_plugins.local.zsh" \
    "$home/.zsh_plugins.local.txt" "$home/.cache" "$home/.zsh_plugins.zsh.zwc")" = "$runtime_state_hash" ||
    fail 'the fragment rewrote or removed Antidote runtime state'
expect_line "$log" 'owner-plugins-active' 'the Owner plugin list was not loaded during the runtime-state check'
find "$home" -mindepth 1 -type d | LC_ALL=C sort > "$scenario_dir/directories-after"
if ! diff -u "$scenario_dir/directories-before" "$scenario_dir/directories-after" \
    > "$scenario_dir/directories-diff"; then
    cat "$scenario_dir/directories-diff" >&2
    fail 'the fragment created a directory outside the managed fragment'
fi
test "$(find "$home/.plasticine" -type f | LC_ALL=C sort)" = "$home/.plasticine/zsh/shared.zsh" ||
    fail 'the fragment wrote Plasticine-owned state outside the managed fragment'

printf '%s\n' 'shell runtime tests passed'
