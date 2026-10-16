#!/bin/bash
# Scenario C: the CI shape, on the repo a.sh finished. Each of five fresh clones is checked with an
# emptied environment, a minimal PATH, an empty TMPDIR, a fresh HOME and no terminal.
. "$(dirname "$0")/lib.sh"

if [ ! -d "$E/a.git" ]; then
	echo "e2e: no finished repo in $E/a.git; run tests/e2e/a.sh first" >&2
	exit 2
fi
ci_path=$E/bin:$(dirname "$(command -v odin)"):/usr/bin:/bin
mkdir "$S/home" "$S/tmp"

# ci <label> <wanted exit> <clone> <odx arguments...>
ci() {
	clone=$3
	cd "$S/$clone"
	step "$1" "$2" env -i HOME="$S/home" TMPDIR="$S/tmp" PATH="$ci_path" odx "${@:4}"
	left=$(find "$S/home" "$S/tmp" -mindepth 1)
	[ -z "$left" ] || fail "odx left files in HOME or TMPDIR: $left"
}

for i in 1 2 3 4 5; do
	step "fresh clone $i" 0 git clone -q "$E/a.git" "$S/clone$i"
	ci "clone $i: odx check" 0 "clone$i" check
	cp "$S/out" "$S/text$i"
	[ "$(wc -l <"$S/out")" -eq 1 ] || fail "stdout holds more than the summary"
	has out "odx: 0 findings, 1 ignored, 0 pending, 0 skipped"
	cmp -s "$S/text1" "$S/text$i" || fail "stdout differs from clone 1's"
	ci "clone $i: odx check --json" 0 "clone$i" check --json
	cp "$S/out" "$S/json$i"
	json 'F == [] and d["errors"] == []'
	cmp -s "$S/json1" "$S/json$i" || fail "the JSON differs from clone 1's"
	step "clone $i: odx wrote nothing into it" 0 git -C "$S/clone$i" status --porcelain --ignored
	empty out
done

printf '\nbadName :: proc() {}\n' >>"$S/clone1/geometry/geometry.odin"
ci "a broken file: exit 1 and its finding" 1 clone1 check
has out "geometry/geometry.odin:"
has out ": name-case: procedure 'badName'"
has out "odx: 1 findings, "

printf '{"version": 2, "odin": ' >"$S/clone2/odx.json"
ci "a corrupt odx.json: exit 2 and an empty stdout" 2 clone2 check
empty out
has err "odx: error: config-invalid: "
echo "c: passed"
