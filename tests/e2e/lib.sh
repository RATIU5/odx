# shellcheck shell=bash
# Shared setup for the e2e scenarios. Each scenario sources this file, which installs the release
# odx and the README's odinfmt into build/e2e/bin and puts that directory first on PATH. $E is
# build/e2e, which outlives the run. $S is the scenario's own temp directory, removed on exit. It
# is outside this repo because odx takes the nearest odx.json above the working directory as the
# repo root, so under build/ every scenario repo would be read as part of odx itself.
# The odinfmt comes from tests/e2e/odinfmt.sh.
# Exit codes: 1 a failed assertion, 2 a missing tool or a bad argument, 3 the formatter's source
# could not be fetched.
set -eu

scenario=$(basename "$0" .sh)
root=$(cd "$(dirname "$0")/../.." && pwd -P)
E=$root/${OUT:-build}/e2e
T=120

for tool in timeout git python3 perl odin; do
	command -v "$tool" >/dev/null && continue
	echo "e2e: '$tool' is not on PATH; every command runs under 'timeout', and odin comes from mise" >&2
	exit 2
done
if [ ! -x "$root/${OUT:-build}/release/odx" ]; then
	echo "e2e: no release binary; run 'mise run release'" >&2
	exit 2
fi
S=$(mktemp -d)
trap 'rm -rf "$S"' EXIT
mkdir -p "$E/bin"
cp "$root/${OUT:-build}/release/odx" "$E/bin/odx"

"$root/tests/e2e/odinfmt.sh"

PATH=$E/bin:$PATH
unset FORCE_COLOR
export PATH NO_COLOR=1 GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
export GIT_AUTHOR_NAME=e2e GIT_AUTHOR_EMAIL=e2e@example.invalid
export GIT_COMMITTER_NAME=e2e GIT_COMMITTER_EMAIL=e2e@example.invalid

# step <label> <wanted exit> <command...> runs the command with stdout in $S/out and stderr in $S/err.
step() {
	label=$1 want=$2
	shift 2
	cmd="$* (in $PWD)"
	echo "$scenario: $label"
	rc=0
	timeout "$T" "$@" >"$S/out" 2>"$S/err" </dev/null || rc=$?
	[ "$rc" = "$want" ] || fail "exit $rc, wanted $want (124 is the ${T}s timeout)"
}

fail() {
	echo "FAIL $scenario: $label: $1"
	echo "command: $cmd"
	echo "--- stdout"
	cat "$S/out"
	echo "--- stderr"
	cat "$S/err"
	exit 1
} >&2

has() { grep -qF -- "$2" "$S/$1" || fail "$1 lacks '$2'"; }
lacks() { ! grep -qF -- "$2" "$S/$1" || fail "$1 has '$2'"; }
empty() { [ ! -s "$S/$1" ] || fail "$1 isn't empty"; }

# json <python expression> asserts it over the last stdout: d is the document, F its findings, H the
# held-back ones and n(rule) a count.
json() {
	python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
F = d["findings"]
H = [f for f in F if f.get("held_back")]
n = lambda rule: sum(f["rule"] == rule for f in F)
sys.exit(not eval(sys.argv[2]))' "$S/out" "$1" || fail "stdout as JSON fails: $1"
}

# odinfmt takes one path per call.
format() {
	what=$1
	shift
	# shellcheck disable=SC2016 # the inner sh expands $dir
	step "$what" 0 sh -c 'for dir; do odinfmt -w "$dir" || exit; done' sh "$@"
}
