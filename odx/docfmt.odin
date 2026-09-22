package odx

import "core:fmt"
import doc "core:odin/doc-format"
import "core:os"
import "core:path/filepath"
import "core:strings"

// Family C: `odin doc -doc-format` per package, the compiler's checked entity table.
// Unavailable compiler evidence keeps suppressions unjudged.

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
		for &p in c.pkgs {
			p.doc_result = {.failed, "cannot create temporary directory"}
			p.doc_skipped = true
		}
		return
	}
	defer os.remove_all(tmp)
	flags := odin_flags(c)

	for &p, i in c.pkgs {
		h, status := doc_package(c, &p, tmp, i, flags)
		switch status {
		case .Fatal:
			continue
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
	Skipped,
	Fatal,
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
	p.doc_skipped = true
	if p.parse_result.status == .failed || p.pkg == nil || len(p.diags) > 0 {
		p.doc_result = {.skipped, "source parsing failed"}
		return nil, .Skipped
	}
	if p.compiler_result.status == .failed {
		p.doc_result = {.skipped, "compiler checking failed"}
		return nil, .Skipped
	}
	p.doc_result = {.failed, "compiler entity export unavailable"}
	out := join({tmp, fmt.tprintf("%d.odin-doc", i)})
	args := make([dynamic]string, context.temp_allocator)
	append(&args, "doc", p.dir, "-doc-format", strings.concatenate({"-out:", out}))
	append(&args, ..flags)
	code: int
	text: string
	ok: bool
	for _ in 0 ..< 3 {
		code, text, ok = run_odin(c, ..args[:])
		// Retry the nightly's observed crashes, never explained compiler failures.
		if !ok || code == 0 || text != "" {break}
	}
	if !ok {return nil, .Fatal}
	if code != 0 {
		p.doc_result.reason = fmt.aprintf("odin doc exited %d: %s", code, text)
		tool_error(c.r, "%s: %s; compiler entity rules were not checked", p.rel, p.doc_result.reason)
		return nil, .Skipped
	}
	data, rerr := os.read_entire_file(out, context.allocator)
	if rerr != nil {
		p.doc_result.reason = "compiler entity export missing or unreadable"
		tool_error(c.r, "odin doc %s: %s (%v)", p.rel, p.doc_result.reason, rerr)
		return nil, .Skipped
	}
	reason: string
	unsupported: bool
	h, reason, unsupported = read_doc_evidence(data)
	if h == nil {
		p.doc_result = {.unsupported if unsupported else .failed, reason}
		tool_error(c.r, "odin doc %s: %s; compiler entity rules were not checked", p.rel, reason)
		return nil, .Fatal
	}
	found := false
	for pkg, pi in doc.from_array(h, h.pkgs) {
		if pi != 0 && doc.from_string(h, pkg.fullpath) == p.dir {found = true; break}
	}
	if !found {
		p.doc_result.reason = "requested package absent from compiler entity export"
		tool_error(c.r, "odin doc %s: %s", p.rel, p.doc_result.reason)
		return nil, .Skipped
	}
	p.doc_skipped = false
	p.doc_result = {.complete, ""}
	return h, .Ok
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
