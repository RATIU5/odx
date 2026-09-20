// M0 spike: run `odin doc <pkg> -doc-format`, read it with core:odin/doc-format,
// list every entity per non-runtime package, and join each to its AST Value_Decl
// by (file, line, column).
package docfmt

import "core:fmt"
import "core:odin/ast"
import doc "core:odin/doc-format"
import "core:odin/parser"
import "core:os"
import "core:path/filepath"
import "core:strings"

main :: proc() {
	if len(os.args) < 2 {
		fmt.eprintln("usage: spike_docfmt <pkg-dir>")
		os.exit(2)
	}
	out := "build/spike.odin-doc"
	os.remove(out)
	state, _, stderr, perr := os.process_exec(
		{
			command = {
				"odin",
				"doc",
				os.args[1],
				"-doc-format",
				"-all-packages",
				fmt.tprintf("-out:%s", out),
			},
		},
		context.allocator,
	)
	if perr != nil || state.exit_code != 0 || !os.exists(out) {
		// 19.2: type errors -> no file written; caller falls back to -json-errors
		fmt.eprintfln("odin doc failed (exit %d), no output file: %s", state.exit_code, stderr)
		os.exit(2)
	}
	data, rerr := os.read_entire_file(out, context.allocator)
	assert(rerr == nil)
	h, derr := doc.read_from_bytes(data)
	if derr != nil {
		fmt.eprintfln("doc-format reader error: %v (version %v)", derr, h.version)
		os.exit(2)
	}
	files := doc.from_array(h, h.files)
	pkgs := doc.from_array(h, h.pkgs)
	ents := doc.from_array(h, h.entities)
	fmt.printfln(
		"format %d.%d.%d  files=%d pkgs=%d entities=%d types=%d bytes=%d",
		h.version.major,
		h.version.minor,
		h.version.patch,
		len(files),
		len(pkgs),
		len(ents),
		h.types.length,
		len(data),
	)

	joined, total := 0, 0
	for pkg, pi in pkgs {
		if pi == 0 || .Runtime in pkg.flags || .Builtin in pkg.flags {continue}
		full := doc.from_string(h, pkg.fullpath)
		if strings.contains(full, "/core/") || strings.contains(full, "/base/") {continue}
		fmt.printfln("PKG %s  %s", doc.from_string(h, pkg.name), full)

		// AST side: parse the package once, index decls by (file base, line, col)
		Key :: struct {
			file:      string,
			line, col: int,
		}
		decls := make(map[Key]^ast.Value_Decl)
		apkg, ok := parser.parse_package_from_path(full)
		assert(ok && apkg != nil)
		for _, f in apkg.files {
			for d in f.decls {
				if vd, isvd := d.derived.(^ast.Value_Decl); isvd {
					decls[{filepath.base(f.fullpath), vd.pos.line, vd.pos.column}] = vd
				}
			}
		}

		for se in doc.from_array(h, pkg.entries) {
			e := ents[se.entity]
			pos := e.pos
			fname := doc.from_string(h, files[pos.file].name)
			ty := doc.from_array(h, h.types)[e.type]
			attrs: [dynamic]string
			for a in doc.from_array(h, e.attributes) {
				append(
					&attrs,
					fmt.tprintf("%s=%s", doc.from_string(h, a.name), doc.from_string(h, a.value)),
				)
			}
			total += 1
			vd, hit := decls[{filepath.base(fname), int(pos.line), int(pos.column)}]
			if hit {joined += 1}
			fmt.printfln(
				"  %-10v %-8s %s:%d:%d  type=%v  attrs=%v  ast=%v",
				e.kind,
				doc.from_string(h, e.name),
				filepath.base(fname),
				pos.line,
				pos.column,
				doc.from_array(h, h.types)[e.type].kind,
				attrs[:],
				hit ? fmt.tprintf("Value_Decl(mutable=%v)", vd.is_mutable) : "MISS",
			)
			_ = ty
		}
	}
	fmt.printfln("joined %d/%d entities to AST decls", joined, total)
	assert(joined == total, "every doc-format entity must join to an AST decl")
}
