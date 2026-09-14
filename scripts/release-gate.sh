#!/bin/sh
set -eu

repo_dir=$(cd -- "$(dirname -- "$0")/.." && pwd)
revision=${1:-}
output_dir=${2:-$repo_dir/dist}
release_version=${3:-}
source_repository=${4:-$repo_dir}

"$repo_dir/scripts/build-release.sh" \
    "$revision" "$output_dir" "$release_version" "$source_repository"
"$repo_dir/scripts/verify-release.sh" \
    "$output_dir" "$revision" "$release_version"
