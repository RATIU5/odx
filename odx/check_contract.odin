package odx

import "core:encoding/json"
import "core:math"
import "core:slice"
import "core:strings"

// One row per (kind, match) combination: the legal selector keys beyond the common three, plus
// the evidence source and boundary prose reported for it. check_fields, rule_evidence,
// PATTERN_MATCHES and CHECK_KEYS all derive from this table; validate_check keeps only the
// per-kind predicates.
Check_Shape :: struct {
	kind:     Check_Kind,
	match:    string, // "" for non-pattern kinds
	fields:   []string, // selector keys after kind/roles/except_roles, in serialization order
	evidence: string,
	boundary: string,
}

// Pattern rows are listed in the order PATTERN_MATCHES reports them in validation errors.
CHECK_SHAPES := [?]Check_Shape {
	{
		kind = .path_role,
		evidence = "configuration",
		boundary = "selected package directories and configured role globs",
	},
	{
		kind = .banned_import,
		fields = {"from"},
		evidence = "source_import_graph",
		boundary = "recursive ordinary source imports with direct test allow exceptions; dependency *_test.odin edges omitted; unconfigured core/base/vendor collections are opaque leaves; required missing/excluded/unknown/outside project evidence is unavailable; no foreign or runtime effect guarantee",
	},
	{
		kind = .vet_tag,
		evidence = "native_tokens",
		boundary = "file tag presence only; no allocator behavior or lifetime proof",
	},
	{
		kind = .require_attribute,
		fields = {"attribute", "on"},
		evidence = "compiler_entities",
		boundary = "compiler-selected exported procedure declarations, excluding @(test); canonical named final-result suffixes and optional structural classification from errors configuration; attribute presence only, no error-intent or caller-handling proof",
	},
	// names: syntactic `pkg.name` or bare `name`; aliases are best effort
	{
		kind = .pattern,
		match = "call",
		fields = {"match", "name", "names"},
		evidence = "native_ast",
		boundary = "recursive syntactic calls in all branches; file import aliases normalized without lexical name resolution; indirect calls not resolved",
	},
	// name: an import glob (`core:fmt`, `core:sys/*`)
	{
		kind = .pattern,
		match = "import",
		fields = {"match", "name"},
		evidence = "native_ast",
		boundary = "package-scope import declarations through all when branches and foreign blocks; one finding per matching declaration; procedure bodies excluded; syntax only, no resolved identity or runtime effect proof",
	},
	// exported / requires_param: package-level procedures
	{
		kind = .pattern,
		match = "proc",
		fields = {"match", "exported", "requires_param"},
		evidence = "native_ast",
		boundary = "package-scope procedure literals through all when branches and foreign blocks; procedure bodies excluded; exported excludes only declarations with their own @(private) attribute, not inherited privacy; parameter types matched by written suffix, not resolved identity",
	},
	// at: package_scope, mutable: package-level value declarations
	{
		kind = .pattern,
		match = "decl",
		fields = {"match", "at", "mutable"},
		evidence = "native_ast",
		boundary = "package-scope decl declarations through all when branches and foreign blocks; one finding per matching declaration; procedure bodies excluded; syntax only, no resolved identity or runtime effect proof",
	},
	// foreign import and foreign block declarations
	{
		kind = .pattern,
		match = "foreign",
		fields = {"match"},
		evidence = "native_ast",
		boundary = "package-scope foreign declarations through all when branches and foreign blocks; one finding per matching declaration; procedure bodies excluded; syntax only, no resolved identity or runtime effect proof",
	},
	// braced then-body with one return, call, or assignment and no else
	{
		kind = .pattern,
		match = "if",
		fields = {"match"},
		evidence = "native_ast",
		boundary = "braced if then-body without else containing exactly one return, call statement, or assignment; includes nested and inactive bodies; excludes declarations, defer and nested control statements; counts syntax, not runtime effects",
	},
}

check_shape :: proc(c: Check_Spec) -> (shape: Check_Shape, ok: bool) {
	match := c.match if c.kind == .pattern else ""
	for row in CHECK_SHAPES {
		if row.kind == c.kind && row.match == match {return row, true}
	}
	return {}, false
}

// Validation and policy exports share the same selector shape.
check_fields :: proc(c: Check_Spec) -> []string {
	fields := make([dynamic]string, context.temp_allocator)
	append(&fields, "kind", "roles", "except_roles")
	if shape, ok := check_shape(c); ok {
		append(&fields, ..shape.fields)
	} else if c.kind == .pattern {
		// An unrecognized match still allows the key that names it; validate_check reports it.
		append(&fields, "match")
	}
	return fields[:]
}

@(private = "file")
pattern_buf: [len(CHECK_SHAPES)]string
@(private = "file")
key_buf: [3 + len(CHECK_SHAPES) * 3]string

