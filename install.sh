#!/bin/sh

set -eu

repo="Plasticine-Yang/plasticine-dotfiles"
download_base="${PLASTICINE_DOWNLOAD_BASE:-https://github.com/$repo/releases}"
plasticine_home="${PLASTICINE_HOME:-$HOME/.plasticine}"
version="${PLASTICINE_VERSION:-}"

detect_os() {
	if [ "${PLASTICINE_OS:-}" ]; then
		printf '%s\n' "$PLASTICINE_OS"
		return 0
	fi
	case "$(uname -s)" in
		Darwin) printf '%s\n' "darwin" ;;
		Linux) printf '%s\n' "linux" ;;
		*) return 1 ;;
	esac
}

detect_arch() {
	if [ "${PLASTICINE_ARCH:-}" ]; then
		printf '%s\n' "$PLASTICINE_ARCH"
		return 0
	fi
	case "$(uname -m)" in
		x86_64 | amd64) printf '%s\n' "amd64" ;;
		arm64 | aarch64) printf '%s\n' "arm64" ;;
		*) return 1 ;;
	esac
}

sha256_file() {
	path="$1"
	if command -v sha256sum >/dev/null 2>&1; then
		sha256sum "$path" | awk '{print $1}'
		return 0
	fi
	if command -v shasum >/dev/null 2>&1; then
		shasum -a 256 "$path" | awk '{print $1}'
		return 0
	fi
	printf '%s\n' "no sha256 tool found" >&2
	return 1
}

download() {
	url="$1"
	output="$2"
	curl -fsSL "$url" -o "$output"
}

asset_base_url() {
	if [ "$version" ]; then
		printf '%s\n' "$download_base/download/$version"
	else
		printf '%s\n' "$download_base/latest/download"
	fi
}

os_name="$(detect_os)" || {
	printf '%s\n' "unsupported operating system" >&2
	exit 1
}
arch_name="$(detect_arch)" || {
	printf '%s\n' "unsupported architecture" >&2
	exit 1
}

case "$os_name/$arch_name" in
	darwin/amd64 | darwin/arm64 | linux/amd64 | linux/arm64) ;;
	*)
		printf '%s\n' "unsupported artifact target: $os_name/$arch_name" >&2
		exit 1
		;;
esac

binary_name="plasticine_${os_name}_${arch_name}"
base_url="$(asset_base_url)"
work_dir="$plasticine_home/bootstrap"
candidate="$work_dir/$binary_name"
manifest="$work_dir/checksums.txt"

mkdir -p "$work_dir"
rm -f "$candidate" "$candidate.partial" "$manifest" "$manifest.partial"

download "$base_url/$binary_name" "$candidate.partial"
download "$base_url/checksums.txt" "$manifest.partial"
mv "$candidate.partial" "$candidate"
mv "$manifest.partial" "$manifest"

expected="$(awk -v name="$binary_name" '$2 == name { print $1 }' "$manifest")"
if [ -z "$expected" ]; then
	printf '%s\n' "checksum manifest missing $binary_name" >&2
	exit 1
fi
actual="$(sha256_file "$candidate")"
if [ "$actual" != "$expected" ]; then
	printf '%s\n' "checksum mismatch for $binary_name" >&2
	exit 1
fi

chmod 0755 "$candidate"
exec "$candidate" __candidate-self-install "$@"
