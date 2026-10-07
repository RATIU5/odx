#!/bin/sh
# Generates the universe table for the running compiler, formats it until a print leaves it
# unchanged, and fails when it differs from odx/universe.odin. The diff names each entry that
# differs. The generated file stays in <out dir>, ready to copy over on a compiler bump. Its name
# doesn't end in .odin, so the directory doesn't become a package.
# Usage: diff.sh <universe binary> <fixture-fmt binary> <out dir>
set -eu

generated=$3/universe.odin.generated
version=$(odin version)
perl -e 'alarm shift; exec @ARGV' 60 "$1" "$(odin root)" "${version#odin version }" >"$generated"

prints=0
while :; do
	printed=$(perl -e 'alarm shift; exec @ARGV' 60 "$2" "$generated")
	if [ -z "$printed" ]; then
		break
	fi
	prints=$((prints + 1))
	if [ "$prints" -gt 8 ]; then
		echo "universe: the formatter keeps changing $generated" >&2
		exit 1
	fi
done

if ! diff -u odx/universe.odin "$generated"; then
	echo "universe: odx/universe.odin differs from the table generated for $version in $generated" >&2
	exit 1
fi
