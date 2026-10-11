#!/bin/bash
# Scenario B: the pinned odinfmt agrees with the `format` rule on real code. The code is odx's own
# sources at HEAD, and also the repo E2E_REPO names, formatting its directories E2E_DIRS.
. "$(dirname "$0")/lib.sh"

# Findings of other rules are not this scenario's business, so exit 1 passes too.
check() { step "$1" 0 sh -c 'odx check --json --pending; [ $? -le 1 ]'; }
own="odx tests/runner tests/selection tests/fixture_fmt"
mkdir "$S/repo"
(cd "$root" && git archive HEAD $own odx.json odinfmt.json) | tar -x -C "$S/repo"
cp -R "$S/repo" "$S/formatted"
cd "$S/formatted"
format "odinfmt over odx's sources at HEAD" $own
# odinfmt also rewrites the vendored printer under odx/, which stays as upstream wrote it.
step "odinfmt changed no file of odx's own" 0 diff -rq -x ols_printer "$S/repo" "$S/formatted"
check "odx check there has no format finding"
json 'n("format") == 0 and d["errors"] == []'
cp -R "$S/formatted" "$S/again"
format "odinfmt a second time" $own
step "the second format changed nothing" 0 diff -rq "$S/again" "$S/formatted"

if [ -z "${E2E_REPO:-}" ]; then
	echo "b: the external repo part was not run: E2E_REPO is unset"
	echo "b: passed"
	exit 0
fi
if [ ! -d "$E2E_REPO" ] || [ -z "${E2E_DIRS:-}" ]; then
	echo "e2e: E2E_REPO must name a directory, and E2E_DIRS its own source directories" >&2
	exit 2
fi
by_rule() {
	python3 -c '
import collections, json, sys
rules = collections.Counter(f["rule"] for f in json.load(open(sys.argv[1]))["findings"])
print("b:   " + (", ".join(f"{n} {rule}" for rule, n in rules.most_common()) or "no findings"))' "$S/out"
}
T=300
cp -R "$E2E_REPO" "$S/ext"
cd "$S/ext"
if [ -e odx.json ]; then
	cp "$root/odinfmt.json" odinfmt.json
else
	step "odx init in a copy of E2E_REPO" 0 odx init
fi
check "odx check before formatting, findings by rule"
by_rule
format "odinfmt over $E2E_DIRS" $E2E_DIRS
check "odx check after formatting, findings by rule"
by_rule
json 'n("format") == 0 and d["errors"] == []'
cp -R "$S/ext" "$S/ext-again"
format "odinfmt a second time" $E2E_DIRS
step "the second format changed nothing" 0 diff -rq "$S/ext-again" "$S/ext"
echo "b: passed"
