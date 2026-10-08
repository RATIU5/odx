package odx

import "base:runtime"
import "core:fmt"
import "core:mem/virtual"
import "core:odin/ast"
import "core:os"
import "core:slice"
import "core:strings"

// odx.json's `vendored` trees are never walked, so no package is vendored.
Package_Status :: enum u8 {
	Strict,
	Pending,
}

Source_File :: struct {
	// Repo-relative with `/`. A symlink's own path, never its target's.
	path:         string,
	// The target's real path when `path` is a symlink, which is the path the compiler reports.
	link_target:  string,
	// The identifier after the file's first `package` token, or "" when it has none.
	name:         string,
	// Where that `package` token starts, or 0 and 0.
	package_line: int,
	package_col:  int,
	// The targets the compiler compiles the file for, `#+test` aside. Empty for an unreadable file.
	targets:      Targets,
	is_test:      bool,
	// False when odx can't read or parse the file, so its parsed rules skip it.
	parsed:       bool,
	size:         int,
	// The paths the file names, and its own link when it is a symlink, before resolving.
	paths:        [dynamic]Path_Ref,
	findings:     [dynamic]Finding,
	ignores:      [dynamic]Ignore,
}

Package :: struct {
	// Repo-relative with `/`, and "." for the root.
	dir:           string,
	// The name of the first file in path order that compiles for a target and isn't a test file.
	name:          string,
	status:        Package_Status,
	// In path order, without the files odx doesn't read.
	files:         [dynamic]Source_File,
	// The targets `odin check` runs for. Empty when the package is skipped or its compiled files
	// disagree on the name.
	check_targets: Targets,
	// The compiled files disagree on the name, which odx reports itself.
	name_conflict: bool,
	// Its own check reported an error in its own files that wasn't relocated, so only the rules
	// that run when muted apply.
	muted:         bool,
}

// Skipped means no non-test file compiles for either target, so the compiler never checks it.
is_skipped :: proc(p: Package) -> bool {
	return p.check_targets == {} && !p.name_conflict
}

@(private = "file")
Walker :: struct {
	config:    Config,
	resolver:  ^Resolver,
	result:    ^Result,
	packages:  [dynamic]Package,
	allocator: runtime.Allocator,
	// Holds directory listings for the whole walk.
	listings:  runtime.Allocator,
	// Holds one file's text and AST at a time.
	scratch:   ^virtual.Arena,
}

// Walks the repo at `root` per Appendix E.3 and returns its packages in path order. Each file holds
// the findings odx reads from it, where `name-case` on an alias also reads the declarations
// `resolver` finds for it, and the first disagreeing file of a package whose files disagree on the
// name holds that `odin` finding. Adds the skipped and pending counts, a note per skipped package
// and a `dir-unreadable` error per directory it can't list to `result`. Allocates the packages and
// what it adds to `result` with `allocator`.
discover :: proc(
	root: string,
	config: Config,
	resolver: ^Resolver,
	result: ^Result,
	allocator: runtime.Allocator,
) -> [dynamic]Package {
	listings, scratch: virtual.Arena
	ensure(virtual.arena_init_growing(&listings) == nil, "out of memory")
	defer virtual.arena_destroy(&listings)
	ensure(virtual.arena_init_growing(&scratch) == nil, "out of memory")
	defer virtual.arena_destroy(&scratch)

	w := Walker {
		config    = config,
		resolver  = resolver,
		result    = result,
		packages  = make([dynamic]Package, allocator),
		allocator = allocator,
		listings  = virtual.arena_allocator(&listings),
		scratch   = &scratch,
	}
	project := root
	if real, err := os.get_absolute_path(root, w.listings); err == nil {
		project = real
	}
	walk_dir(&w, ".", root, os.base(project))

	slice.sort_by(w.packages[:], proc(a, b: Package) -> bool {
		return a.dir != b.dir && (a.dir == "." || (b.dir != "." && a.dir < b.dir))
	})
	for p in w.packages {
		if p.status == .Pending {
			result.pending += 1
		}
	}
	slice.sort(result.notes[:])
	return w.packages
}

