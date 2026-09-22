package odx

import "core:encoding/json"
import "core:math"
import "core:slice"
import "core:strings"

validate_check :: proc(c: ^Check_Spec, spec: json.Object, at: string, errs: ^[dynamic]string) {
	require_key(errs, at, spec, "kind")
	check_enum(errs, at, spec, "kind", Check_Kind)
	allowed := make([dynamic]string, context.temp_allocator)
	append(&allowed, "kind", "roles", "except_roles")
	switch c.kind {
	case .path_role, .vet_tag:
	case .banned_import:
		append(&allowed, "from")
		if "from" in spec {check_string_value(spec, "from", at, errs, "dependencies.may_import")}
	case .require_attribute:
		append(&allowed, "attribute", "on")
		require_key(errs, at, spec, "attribute")
		check_string_value(spec, "attribute", at, errs)
		if "on" in spec {check_string_value(spec, "on", at, errs, "exported_procs")}
	case .pattern:
		append(&allowed, "match")
		if !slice.contains(
			PATTERN_MATCHES,
			c.match,
		) {errf(errs, "%s: check.match must be one of %v", at, PATTERN_MATCHES)}
		switch c.match {
		case "call":
			append(&allowed, "name", "names")
			if "name" in spec {check_string_value(spec, "name", at, errs)}
			if "names" in spec {check_string_array(spec, "names", at, errs, false)}
			names := make([dynamic]string)
			for name in c.names {if !slice.contains(names[:], name) {append(&names, name)}}
			if c.name != "" && !slice.contains(names[:], c.name) {append(&names, c.name)}
			c.names = names[:]
			if len(c.names) == 0 {errf(errs, "%s: match: call needs name or names", at)}
		case "import":
			append(&allowed, "name")
			require_key(errs, at, spec, "name")
			check_string_value(spec, "name", at, errs)
		case "proc":
			append(&allowed, "exported", "requires_param")
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
			append(&allowed, "at", "mutable")
			require_key(errs, at, spec, "at")
			check_string_value(spec, "at", at, errs, "package_scope")
			if "mutable" in spec {check_boolean_value(spec, "mutable", at, errs)}
		case "foreign":
		}
	}
	check_keys(errs, at, "check.", spec, allowed[:])
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
