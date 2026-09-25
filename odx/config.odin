package odx

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:reflect"

Role :: enum {
	pure,
	service,
	edge,
}

Config :: struct {
	roles:          [Role][]string,
	external:       []string,
	error_types:    []string,
	exclude:        []string,
	compiler_flags: []string,
}

@(rodata)
DEFAULT_COMPILER_FLAGS := []string {
	"-vet",
	"-strict-style",
	"-vet-using-param",
	"-disallow-do",
	"-warnings-as-errors",
}

Entry :: struct {
	key:   string,
	value: json.Value,
}

// load_config reads root/odx.json. A non-empty reason says why it couldn't be used,
// without the file name. Everything is allocated with context.allocator.
load_config :: proc(root: string) -> (cfg: Config, reason: string) {
	path, _ := filepath.join({root, "odx.json"})
	data, read_err := os.read_entire_file(path, context.allocator)
	if read_err == os.General_Error.Not_Exist {
		return {}, "not found; minimal odx.json: {}"
	}
	if read_err != nil {
		return {}, os.error_string(read_err)
	}
	entries: []Entry
	if entries, reason = read_object(string(data)); reason != "" {
		return {}, reason
	}
	return decode_config(entries)
}

// read_object parses data as one JSON object with unique keys, keeping them in order.
// json.parse can't do this: it accepts trailing text and doesn't name a repeated key.
read_object :: proc(data: string) -> (entries: []Entry, reason: string) {
	p := json.make_parser_from_string(data, .JSON)
	if p.curr_token.kind != .Open_Brace {
		_, err := json.parse_value(&p)
		if err != nil || p.curr_token.kind != .EOF {
			return nil, "not valid JSON"
		}
		return nil, "not a JSON object"
	}
	list, err := parse_entries(&p)
	if err != nil || p.curr_token.kind != .EOF {
		return nil, "not valid JSON"
	}
	seen: map[string]bool
	for e in list {
		if e.key in seen {
			return nil, fmt.aprintf("repeated key %q", e.key)
		}
		seen[e.key] = true
	}
	return list[:], ""
}

parse_entries :: proc(p: ^json.Parser) -> (entries: [dynamic]Entry, err: json.Error) {
	json.expect_token(p, .Open_Brace) or_return
	for p.curr_token.kind != .Close_Brace {
		e: Entry
		e.key = json.parse_object_key(p, context.allocator) or_return
		json.parse_colon(p) or_return
		e.value = json.parse_value(p) or_return
		append(&entries, e)
		if json.parse_comma(p) {
			break
		}
	}
	err = json.expect_token(p, .Close_Brace)
	return
}

// decode_config checks odx's schema: known keys, each an array of strings.
decode_config :: proc(entries: []Entry) -> (cfg: Config, reason: string) {
	cfg.compiler_flags = DEFAULT_COMPILER_FLAGS
	for e in entries {
		field: ^[]string
		if role, is_role := reflect.enum_from_name(Role, e.key); is_role {
			field = &cfg.roles[role]
		} else {
			switch e.key {
			case "external":
				field = &cfg.external
			case "error_types":
				field = &cfg.error_types
			case "exclude":
				field = &cfg.exclude
			case "compiler_flags":
				field = &cfg.compiler_flags
			case:
				return {}, fmt.aprintf("unknown key %q", e.key)
			}
		}
		if field^, reason = string_list(e); reason != "" {
			return {}, reason
		}
	}
	return cfg, ""
}

string_list :: proc(e: Entry) -> (list: []string, reason: string) {
	array, is_array := e.value.(json.Array)
	if !is_array {
		return nil, fmt.aprintf("%q is %s, not an array of strings", e.key, describe(e.value))
	}
	list = make([]string, len(array))
	for element, i in array {
		s, is_string := element.(json.String)
		if !is_string {
			return nil, fmt.aprintf(
				"%q element %d is %s, not a string",
				e.key,
				i,
				describe(element),
			)
		}
		list[i] = s
	}
	return list, ""
}

describe :: proc(value: json.Value) -> string {
	switch _ in value {
	case nil, json.Null:
		return "null"
	case json.Integer, json.Float:
		return "a number"
	case json.Boolean:
		return "a boolean"
	case json.String:
		return "a string"
	case json.Array:
		return "an array"
	case json.Object:
		return "an object"
	}
	unreachable()
}
