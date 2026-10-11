package odx

import "base:runtime"
import "core:fmt"
import "core:mem/virtual"
import "core:odin/ast"
import "core:os"
import "core:slice"
import "core:strconv"
import "core:strings"

Path_Kind :: enum u8 {
	Import,
	Foreign_Import,
	Load,
	Load_Directory,
	Load_Hash,
	File_Symlink,
}

Path_Kind_Info :: struct {
	name:             string,
	// The directive's name in source, or "" for a kind that isn't a directive.
	directive:        string,
	allows_odin_code: bool,
	// Odin source spells the path, so collections apply, `path-case` checks it, and it resolves
	// from the directory of the file's real path, as the compiler does for a file symlink.
	in_source:        bool,
}

@(rodata)
PATH_KINDS := [Path_Kind]Path_Kind_Info {
	.Import = {name = "import", allows_odin_code = true, in_source = true},
	.Foreign_Import = {name = "foreign import", allows_odin_code = true, in_source = true},
	.Load = {name = "#load", directive = "load", allows_odin_code = true, in_source = true},
	.Load_Directory = {
		name = "#load_directory",
		directive = "load_directory",
		allows_odin_code = true,
		in_source = true,
	},
	.Load_Hash = {
		name = "#load_hash",
		directive = "load_hash",
		allows_odin_code = true,
		in_source = true,
	},
	.File_Symlink = {name = "symlink"},
}

@(rodata)
ODIN_CODE_DIRS := [?]string{"base", "core", "vendor"}

Path_Ref :: struct {
	kind:      Path_Kind,
	// Unquoted, as the source or the link spells it.
	written:   string,
	// The import, `foreign import` or directive, or 1:1 for a file symlink.
	line:      int,
	col:       int,
	// The string literal, where `path-case` reports.
	path_line: int,
	path_col:  int,
}

file_symlink_ref :: proc(link_text: string) -> Path_Ref {
	return {kind = .File_Symlink, written = link_text, line = 1, col = 1}
}

// Real paths without a trailing `/`.
Roots :: struct {
	repo:      string,
	odin_code: [len(ODIN_CODE_DIRS)]string,
}

escapes :: proc(kind: Path_Kind, real: string, roots: Roots) -> bool {
	if is_within(real, roots.repo) {
		return false
	}
	if PATH_KINDS[kind].allows_odin_code {
		for dir in roots.odin_code {
			if is_within(real, dir) {
				return false
			}
		}
	}
	return true
}

// A path given by a constant expression has no text to resolve.
// Clones the paths with `refs`' allocator and unquotes them with `context.allocator`.
collect_path_refs :: proc(file: ^ast.File, refs: ^[dynamic]Path_Ref) {
	visitor := ast.Visitor {
		visit = visit_path_node,
		data  = &Path_Collector{file.src, refs},
	}
	for decl in file.decls {
		ast.walk(&visitor, decl)
	}
}

@(private = "file")
Path_Collector :: struct {
	src:  string,
	refs: ^[dynamic]Path_Ref,
}

@(private = "file")
visit_path_node :: proc(v: ^ast.Visitor, node: ^ast.Node) -> ^ast.Visitor {
	if node == nil {
		return v
	}
	c := (^Path_Collector)(v.data)
	#partial switch n in node.derived {
	case ^ast.Import_Decl:
		add_path_ref(c, .Import, n.pos.offset, n.relpath.pos.offset, n.relpath.text)
	case ^ast.Foreign_Import_Decl:
		for path in n.fullpaths {
			if lit, is_lit := path.derived.(^ast.Basic_Lit); is_lit && lit.tok.kind == .String {
				add_path_ref(c, .Foreign_Import, n.pos.offset, lit.pos.offset, lit.tok.text)
			}
		}
	case ^ast.Call_Expr:
		directive, is_directive := n.expr.derived.(^ast.Basic_Directive)
		if !is_directive || len(n.args) == 0 {
			break
		}
		lit, is_lit := n.args[0].derived.(^ast.Basic_Lit)
		if !is_lit || lit.tok.kind != .String {
			break
		}
		for info, kind in PATH_KINDS {
			if info.directive == directive.name {
				add_path_ref(c, kind, n.pos.offset, lit.pos.offset, lit.tok.text)
				break
			}
		}
	}
	return v
}

