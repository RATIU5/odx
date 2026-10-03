#!/bin/sh
# Runs the 80 `odin check` commands odx runs on the perf fixture, in parallel, as the floor odx's
# own time is measured against. Prints nothing and exits 0 when every check exits 0 with empty
# stderr. Time it from outside with `/usr/bin/time -l`.
# Usage: floor.sh <fixture repo>
set -eu

repo=$(cd "$1" && pwd -P)
jobs=$(sysctl -n hw.ncpu 2>/dev/null || nproc)

for dir in "$repo"/p*/; do
	for target in darwin_arm64 linux_amd64; do
		printf '%s\0%s\0' "${dir%/}" "$target"
	done
done | xargs -0 -P "$jobs" -n 2 sh -c '
	name=$(basename "$1")
	# Any stderr is a finding or a crash, so it fails the floor like a non-zero exit.
	if err=$(odin check "$1" -json-errors -max-error-count:1000000 -thread-count:1 \
		-ignore-unused-defineables -target:"$2" -no-entry-point -vet -vet-cast -strict-style \
		-vet-packages:"$name" -strict-style-packages:"$name" 2>&1 >/dev/null) && [ -z "$err" ]; then
		exit 0
	fi
	printf "floor: odin check %s -target:%s failed\n%s\n" "$1" "$2" "$err" >&2
	exit 1
' floor
