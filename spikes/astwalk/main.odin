// M0 spike: time walking a multi-directory tree, parsing each dir as a package
// (arena per package, freed after), and visiting every AST node.
package astwalk

import "core:fmt"
import "core:mem/virtual"
import "core:odin/ast"
import "core:odin/parser"
import "core:odin/tokenizer"
import "core:os"
import "core:slice"
import "core:strings"
import "core:time"

Stats :: struct {
	dirs, files, nodes, syntax_errs: int,
}

count_nodes :: proc(v: ^ast.Visitor, n: ^ast.Node) -> ^ast.Visitor {
	if n == nil {return nil}
	(cast(^Stats)v.data).nodes += 1
	return v
}

main :: proc() {
	if len(os.args) < 2 {
		fmt.eprintln("usage: spike_astwalk <root-dir>")
		os.exit(2)
	}
	root := os.args[1]
	start := time.tick_now()
	st: Stats

	// collect directories that contain at least one .odin file
	dirs := make(map[string]bool)
	w := os.walker_create_path(root)
	defer os.walker_destroy(&w)
	for fi in os.walker_walk(&w) {
		if fi.type == .Regular && strings.has_suffix(fi.name, ".odin") {
			dirs[strings.clone(fi.fullpath[:len(fi.fullpath) - len(fi.name) - 1])] = true
		}
	}
	if p, err := os.walker_error(&w); err != nil {fmt.eprintfln("walk error at %s: %v", p, err)}
	walked := time.tick_since(start)

	sorted := slice.map_keys(dirs) or_else nil
	slice.sort(sorted)
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == nil)
	for dir in sorted {
		context.allocator = virtual.arena_allocator(&arena)
		p := parser.default_parser()
		p.err = proc(pos: tokenizer.Pos, msg: string, args: ..any) {} 	// ponytail: swallow; odx collects via thread-local per 17.20
		pkg, _ := parser.parse_package_from_path(dir, &p)
		st.dirs += 1
		if pkg != nil {
			keys := slice.map_keys(pkg.files) or_else nil
			slice.sort(keys)
			for k in keys {
				f := pkg.files[k]
				st.files += 1
				st.syntax_errs += f.syntax_error_count
				v := ast.Visitor {
					visit = count_nodes,
					data  = &st,
				}
				ast.walk(&v, f)
			}
		}
		virtual.arena_free_all(&arena)
	}
	total := time.tick_since(start)
	fmt.printfln(
		"dirs=%d files=%d nodes=%d syntax_errors=%d",
		st.dirs,
		st.files,
		st.nodes,
		st.syntax_errs,
	)
	fmt.printfln(
		"walk=%.0fms parse+visit=%.0fms total=%.0fms",
		time.duration_milliseconds(walked),
		time.duration_milliseconds(total - walked),
		time.duration_milliseconds(total),
	)
}
