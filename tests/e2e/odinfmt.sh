#!/bin/bash
# Builds the README's odinfmt into build/e2e/bin/odinfmt, for tests/e2e/lib.sh and dist/dist.sh.
# It clones OLS at the commit odx/ols_printer/README.md names and builds with the odin on PATH, for
# the minimum macOS that mise.toml sets as MACOS_MIN. The binary is kept with a stamp,
# build/e2e/odinfmt.built, that holds the commit, the minimum and `odin version`, so a later run
# does nothing until one of them changes.
# Exit codes: 1 the build failed or the two READMEs disagree, 2 a missing tool or no MACOS_MIN,
# 3 the formatter's source could not be fetched.
set -eu

root=$(cd "$(dirname "$0")/../.." && pwd -P)
E=$root/${OUT:-build}/e2e

for tool in timeout git odin; do
	command -v "$tool" >/dev/null && continue
	echo "e2e: '$tool' is not on PATH; the formatter build needs it, and odin comes from mise" >&2
	exit 2
done
if [ -z "${MACOS_MIN:-}" ]; then
	echo "e2e: MACOS_MIN is not set; mise.toml sets it, so run this through mise" >&2
	exit 2
fi

# odx/ols_printer/README.md is where a printer bump records the commit, so README.md must follow it.
# shellcheck disable=SC2016 # the backticks are the README table's own
commit=$(sed -n 's/^| OLS commit | `\([0-9a-f]\{40\}\)` |$/\1/p' "$root/odx/ols_printer/README.md")
if [ "$(grep -o '[0-9a-f]\{40\}' "$root/README.md" | sort -u)" != "$commit" ]; then
	echo "e2e: README.md and odx/ols_printer/README.md name different OLS commits" >&2
	exit 1
fi
built="$commit $MACOS_MIN $(odin version)"
if [ -x "$E/bin/odinfmt" ] && [ "$(cat "$E/odinfmt.built" 2>/dev/null)" = "$built" ]; then
	exit 0
fi

# Only the binary is kept: `mise run self` checks every .odin file under build/, so the OLS checkout
# can't stay there.
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
mkdir -p "$E/bin"
rm -f "$E/bin/odinfmt"
if ! timeout 300 git clone -q https://github.com/DanielGavin/ols "$W/ols" >"$E/ols.log" 2>&1; then
	echo "e2e: could not fetch the formatter: git clone of DanielGavin/ols failed, see $E/ols.log" >&2
	exit 3
fi
if ! (cd "$W/ols" && git checkout -q "$commit" && timeout 300 ./odinfmt.sh "-minimum-os-version:$MACOS_MIN") >>"$E/ols.log" 2>&1; then
	echo "e2e: could not build odinfmt at $commit, see $E/ols.log" >&2
	exit 1
fi
cp "$W/ols/odinfmt" "$E/bin/odinfmt"
echo "$built" >"$E/odinfmt.built"
echo "e2e: built odinfmt at OLS $commit"
