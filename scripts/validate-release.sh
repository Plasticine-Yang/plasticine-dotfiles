#!/bin/sh

set -eu

root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
first_build="$(mktemp -d)"
second_build="$(mktemp -d)"
version="${PLASTICINE_VERSION:-$(git describe --tags --exact-match 2>/dev/null || printf '%s' dev)}"
commit="${PLASTICINE_COMMIT:-$(git rev-parse HEAD 2>/dev/null || printf '%s' unknown)}"
commit_time="${PLASTICINE_COMMIT_TIME:-$(git show -s --format=%cI HEAD 2>/dev/null || printf '%s' 1970-01-01T00:00:00Z)}"

cleanup() {
	rm -rf "$first_build" "$second_build"
}
trap cleanup EXIT HUP INT TERM

cd "$root"

go test ./...
scripts/validate-bootstrap.sh
go run ./cmd/plasticine-gate tool-lock tool-lock.json

scripts/build-release.sh "$first_build"
go run ./cmd/plasticine-gate artifacts "$first_build"

scripts/build-release.sh "$second_build"
go run ./cmd/plasticine-gate artifacts "$second_build"
go run ./cmd/plasticine-gate compare-manifests "$first_build" "$second_build"

PLASTICINE_BINARY="$first_build/plasticine_$(go env GOOS)_$(go env GOARCH)" \
        PLASTICINE_EXPECT_VERSION="$version" \
        PLASTICINE_EXPECT_COMMIT="$commit" \
        PLASTICINE_EXPECT_COMMIT_TIME="$commit_time" \
        scripts/smoke.sh
