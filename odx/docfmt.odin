package odx

import "core:fmt"
import doc "core:odin/doc-format"
import "core:os"
import "core:path/filepath"
import "core:strings"

// Family C: `odin doc -doc-format` per package, the compiler's checked entity table.
// A package that fails to type-check writes no file; family A already reported why, so it is
// marked doc_skipped and its ignores stay unjudged.

// is_family_c: kinds that need the type-checked entity table; skipped under --fast.
is_family_c :: proc(k: Check_Kind) -> bool {
	return k == .require_attribute || k == .foreign_error_type
}

run_family_c :: proc(c: ^Ctx) {
	rules := make([dynamic]^Active_Rule)
	for &a in c.rules {if is_family_c(a.rule.check.kind) {append(&rules, &a)}}
	if len(rules) == 0 {return}
	tmp, terr := os.make_directory_temp("", "odx-doc-*", context.allocator)
	if terr != nil {
		tool_error(c.r, "cannot create temp dir for odin doc")
		return
	}
	defer os.remove_all(tmp)
	flags := odin_flags(c)

	for &p, i in c.pkgs {
		h, status := doc_package(c, &p, tmp, i, flags)
		switch status {
		case .Fatal:
			return
		case .Skipped:
			p.doc_skipped = true
			continue
		case .Ok:
			check_entities(c, &p, h, rules[:])
		}
	}
}

Doc_Status :: enum {
	Ok,
	Skipped, // did not type-check, or nothing to parse: family A already said why
	Fatal, // odin missing or reader version mismatch: a tool error was recorded
}

doc_package :: proc(
	c: ^Ctx,
	p: ^Package,
	tmp: string,
	i: int,
	flags: []string,
) -> (
	h: ^doc.Header,
	status: Doc_Status,
) {
	if p.pkg == nil || len(p.diags) > 0 {return nil, .Skipped}
	out := join({tmp, fmt.tprintf("%d.odin-doc", i)})
	args := make([dynamic]string, context.temp_allocator)
	append(&args, "doc", p.dir, "-doc-format", strings.concatenate({"-out:", out}))
	append(&args, ..flags)
	code: int
	text: string
	ok: bool
	for _ in 0 ..< 3 {
		code, text, ok = run_odin(c, ..args[:])
		// ponytail: the 2026-09 nightly segfaults intermittently (exit 11, no output): retry
		if !(ok && code != 0 && text == "") {break}
	}
	if !ok {return nil, .Fatal}
	if code != 0 || !os.exists(out) {return nil, .Skipped}
	data, rerr := os.read_entire_file(out, context.allocator)
	if rerr != nil {return nil, .Skipped}
	derr: doc.Reader_Error
	h, derr = doc.read_from_bytes(data)
	if derr != nil {
		tool_error(
			c.r,
			"doc-format reader: %v (compiler wrote version %d.%d.%d); this odx supports %d.%d.x only",
			derr,
			h.version.major,
			h.version.minor,
			h.version.patch,
			DOC_FORMAT_MAJOR,
			DOC_FORMAT_MINOR,
		)
		return nil, .Fatal
	}
	return h, .Ok
}

DOC_FORMAT_MAJOR :: 0
DOC_FORMAT_MINOR :: 3

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
			if "test" in attrs {continue}
			last := last_result_name(h, types, e.type)
			for a in rules {
				if !role_applies(&a.rule.check, p.role) {continue}
				if a.rule.check.kind == .foreign_error_type {
					// An error crosses the package boundary untranslated. The doc format records
					// no position for a type defined outside the documented package, so "" means
					// exactly "declared elsewhere".
					if !has_suffix_any(last, a.rule.check.result_type_suffix) {continue}
					if decl := last_result_pkg(h, types, files, e.type); decl != p.dir {
						fname := doc.from_string(h, files[e.pos.file].name)
						file, _ := rel_of(c.root, join({p.dir, filepath.base(fname)}))
						drel := "another package"
						if decl != "" {drel, _ = rel_of(c.root, decl)}
						report(
							c,
							a,
							file,
							int(e.pos.line),
							int(e.pos.column),
							fmt.tprintf(
								"%s returns %s declared in %s; translate it into this package's Error at the boundary",
								doc.from_string(h, e.name),
								last,
								drel,
							),
							doc.from_string(h, e.name),
						)
					}
					continue
				}
				if a.rule.check.attribute in attrs ||
				   !has_suffix_any(last, a.rule.check.result_type_suffix) {continue}
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
							a.rule.check.attribute,
							")",
						},
					),
					doc.from_string(h, e.name),
				)
			}
		}
	}
}

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
last_result_pkg :: proc(
	h: ^doc.Header,
	types: []doc.Type,
	files: []doc.File,
	ti: doc.Type_Index,
) -> string {
	t := types[ti]
	if t.kind != .Proc {return ""}
	sub := doc.from_array(h, t.types)
	if len(sub) < 2 || sub[1] == 0 {return ""}
	res_ents := doc.from_array(h, types[sub[1]].entities)
	if len(res_ents) == 0 {return ""}
	ents := doc.from_array(h, h.entities)
	last := types[ents[res_ents[len(res_ents) - 1]].type]
	if last.kind != .Named {return ""}
	defs := doc.from_array(h, last.entities)
	if len(defs) == 0 {return ""}
	pkgs := doc.from_array(h, h.pkgs)
	return doc.from_string(h, pkgs[files[ents[defs[0]].pos.file].pkg].fullpath)
}

@(private = "file")
has_suffix_any :: proc(s: string, suffixes: []string) -> bool {
	if s == "" {return false}
	for suf in suffixes {if strings.has_suffix(s, suf) {return true}}
	return false
}
