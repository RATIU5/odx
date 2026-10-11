package odx

import "base:runtime"
import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:slice"
import "core:strconv"
import "core:strings"

Entry_Kind :: enum u8 {
	Error,
	Warning,
}

// One compiler diagnostic as the compiler reported it.
Compiler_Entry :: struct {
	kind: Entry_Kind,
	// The compiler's absolute path, or "" for a null `pos`.
	file: string,
	line: int,
	col:  int,
	msgs: []string,
}

Clean :: struct {}

Diagnostics :: struct {
	entries: []Compiler_Entry,
}

// `reason` completes "checking <package> for <target> ...", and is "" for a check that timed out,
// whose message names the limit. `unread` says odx has no stderr to show, because it couldn't run
// the check or read what the check wrote.
Untrusted :: struct {
	reason: string,
	stderr: string,
	unread: bool,
}

// The caller attaches the package and the target.
Check_Outcome :: union {
	Clean,
	Diagnostics,
	Untrusted,
}

// Decides one check's outcome from how it ended and its stderr alone, per the table in Appendix
// E.4. `stderr` is all the check wrote, so an empty one with exit code 0 is a clean check.
// `retried` says this is the check's second run, which the pool gives a check that a signal ended.
// The outcome borrows `stderr` and allocates the rest with `allocator`.
read_check :: proc(
	status: Child_Status,
	timed_out: bool,
	retried: bool,
	stderr: string,
	allocator: runtime.Allocator,
) -> Check_Outcome {
	context.allocator = allocator
	if timed_out {
		return Untrusted{stderr = stderr}
	}
	exit_code: int
	switch s in status {
	case Signaled:
		reason := fmt.aprintf("died by signal %d%s", s.signal, " twice" if retried else "")
		return Untrusted{reason = reason, stderr = stderr}
	case Exited:
		exit_code = s.code
	}
	switch {
	case exit_code != 0 && exit_code != 1:
		return Untrusted {
			reason = fmt.aprintf("ended with exit code %d", exit_code),
			stderr = stderr,
		}
	case stderr == "" && exit_code == 0:
		return Clean{}
	}
	entries, error_count, readable := read_document(stderr)
	if !readable {
		return Untrusted {
			reason = fmt.aprintf(
				"exited %d without one compiler JSON document on stderr",
				exit_code,
			),
			stderr = stderr,
		}
	}
	errors := 0
	for entry in entries {
		if entry.kind == .Error {
			errors += 1
		}
	}
	switch {
	case exit_code == 0 && errors > 0:
		return Untrusted {
			reason = fmt.aprintf("exited 0 but reported %d errors", errors),
			stderr = stderr,
		}
	case exit_code == 1 && errors == 0:
		return Untrusted{reason = "exited 1 but reported no error", stderr = stderr}
	case exit_code == 1 && error_count != len(entries):
		reason := fmt.aprintf(
			"exited 1 with error_count %d for %d entries",
			error_count,
			len(entries),
		)
		return Untrusted{reason = reason, stderr = stderr}
	}
	return Diagnostics{entries}
}

// `json.parse` accepts trailing data, so the document counts only when the parser reaches the end
// of input (probe R-H).
@(private = "file")
read_document :: proc(stderr: string) -> (entries: []Compiler_Entry, error_count: int, ok: bool) {
	p := json.make_parser(stderr, .JSON, true)
	value, err := json.parse_value(&p)
	if err != nil || p.curr_token.kind != .EOF {
		return
	}
	root := value.(json.Object) or_return
	count := root["error_count"].(json.Integer) or_return
	list := root["errors"].(json.Array) or_return
	result := make([]Compiler_Entry, len(list))
	for item, i in list {
		result[i] = read_entry(item) or_return
	}
	return result, int(count), true
}

// Syntax errors and missing imports arrive typed as warnings (probe R-A), so the first message
// decides.
@(private = "file")
read_entry :: proc(item: json.Value) -> (entry: Compiler_Entry, ok: bool) {
	object := item.(json.Object) or_return
	kind := object["type"].(json.String) or_return
	list := object["msgs"].(json.Array) or_return
	if len(list) == 0 {
		return
	}
	msgs := make([]string, len(list))
	for m, i in list {
		msgs[i] = m.(json.String) or_return
	}
	entry.msgs = msgs
	entry.kind =
		.Error if kind == "error" || strings.has_prefix(msgs[0], "Syntax Error:") else .Warning
	#partial switch pos in object["pos"] {
	case json.Null:
	case json.Object:
		entry.file = pos["file"].(json.String) or_return
		entry.line = int(pos["line"].(json.Integer) or_return)
		entry.col = int(pos["column"].(json.Integer) or_return)
	case:
		return
	}
	return entry, true
}