@(private = "file")
SKIP_REASON :: "no non-test file compiles for darwin_arm64 or linux_amd64"

Dir_Entry_Kind :: enum u8 {
	Other,
	// A directory itself. A link to one is `Other`, because odx never walks it.
	Dir,
	// A `.odin` file the compiler never compiles, which still makes its directory a package.
	Hidden_Source,
	// A `.odin` file odx reads, unless its tags say `#+build ignore`.
	Source,
}

// The entries of the directory at `abs` in name order, which is the order odx reads its files in.
// Allocates with `allocator`.
list_dir :: proc(
	abs: string,
	allocator: runtime.Allocator,
) -> (
	entries: []os.File_Info,
	err: os.Error,
) {
	entries = os.read_directory_by_path(abs, -1, allocator) or_return
	slice.sort_by(entries, proc(a, b: os.File_Info) -> bool {return a.name < b.name})
	return
}

// What discovery and the resolver's loader both make of a directory entry, so they read the same
// files. It follows a link only to learn its kind, and allocates that with `allocator`.
dir_entry_kind :: proc(entry: os.File_Info, allocator: runtime.Allocator) -> Dir_Entry_Kind {
	if entry.type == .Symlink {
		if info, err := os.stat(entry.fullpath, allocator); err == nil && info.type == .Directory {
			return .Other
		}
	}
	switch {
	case entry.type == .Directory:
		return .Dir
	case !strings.has_suffix(entry.name, ".odin"):
		return .Other
	case is_hidden_file(entry.name):
		return .Hidden_Source
	}
	return .Source
}

// `project` is the name the compiler gives a build of this directory.
@(private = "file")
walk_dir :: proc(w: ^Walker, rel, abs, project: string) {
	entries, err := list_dir(abs, w.listings)
	if err != nil {
		message := fmt.aprintf(
			"could not list %s: %s",
			rel,
			os.error_string(err),
			allocator = w.allocator,
		)
		append(&w.result.errors, Error{.Dir_Unreadable, message})
		return
	}

	is_package := false
	pkg := Package {
		dir    = strings.clone(rel, w.allocator),
		status = .Pending if is_pending(w.config.pending[:], rel) else .Strict,
		files  = make([dynamic]Source_File, w.allocator),
	}
	for entry in entries {
		kind := dir_entry_kind(entry, w.listings)
		if kind == .Other {
			continue
		}
		child := entry.name
		if rel != "." {
			child = fmt.aprintf("%s/%s", rel, entry.name, allocator = w.listings)
		}
		switch kind {
		case .Other:
		case .Dir:
			if strings.has_prefix(entry.name, ".") ||
			   is_listed_dir(w.config.exclude_dirs[:], child) ||
			   is_listed_dir(w.config.vendored[:], child) {
				continue
			}
			walk_dir(w, child, entry.fullpath, entry.name)
		case .Hidden_Source:
			is_package = true
		case .Source:
			is_package = true
			if file, read := read_file(w, rel, child, entry.fullpath, project); read {
				if entry.type == .Symlink {
					// A link that can't be resolved can't be read either, and read_file already
					// reported that.
					if target, link_err := os.get_absolute_path(entry.fullpath, w.allocator);
					   link_err == nil {
						file.link_target = target
					}
					if text, link_err := os.read_link(entry.fullpath, w.allocator);
					   link_err == nil {
						append(&file.paths, file_symlink_ref(text))
					}
				}
				append(&pkg.files, file)
			}
		}
	}
	if !is_package {
		return
	}
	name_package(w, &pkg)
	append(&w.packages, pkg)
}

