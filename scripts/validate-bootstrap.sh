#!/bin/sh

set -eu

sh -n install.sh

if command -v shellcheck >/dev/null 2>&1; then
	shellcheck -s sh install.sh
elif [ "${REQUIRE_SHELLCHECK:-0}" = "1" ]; then
	printf '%s\n' "shellcheck is required but was not found" >&2
	exit 1
else
	printf '%s\n' "shellcheck not found; POSIX syntax validation passed"
fi