ODIN_ROOT_PREFIX :: "$ODIN_ROOT/"

// Where code lives, built once per run.
Code_Map :: struct {
	// Real paths without a trailing `/`.
	repo_root: string,
	odin_root: string,
	// Every discovered package by dir. Only strict and pending packages are discovered, so a path
	// outside them has no owner. The pointers borrow the slice passed to `make_code_map`.
	packages:  map[string]^Package,
	// Cleaned `vendored` dirs, repo-relative.
	vendored:  []string,
}

// Realpaths both roots, because the compiler reports real paths. Allocates with `allocator`. The
// map borrows pointers into `packages`, so the array behind it must outlive the Code_Map and must
// not grow or move.
make_code_map :: proc(
	repo_root, odin_root: string,
	packages: []Package,
	vendored: []string,
	allocator: runtime.Allocator,
) -> Code_Map {
	context.allocator = allocator
	code := Code_Map {
		repo_root = real_root(repo_root, allocator),
		odin_root = real_root(odin_root, allocator),
		packages  = make(map[string]^Package, len(packages)),
		vendored  = make([]string, len(vendored)),
	}
	for &p in packages {
		code.packages[p.dir] = &p
	}
	for dir, i in vendored {
		code.vendored[i], _ = os.clean_path(dir, allocator)
	}
	return code
}

// Returns the real path, or `path` when it has none, without a trailing `/`. Allocates with
// `allocator`.
real_root :: proc(path: string, allocator: runtime.Allocator) -> string {
	real, err := os.get_absolute_path(path, allocator)
	if err != nil {
		real = path
	}
	return strings.trim_right(real, "/") if real != "/" else real
}

Placed :: struct {
	using located: Located,
	message:       string,
	relocated:     bool,
}

// Applies Appendix E.4's normalization, in its order, to one entry of `checked`'s check. Allocates
// with `allocator`.
normalize :: proc(
	entry: Compiler_Entry,
	code: Code_Map,
	checked: Package,
	allocator: runtime.Allocator,
) -> (
	placed: Placed,
) {
	context.allocator = allocator
	message := join_msgs(entry.msgs)
	message = delete_ids(message)
	message = rewrite_roots(message, code)

	if entry.file == "" {
		placed.path = checked.files[0].path
		placed.line, placed.col = 1, 1
	} else {
		placed.path = rewrite_roots(entry.file, code)
		placed.line, placed.col = entry.line, max(entry.col, 1)
		if entry.line == 0 {
			placed.line, placed.col = 1, 1
		}
	}

	if in_odin_root_or_vendored(placed.path, code) {
		if caller, found := last_owned_caller(entry.msgs, code); found {
			message = fmt.aprintf(
				"%s (reported at %s:%d:%d)",
				message,
				placed.path,
				placed.line,
				placed.col,
			)
			placed.located = caller
			placed.relocated = true
		}
	}

	for file in checked.files {
		if file.link_target != "" && rewrite_roots(file.link_target, code) == placed.path {
			placed.path = file.path
			break
		}
	}
	placed.message = message
	return
}

@(private = "file")
join_msgs :: proc(msgs: []string) -> string {
	b := strings.builder_make()
	for m in msgs {
		line := strings.trim_space(m)
		if line == "" {
			continue
		}
		if strings.builder_len(b) > 0 {
			strings.write_byte(&b, ' ')
		}
		strings.write_string(&b, line)
	}
	return strings.to_string(b)
}

// Deletes each `/* <digits>!<digits> */`, which differs per target and importer (probe R-D), with
// the space before it.
@(private = "file")
delete_ids :: proc(message: string) -> string {
	b := strings.builder_make()
	rest := message
	for {
		i := strings.index(rest, "/* ")
		if i < 0 {
			break
		}
		n := id_length(rest[i:])
		if n == 0 {
			strings.write_string(&b, rest[:i + len("/* ")])
			rest = rest[i + len("/* "):]
			continue
		}
		strings.write_string(&b, strings.trim_suffix(rest[:i], " "))
		rest = rest[i + n:]
	}
	strings.write_string(&b, rest)
	return strings.to_string(b)
}

