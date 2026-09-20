package odx

import "core:fmt"
import "core:odin/ast"
import "core:odin/parser"
import "core:odin/tokenizer"
import "core:os"
import "core:path/filepath"
import "core:slice"
import "core:strings"

// Project is everything loaded from disk before any command runs: root, rulebook, config.
Project :: struct {
	root: string, // "" when no odx.json5 was found (topics/explain still work)
	rb:   Rulebook,
	cfg:  Config,
	errs: [dynamic]string, // config and topic problems, sorted
}

// load_project layers built-ins, .odx/topics and odx.json5 and validates them together.
load_project :: proc(root_override: string) -> (p: Project) {
	p.root = find_root(root_override)
	p.rb = load_rulebook(p.root, &p.errs)
	if p.root != "" {
		p.cfg = load_config(p.root, &p.errs)
		for id in sorted_keys(p.cfg.disabled) {
			if find_rule(&p.rb, id) ==
			   nil {errf(&p.errs, "%s: disabled %s is not a known rule", CONFIG_FILE, id)}
		}
		dirs := package_dirs(p.root, &p.cfg)
		for role in sorted_keys(p.cfg.roles) {
			for g in p.cfg.roles[role] {
				hit := false
				for d in dirs {hit ||= glob_match(g, d)}
				if !hit {errf(&p.errs, "%s: roles.%s glob %q matches no package directory", CONFIG_FILE, role, g)}
			}
		}
	}
	slice.sort(p.errs[:])
	return
}

// must_load is load_project for commands that cannot proceed with a broken setup.
must_load :: proc(o: Opts, need_config: bool) -> Project {
	p := load_project(o.root)
	if need_config &&
	   p.root ==
		   "" {fail("no %s found here or in any parent (use --root or `odx init`)", CONFIG_FILE)}
	if len(p.errs) > 0 {
		for e in p.errs {fmt.eprintln("odx:", e)}
		os.exit(EXIT_TOOL)
	}
	return p
}

sorted_keys :: proc(m: map[string]$V) -> []string {
	keys, _ := slice.map_keys(m, context.temp_allocator)
	slice.sort(keys)
	return keys
}

// Package is one directory of .odin files with its role and parsed AST (17.5, 17.7).
Package :: struct {
	dir:        string, // absolute
	rel:        string, // relative to root, "/" separators, "" for root itself
	role:       string, // "" = unmapped
	role_count: int, // 0 unmapped, >1 conflict
	pkg:        ^ast.Package, // nil if the directory failed to parse at all
	files:      []^ast.File, // sorted by path
	diags:      []Diag, // parse errors
}

Diag :: struct {
	pos: tokenizer.Pos,
	msg: string,
}

// Parser.err has no user-data slot (17.20); collect through a thread-local.
@(thread_local)
parse_diags: [dynamic]Diag

collect_diag :: proc(pos: tokenizer.Pos, msg: string, args: ..any) {
	append(&parse_diags, Diag{pos, fmt.aprintf(msg, ..args)})
}

// package_dirs lists every directory under root holding a .odin file, minus exclude, sorted.
package_dirs :: proc(root: string, cfg: ^Config) -> []string {
	dirs := make(map[string]bool)
	w := os.walker_create_path(root)
	defer os.walker_destroy(&w)
	for fi in os.walker_walk(&w) {
		rel, _ := rel_of(root, fi.fullpath)
		switch {
		case fi.type == .Symlink:
			os.walker_skip_dir(&w)
		case fi.type == .Directory:
			if is_excluded(cfg, rel) {os.walker_skip_dir(&w)}
		case fi.type == .Regular && strings.has_suffix(fi.name, ".odin"):
			dir, _ := rel_of(root, filepath.dir(fi.fullpath))
			dirs[dir] = true
		}
	}
	return sorted_keys(dirs)
}

// load_packages resolves roles and parses each package (all files, all platforms: 17.7).
load_packages :: proc(root: string, cfg: ^Config, rels: []string) -> []Package {
	pkgs := make([]Package, len(rels))
	for rel, i in rels {
		p := &pkgs[i]
		p.rel = rel
		p.dir = join({root, rel})
		p.role, p.role_count = role_of(cfg, rel)
		clear(&parse_diags)
		ps := parser.default_parser()
		ps.err = collect_diag
		ps.warn = collect_diag
		p.pkg, _ = parser.parse_package_from_path(p.dir, &ps)
		p.diags = slice.clone(parse_diags[:])
		if p.pkg != nil {
			keys := sorted_keys(p.pkg.files)
			p.files = make([]^ast.File, len(keys))
			for k, j in keys {p.files[j] = p.pkg.files[k]}
		}
	}
	return pkgs
}

// select_packages narrows package dirs to those at or below the given paths (a file selects its dir).
select_packages :: proc(root: string, rels: []string, paths: []string) -> []string {
	want := make([dynamic]string, context.temp_allocator)
	for a in paths {
		// a relative path is tried from cwd first, then from the root (for `--root x sub/pkg`)
		abs, _ := filepath.abs(a)
		if !os.exists(abs) && !filepath.is_abs(a) {abs = join({root, a})}
		if !os.is_directory(abs) {abs = filepath.dir(abs)}
		rel, inside := rel_of(root, abs)
		if !inside {fail("%s is outside the project root %s", a, root)}
		append(&want, rel)
	}
	out := make([dynamic]string)
	for r in rels {
		for w in want {
			if w == "" ||
			   r == w ||
			   strings.has_prefix(r, strings.concatenate({w, "/"}, context.temp_allocator)) {
				append(&out, r)
				break
			}
		}
	}
	return out[:]
}
