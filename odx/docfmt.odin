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
	return k == .require_attribute
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

@(require_results)
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
		// ponytail: the 2026-09 nightly crashes intermittently on `odin doc`: retry a failure
		// that carries no diagnostic (a crash), not one the compiler explained
		if !ok || code == 0 || strings.contains(text, "Error:") {break}
	}
	if !ok {return nil, .Fatal}
	if code != 0 && !strings.contains(text, "Error:") {
		// no diagnostic means the tool failed, not the code; say which rule that silences
		rel, _ := rel_of(c.root, p.dir)
		tool_error(c.r, "odin doc failed on %s (exit %d) with no diagnostic: errors/R3 (require_results) is NOT checked there", rel, code)
		return nil, .Skipped
	}
	if code != 0 || !os.exists(out) {return nil, .Skipped} 	// family A already said why
	data, rerr := os.read_entire_file(out, context.allocator)
	if rerr != nil {return nil, .Skipped}
	derr: doc.Reader_Error
	h, derr = doc.read_from_bytes(data)
	want := doc.Version_Type_Default
	if derr == .Invalid_Version {
		// core's reader wants the exact version it was built with; a newer minor within the
		// same major only adds fields, so read it and say so once. A major bump is fatal and
		// names what stops being checked, rather than going quiet.
		hb := (^doc.Header_Base)(raw_data(data))
		got := hb.version
		if got.major == want.major && got.minor >= want.minor {
			if !doc_version_warned {
				doc_version_warned = true
				fmt.eprintfln(
					"odx: warning: odin doc-format %d.%d.%d is newer than the %d.%d.x this odx was built against; reading it anyway",
					got.major,
					got.minor,
					got.patch,
					want.major,
					want.minor,
				)
			}
			return (^doc.Header)(hb), .Ok
		}
		tool_error(
			c.r,
			"doc-format %d.%d.%d is not the %d.%d.x this odx reads: errors/R3 (require_results) is NOT checked until odx is rebuilt against this compiler",
			got.major,
			got.minor,
			got.patch,
			want.major,
			want.minor,
		)
		return nil, .Fatal
	}
	if derr != nil {
		tool_error(c.r, "doc-format reader: %v; errors/R3 (require_results) is NOT checked", derr)
		return nil, .Fatal
	}
	return h, .Ok
}

// ponytail: one process, one warning; the doc pass runs per package.
@(private = "file")
doc_version_warned: bool

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
			last, is_err := last_result_error(h, types, ents, e.type, c.cfg.errors.types)
			for a in rules {
				if !role_applies(&a.rule.check, p.role) {continue}
				if a.rule.check.attribute in attrs || !is_err {continue}
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

// last_result_error: the name of a procedure's last result type and whether it is an error
// type: a name ending in one of `suffixes` (odx.json5 errors.types), or, regardless of name,
// an enum with a None/Ok variant or a union that admits nil. The name is the entry point a
// grep could do; the structure is what only the checked entity table can say.
@(private = "file")
last_result_error :: proc(
	h: ^doc.Header,
	types: []doc.Type,
	ents: []doc.Entity,
	ti: doc.Type_Index,
	suffixes: []string,
) -> (
	name: string,
	is_err: bool,
) {
	t := types[ti]
	if t.kind != .Proc {return}
	sub := doc.from_array(h, t.types)
	if len(sub) < 2 || sub[1] == 0 {return}
	res_ents := doc.from_array(h, types[sub[1]].entities)
	if len(res_ents) == 0 {return}
	last := types[ents[res_ents[len(res_ents) - 1]].type]
	if last.kind != .Named {return}
	name = doc.from_string(h, last.name)
	for suf in suffixes {if strings.has_suffix(name, suf) {return name, true}}
	named := doc.from_array(h, last.types)
	if len(named) == 0 {return}
	base := types[named[0]]
	#partial switch base.kind {
	case .Enum:
		for ei in doc.from_array(h, base.entities) {
			switch doc.from_string(h, ents[ei].name) {
			case "None", "Ok":
				return name, true
			}
		}
	case .Union:
		flags := transmute(doc.Type_Flags_Union)base.flags
		return name, .No_Nil not_in flags
	}
	return
}