// The length of the `/* <digits>!<digits> */` that `s` starts with, or 0.
@(private = "file")
id_length :: proc(s: string) -> int {
	i := len("/* ")
	digits :: proc(s: string, i: int) -> int {
		j := i
		for j < len(s) && '0' <= s[j] && s[j] <= '9' {
			j += 1
		}
		return j
	}
	j := digits(s, i)
	if j == i || j >= len(s) || s[j] != '!' {
		return 0
	}
	k := digits(s, j + 1)
	if k == j + 1 || !strings.has_prefix(s[k:], " */") {
		return 0
	}
	return k + len(" */")
}

// Rewrites each path under the repo root as repo-relative and each path under the Odin root as
// `$ODIN_ROOT/...`. The longer root goes first, so a root inside the other is still found. A root
// counts only where a path can start, so `/a/src/x` keeps its text when the repo root is `/src`.
@(private = "file")
rewrite_roots :: proc(text: string, code: Code_Map) -> string {
	first, second := code.repo_root, code.odin_root
	first_with, second_with := "", ODIN_ROOT_PREFIX
	if len(second) > len(first) {
		first, second = second, first
		first_with, second_with = second_with, first_with
	}
	return replace_root(replace_root(text, first, first_with), second, second_with)
}

@(private = "file")
replace_root :: proc(text, root, with: string) -> string {
	if root == "" || root == "/" {
		return text
	}
	needle := strings.concatenate({root, "/"}, context.temp_allocator)
	b := strings.builder_make()
	rest := text
	for {
		i := strings.index(rest, needle)
		if i < 0 {
			break
		}
		offset := len(text) - len(rest) + i
		path_starts := offset == 0 || strings.index_byte(" \t'\"`(", text[offset - 1]) >= 0
		strings.write_string(&b, rest[:i])
		strings.write_string(&b, with if path_starts else needle)
		rest = rest[i + len(needle):]
	}
	strings.write_string(&b, rest)
	return strings.to_string(b)
}

// `path` is a location as `rewrite_roots` leaves it.
@(private = "file")
in_odin_root_or_vendored :: proc(path: string, code: Code_Map) -> bool {
	if strings.has_prefix(path, ODIN_ROOT_PREFIX) {
		return true
	}
	for dir in code.vendored {
		if strings.has_prefix(path, dir) && len(path) > len(dir) && path[len(dir)] == '/' {
			return true
		}
	}
	return false
}

Located :: struct {
	path: string,
	line: int,
	col:  int,
}

// The last `<path>(<line>:<col>) at caller location` line that lies in a strict or pending package.
// It is read from the lines, before they are joined, so a path with spaces still parses.
@(private = "file")
last_owned_caller :: proc(msgs: []string, code: Code_Map) -> (caller: Located, found: bool) {
	#reverse for m in msgs {
		line := strings.trim_space(m)
		located := strings.trim_suffix(line, " at caller location")
		if len(located) == len(line) {
			continue
		}
		c, ok := read_located(located, code)
		if ok && package_dir(c.path) in code.packages {
			return c, true
		}
	}
	return
}

// Reads `<path>(<line>:<col>)` and rewrites the path like a location's.
@(private = "file")
read_located :: proc(text: string, code: Code_Map) -> (located: Located, ok: bool) {
	located = split_located(text) or_return
	located.path = rewrite_roots(located.path, code)
	return located, true
}

// Splits `<path>(<line>:<col>)`, the compiler's way of naming a position inside a message.
split_located :: proc(text: string) -> (located: Located, ok: bool) {
	if !strings.has_suffix(text, ")") {
		return
	}
	open := strings.last_index_byte(text, '(')
	colon := strings.last_index_byte(text, ':')
	if open < 0 || colon < open {
		return
	}
	line := strconv.parse_int(text[open + 1:colon], 10) or_return
	col := strconv.parse_int(text[colon + 1:len(text) - 1], 10) or_return
	return {text[:open], max(line, 1), max(col, 1)}, true
}

