#!/bin/sh
set -eu
umask 022

repo_dir=$(cd -- "$(dirname -- "$0")/.." && pwd -P)
all_suites='test-runner workflows ci-gate check-runner integration combined-installation chezmoi git-config npmrc installer cli self-update bootstrap-installation diff-config shell shell-runtime lazygit lazygit-runtime fnm fnm-runtime neovim neovim-runtime herdr release release-payload'
case ${1:---all} in
    --help|-h)
        printf '%s\n' 'usage: scripts/check.sh [--all | suite ...]' "$all_suites"
        exit 0 ;;
    --all)
        [ "$#" -le 1 ] || { printf '%s\n' '--all takes no additional suites' >&2; exit 2; }
        # Suite names are a fixed list, deliberately split into arguments.
        # shellcheck disable=SC2086
        set -- $all_suites ;;
esac

required_tools='shellcheck'
for suite do
    case " $all_suites " in
        *" $suite "*) ;;
        *) printf 'unknown test suite: %s\n' "$suite" >&2; exit 2 ;;
    esac
    case $suite in
        test-runner|workflows|ci-gate|check-runner|cli|self-update|release-payload) ;;
        shell-runtime|fnm-runtime) required_tools="$required_tools zsh" ;;
        neovim-runtime) required_tools="$required_tools nvim" ;;
        *) required_tools="$required_tools chezmoi zsh" ;;
    esac
    case $suite in
        installer|bootstrap-installation|combined-installation|diff-config|herdr|lazygit)
            required_tools="$required_tools expect" ;;
        npmrc) required_tools="$required_tools node npm" ;;
    esac
done

# Resolve the few required runtimes before clearing the operator's PATH.
# Other commands come from system directories, never personal tool shims.
task_parent=$repo_dir/.agent-tmp/checks
mkdir -p "$task_parent"
task_root=$(mktemp -d "$task_parent/run.XXXXXX")
trap 'rm -rf "$task_root"' EXIT HUP INT TERM
mkdir -p "$task_root/bin" "$task_root/home" "$task_root/tmp"
missing=0
for tool in $required_tools; do
    [ ! -e "$task_root/bin/$tool" ] || continue
    candidate=$tool
    [ "$tool" != chezmoi ] || candidate=${CHEZMOI_BIN:-chezmoi}
    [ "$tool" != nvim ] || candidate=${NVIM_BIN:-nvim}
    tool_path=$(command -v "$candidate" 2>/dev/null || true)
    if [ -z "$tool_path" ] || [ ! -x "$tool_path" ]; then
        printf 'missing check dependency: %s (%s)\n' "$tool" "$candidate" >&2
        missing=1
        continue
    fi
    case $tool_path in
        /*) ;;
        *) tool_path=$(cd -- "$(dirname -- "$tool_path")" && pwd -P)/${tool_path##*/} ;;
    esac
    ln -s "$tool_path" "$task_root/bin/$tool"
done
[ "$missing" -eq 0 ] || exit 1
case " $required_tools " in
    *' npm '*)
        policy=$(env -i HOME="$task_root/home" \
            PATH="$task_root/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
            npm --userconfig "$task_root/home/.npmrc" --globalconfig /dev/null \
            config get dangerously-allow-all-scripts 2>/dev/null || true)
        [ "$policy" = false ] || {
            printf '%s\n' 'npmrc checks require npm with script-policy support (CI uses Node 24.21.0 and npm 12.0.2).' >&2
            exit 1
        } ;;
esac

# Keep the operator's working tree and index intact. Copy tracked and new
# non-ignored files, including uncommitted changes, with checkout permissions.
git -C "$repo_dir" ls-files --cached --others --exclude-standard -z > "$task_root/files"
snapshot=$task_root/source
mkdir -p "$snapshot"
perl -0 -MFile::Copy=copy -MFile::Path=make_path -MFile::Basename=dirname -e '
    my ($source, $target) = @ARGV;
    while (my $name = <STDIN>) {
        chomp $name;
        my $from = "$source/$name";
        next unless -e $from || -l $from; # Deleted tracked files stay deleted.
        my $to = "$target/$name";
        make_path(dirname($to));
        if (-l $from) {
            symlink(readlink($from), $to) or die "symlink $name: $!\n";
        } elsif (-f $from) {
            copy($from, $to) or die "copy $name: $!\n";
            chmod(((stat($from))[2] & 0111) ? 0755 : 0644, $to)
                or die "chmod $name: $!\n";
        } else {
            die "unsupported check input: $name\n";
        }
    }
' "$repo_dir" "$snapshot" < "$task_root/files"

# Re-enter once with a clean environment; fixtures still own their own HOME.
# shellcheck disable=SC2016
env -i HOME="$task_root/home" TMPDIR="$task_root/tmp" \
    PATH="$task_root/bin:/usr/bin:/bin:/usr/sbin:/sbin" LC_ALL=C \
    /bin/sh -eu -c '
        cd "$1"
        shift
        git init -q
        git symbolic-ref HEAD refs/heads/main
        git add -A
        git diff --cached --check
        git -c user.name=test -c user.email=test@example.com commit -qm check-snapshot
        export CHEZMOI_BIN=chezmoi NVIM_BIN=nvim PLASTICINE_REQUIRE_NPMRC_RUNTIME=1
        shellcheck scripts/check.sh scripts/run-test.sh
        for suite do
            shellcheck "tests/$suite.sh"
            case $suite in
                test-runner|workflows|ci-gate|check-runner|cli) limit=30 ;;
                shell) limit=300 ;;
                *) limit=180 ;;
            esac
            ./scripts/run-test.sh "$limit" "$suite" "./tests/$suite.sh"
            case $suite in
                npmrc|self-update)
                    ./scripts/run-test.sh "$limit" "$suite-bash" bash "./tests/$suite.sh" ;;
            esac
        done
    ' check "$snapshot" "$@"
