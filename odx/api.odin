package odx

import "core:fmt"
import doc "core:odin/doc-format"
import "core:os"
import "core:path/filepath"
import "core:slice"
import "core:strings"

// `odx api`: one text snapshot per package in api/<pkg>.txt, cargo-public-api style (20.6):
// one fully qualified line per exported entity, resolved types, whitelisted attributes,
// sorted by kind rank then name, diffed as a multiset keyed on `kind path`.
// Missing snapshot: written. Differs: added/removed/changed printed, exit 1.
// ODX_UPDATE_SNAPSHOTS=1 rewrites; the git diff is the review.

API_DIR :: "api"
API_HEADER :: "format_version: 1"
API_ATTRS := []string{"require_results", "deprecated"} // plus any odx_* custom attribute
KIND_RANK := [doc.Entity_Kind]int {
	.Type_Name    = 0,
	.Constant     = 1,
	.Variable     = 2,
	.Procedure    = 3,
	.Proc_Group   = 4,
	.Invalid      = 9,
	.Import_Name  = 9,
	.Library_Name = 9,
	.Builtin      = 9,
}

cmd_api :: proc(o: Opts) {
	p := must_load(o, true)
	c := make_ctx(&p, o.args[:])
	changed := api_snapshots(&c, os.get_env("ODX_UPDATE_SNAPSHOTS", context.temp_allocator) == "1")
	print_tool_errors(c.r)
	if len(c.r.tool_errors) > 0 {os.exit(EXIT_TOOL)}
	if changed > 0 {os.exit(EXIT_VIOLATION)}
}

// api_snapshots renders every package and compares (or writes) its snapshot; returns the
// number of packages whose API differs from the committed file.
api_snapshots :: proc(c: ^Ctx, update: bool) -> (changed: int) {
	tmp, terr := os.make_directory_temp("", "odx-api-*", context.allocator)
	if terr != nil {
		tool_error(c.r, "cannot create temp dir for odin doc")
		return
	}
	defer os.remove_all(tmp)
	flags := odin_flags(c)
	for &p, i in c.pkgs {
		h, status := doc_package(c, &p, tmp, i, flags)
		if status == .Fatal {return}
		if status == .Skipped {
			tool_error(c.r, "%s does not type-check; run odx check", p.rel)
			continue
		}
		text := render_api(h, p.dir)
		name := p.rel if p.rel != "" else "root"
		path := join(
			{c.root, API_DIR, strings.concatenate({name, ".txt"}, context.temp_allocator)},
		)
		old, rerr := os.read_entire_file(path, context.allocator)
		switch {
		case rerr != nil || update:
			os.make_directory_all(filepath.dir(path))
			write_atomic(path, text)
			fmt.printfln("wrote %s/%s.txt", API_DIR, name)
		case string(old) == text:
			fmt.printfln("ok %s", name)
		case:
			changed += 1
			fmt.printfln(
				"%s: API differs from %s/%s.txt (ODX_UPDATE_SNAPSHOTS=1 odx api to re-bless)",
				name,
				API_DIR,
				name,
			)
			for l in api_diff(string(old), text) {fmt.println("  ", l)}
		}
	}
	return
}

// api_diff: a multiset keyed on `kind path`; same key with a different rendering is changed.
api_diff :: proc(old, new: string) -> []string {
	index :: proc(text: string) -> map[string][dynamic]string {
		m := make(map[string][dynamic]string, context.temp_allocator)
		for l in strings.split_lines(text, context.temp_allocator) {
			if l == "" || l == API_HEADER {continue}
			kind, _, rest := strings.partition(l, " ")
			path, _, _ := strings.partition(rest, " ")
			key := strings.concatenate({kind, " ", path}, context.temp_allocator)
			lines := m[key]
			append(&lines, l)
			m[key] = lines
		}
		return m
	}
	a, b := index(old), index(new)
	out := make([dynamic]string)
	for k in sorted_keys(a) {
		if k not_in b {for l in a[k] {append(&out, strings.concatenate({"removed ", l}))}}
	}
	for k in sorted_keys(b) {
		if k not_in a {
			for l in b[k] {append(&out, strings.concatenate({"added   ", l}))}
		} else if !slice.equal(a[k][:], b[k][:]) {
			for l in b[k] {append(&out, strings.concatenate({"changed ", l}))}
		}
	}
	return out[:]
}

// Api_Ctx carries the header and the entity -> package map needed to absolutize names.
Api_Ctx :: struct {
	h:      ^doc.Header,
	ents:   []doc.Entity,
	types:  []doc.Type,
	pkg_of: map[doc.Entity_Index]string, // entity -> package name, for Named types
}