@(init)
derive_check_tables :: proc "contextless" () {
	nm, nk := 0, 3
	key_buf[0], key_buf[1], key_buf[2] = "kind", "roles", "except_roles"
	for row in CHECK_SHAPES {
		if row.kind == .pattern {
			pattern_buf[nm] = row.match
			nm += 1
		}
		field_loop: for f in row.fields {
			for k in key_buf[:nk] {if k == f {continue field_loop}}
			key_buf[nk] = f
			nk += 1
		}
	}
	PATTERN_MATCHES = pattern_buf[:nm]
	CHECK_KEYS = key_buf[:nk]
}

validate_check :: proc(c: ^Check_Spec, spec: json.Object, at: string, errs: ^[dynamic]string) {
	require_key(errs, at, spec, "kind")
	check_enum(errs, at, spec, "kind", Check_Kind)
	allowed := check_fields(c^)
	switch c.kind {
	case .path_role, .vet_tag:
	case .banned_import:
		if "from" in spec {check_string_value(spec, "from", at, errs, "dependencies.may_import")}
	case .require_attribute:
		require_key(errs, at, spec, "attribute")
		check_string_value(spec, "attribute", at, errs)
		if "on" in spec {check_string_value(spec, "on", at, errs, "exported_procs")}
	case .pattern:
		if !slice.contains(
			PATTERN_MATCHES,
			c.match,
		) {errf(errs, "%s: check.match must be one of %v", at, PATTERN_MATCHES)}
		switch c.match {
		case "call":
			if "name" in spec {check_string_value(spec, "name", at, errs)}
			if "names" in spec {check_string_array(spec, "names", at, errs, false)}
			names := make([dynamic]string)
			for name in c.names {if !slice.contains(names[:], name) {append(&names, name)}}
			if c.name != "" && !slice.contains(names[:], c.name) {append(&names, c.name)}
			c.names = names[:]
			if len(c.names) == 0 {errf(errs, "%s: match: call needs name or names", at)}
		case "import":
			require_key(errs, at, spec, "name")
			check_string_value(spec, "name", at, errs)
		case "proc":
			if "exported" in spec {check_boolean_value(spec, "exported", at, errs)}
			if value, present := spec["requires_param"]; present {
				param, ok := value.(json.Object)
				if !ok {errf(errs, "%s: check.requires_param must be an object", at)} else {
					check_keys(errs, at, "check.requires_param.", param, {"index", "type_suffix"})
					require_key(errs, at, param, "type_suffix")
					check_string_value(param, "type_suffix", at, errs)
					if index, has_index := param["index"]; has_index {
						valid := false
						#partial switch n in index {
						case json.Integer:
							valid = n >= 0 && u64(n) <= u64(max(int))
						case json.Float:
							valid =
								!math.is_nan(n) &&
								!math.is_inf(n) &&
								n >= 0 &&
								n < f64(max(int)) &&
								math.trunc(n) == n
						}
						if !valid {errf(errs, "%s: check.requires_param.index must be a nonnegative integer representable as int", at)}
					}
				}
			}
		case "decl":
			require_key(errs, at, spec, "at")
			check_string_value(spec, "at", at, errs, "package_scope")
			if "mutable" in spec {check_boolean_value(spec, "mutable", at, errs)}
		case "foreign", "if":
		}
	}
	check_keys(errs, at, "check.", spec, allowed)
	role_keys := []string{"roles", "except_roles"}
	for key in role_keys {
		if key in spec {check_string_array(spec, key, at, errs, true)}
	}
}

check_string_value :: proc(
	spec: json.Object,
	key, at: string,
	errs: ^[dynamic]string,
	expected := "",
) -> bool {
	value, ok := spec[key].(json.String)
	if !ok || strings.trim_space(value) == "" {
		errf(errs, "%s: check.%s must be a nonempty string", at, key)
		return false
	}
	if expected != "" && value != expected {
		errf(errs, "%s: check.%s must be %s", at, key, expected)
		return false
	}
	return true
}

check_boolean_value :: proc(spec: json.Object, key, at: string, errs: ^[dynamic]string) {
	if _, ok := spec[key].(json.Boolean);
	   !ok {errf(errs, "%s: check.%s must be a boolean", at, key)}
}

check_string_array :: proc(
	spec: json.Object,
	key, at: string,
	errs: ^[dynamic]string,
	allow_unmapped: bool,
) {
	items, ok := spec[key].(json.Array)
	if !ok {
		errf(errs, "%s: check.%s must be an array of strings", at, key)
		return
	}
	for value in items {
		s, is_string := value.(json.String)
		if !is_string || (strings.trim_space(s) == "" && !(allow_unmapped && s == "")) {
			errf(
				errs,
				"%s: check.%s entries must be nonempty strings%s",
				at,
				key,
				" or the empty unmapped-role string" if allow_unmapped else "",
			)
		}
	}
}
