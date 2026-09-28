package odx

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:reflect"
import "core:strconv"
import "core:strings"

CONFIG_FILE :: "odx.json"
CONFIG_VERSION :: 1
SUPPORTED_VERSIONS :: "1"

// Role is a key under "packages" in odx.json.
Role :: enum {
	stateless,
	app,
	external,
}

// Entry is one string from odx.json with its 1-based position, so later checks can point at it.
Entry :: struct {
	value:  string,
	line:   int,
	column: int,
}

// Config is odx.json after its shape is checked. Whether its directories and collection
// paths exist is checked later, against the repository.
Config :: struct {
	version:      int,
	packages:     [Role][]Entry,
	exclude_dirs: []Entry,
	collections:  []Entry,
	defines:      []Entry,
}

// load_config reads root/odx.json. Every problem is appended to r; ok is false if there was
// any. Everything is allocated with context.allocator.
@(require_results)
load_config :: proc(r: ^Report, root: string) -> (cfg: Config, ok: bool) {
	path, _ := filepath.join({root, CONFIG_FILE})
	data, read_err := os.read_entire_file(path, context.allocator)
	if read_err == os.General_Error.Not_Exist {
		append(
			&r.reasons,
			Reason{path = CONFIG_FILE, message = `not found; minimal odx.json: {"version": 1}`},
		)
		return
	}
	if read_err != nil {
		append(&r.reasons, Reason{path = CONFIG_FILE, message = os.error_string(read_err)})
		return
	}
	d := Decoder {
		r    = r,
		data = string(data),
	}
	start := len(r.reasons)
	root_node := parse_json(&d) or_return
	cfg = decode_config(&d, root_node)
	return cfg, len(r.reasons) == start
}

// Decoder reads odx.json as strict JSON (RFC 8259) into Nodes that keep their offsets.
// json.parse can't be used: it skips a BOM, accepts trailing commas and trailing text,
// keeps only the last of a repeated key, and has no positions.
Decoder :: struct {
	r:    ^Report,
	data: string,
	t:    json.Tokenizer,
	tok:  json.Token,
}

Json_Kind :: enum {
	Null,
	Boolean,
	Integer,
	Float,
	String,
	Array,
	Object,
}

// Node is one JSON value. text is the unquoted value of a string and the source text of
// any other scalar.
Node :: struct {
	kind:     Json_Kind,
	offset:   int,
	text:     string,
	elements: []Node,
	members:  []Member,
}

Member :: struct {
	key:    string,
	offset: int,
	value:  Node,
}

// position turns a byte offset into a 1-based line and a 1-based column counted in code
// points, as the compiler counts them.
position :: proc(data: string, offset: int) -> (line, column: int) {
	line, column = 1, 1
	for c in data[:offset] {
		if c == '\n' {
			line += 1
			column = 1
		} else {
			column += 1
		}
	}
	return
}

config_error :: proc(d: ^Decoder, offset: int, format: string, args: ..any) {
	line, column := position(d.data, offset)
	append(&d.r.reasons, Reason{CONFIG_FILE, line, column, fmt.aprintf(format, ..args)})
}

syntax_error :: proc(d: ^Decoder, offset: int, detail: string) {
	if detail == "" {
		config_error(d, offset, "not valid JSON")
	} else {
		config_error(d, offset, "not valid JSON: %s", detail)
	}
}

// unexpected reports the current token as a syntax error.
unexpected :: proc(d: ^Decoder) {
	syntax_error(d, d.tok.offset, d.tok.kind == .EOF ? "unexpected end of file" : "")
}

@(require_results)
advance :: proc(d: ^Decoder) -> bool {
	err: json.Error
	d.tok, err = json.get_token(&d.t)
	// The tokenizer also ends at a NUL byte; only the real end of the data is the end.
	if err == .None || (err == .EOF && d.tok.offset == len(d.data)) {
		return true
	}
	syntax_error(d, d.tok.offset, strings.has_prefix(d.data[d.tok.offset:], "/") ? "comment" : "")
	return false
}

@(require_results)
expect :: proc(d: ^Decoder, kind: json.Token_Kind) -> bool {
	if d.tok.kind != kind {
		unexpected(d)
		return false
	}
	return advance(d)
}

// parse_json parses the whole file. It stops at the first syntax error.
@(require_results)
parse_json :: proc(d: ^Decoder) -> (n: Node, ok: bool) {
	if strings.has_prefix(d.data, "\xef\xbb\xbf") {
		syntax_error(d, 0, "starts with a UTF-8 byte order mark")
		return
	}
	d.t = json.make_tokenizer(d.data, .JSON, parse_integers = true)
	advance(d) or_return
	n = parse_value(d) or_return
	if d.tok.kind != .EOF {
		syntax_error(d, d.tok.offset, "text after the top-level value")
		return
	}
	return n, true
}

@(require_results)
parse_value :: proc(d: ^Decoder) -> (n: Node, ok: bool) {
	n.offset = d.tok.offset
	n.text = d.tok.text
	#partial switch d.tok.kind {
	case .Null:
		n.kind = .Null
	case .True, .False:
		n.kind = .Boolean
	case .Integer:
		n.kind = .Integer
	case .Float:
		n.kind = .Float
	case .String:
		n.kind = .String
		err: json.Error
		if n.text, err = json.unquote_string(d.tok, .JSON, context.allocator); err != .None {
			unexpected(d)
			return
		}
	case .Open_Bracket:
		return parse_array(d)
	case .Open_Brace:
		return parse_object(d)
	case:
		unexpected(d)
		return
	}
	return n, advance(d)
}