@(private = "file")
add_path_ref :: proc(
	c: ^Path_Collector,
	kind: Path_Kind,
	offset, path_offset: int,
	literal: string,
) {
	allocator := c.refs.allocator
	written, _, ok := strconv.unquote_string(literal)
	if !ok {
		return
	}
	ref := Path_Ref {
		kind    = kind,
		written = strings.clone(written, allocator),
	}
	ref.line, ref.col = text_position(c.src, offset)
	ref.path_line, ref.path_col = text_position(c.src, path_offset)
	append(c.refs, ref)
}

// One component the source spells in a different case than the directory entry it resolves to.
Case_Difference :: struct {
	written: string,
	on_disk: string,
}

@(private = "file")
Path_Resolver :: struct {
	roots:       Roots,
	// As `odin root` printed it, where the compiler finds the Odin root's collections.
	odin_root:   string,
	collections: []Collection,
	// Each directory's entries sorted by name, read once per run.
	listings:    map[string][]os.File_Info,
	allocator:   runtime.Allocator,
}

// Adds `import-escape` and `path-case` per Appendix E.5 to the findings of each file that names an
// escaping or miscased path. `repo_root` and `odin_root` need not be real paths. Allocates what it
// adds with `allocator`.
check_paths :: proc(
	packages: []Package,
	repo_root, odin_root: string,
	collections: []Collection,
	allocator: runtime.Allocator,
) {
	work: virtual.Arena
	ensure(virtual.arena_init_growing(&work) == nil, "out of memory")
	defer virtual.arena_destroy(&work)
	scratch := virtual.arena_allocator(&work)

	r := Path_Resolver {
		roots = {repo = real_root(repo_root, scratch)},
		odin_root = odin_root,
		collections = collections,
		listings = make(map[string][]os.File_Info, scratch),
		allocator = scratch,
	}
	for dir, i in ODIN_CODE_DIRS {
		r.roots.odin_code[i] = real_root(
			fmt.aprintf("%s/%s", odin_root, dir, allocator = scratch),
			scratch,
		)
	}
	last := len(ODIN_CODE_DIRS) - 1
	odin_code_reach := fmt.aprintf(
		"the repo and the Odin root's %s and %s",
		strings.join(ODIN_CODE_DIRS[:last], ", ", scratch),
		ODIN_CODE_DIRS[last],
		allocator = scratch,
	)

	for &pkg in packages {
		pkg_dir := r.roots.repo
		if pkg.dir != "." {
			pkg_dir = fmt.aprintf("%s/%s", r.roots.repo, pkg.dir, allocator = scratch)
		}
		for &file in pkg.files {
			source_dir := parent_dir(file.link_target) if file.link_target != "" else pkg_dir
			for ref in file.paths {
				info := PATH_KINDS[ref.kind]
				real, difference := resolve_path(
					&r,
					ref,
					source_dir if info.in_source else pkg_dir,
				)
				if real, named := real.?; named && escapes(ref.kind, real, r.roots) {
					reach := odin_code_reach if info.allows_odin_code else "the repo"
					message := fmt.aprintf(
						"%s '%s' resolves outside %s",
						info.name,
						ref.written,
						reach,
						allocator = allocator,
					)
					append(
						&file.findings,
						Finding {
							path = file.path,
							line = ref.line,
							col = ref.col,
							rule = .Import_Escape,
							message = message,
						},
					)
				}
				if d, differs := difference.?; differs {
					message := fmt.aprintf(
						"%s '%s' names '%s', which is '%s' on disk",
						info.name,
						ref.written,
						d.written,
						d.on_disk,
						allocator = allocator,
					)
					append(
						&file.findings,
						Finding {
							path = file.path,
							line = ref.path_line,
							col = ref.path_col,
							rule = .Path_Case,
							message = message,
						},
					)
				}
			}
		}
	}
}

