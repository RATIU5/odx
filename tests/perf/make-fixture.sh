#!/bin/sh
# Creates the 40-package perf fixture repo: packages p01 to p40, each clean under odx's strict check
# on both targets and about as costly to check as any package that imports core:fmt. With
# --findings, each package also has one 101-column line, a finding that pending can hold back.
# Usage: make-fixture.sh [--findings] <dir>
set -eu

findings=false
if [ "$1" = --findings ]; then
	findings=true
	shift
fi
dir=$1
if [ -e "$dir" ] && [ -n "$(ls -A "$dir")" ]; then
	echo "make-fixture: $dir exists and isn't empty" >&2
	exit 1
fi
mkdir -p "$dir"
git -C "$dir" init -q

version=$(odin version)
printf '{"version": 2, "odin": "%s"}\n' "${version#odin version }" >"$dir/odx.json"

for n in $(seq -w 1 40); do
	p=p$n
	mkdir "$dir/$p"
	/bin/cat >"$dir/$p/item.odin" <<ODIN
package $p

import "core:strings"

Item :: struct {
	name:  string,
	count: int,
}

make_item :: proc(name: string, count: int) -> Item {
	return Item{name = strings.to_upper(name, context.temp_allocator), count = count}
}
ODIN
	/bin/cat >"$dir/$p/total.odin" <<ODIN
package $p

import "core:slice"

sort_items :: proc(items: []Item) {
	slice.sort_by(items, proc(a, b: Item) -> bool {
		return a.count < b.count
	})
}

total :: proc(items: []Item) -> (sum: int) {
	for item in items {
		sum += item.count
	}
	return
}
ODIN
	/bin/cat >"$dir/$p/report.odin" <<ODIN
package $p

import "core:fmt"

report :: proc(items: []Item) -> string {
	sort_items(items)
	return fmt.tprintf("$p: %d items, total %d", len(items), total(items))
}
ODIN
	if $findings; then
		printf '\nLONG :: "%s"\n' "$(printf '%091d' 0)" >>"$dir/$p/report.odin"
	fi
done