@(require_results)
parse_array :: proc(d: ^Decoder) -> (n: Node, ok: bool) {
	n = {
		kind   = .Array,
		offset = d.tok.offset,
	}
	advance(d) or_return
	elements: [dynamic]Node
	for d.tok.kind != .Close_Bracket {
		append(&elements, parse_value(d) or_return)
		if d.tok.kind != .Comma {break}
		comma := d.tok.offset
		advance(d) or_return
		if d.tok.kind == .Close_Bracket {
			syntax_error(d, comma, "trailing comma")
			return
		}
	}
	expect(d, .Close_Bracket) or_return
	n.elements = elements[:]
	return n, true
}

@(require_results)
parse_object :: proc(d: ^Decoder) -> (n: Node, ok: bool) {
	n = {
		kind   = .Object,
		offset = d.tok.offset,
	}
	advance(d) or_return
	members: [dynamic]Member
	for d.tok.kind != .Close_Brace {
		if d.tok.kind != .String {
			unexpected(d)
			return
		}
		key := parse_value(d) or_return
		expect(d, .Colon) or_return
		value := parse_value(d) or_return
		append(&members, Member{key.text, key.offset, value})
		if d.tok.kind != .Comma {break}
		comma := d.tok.offset
		advance(d) or_return
		if d.tok.kind == .Close_Brace {
			syntax_error(d, comma, "trailing comma")
			return
		}
	}
	expect(d, .Close_Brace) or_return
	n.members = members[:]
	return n, true
}

// decode_config checks the shape of odx.json, version 1, and reports every problem.
// When the version is missing or unsupported, the other keys aren't checked, since what's
// valid depends on the version.
decode_config :: proc(d: ^Decoder, root: Node) -> (cfg: Config) {
	check_repeated_keys(d, root)
	if root.kind != .Object {
		config_error(d, root.offset, "top-level value is %s, not an object", describe(root))
		return
	}
	version, found := find_member(root, "version")
	if !found {
		append(
			&d.r.reasons,
			Reason {
				path = CONFIG_FILE,
				message = `"version" is missing; supported versions: ` + SUPPORTED_VERSIONS,
			},
		)
		return
	}
	if version.kind != .Integer {
		config_error(
			d,
			version.offset,
			`"version" is %s, not an integer; supported versions: %s`,
			describe(version),
			SUPPORTED_VERSIONS,
		)
		return
	}
	if v, is_int := strconv.parse_int(version.text, 10); !is_int || v != CONFIG_VERSION {
		config_error(
			d,
			version.offset,
			"version %s is not supported; supported versions: %s",
			version.text,
			SUPPORTED_VERSIONS,
		)
		return
	}
	cfg.version = CONFIG_VERSION
	for m in root.members {
		switch m.key {
		case "version":
		case "packages":
			if m.value.kind != .Object {
				config_error(
					d,
					m.value.offset,
					`"packages" is %s, not an object`,
					describe(m.value),
				)
				continue
			}
			for p in m.value.members {
				label := fmt.aprintf("packages.%s", p.key)
				role, is_role := reflect.enum_from_name(Role, p.key)
				if !is_role {
					config_error(d, p.offset, "unknown key %q", label)
					continue
				}
				cfg.packages[role] = string_list(d, p.value, label)
			}
		case "exclude_dirs":
			cfg.exclude_dirs = string_list(d, m.value, m.key)
		case "collections":
			cfg.collections = string_list(d, m.value, m.key)
		case "defines":
			cfg.defines = string_list(d, m.value, m.key)
		case:
			config_error(d, m.offset, "unknown key %q", m.key)
		}
	}
	return cfg
}

check_repeated_keys :: proc(d: ^Decoder, n: Node) {
	for m, i in n.members {
		for prev in n.members[:i] {
			if prev.key == m.key {
				config_error(d, m.offset, "repeated key %q", m.key)
				break
			}
		}
		check_repeated_keys(d, m.value)
	}
	for e in n.elements {
		check_repeated_keys(d, e)
	}
}

@(require_results)
find_member :: proc(n: Node, key: string) -> (value: Node, found: bool) {
	for m in n.members {
		if m.key == key {return m.value, true}
	}
	return
}

string_list :: proc(d: ^Decoder, n: Node, label: string) -> []Entry {
	if n.kind != .Array {
		config_error(d, n.offset, "%q is %s, not an array of strings", label, describe(n))
		return nil
	}
	list := make([]Entry, len(n.elements))
	for e, i in n.elements {
		if e.kind != .String {
			config_error(d, e.offset, "element of %q is %s, not a string", label, describe(e))
			continue
		}
		line, column := position(d.data, e.offset)
		list[i] = {e.text, line, column}
	}
	return list
}

// describe names a value's type; scalars other than strings are shown as written.
describe :: proc(n: Node) -> string {
	switch n.kind {
	case .Null, .Boolean, .Integer, .Float:
		return n.text
	case .String:
		return "a string"
	case .Array:
		return "an array"
	case .Object:
		return "an object"
	}
	unreachable()
}
