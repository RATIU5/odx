#!/bin/bash
# Scenario A: a new small repo through the README's Workflow, from the first `odx check` to exit 0.
# The repo is tests/fixtures/e2e/repo: a library, a `main`, a package for one platform and a
# vendored tree, with rule breaks in each. c.sh clones the finished repo from the bare
# build/e2e/a.git.
. "$(dirname "$0")/lib.sh"

# edit <file> <text> <replacement> fails when the file doesn't hold the text.
edit() {
	FROM=$2 TO=$3 perl -0pi -e '$n = s/\Q$ENV{FROM}\E/$ENV{TO}/; END { $? = 1 unless $n }' "$1" ||
		fail "$1 doesn't hold: $2"
}
strict() {
	python3 -c '
import json, sys
d = json.load(open("odx.json"))
del d["pending"][sys.argv[1]]
json.dump(d, open("odx.json", "w"), indent="\t")' "$1"
}
own="geometry app macos_paths"

cp -R "$root/tests/fixtures/e2e/repo" "$S/repo"
cd "$S/repo"
git init -q .
git add -A
git commit -qm "initial import"

step "odx --help" 0 odx --help
has out "odx check [--json] [--pending]"
step "odx --version" 0 odx --version
has out "odx $(odx --version | cut -d' ' -f2) rule set "
has out "odin $(odin version | cut -d' ' -f3)"

step "odx check with no odx.json: every package strict" 1 odx check
has err "odx: no odx.json"
has out "app/main.odin:17:15: odin: "
has out "geometry/geometry.odin:3:1: format: "
has out "vendor/tinyfmt/tinyfmt.odin"
lacks out "do-stmt"

step "odx init" 0 odx init
has out "init: 1 strict, 2 pending, 1 vendored, 0 skipped"
step "odx init wrote the odinfmt.json the odx repo formats with" 0 cmp odinfmt.json "$root/odinfmt.json"
step "odx init again writes nothing" 2 odx init
has err "odx: error: init-exists: "
empty out

step "odx check: only the strict package's findings" 1 odx check
has out "app/main.odin:17:15: odin: "
lacks out "geometry/"
lacks out "vendor/"
has out "odx: 1 findings, 0 ignored, 2 pending, 0 skipped"
step "odx check --pending: the held-back findings too" 1 odx check --pending
has err "odx: held-back findings:"
has out "geometry/geometry.odin:3:1: format: "
has out "macos_paths/paths.odin:9:2: odin: "
has out "odx: 1 findings, 0 ignored, 2 pending, 0 skipped"
step "odx check --json" 1 odx check --json
json 'len(F) == 1 and F[0]["rule"] == "odin" and not H and d["summary"]["pending"] == 2'
step "odx check --json --pending: held-back findings carry held_back" 1 odx check --json --pending
json 'n("format") == 2 and len(H) == len(F) - 1'
json 'all(f["path"].startswith(("geometry/", "macos_paths/")) for f in H)'
json 'all("held_back" not in f for f in F if f["path"].startswith("app/"))'
step "so far odx wrote odx.json and odinfmt.json and nothing else" 0 git status --porcelain --ignored
[ "$(tr '\n' ' ' <"$S/out")" = "?? odinfmt.json ?? odx.json " ] || fail "other paths are new or changed"
git add -A
git commit -qm "odx init"

format "format with the pinned odinfmt and the written odinfmt.json" $own
step "no format finding is left" 1 odx check --json --pending
json 'n("format") == 0'
git commit -qam "format"
format "format again" $own
step "the second format changed nothing" 0 git status --porcelain
empty out

perl -pi -e 's/\bMaxShapes\b/MAX_SHAPES/g; s/\btotalArea\b/total_area/g' geometry/*.odin app/*.odin
step "naming fixed in the pending library" 1 odx check --pending
lacks out "MaxShapes"
lacks out "totalArea"
has out "name-case: package-level literal variable 'kind_names'"

strict macos_paths
step "the darwin-only package as strict" 1 odx check
has out "macos_paths/paths.odin:"
has out ": odin: 'sep' declared but not used"
perl -ni -e 'print unless /sep := /' macos_paths/paths.odin
step "the darwin-only package fixed" 1 odx check
lacks out "macos_paths/"
has out "0 skipped"

edit app/main.odin 'count: int = "two"' 'count: int = 2'
step "the compile error fixed shows the finding it hid" 1 odx check
has out "app/main.odin:"
has out ": import-order: "
lacks out "do-stmt"
edit app/main.odin $'import "../geometry"\nimport "core:fmt"\nimport "core:os"\n' \
	$'import "core:fmt"\nimport "core:os"\n\nimport "../geometry"\n'
format "format after the import fix" $own
step "main is clean, the library still pending" 0 odx check
has out "odx: 0 findings, 0 ignored, 1 pending, 0 skipped"

edit geometry/geometry.odin $'/*\n\tShapes used by the app. Areas are in square units.\n*/' \
	'// Shapes used by the app. Areas are in square units.'
edit geometry/geometry.odin 'if factor <= 0 {return}' $'if factor <= 0 {\n\t\treturn\n\t}'
edit geometry/geometry.odin 'kind_names := ' $'// odx:ignore name-case\nkind_names := '
step "an ignore with no reason is a held-back finding" 0 odx check --pending
has err "odx: held-back findings:"
has out ": ignore-invalid: "
has out "name-case: package-level literal variable 'kind_names'"
edit geometry/geometry.odin $'ignore name-case\n' $'ignore name-case filled at startup on some targets\n'
step "the library has nothing left, so its pending entry is stale" 1 odx check
has out "odx.json:"
has out ": pending-stale: 'geometry'"
strict geometry
format "format before the last check" $own
step "odx check: every package strict, one ignore, do bodies kept" 0 odx check
has out "odx: 0 findings, 1 ignored, 0 pending, 0 skipped"
step "odx check --json agrees" 0 odx check --json
json 'F == [] and d["errors"] == [] and d["summary"]["ignored"] == 1'
step "the library and main still hold a do body" 0 grep -c ' do ' geometry/geometry.odin app/main.odin
lacks out ":0"

git commit -qam "strict everywhere"
step "the repo holds nothing but its commits" 0 git status --porcelain --ignored
empty out
rm -rf "$E/a.git"
git clone -q --bare "$S/repo" "$E/a.git"
echo "a: passed"
