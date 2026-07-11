#!/bin/sh

set -eu

root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
first_build="$(mktemp -d)"
second_build="$(mktemp -d)"

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

PLASTICINE_BINARY="$first_build/plasticine_$(go env GOOS)_$(go env GOARCH)" scripts/smoke.sh
