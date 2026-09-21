package odx

import "core:fmt"
import "core:odin/ast"
import "core:os"
import "core:slice"
import "core:strings"

// Capabilities: what each package transitively reaches, from `odin check -show-import-graph`
// (a DOT digraph, absolute package paths as nodes) plus an AST look for `foreign`. A report,
// not a verdict: constraints are the roles preset (dependencies/R2-R4).
// ponytail: one uncached `odin check` per package; cache if doctor or `for` get hot.
// check_imports keeps its AST walk because it gives the line to point at.

CAPABILITIES := []struct {
	name, suffix: string,
}{{"os", "/core/os"}, {"net", "/core/net"}, {"threads", "/core/thread"}, {"threads", "/core/sync"}}

Reach :: struct {
	via: map[string]string, // capability name -> first import path on the way there ("" = none)
}

// import_graph: absolute dir -> imported dirs, over the package's transitive closure.
import_graph :: proc(c: ^Ctx, p: ^Package) -> (edges: map[string][dynamic]string, ok: bool) {
	args := make([dynamic]string, context.temp_allocator)
	append(&args, "check", p.dir)
	append(&args, ..odin_flags(c))
	append(&args, "-no-entry-point", "-show-import-graph")
	cmd := make([dynamic]string, context.temp_allocator)
	append(&cmd, odin_exe(c.cfg))
	append(&cmd, ..args[:])
	state, out, _, err := os.process_exec({command = cmd[:]}, context.allocator)
	if err != nil {return nil, false}
	edges = make(map[string][dynamic]string)
	for line in strings.split_lines(string(out), context.temp_allocator) {
		from, arrow, to := strings.partition(strings.trim_space(line), " -> ")
		if arrow == "" {continue}
		a := strings.trim(from, `"`)
		b := strings.trim(strings.trim_suffix(strings.trim_space(to), ";"), `"`)
		if !strings.contains(a, "/") || !strings.contains(b, "/") {continue} 	// intrinsics, builtin
		arr := edges[a] // ponytail: copy-append-store; &edges[a] crashed on this compiler
		append(&arr, b)
		edges[a] = arr
	}
	if len(edges) == 0 && state.exit_code != 0 {return nil, false}
	return edges, true
}

// reach_of: for each capability, the first project-visible step on a path to it, "" if none.
reach_of :: proc(c: ^Ctx, p: ^Package) -> (r: Reach, ok: bool) {
	edges, gok := import_graph(c, p)
	if !gok {return r, false}
	r.via = make(map[string]string)
	seen := make(map[string]bool, context.temp_allocator)
	Frame :: struct {
		node, first: string,
	}
	stack := make([dynamic]Frame, context.temp_allocator)
	roots := edges[p.dir]
	for d in roots {append(&stack, Frame{d, d})}
	for len(stack) > 0 {
		f := pop(&stack)
		if seen[f.node] {continue}
		seen[f.node] = true
		for cap in CAPABILITIES {
			if strings.has_suffix(f.node, cap.suffix) &&
			   cap.name not_in r.via {r.via[cap.name] = f.first}
		}
		next := edges[f.node]
		for d in next {append(&stack, Frame{d, f.first})}
	}
	for d in sorted_keys(seen) {
		if rel, inside := rel_of(c.root, d); inside && has_foreign(c, rel) {
			r.via["foreign"] = d
			break
		}
	}
	if has_foreign(c, p.rel) {r.via["foreign"] = "own files"}
	return r, true
}

has_foreign :: proc(c: ^Ctx, rel: string) -> bool {
	for pk in c.pkgs {
		if pk.rel != rel {continue}
		for f in pk.files {
			for d in f.decls {
				#partial switch _ in d.derived {
				case ^ast.Foreign_Import_Decl, ^ast.Foreign_Block_Decl:
					return true
				}
			}
		}
	}
	return false
}

// reach_line: "core: reaches os via core:os, threads via core/sync" or "reaches nothing".
reach_line :: proc(c: ^Ctx, p: ^Package) -> string {
	r, ok := reach_of(c, p)
	if !ok {return "reach unknown (odin check failed)"}
	if len(r.via) == 0 {return "reaches nothing (no os, net, threads, foreign)"}
	parts := make([dynamic]string, context.temp_allocator)
	for name in sorted_keys(r.via) {
		via := r.via[name]
		if rel, inside := rel_of(c.root, via); inside {via = rel}
		if i := strings.index(via, "/core/");
		   i >=
		   0 {via = strings.concatenate({"core:", via[i + len("/core/"):]}, context.temp_allocator)}
		append(&parts, fmt.tprintf("%s via %s", name, via))
	}
	return strings.concatenate({"reaches ", strings.join(parts[:], ", ", context.temp_allocator)})
}

report_dependencies :: proc(c: ^Ctx) {
	fmt.println("dependencies (from -show-import-graph):")
	for &p in c.pkgs {
		if p.pkg == nil {continue}
		role := p.role if p.role_count == 1 else "no role"
		fmt.printfln("  %-24s %-8s %s", p.rel if p.rel != "" else ".", role, reach_line(c, &p))
	}
	_ = slice.contains
}