render_api :: proc(h: ^doc.Header, dir: string) -> string {
	a := Api_Ctx {
		h      = h,
		ents   = doc.from_array(h, h.entities),
		types  = doc.from_array(h, h.types),
		pkg_of = make(map[doc.Entity_Index]string, context.temp_allocator),
	}
	pkgs := doc.from_array(h, h.pkgs)
	for pkg, pi in pkgs {
		if pi == 0 {continue}
		for se in doc.from_array(h, pkg.entries) {a.pkg_of[se.entity] = doc.from_string(h, pkg.name)}
	}
	Line :: struct {
		rank: int,
		text: string,
	}
	lines := make([dynamic]Line, context.temp_allocator)
	for pkg, pi in pkgs {
		if pi == 0 || doc.from_string(h, pkg.fullpath) != dir {continue}
		pname := doc.from_string(h, pkg.name)
		for se in doc.from_array(h, pkg.entries) {
			e := a.ents[se.entity]
			if .Private in e.flags ||
			   e.kind == .Import_Name ||
			   e.kind == .Library_Name ||
			   e.kind == .Builtin {continue}
			b := strings.builder_make(context.temp_allocator)
			kind := strings.to_lower(fmt.tprint(e.kind), context.temp_allocator)
			fmt.sbprintf(&b, "%s %s.%s", kind, pname, doc.from_string(h, e.name))
			switch e.kind {
			case .Type_Name:
				// an alias points straight at its base type; `distinct` (and every struct, union,
				// enum and bit_field) is a Named type wrapping the base (19.2)
				base, named := e.type, a.types[e.type].kind == .Named
				if named &&
				   a.types[e.type].types.length >
					   0 {base = doc.from_array(h, a.types[e.type].types)[0]}
				keyword :=
					"distinct " if named && a.types[base].kind not_in ALWAYS_DISTINCT else ""
				fmt.sbprintf(&b, " :: %s%s", keyword, render_type(&a, base, 0))
			case .Constant:
				fmt.sbprintf(&b, " :: %s", render_type(&a, e.type, 0))
			case .Variable:
				fmt.sbprintf(&b, ": %s", render_type(&a, e.type, 0))
			case .Procedure:
				fmt.sbprintf(&b, " :: %s", render_type(&a, e.type, 0))
			case .Proc_Group:
				names := make([dynamic]string, context.temp_allocator)
				for gi in doc.from_array(h, e.grouped_entities) {append(&names, doc.from_string(h, a.ents[gi].name))}
				slice.sort(names[:])
				strings.write_string(
					&b,
					strings.concatenate(
						{" :: proc{", strings.join(names[:], ", ", context.temp_allocator), "}"},
						context.temp_allocator,
					),
				)
			case .Invalid, .Import_Name, .Library_Name, .Builtin:
			}
			attrs := make([dynamic]string, context.temp_allocator)
			for at in doc.from_array(h, e.attributes) {
				name := doc.from_string(h, at.name)
				if !slice.contains(API_ATTRS, name) && !strings.has_prefix(name, "odx_") {continue}
				val := doc.from_string(h, at.value)
				append(&attrs, name if val == "" else fmt.tprintf("%s=%s", name, val))
			}
			slice.sort(attrs[:])
			if len(attrs) >
			   0 {fmt.sbprintf(&b, " @(%s)", strings.join(attrs[:], ", ", context.temp_allocator))}
			append(&lines, Line{KIND_RANK[e.kind], strings.clone(strings.to_string(b))})
		}
	}
	slice.sort_by(
		lines[:],
		proc(x, y: Line) -> bool {return x.rank < y.rank if x.rank != y.rank else x.text < y.text},
	)
	out := strings.builder_make()
	fmt.sbprintln(&out, API_HEADER)
	for l in lines {fmt.sbprintln(&out, l.text)}
	return strings.to_string(out)
}

// render_type: a resolved, package-qualified rendering. Deterministic is what matters; the
// exact spelling is odx's, not the compiler's. Depth-limited against recursive types.
// ALWAYS_DISTINCT: type kinds that are unique types without the keyword.
ALWAYS_DISTINCT :: bit_set[doc.Type_Kind]{.Struct, .Union, .Enum, .Bit_Field}

