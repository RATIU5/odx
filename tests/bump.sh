#!/usr/bin/env bash
# Rewrites the compiler pin and the rule set in the test fixtures for a compiler bump; lists the changes by category, and writes them only with --apply.
set -euo pipefail
if [ $# -lt 4 ]; then
	echo "usage: tests/bump.sh <old odin> <new odin> <old rule set> <new rule set> [--apply]" >&2
	exit 2
fi
cd "$(dirname "$0")"
exec python3 - "$@" <<'EOF'
import collections, os, re, sys

old_odin, new_odin, old_set, new_set = sys.argv[1:5]
apply = sys.argv[5:] == ["--apply"]
VERSION = (r'("version"\s*:\s*)%s(?!\d)' % old_set, r"\g<1>" + new_set)
ODIN = (re.escape(old_odin), new_odin)
# Category, which lines of which files it reads, and the one rewrite it makes there.
CONFIG = [
    ("odx.json: the compiler", ODIN),
    ('odx.json: "version"', VERSION),
]
EXPECTED = [
    ('expected: "rules N" in the summary', (r"\(rules %s, odx " % old_set, "(rules %s, odx " % new_set)),
    ('expected: "rules" in the JSON summary', (r'"rules":%s,"release"' % old_set, '"rules":%s,"release"' % new_set)),
    ('expected: "rule set N" in a message', (r"rule set %s(?!\d)" % old_set, "rule set " + new_set)),
]
WRITTEN = [('expected: "version" in the odx.json a command wrote', VERSION)]
SCRIPTS = [('scripts that write an odx.json: "version"', VERSION)]

counts = collections.Counter()
files = collections.defaultdict(set)
samples = {}


def rewrite(path, categories_of):
    with open(path, encoding="utf-8", errors="surrogateescape", newline="") as f:
        lines = f.readlines()
    written = False
    changed = False
    for i, line in enumerate(lines):
        if line.startswith("--- "):
            written = line.startswith("--- odx.json")
        for name, (pattern, replacement) in categories_of(written):
            new = re.sub(pattern, replacement, line)
            if new != line:
                counts[name] += 1
                files[name].add(path)
                samples.setdefault(name, (path, i + 1, line.rstrip("\n"), new.rstrip("\n")))
                line = new
                changed = True
        lines[i] = line
    if changed and apply:
        with open(path, "w", encoding="utf-8", errors="surrogateescape", newline="") as f:
            f.writelines(lines)


for root, dirs, names in os.walk("golden"):
    dirs.sort()
    for name in sorted(names):
        path = os.path.join(root, name)
        if not os.path.isfile(path) or os.path.islink(path):
            continue
        if name == "odx.json":
            rewrite(path, lambda written: CONFIG)
        elif name == "expected" and root.count(os.sep) == 1:
            rewrite(path, lambda written: WRITTEN if written else EXPECTED)
for path in ["e2e/c.sh", "perf/make-fixture.sh"]:
    rewrite(path, lambda written: SCRIPTS)

for name, _ in CONFIG + EXPECTED + WRITTEN + SCRIPTS:
    print("%5d lines in %3d files  %s" % (counts[name], len(files[name]), name))
    if name in samples:
        path, number, before, after = samples[name]
        print("      first: %s:%d\n        - %s\n        + %s" % (path, number, before, after))
print("written" if apply else "dry run; pass --apply to write")
EOF
