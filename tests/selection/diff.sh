#!/bin/sh
# Compares the files odx predicts `odin check` compiles with the files the compiler compiles, per
# package dir under tests/fixtures/target-selection and per target. Every fixture file declares its
# own ill-typed variable, so the compiler names each file it compiled in one error.
# Usage: diff.sh <selection binary>
set -eu

selection=$1
fixtures=$(cd "$(dirname "$0")/../fixtures/target-selection" && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

perl -e 'alarm shift; exec @ARGV' 60 "$selection" "$fixtures" >"$work/odx.txt"

: >"$work/odin.txt"
for dir in "$fixtures"/*/; do
	dir=${dir%/}
	name=$(basename "$dir")
	for target in darwin_arm64 linux_amd64; do
		# The compiler exits 1 here by design, so only its output counts.
		perl -e 'alarm shift; exec @ARGV' 120 odin check "$dir" -no-entry-point -thread-count:1 \
			-max-error-count:1000000 -target:"$target" >"$work/check.txt" 2>&1 || true
		if grep -E '^/[^(]*\.odin\([0-9]+:[0-9]+\) ' "$work/check.txt" | grep -qv "Cannot convert '\""; then
			echo "selection: odin check $name -target:$target reported an error other than a fixture variable:" >&2
			cat "$work/check.txt" >&2
			exit 1
		fi
		files=$(sed -n -E 's|^(/[^(]*\.odin)\([0-9]+:[0-9]+\) .*|\1|p' "$work/check.txt" | xargs -n1 basename | LC_ALL=C sort | tr '\n' ' ')
		echo "$name $target $files" | sed 's/ *$//' >>"$work/odin.txt"
	done
done

if diff -u --label compiler "$work/odin.txt" --label odx "$work/odx.txt"; then
	echo "selection: odx matches the compiler on $(wc -l <"$work/odin.txt" | tr -d ' ') package targets"
else
	echo "selection: odx differs from the compiler" >&2
	exit 1
fi