render_type :: proc(a: ^Api_Ctx, ti: doc.Type_Index, depth: int) -> string {
	if depth > 6 {return "..."}
	t := a.types[ti]
	h := a.h
	sub := doc.from_array(h, t.types)
	elem :: proc(a: ^Api_Ctx, sub: []doc.Type_Index, i, depth: int) -> string {
		return render_type(a, sub[i], depth + 1) if i < len(sub) else "?"
	}
	switch t.kind {
	case .Basic:
		return doc.from_string(h, t.name)
	case .Named:
		name := doc.from_string(h, t.name)
		ents := doc.from_array(h, t.entities)
		if len(ents) > 0 {
			if pkg, ok := a.pkg_of[ents[0]];
			   ok &&
			   !strings.contains(
					   name,
					   ".",
				   ) {return strings.concatenate({pkg, ".", name}, context.temp_allocator)}
		}
		return name
	case .Generic:
		return strings.concatenate({"$", doc.from_string(h, t.name)}, context.temp_allocator)
	case .Pointer:
		return strings.concatenate({"^", elem(a, sub, 0, depth)}, context.temp_allocator)
	case .Multi_Pointer:
		return strings.concatenate({"[^]", elem(a, sub, 0, depth)}, context.temp_allocator)
	case .Soa_Pointer:
		return strings.concatenate({"#soa ^", elem(a, sub, 0, depth)}, context.temp_allocator)
	case .Slice:
		return strings.concatenate({"[]", elem(a, sub, 0, depth)}, context.temp_allocator)
	case .Dynamic_Array:
		return strings.concatenate({"[dynamic]", elem(a, sub, 0, depth)}, context.temp_allocator)
	case .Fixed_Capacity_Dynamic_Array:
		return fmt.tprintf("[dynamic, %d]%s", t.elem_counts[0], elem(a, sub, 0, depth))
	case .Array:
		return fmt.tprintf("[%d]%s", t.elem_counts[0], elem(a, sub, 0, depth))
	case .Enumerated_Array:
		return fmt.tprintf("[%s]%s", elem(a, sub, 0, depth), elem(a, sub, 1, depth))
	case .Simd_Vector:
		return fmt.tprintf("#simd[%d]%s", t.elem_counts[0], elem(a, sub, 0, depth))
	case .Matrix:
		return fmt.tprintf(
			"matrix[%d, %d]%s",
			t.elem_counts[0],
			t.elem_counts[1],
			elem(a, sub, 0, depth),
		)
	case .Map:
		return fmt.tprintf("map[%s]%s", elem(a, sub, 0, depth), elem(a, sub, 1, depth))
	case .SOA_Struct_Fixed:
		return fmt.tprintf("#soa[%d]%s", t.elem_counts[0], elem(a, sub, 0, depth))
	case .SOA_Struct_Slice:
		return strings.concatenate({"#soa[]", elem(a, sub, 0, depth)}, context.temp_allocator)
	case .SOA_Struct_Dynamic:
		return strings.concatenate(
			{"#soa[dynamic]", elem(a, sub, 0, depth)},
			context.temp_allocator,
		)
	case .Relative_Pointer, .Relative_Multi_Pointer:
		return fmt.tprintf("#relative(%s) %s", elem(a, sub, 1, depth), elem(a, sub, 0, depth))
	case .Bit_Set:
		return fmt.tprintf("bit_set[%s]", elem(a, sub, 0, depth))
	case .Bit_Field:
		return strings.concatenate(
			{"bit_field ", elem(a, sub, 0, depth), " {", render_fields(a, t, depth), "}"},
			context.temp_allocator,
		)
	case .Struct:
		return strings.concatenate(
			{"struct {", render_fields(a, t, depth), "}"},
			context.temp_allocator,
		)
	case .Union:
		parts := make([dynamic]string, context.temp_allocator)
		for s in sub {append(&parts, render_type(a, s, depth + 1))}
		return strings.concatenate(
			{"union {", strings.join(parts[:], ", ", context.temp_allocator), "}"},
			context.temp_allocator,
		)
	case .Enum:
		names := make([dynamic]string, context.temp_allocator)
		for ei in doc.from_array(h, t.entities) {
			name, value :=
				doc.from_string(h, a.ents[ei].name), doc.from_string(h, a.ents[ei].init_string)
			append(&names, name if value == "" else fmt.tprintf("%s = %s", name, value))
		}
		return strings.concatenate(
			{"enum {", strings.join(names[:], ", ", context.temp_allocator), "}"},
			context.temp_allocator,
		)
	case .Parameters:
		return render_fields(a, t, depth)
	case .Proc:
		flags := transmute(doc.Type_Flags_Proc)t.flags
		b := strings.builder_make(context.temp_allocator)
		strings.write_string(&b, "proc")
		if cc := doc.from_string(h, t.calling_convention);
		   cc != "" && cc != "odin" {fmt.sbprintf(&b, " %q", cc)}
		fmt.sbprintf(&b, "(%s)", elem(a, sub, 0, depth) if len(sub) > 0 && sub[0] != 0 else "")
		if len(sub) > 1 && sub[1] != 0 {fmt.sbprintf(&b, " -> (%s)", elem(a, sub, 1, depth))}
		if .Diverging in flags {strings.write_string(&b, " -> !")}
		if .Optional_Ok in flags {strings.write_string(&b, " #optional_ok")}
		return strings.to_string(b)
	case .Invalid:
	}
	return "?"
}

// render_fields: `name: type` per entity, defaults shown as source text.
render_fields :: proc(a: ^Api_Ctx, t: doc.Type, depth: int) -> string {
	parts := make([dynamic]string, context.temp_allocator)
	for ei in doc.from_array(a.h, t.entities) {
		e := a.ents[ei]
		name := doc.from_string(a.h, e.name)
		s := render_type(a, e.type, depth + 1)
		if name != "" {s = fmt.tprintf("%s: %s", name, s)}
		if init := doc.from_string(a.h, e.init_string);
		   init != "" {s = fmt.tprintf("%s = %s", s, init)}
		if .Param_Ellipsis in e.flags {s = strings.concatenate({"..", s}, context.temp_allocator)}
		append(&parts, s)
	}
	return strings.join(parts[:], ", ", context.temp_allocator)
}