// A file's package is its directory, and "." is the root.
package_dir :: proc(path: string) -> string {
	i := strings.last_index_byte(path, '/')
	return path[:i] if i >= 0 else "."
}

// Errors count wherever they lie, because every package must compile. Warnings count only where the
// team owns the code (ADR 0006). `owner` is nil outside every package, and otherwise borrows from
// the `packages` slice behind `code`.
owner_of :: proc(kind: Entry_Kind, path: string, code: Code_Map) -> (owner: ^Package, kept: bool) {
	owner = code.packages[package_dir(path)]
	return owner, kind == .Error || owner != nil
}

// Only the package's own check mutes it, so a package that holds a finding through another
// package's check keeps its rules.
mutes :: proc(kind: Entry_Kind, placed: Placed, checked: Package) -> bool {
	if kind != .Error || placed.relocated {
		return false
	}
	for file in checked.files {
		if file.path == placed.path {
			return true
		}
	}
	return false
}

// One `Redeclaration of 'N' in this scope` entry with the earlier declarations it names, or one
// `Redeclaration of the entry pointer procedure 'N'` entry, which names none.
Redeclaration :: struct {
	name:   string,
	placed: Placed,
	others: []Located,
}

// Returns false for any other entry. Allocates with `allocator`.
read_redeclaration :: proc(
	entry: Compiler_Entry,
	placed: Placed,
	code: Code_Map,
	allocator: runtime.Allocator,
) -> (
	r: Redeclaration,
	ok: bool,
) {
	IN_SCOPE :: "' in this scope"
	ENTRY_POINT :: "Redeclaration of the entry pointer procedure '"
	context.allocator = allocator
	first := entry.msgs[0]
	switch {
	case strings.has_prefix(first, ENTRY_POINT) && strings.has_suffix(first, "'"):
		r.name = first[len(ENTRY_POINT):len(first) - 1]
	case strings.has_prefix(first, "Redeclaration of '") && strings.has_suffix(first, IN_SCOPE):
		r.name = first[len("Redeclaration of '"):len(first) - len(IN_SCOPE)]
	case:
		return
	}
	others := make([dynamic]Located)
	for m in entry.msgs[1:] {
		line := strings.trim_space(m)
		located := strings.trim_prefix(line, "at ")
		if len(located) == len(line) {
			return
		}
		append(&others, read_located(located, code) or_return)
	}
	r.placed, r.others = placed, others[:]
	return r, true
}

// The compiler reports a redeclared name at each later declaration, naming the earlier ones, but
// the one it counts as first follows the order it read the files in, which varies under load
// (Appendix C). The positions the entries name link into one group per declared name, and odx
// reports each declaration after the first in path order. A lone entry that names nothing keeps its
// message. Allocates with `allocator`.
settle_redeclarations :: proc(records: []Redeclaration, allocator: runtime.Allocator) -> []Placed {
	context.allocator = allocator
	at := make([]Located, len(records))
	others := make([][]Located, len(records))
	for r, i in records {
		at[i], others[i] = r.placed.located, r.others
	}
	groups, of := group_sites(at, others)

	settled := make([dynamic]Placed)
	for r, i in records {
		if len(groups[of[i]]) == 1 {
			append(&settled, r.placed)
		}
	}
	for group, g in groups {
		if len(group) == 1 {
			continue
		}
		first := group[0]
		name := records[slice.linear_search(of, g) or_else 0].name
		for c in group[1:] {
			message := fmt.aprintf(
				"Redeclaration of '%s' in this scope at %s(%d:%d)",
				name,
				first.path,
				first.line,
				first.col,
			)
			append(&settled, Placed{located = c, message = message})
		}
	}
	slice.sort_by(settled[:], proc(a, b: Placed) -> bool {
		return located_less(a.located, b.located)
	})
	return settled[:]
}

// One `Duplicate declaration of 'package N'` entry. The compiler found the name at `placed` after
// it had read a package of that name at `other`. `text` is the message without the line that names
// `other`.
Duplicate_Package :: struct {
	text:   string,
	placed: Placed,
	other:  Located,
}