// `read` is false for a file odx doesn't read.
@(private = "file")
read_file :: proc(w: ^Walker, dir, path, abs, project: string) -> (file: Source_File, read: bool) {
	defer virtual.arena_free_all(w.scratch)
	scratch := virtual.arena_allocator(w.scratch)

	file.path = strings.clone(path, w.allocator)
	file.paths = make([dynamic]Path_Ref, w.allocator)
	file.findings = make([dynamic]Finding, w.allocator)
	file.ignores = make([dynamic]Ignore, w.allocator)
	check_file_name(&file.findings, file.path)
	data, err := os.read_entire_file(abs, scratch)
	if err != nil {
		message := fmt.aprintf(
			"odx can't read this file: %s",
			os.error_string(err),
			allocator = w.allocator,
		)
		append(
			&file.findings,
			Finding {
				path = file.path,
				line = 1,
				col = 1,
				rule = .Parse_Unsupported,
				message = message,
			},
		)
		return file, true
	}
	src := string(data)
	file.size = len(src)
	header := scan_header(src, scratch)
	verdict := judge_tags(header.tags[:], project)
	if verdict.ignored {
		return
	}
	file.name = strings.clone(header.name, w.allocator)
	file.targets = file_name_targets(os.base(abs)) & verdict.targets
	file.is_test = verdict.is_test
	if header.package_offset >= 0 {
		file.package_line, file.package_col = text_position(src, header.package_offset)
	}
	check_package_name(&file, dir)
	check_file_tags(&file.findings, file.path, src, header.tags[:], scratch)
	parse_error: Maybe(Parse_Error)
	{
		context.allocator = scratch
		parsed: ^ast.File
		parsed, parse_error = parse_source(src, w.allocator)
		layout := Layout {
			gaps               = make([dynamic]Alignment_Gap, scratch),
			foreign_decl_lines = make([dynamic]Line_Run, scratch),
		}
		if parse_error == nil {
			collect_path_refs(parsed, &file.paths)
			walk_file(parsed, file.path, abs, &file.findings, &layout, w.resolver)
		}
		check_line_length(&file.findings, file.path, src, layout)
		read_ignores(&file, src, parsed, header.package_offset, w.allocator, scratch)
	}
	if e, failed := parse_error.?; failed {
		line, col := text_position(src, e.offset)
		message := fmt.aprintf("odx can't parse this file: %s", e.message, allocator = w.allocator)
		append(
			&file.findings,
			Finding {
				path = file.path,
				line = line,
				col = col,
				rule = .Parse_Unsupported,
				message = message,
			},
		)
	} else {
		file.parsed = true
	}
	return file, true
}

// Names the package, reports the first compiled file whose name differs, and decides which targets
// `odin check` runs for. The compiler blames whichever file it happens to read later, so odx goes
// by path order to give the same finding on every filesystem.
@(private = "file")
name_package :: proc(w: ^Walker, pkg: ^Package) {
	compiled: Targets
	for file in pkg.files {
		if file.is_test || file.targets == {} {
			continue
		}
		compiled += file.targets
		if pkg.name == "" {
			pkg.name = file.name
		}
	}
	if compiled == {} {
		w.result.skipped += 1
		note := fmt.aprintf("odx: skipped %s: %s", pkg.dir, SKIP_REASON, allocator = w.allocator)
		append(&w.result.notes, note)
		return
	}
	for &file in pkg.files {
		if file.is_test || file.targets == {} || file.name == "" || file.name == pkg.name {
			continue
		}
		message := fmt.aprintf(
			"Different package name, expected '%s', got '%s'",
			pkg.name,
			file.name,
			allocator = w.allocator,
		)
		finding := Finding {
			path    = file.path,
			line    = file.package_line,
			col     = file.package_col,
			rule    = .Odin,
			message = message,
		}
		append(&file.findings, finding)
		pkg.name_conflict = true
		return
	}
	pkg.check_targets = compiled
}

// odx.json's dirs may carry `./` or a trailing `/`.
@(private = "file")
is_listed_dir :: proc(dirs: []string, rel: string) -> bool {
	for dir in dirs {
		if cleaned, _ := os.clean_path(dir, context.temp_allocator); cleaned == rel {
			return true
		}
	}
	return false
}

@(private = "file")
is_pending :: proc(entries: []Pending_Entry, rel: string) -> bool {
	for entry in entries {
		if is_listed_dir({entry.dir}, rel) {
			return true
		}
	}
	return false
}
