package odx

import "core:fmt"
import doc "core:odin/doc-format"
import "core:os"
import "core:path/filepath"
import "core:strings"

// Family C: `odin doc -doc-format` per package, the compiler's checked entity table (19.2).
// Only `require_attribute` rules today. A package that fails to type-check writes no file;
// family A already reported why, so it is skipped silently.

run_family_c :: proc(c: ^Ctx) {
	rules := make([dynamic]^Active_Rule)
	for &a in c.rules {if a.spec.kind == "require_attribute" {append(&rules, &a)}}
	if len(rules) == 0 {return}
	tmp, terr := os.make_directory_temp("", "odx-doc-*", context.allocator)
	if terr != nil {
		append(&c.r.tool_errors, "cannot create temp dir for odin doc")
		return
	}
	defer os.remove_all(tmp)
	flags := odin_flags(c)

	for &p, i in c.pkgs {
		if p.pkg == nil || len(p.diags) > 0 {continue}
		out := join({tmp, fmt.tprintf("%d.odin-doc", i)})
		args := make([dynamic]string, context.temp_allocator)
		append(&args, "doc", p.dir, "-doc-format", strings.concatenate({"-out:", out}))
		append(&args, ..flags)
		code, _, ok := run_odin(c, ..args[:])
		if !ok {return}
		if code != 0 || !os.exists(out) {continue}
		data, rerr := os.read_entire_file(out, context.allocator)
		if rerr != nil {continue}
		h, derr := doc.read_from_bytes(data)
		if derr != nil {
			append(
				&c.r.tool_errors,
				fmt.aprintf(
					"doc-format reader: %v (compiler wrote version %d.%d.%d). Family C skipped.",
					derr,
					h.version.major,
					h.version.minor,
					h.version.patch,
				),
			)
			return
		}
		check_entities(c, &p, h, rules[:])
	}
}

@(private = "file")
check_entities :: proc(c: ^Ctx, p: ^Package, h: ^doc.Header, rules: []^Active_Rule) {
	files := doc.from_array(h, h.files)
	pkgs := doc.from_array(h, h.pkgs)
	ents := doc.from_array(h, h.entities)
	types := doc.from_array(h, h.types)
	for pkg, pi in pkgs {
		if pi == 0 || doc.from_string(h, pkg.fullpath) != p.dir {continue}
		for se in doc.from_array(h, pkg.entries) {
			e := ents[se.entity]
			if e.kind != .Procedure {continue}
			attrs := make(map[string]bool, context.temp_allocator)
			for at in doc.from_array(h, e.attributes) {attrs[doc.from_string(h, at.name)] = true}
			if "test" in attrs {continue} 	// 17.13
			last := last_result_name(h, types, e.type)
			for a in rules {
				if !role_applies(&a.spec, p.role) ||
				   a.spec.attribute in attrs ||
				   !has_suffix_any(last, a.spec.result_type_suffix) {continue}
				fname := doc.from_string(h, files[e.pos.file].name)
				file, _ := rel_of(c.root, join({p.dir, filepath.base(fname)}))
				report(
					c,
					a,
					file,
					int(e.pos.line),
					int(e.pos.column),
					strings.concatenate(
						{
							doc.from_string(h, e.name),
							" returns ",
							last,
							" but lacks @(",
							a.spec.attribute,
							")",
						},
					),
				)
			}
		}
	}
}

// last_result_name: the named type of a procedure's last result, "" if none or unnamed.
@(private = "file")
last_result_name :: proc(h: ^doc.Header, types: []doc.Type, ti: doc.Type_Index) -> string {
	t := types[ti]
	if t.kind != .Proc {return ""}
	sub := doc.from_array(h, t.types)
	if len(sub) < 2 || sub[1] == 0 {return ""}
	res_ents := doc.from_array(h, types[sub[1]].entities)
	if len(res_ents) == 0 {return ""}
	ents := doc.from_array(h, h.entities)
	last := types[ents[res_ents[len(res_ents) - 1]].type]
	return doc.from_string(h, last.name) if last.kind == .Named else ""
}

@(private = "file")
has_suffix_any :: proc(s: string, suffixes: []string) -> bool {
	if s == "" {return false}
	for suf in suffixes {if strings.has_suffix(s, suf) {return true}}
	return false
}