@(private = "file")
MAX_LINKS :: 40

// Returns the path with every symlink followed, or nil for a `system:` library or a collection odx
// doesn't know, which name no path, and the first spelled component whose case differs from the
// directory entry it names. `dir` is the real path of the directory it resolves from. A missing
// part is taken as written, so a link or path into a tree that isn't there escapes on every machine
// alike.
@(private = "file")
resolve_path :: proc(
	r: ^Path_Resolver,
	ref: Path_Ref,
	dir: string,
) -> (
	real: Maybe(string),
	difference: Maybe(Case_Difference),
) {
	start, rest := dir, ref.written
	in_source := PATH_KINDS[ref.kind].in_source
	if colon := strings.index_byte(ref.written, ':'); colon > 0 && in_source {
		name := ref.written[:colon]
		rest = ref.written[colon + 1:]
		if slice.contains(RESERVED_COLLECTIONS[:], name) {
			start = real_root(
				fmt.aprintf("%s/%s", r.odin_root, name, allocator = r.allocator),
				r.allocator,
			)
		} else {
			found := false
			for c in r.collections {
				if c.name == name {
					start, found = c.path, true
					break
				}
			}
			if !found {
				return nil, nil
			}
		}
	} else if strings.has_prefix(rest, "/") {
		start = "/"
	}

	steps := make([dynamic]Step, r.allocator)
	push_in_pop_order(&steps, rest, in_source)

	current := start
	missing_depth := 0
	links := 0
	for len(steps) > 0 {
		step := pop(&steps)
		switch step.name {
		case "", ".":
			continue
		case "..":
			current = parent_dir(current)
			missing_depth = max(missing_depth - 1, 0)
			continue
		}
		entry: os.File_Info
		found := false
		if missing_depth == 0 {
			entry, found = find_entry(r, current, step.name)
		}
		if !found {
			current = join_dir(current, step.name, r.allocator)
			missing_depth += 1
			continue
		}
		if step.spelled && entry.name != step.name && difference == nil {
			difference = Case_Difference{step.name, entry.name}
		}
		current = join_dir(current, entry.name, r.allocator)
		if entry.type != .Symlink {
			continue
		}
		links += 1
		target, err := os.read_link(current, r.allocator)
		if err != nil || links > MAX_LINKS {
			missing_depth += 1
			continue
		}
		current = "/" if strings.has_prefix(target, "/") else parent_dir(current)
		push_in_pop_order(&steps, target, false)
	}
	return current, difference
}

// One path component, and whether Odin source spells it rather than a symlink.
@(private = "file")
Step :: struct {
	name:    string,
	spelled: bool,
}

@(private = "file")
push_in_pop_order :: proc(steps: ^[dynamic]Step, path: string, spelled: bool) {
	parts := strings.split(path, "/", steps.allocator)
	#reverse for part in parts {
		append(steps, Step{name = part, spelled = spelled})
	}
}

// Matches the exact name first, so a case-sensitive filesystem holding both spellings resolves the
// way the compiler does there.
@(private = "file")
find_entry :: proc(r: ^Path_Resolver, dir, name: string) -> (entry: os.File_Info, found: bool) {
	entries, cached := r.listings[dir]
	if !cached {
		entries, _ = list_dir(dir, r.allocator)
		r.listings[strings.clone(dir, r.allocator)] = entries
	}
	for e in entries {
		if e.name == name {
			return e, true
		}
	}
	for e in entries {
		if strings.equal_fold(e.name, name) {
			return e, true
		}
	}
	return {}, false
}

parent_dir :: proc(path: string) -> string {
	i := strings.last_index_byte(path, '/')
	return path[:i] if i > 0 else "/"
}

@(private = "file")
join_dir :: proc(dir, name: string, allocator: runtime.Allocator) -> string {
	if dir == "/" {
		return strings.concatenate({"/", name}, allocator)
	}
	return strings.concatenate({dir, "/", name}, allocator)
}
