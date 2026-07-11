#!/bin/sh

set -eu

out_dir="${1:-dist}"
module="github.com/Plasticine-Yang/plasticine-dotfiles"
version="${PLASTICINE_VERSION:-$(git describe --tags --exact-match 2>/dev/null || printf '%s' dev)}"
commit="${PLASTICINE_COMMIT:-$(git rev-parse HEAD 2>/dev/null || printf '%s' unknown)}"
commit_time="${PLASTICINE_COMMIT_TIME:-$(git show -s --format=%cI HEAD 2>/dev/null || printf '%s' 1970-01-01T00:00:00Z)}"
ldflags="-buildid= -s -w -X ${module}/internal/version.version=${version} -X ${module}/internal/version.commit=${commit} -X ${module}/internal/version.commitTime=${commit_time}"

tag="$(git describe --tags --exact-match 2>/dev/null || true)"
if [ "$tag" ] && [ "$version" != "$tag" ]; then
	printf '%s\n' "tag/version mismatch: tag=$tag version=$version" >&2
	exit 1
fi
case "$version" in
	dev | v[0-9]*.[0-9]*.[0-9]*) ;;
	*)
		printf '%s\n' "version must be dev or SemVer tag vX.Y.Z: $version" >&2
		exit 1
		;;
esac

mkdir -p "$out_dir"
rm -f "$out_dir"/plasticine_* "$out_dir"/checksums.txt

build_target() {
	os_name="$1"
	arch_name="$2"
	output="$out_dir/plasticine_${os_name}_${arch_name}"
	CGO_ENABLED=0 GOOS="$os_name" GOARCH="$arch_name" go build -mod=readonly -trimpath -buildvcs=false -ldflags "$ldflags" -o "$output" ./cmd/plasticine
	chmod 0755 "$output"
}

build_target darwin amd64
build_target darwin arm64
build_target linux amd64
build_target linux arm64

(
	cd "$out_dir"
	for artifact in plasticine_*; do
		if command -v sha256sum >/dev/null 2>&1; then
			sha256sum "$artifact"
		else
			shasum -a 256 "$artifact"
		fi
	done | sort > checksums.txt
)

go run ./cmd/plasticine-gate artifacts "$out_dir" >/dev/null 2>&1 || {
	go run ./cmd/plasticine-gate artifacts "$out_dir"
	exit 1
}