// Returns false for any other entry. Allocates with `allocator`.
read_duplicate_package :: proc(
	entry: Compiler_Entry,
	placed: Placed,
	code: Code_Map,
	allocator: runtime.Allocator,
) -> (
	d: Duplicate_Package,
	ok: bool,
) {
	PREVIOUS :: " found at previous location"
	context.allocator = allocator
	last := len(entry.msgs) - 1
	if last < 1 || !strings.has_prefix(entry.msgs[0], "Duplicate declaration of 'package ") {
		return
	}
	line := strings.trim_space(entry.msgs[last])
	located := strings.trim_suffix(line, PREVIOUS)
	if len(located) == len(line) {
		return
	}
	d.other = read_located(located, code) or_return
	d.text = rewrite_roots(delete_ids(join_msgs(entry.msgs[:last])), code)
	d.placed = placed
	return d, true
}

// The compiler reports a package name that two packages share at the one it read second, naming
// the first, and the order it reads them in varies under load. So an importer's checks for the two
// targets can blame either site, and odx then showed one finding or two. The sites link into one
// group per clash, as `settle_redeclarations` links declarations, and odx reports each group once,
// at the site that sorts first, naming the others in the same order: the repo's sites, then the
// Odin root's, each in path order. So the finding lies in the repo whenever a site does. `of` gives
// each record's index in `settled`. Allocates with `allocator`.
settle_duplicate_packages :: proc(
	records: []Duplicate_Package,
	allocator: runtime.Allocator,
) -> (
	settled: []Placed,
	of: []int,
) {
	context.allocator = allocator
	at := make([]Located, len(records))
	others := make([][]Located, len(records))
	for &r, i in records {
		at[i], others[i] = r.placed.located, slice.from_ptr(&r.other, 1)
	}
	groups: [][]Located
	groups, of = group_sites(at, others)

	settled = make([]Placed, len(groups))
	for group, g in groups {
		ordered := make([dynamic]Located, 0, len(group))
		for in_odin_root in ([2]bool{false, true}) {
			for c in group {
				if strings.has_prefix(c.path, ODIN_ROOT_PREFIX) == in_odin_root {
					append(&ordered, c)
				}
			}
		}
		b := strings.builder_make()
		strings.write_string(&b, records[slice.linear_search(of, g) or_else 0].text)
		for c in ordered[1:] {
			fmt.sbprintf(&b, " %s(%d:%d) found at previous location", c.path, c.line, c.col)
		}
		settled[g] = Placed {
			located = ordered[0],
			message = strings.to_string(b),
		}
	}
	return
}

// Links each `at[i]` with the positions in `others[i]`. Returns every set of linked positions, each
// in path order, and the set each `at[i]` is in. Allocates with `context.allocator`.
@(private = "file")
group_sites :: proc(at: []Located, others: [][]Located) -> (groups: [][]Located, of: []int) {
	Links :: struct {
		ids:       map[string]int,
		positions: [dynamic]Located,
		parent:    [dynamic]int,
	}
	node :: proc(l: ^Links, c: Located) -> int {
		key := fmt.tprintf("%s:%d:%d", c.path, c.line, c.col)
		if i, found := l.ids[key]; found {
			return i
		}
		i := len(l.positions)
		l.ids[strings.clone(key)] = i
		append(&l.positions, c)
		append(&l.parent, i)
		return i
	}
	root :: proc(l: ^Links, i: int) -> int {
		r := i
		for l.parent[r] != r {
			r = l.parent[r]
		}
		return r
	}

	l: Links
	own := make([]int, len(at))
	for c, i in at {
		own[i] = node(&l, c)
		for o in others[i] {
			b := root(&l, node(&l, o))
			l.parent[b] = root(&l, own[i])
		}
	}
	group_of_root := make(map[int]int)
	members := make([dynamic][dynamic]Located)
	for c, i in l.positions {
		r := root(&l, i)
		if r not_in group_of_root {
			group_of_root[r] = len(members)
			append(&members, make([dynamic]Located))
		}
		append(&members[group_of_root[r]], c)
	}
	groups = make([][]Located, len(members))
	for group, g in members {
		slice.sort_by(group[:], located_less)
		groups[g] = group[:]
	}
	of = make([]int, len(at))
	for &g, i in of {
		g = group_of_root[root(&l, own[i])]
	}
	return
}

@(private = "file")
located_less :: proc(a, b: Located) -> bool {
	if a.path != b.path {
		return a.path < b.path
	}
	return a.line < b.line || (a.line == b.line && a.col < b.col)
}
