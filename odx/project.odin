package odx

import "core:fmt"
import "core:odin/ast"
import "core:odin/parser"
import "core:odin/tokenizer"
import "core:os"
import "core:path/filepath"
import "core:slice"
import "core:strings"

// odx is short-lived: loaders allocate on context.allocator and never free.
Project :: struct {
	root: string, // "" when no odx.json5 was found (topics/explain still work)
	rb:   Rulebook,
	cfg:  Config,
	dirs: []string, // every package directory under root, minus exclude, sorted
	errs: [dynamic]string,
}

load_project :: proc(root_override: string) -> (p: Project) {
	p.root = find_root(root_override)
	p.rb = load_rulebook(p.root, &p.errs)
	if p.root != "" {
		p.cfg = load_config(p.root, &p.errs)
		validate_project(&p)
	}
	slice.sort(p.errs[:])
	return
}

validate_project :: proc(p: ^Project) {
	for id in sorted_keys(p.cfg.disabled) {
		if find_rule(&p.rb, id) ==
		   nil {errf(&p.errs, "%s: disabled %s is not a known rule", CONFIG_FILE, id)}
	}
	p.dirs = package_dirs(p.root, &p.cfg, &p.errs)
	for role in sorted_keys(p.cfg.roles) {
		for g in p.cfg.roles[role] {
			hit := false
			for d in p.dirs {hit ||= glob_match(g, d)}
			if !hit {errf(&p.errs, "%s: roles.%s glob %q matches no package directory", CONFIG_FILE, role, g)}
		}
	}
	for d in p.dirs {
		if _, n := role_of(&p.cfg, d); n > 1 {
			errf(&p.errs, "%s: %s matches more than one role", CONFIG_FILE, d if d != "" else ".")
		}
	}
}

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

Package :: struct {
	dir:             string,
	rel:             string, // relative to root, "/" separators, "" for root itself
	role:            string, // "" = unmapped
	role_count:      int, // 0 unmapped, >1 conflict
	pkg:             ^ast.Package, // nil if the directory failed to parse at all
	files:           []^ast.File,
	diags:           []Diag,
	doc_skipped:     bool, // family C found no .odin-doc (type error); its ignores are never stale
	parse_result:    Evidence_Result,
	compiler_result: Evidence_Result,
	doc_result:      Evidence_Result,
	import_result:   Evidence_Result,
}

Diag :: struct {
	pos: tokenizer.Pos,
	msg: string,
}

// Parser.err has no user-data slot; collect through a thread-local.
@(thread_local)
parse_diags: [dynamic]Diag

collect_diag :: proc(pos: tokenizer.Pos, msg: string, args: ..any) {
	append(&parse_diags, Diag{pos, fmt.aprintf(msg, ..args)})
}

package_dirs :: proc(root: string, cfg: ^Config, errs: ^[dynamic]string = nil) -> []string {
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
		case fi.type == .Regular && fi.name == CONFIG_FILE && rel != CONFIG_FILE:
			if errs !=
			   nil {errf(errs, "%s: nested %s; one config per project (17.5)", rel, CONFIG_FILE)}
		}
	}
	return sorted_keys(dirs)
}

// load_packages parses every file of each package regardless of platform.
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
		collected: bool
		p.pkg, collected = parser.collect_package(p.dir)
		p.parse_result = Evidence_Result{.complete, ""}
		if !collected {
			p.parse_result = Evidence_Result{.failed, "could not collect every source file"}
		}
		if p.pkg != nil {
			keys := sorted_keys(p.pkg.files)
			p.files = make([]^ast.File, len(keys))
			for k, j in keys {
				f := p.pkg.files[k]
				p.files[j] = f
				parsed := parser.parse_file(&ps, f)
				if !parsed || f.syntax_error_count > 0 || f.pkg_decl == nil {
					p.parse_result = Evidence_Result{.failed, "source parsing failed"}
				}
				if f.pkg_decl == nil {continue}
				if p.pkg.name == "" {
					p.pkg.name = f.pkg_decl.name
				} else if p.pkg.name != f.pkg_decl.name {
					collect_diag(
						f.pkg_decl.pos,
						"different package name, expected '%s', got '%s'",
						p.pkg.name,
						f.pkg_decl.name,
					)
				}
			}
		}
		p.diags = slice.clone(parse_diags[:])
		if len(p.diags) > 0 {
			p.parse_result = Evidence_Result{.failed, "source parsing produced diagnostics"}
		}
	}
	return pkgs
}

select_packages :: proc(root: string, rels: []string, paths: []string) -> []string {
	want := make([dynamic]string, context.temp_allocator)
	for a in paths {
		// a relative path is tried from cwd first, then from the root (for `--root x sub/pkg`)
		abs := canonical(a)
		if !os.exists(abs) && !filepath.is_abs(a) {abs = canonical(join({root, a}))}
		if !os.exists(abs) {fail("%s does not exist", a)}
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
