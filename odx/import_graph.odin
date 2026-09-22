package odx

import "core:fmt"
import "core:odin/ast"
import "core:path/filepath"
import "core:slice"
import "core:strconv"
import "core:strings"

Import_Edge :: struct {
	node:              ^ast.Node,
	path, label, role: string,
	match_path:        string,
	kind:              enum {
		project,
		toolchain,
		unavailable,
	},
	target:            int,
	is_test:           bool,
	reason:            string,
}

Import_Graph :: struct {
	packages: []Package,
	by_dir:   map[string]int,
	edges:    [][]Import_Edge,
}

make_import_graph :: proc(root: string, cfg: ^Config, packages: []Package) -> Import_Graph {
	g := Import_Graph {
		packages = packages,
		by_dir   = make(map[string]int),
		edges    = make([][]Import_Edge, len(packages)),
	}
	for p, i in packages {g.by_dir[canonical(p.dir)] = i}
	for &p, i in packages {
		edges: [dynamic]Import_Edge
		for f in p.files {
			imports: [dynamic]^ast.Import_Decl
			visitor := ast.Visitor {
				data = &imports,
				visit = proc(v: ^ast.Visitor, n: ^ast.Node) -> ^ast.Visitor {
					if n == nil {return nil}
					if imp, ok := n.derived.(^ast.Import_Decl); ok {
						append(cast(^[dynamic]^ast.Import_Decl)v.data, imp)
					}
					return v
				},
			}
			ast.walk(&visitor, f)
			for imp in imports {
				e := resolve_import(&g, root, cfg, &p, imp)
				e.is_test = strings.has_suffix(f.fullpath, "_test.odin")
				append(&edges, e)
			}
		}
		g.edges[i] = edges[:]
	}
	return g
}

resolve_import :: proc(
	g: ^Import_Graph,
	root: string,
	cfg: ^Config,
	p: ^Package,
	imp: ^ast.Import_Decl,
) -> Import_Edge {
	e := Import_Edge {
		node = &imp.node,
		kind = .unavailable,
	}
	decoded: bool
	e.path, _, decoded = strconv.unquote_string(imp.relpath.text)
	if !decoded {
		e.path = imp.relpath.text
		e.reason = "cannot decode import string"
		return e
	}
	e.label = e.path
	e.match_path = e.path
	collection, separator, rest := strings.partition(e.path, ":")
	base, sub := p.dir, e.path
	if separator != "" {
		if cpath, configured := cfg.odin.collections[collection]; configured {
			base, sub = join({root, cpath}), rest
		} else if collection == "core" || collection == "base" || collection == "vendor" {
			clean, _ := filepath.clean(rest)
			if clean == "." ||
			   clean == ".." ||
			   strings.has_prefix(clean, "../") ||
			   filepath.is_abs(clean) {
				e.reason = fmt.aprintf(
					"%s does not name a package within its toolchain collection",
					e.path,
				)
				return e
			}
			e.match_path = strings.concatenate({collection, ":", clean})
			e.label = e.match_path
			e.kind = .toolchain
			return e
		} else {
			e.reason = fmt.aprintf("unknown collection in %s", e.path)
			return e
		}
	}
	dir := canonical(join({base, sub}))
	rel, inside := rel_of(root, dir)
	if !inside {
		e.reason = fmt.aprintf("%s resolves outside the project", e.path)
		return e
	}
	e.label = rel
	e.role, _ = role_of(cfg, rel)
	if index, exists := g.by_dir[dir]; exists {
		e.kind, e.target = .project, index
	} else {
		e.reason = fmt.aprintf(
			"%s resolves to %s, which is missing, excluded, or not a discovered source package",
			e.path,
			rel,
		)
	}
	return e
}

// Breadth-first traversal gives a stable shortest package chain. Dependency tests
// are not production dependencies; the selected package's own tests are checked.
import_reach :: proc(
	g: ^Import_Graph,
	start: Import_Edge,
	deny: []string,
) -> (
	found: map[string]string,
	evidence: Evidence_Result,
) {
	found = make(map[string]string, context.temp_allocator)
	evidence = {.complete, ""}
	if start.kind == .unavailable {return found, {.unsupported, start.reason}}
	if start.kind != .project || len(deny) == 0 {return}
	Step :: struct {
		index: int,
		chain: string,
	}
	queue := make([dynamic]Step, context.temp_allocator)
	append(&queue, Step{start.target, start.label})
	seen := make(map[int]bool, context.temp_allocator)
	seen[start.target] = true
	for i := 0; i < len(queue); i += 1 {
		step := queue[i]
		p := &g.packages[step.index]
		if p.parse_result.status != .complete {
			if evidence.status == .complete {
				evidence = {
					.failed,
					fmt.aprintf("cannot parse dependency %s via %s", p.rel, step.chain),
				}
			}
			continue
		}
		for e in g.edges[step.index] {
			if e.is_test {continue}
			if (import_matches(deny, e.path) || import_matches(deny, e.match_path)) &&
			   e.match_path not_in found {found[e.match_path] = step.chain}
			if e.kind == .unavailable && evidence.status == .complete {
				evidence = {.unsupported, fmt.aprintf("%s via %s", e.reason, step.chain)}
			}
			if e.kind == .project && e.target not_in seen {
				seen[e.target] = true
				append(&queue, Step{e.target, strings.concatenate({step.chain, " -> ", e.label})})
			}
		}
	}
	return
}

check_imports :: proc(c: ^Ctx, p: ^Package, a: ^Active_Rule) {
	layer, has_layer := c.cfg.dependencies[p.role]
	if !has_layer {return}
	p.import_result = {.complete, ""}
	index, exists := c.graph.by_dir[canonical(p.dir)]
	if !exists {
		p.import_result = {.unsupported, "selected package is missing from project source graph"}
		return
	}
	for e in c.graph.edges[index] {
		allowed :=
			import_matches(ALWAYS_ALLOWED, e.match_path) ||
			(e.is_test && slice.contains(TEST_ALLOWED, e.match_path))
		for m in layer.may_import {
			allowed ||=
				(e.role != "" && m == e.role) ||
				import_glob(m, e.path) ||
				import_glob(m, e.match_path)
		}
		found, evidence := import_reach(&c.graph, e, layer.deny)
		if evidence.status != .complete &&
		   p.import_result.status == .complete {p.import_result = evidence}
		if !allowed ||
		   import_matches(layer.deny, e.path) ||
		   import_matches(layer.deny, e.match_path) {
			what := e.label if e.role == "" else fmt.tprintf("%s (role %s)", e.label, e.role)
			report_at(
				c,
				a,
				e.node,
				fmt.tprintf("%s package may not import %s", p.role, what),
				e.path,
			)
			continue
		}
		for denied in sorted_keys(found) {
			report_at(
				c,
				a,
				e.node,
				fmt.tprintf("%s package reaches %s via %s", p.role, denied, found[denied]),
				strings.concatenate({e.path, " -> ", denied}),
			)
		}
	}
}
