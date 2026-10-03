package odx

import "base:runtime"
import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:slice"
import "core:strconv"
import "core:strings"
import "core:unicode"
import "core:unicode/utf8"

CONFIG_FILE :: "odx.json"

Repo :: struct {
	root:       string,
	has_config: bool,
}

Config :: struct {
	rule_set:     int,
	odin:         string,
	pending:      [dynamic]Pending_Entry,
	vendored:     [dynamic]string,
	exclude_dirs: [dynamic]string,
	collections:  [dynamic]Collection,
	defines:      [dynamic]Define,
}

// `line` and `col` locate the key in odx.json, where `pending-stale` reports.
Pending_Entry :: struct {
	dir:    string,
	reason: string,
	line:   int,
	col:    int,
}

// `path` is the directory's real path, which is what the compiler gets.
Collection :: struct {
	name: string,
	path: string,
}

Define :: struct {
	name:  string,
	value: string,
}

Config_Key :: enum u8 {
	Version,
	Odin,
	Pending,
	Vendored,
	Exclude_Dirs,
	Collections,
	Defines,
}

Config_Key_Info :: struct {
	name:     string,
	required: bool,
	shape:    string,
}

@(rodata)
CONFIG_KEYS := [Config_Key]Config_Key_Info {
	.Version      = {"version", true, "an integer"},
	.Odin         = {"odin", true, "a string"},
	.Pending      = {"pending", false, "an object of dir to reason"},
	.Vendored     = {"vendored", false, "an array of dirs"},
	.Exclude_Dirs = {"exclude_dirs", false, "an array of dirs"},
	.Collections  = {"collections", false, "an array of 'name=path' strings"},
	.Defines      = {"defines", false, "an array of 'NAME=value' strings"},
}

// The Odin root provides these, so a collection by one of these names would shadow it or escape the repo.
@(rodata)
RESERVED_COLLECTIONS := [?]string{"base", "core", "vendor", "shared"}

// The root is the nearest ancestor of the absolute `cwd` holding `odx.json`, else the nearest holding
// `.git`, else `cwd`. Allocates the root with `allocator`.
find_repo :: proc(cwd: string, allocator: runtime.Allocator) -> Repo {
	for marker in ([]string{CONFIG_FILE, ".git"}) {
		dir := cwd
		for {
			if os.exists(fmt.tprintf("%s/%s", dir, marker)) {
				return {strings.clone(dir, allocator), marker == CONFIG_FILE}
			}
			parent := os.dir(dir)
			if parent == dir {
				break
			}
			dir = parent
		}
	}
	return {strings.clone(cwd, allocator), false}
}

// Allocates the config and the errors with `allocator`, which suits an arena.
load_config :: proc(
	root: string,
	allocator: runtime.Allocator,
) -> (
	config: Config,
	errors: [dynamic]Error,
) {
	data, err := os.read_entire_file(fmt.tprintf("%s/%s", root, CONFIG_FILE), allocator)
	if err != nil {
		errors = make([dynamic]Error, allocator)
		append(&errors, invalid(allocator, "could not read %s: %v", CONFIG_FILE, err))
		return
	}
	return parse_config(string(data), root, allocator)
}

// Reports every schema problem in source order, or only the first syntax error. Collection paths
// resolve against `root`. Allocates the config and the errors with `allocator`, which suits an arena.
parse_config :: proc(
	text, root: string,
	allocator: runtime.Allocator,
) -> (
	config: Config,
	errors: [dynamic]Error,
) {
	context.allocator = allocator
	errors = make([dynamic]Error)

	value, syntax := read_json(text)
	if e, bad := syntax.?; bad {
		line, col := text_position(text, e.offset)
		append(
			&errors,
			invalid(allocator, "%s:%d:%d: not strict JSON: %s", CONFIG_FILE, line, col, e.what),
		)
		return
	}
	object, is_object := value.(Json_Object)
	if !is_object {
		append(&errors, invalid(allocator, "%s must hold one JSON object", CONFIG_FILE))
		return
	}

	real_root, root_err := os.get_absolute_path(root, allocator)
	if root_err != nil {
		real_root = root
	}
	seen: bit_set[Config_Key]
	members: for member in object {
		for info, key in CONFIG_KEYS {
			if info.name == member.key {
				seen += {key}
				if !decode_key(&config, &errors, key, member.value, real_root) {
					append(&errors, invalid(allocator, "'%s' must be %s", info.name, info.shape))
				}
				continue members
			}
		}
		append(&errors, invalid(allocator, "unknown key '%s'", member.key))
	}
	for info, key in CONFIG_KEYS {
		if info.required && key not_in seen {
			append(&errors, invalid(allocator, "missing required key '%s'", info.name))
		}
	}
	for dir in config.vendored {
		clean_dir, _ := os.clean_path(dir, context.temp_allocator)
		for entry in config.pending {
			clean_entry, _ := os.clean_path(entry.dir, context.temp_allocator)
			if clean_dir == clean_entry {
				append(
					&errors,
					invalid(allocator, "'%s' is listed under both 'vendored' and 'pending'", dir),
				)
			}
		}
	}
	return
}

// Appends the problems a well-typed value has. Returns false when the value has the wrong type.
@(private = "file")
decode_key :: proc(
	config: ^Config,
	errors: ^[dynamic]Error,
	key: Config_Key,
	value: Json_Value,
	real_root: string,
) -> (
	well_typed: bool,
) {
	switch key {
	case .Version:
		n := value.(i64) or_return
		switch {
		case n < 1:
			append(errors, invalid(context.allocator, "'version' %d is not a rule set", n))
		case n > RULE_SET:
			append(
				errors,
				invalid(
					context.allocator,
					"'version' %d is newer than rule set %d, the newest this release supports",
					n,
					RULE_SET,
				),
			)
		case:
			config.rule_set = int(n)
		}
	case .Odin:
		config.odin = value.(string) or_return
	case .Pending:
		object := value.(Json_Object) or_return
		for member in object {
			reason := member.value.(string) or_return
			if strings.trim_space(reason) == "" {
				append(
					errors,
					invalid(
						context.allocator,
						"'pending' entry '%s' has an empty reason",
						member.key,
					),
				)
			}
			append(&config.pending, Pending_Entry{member.key, reason, member.line, member.col})
		}
	case .Vendored:
		config.vendored = decode_strings(value) or_return
	case .Exclude_Dirs:
		config.exclude_dirs = decode_strings(value) or_return
	case .Collections:
		for entry in decode_strings(value) or_return {
			decode_collection(config, errors, entry, real_root)
		}
	case .Defines:
		for entry in decode_strings(value) or_return {
			decode_define(config, errors, entry)
		}
	}
	return true
}

@(private = "file")
decode_strings :: proc(value: Json_Value) -> (strs: [dynamic]string, ok: bool) {
	array := value.(Json_Array) or_return
	for element in array {
		append(&strs, element.(string) or_return)
	}
	return strs, true
}

// The compiler rejects an empty name or path, a name that starts with a digit, a name already in use,
// and a path that isn't a directory. odx also requires an identifier and a path inside the repo.
@(private = "file")
decode_collection :: proc(config: ^Config, errors: ^[dynamic]Error, entry, real_root: string) {
	name, path, ok := split_entry(entry)
	if !ok {
		append(
			errors,
			invalid(context.allocator, "'collections' entry '%s' is not 'name=path'", entry),
		)
		return
	}
	name_ok := false
	switch {
	case !is_identifier(name):
		append(
			errors,
			invalid(context.allocator, "collection name '%s' is not an identifier", name),
		)
	case slice.contains(RESERVED_COLLECTIONS[:], name):
		append(
			errors,
			invalid(context.allocator, "collection name '%s' is reserved for the Odin root", name),
		)
	case is_listed(config.collections[:], name):
		append(errors, invalid(context.allocator, "collection '%s' is listed twice", name))
	case:
		name_ok = true
	}

	full := path if os.is_absolute_path(path) else fmt.tprintf("%s/%s", real_root, path)
	real, real_err := os.get_absolute_path(full, context.allocator)
	switch {
	case real_err != nil || !os.is_directory(real):
		append(
			errors,
			invalid(context.allocator, "collection '%s' path '%s' is not a directory", name, path),
		)
	case !is_within(real, real_root):
		append(
			errors,
			invalid(
				context.allocator,
				"collection '%s' path '%s' is outside the repo",
				name,
				path,
			),
		)
	case name_ok:
		append(&config.collections, Collection{name, real})
	}
}

// The compiler rejects an empty name or value, a name that starts with a digit, and a name already in use.
// It accepts any non-empty value. odx also requires an identifier.
@(private = "file")
decode_define :: proc(config: ^Config, errors: ^[dynamic]Error, entry: string) {
	name, value, ok := split_entry(entry)
	switch {
	case !ok:
		append(
			errors,
			invalid(context.allocator, "'defines' entry '%s' is not 'NAME=value'", entry),
		)
	case !is_identifier(name):
		append(errors, invalid(context.allocator, "define name '%s' is not an identifier", name))
	case is_listed(config.defines[:], name):
		append(errors, invalid(context.allocator, "define '%s' is listed twice", name))
	case:
		append(&config.defines, Define{name, value})
	}
}

// Splits at the first `=`, as the compiler does, and fails when either side is empty.
@(private = "file")
split_entry :: proc(entry: string) -> (left, right: string, ok: bool) {
	i := strings.index_byte(entry, '=')
	if i <= 0 || i == len(entry) - 1 {
		return
	}
	return entry[:i], entry[i + 1:], true
}

@(private = "file")
is_listed :: proc(entries: []$T, name: string) -> bool {
	for entry in entries {
		if entry.name == name {
			return true
		}
	}
	return false
}

@(private = "file")
is_identifier :: proc(s: string) -> bool {
	for r, i in s {
		if r != '_' && !unicode.is_letter(r) && (i == 0 || !unicode.is_digit(r)) {
			return false
		}
	}
	return s != ""
}

is_within :: proc(path, dir: string) -> bool {
	if !strings.has_prefix(path, dir) {
		return false
	}
	return len(path) == len(dir) || strings.has_suffix(dir, "/") || path[len(dir)] == '/'
}

@(private = "file")
invalid :: proc(allocator: runtime.Allocator, format: string, args: ..any) -> Error {
	return Error{.Config_Invalid, fmt.aprintf(format, ..args, allocator = allocator)}
}

// Lines and columns count from 1, and columns count code points.
text_position :: proc(text: string, offset: int) -> (line, col: int) {
	before := text[:clamp(offset, 0, len(text))]
	line_start := strings.last_index_byte(before, '\n') + 1
	return 1 + strings.count(before, "\n"), 1 + utf8.rune_count_in_string(before[line_start:])
}

// A JSON tree that keeps object members in source order with their key's position.
@(private = "file")
Json_Value :: union {
	Json_Null,
	bool,
	i64,
	f64,
	string,
	Json_Array,
	Json_Object,
}

@(private = "file")
Json_Null :: struct {}

@(private = "file")
Json_Array :: distinct [dynamic]Json_Value

@(private = "file")
Json_Object :: distinct [dynamic]Json_Member

@(private = "file")
Json_Member :: struct {
	key:   string,
	line:  int,
	col:   int,
	value: Json_Value,
}

@(private = "file")
Syntax_Error :: struct {
	offset: int,
	what:   string,
}

@(private = "file")
Json_Reader :: struct {
	data:      string,
	tokenizer: json.Tokenizer,
	token:     json.Token,
}

// Reads one strict JSON document with `core:encoding/json`'s tokenizer. Its parser accepts trailing
// commas, trailing text and tokens the tokenizer flagged, even under `.JSON`. Allocates with
// `context.allocator`.
@(private = "file")
read_json :: proc(data: string) -> (value: Json_Value, err: Maybe(Syntax_Error)) {
	// The tokenizer skips these as whitespace, and JSON doesn't allow them.
	if i := strings.index_any(data, "\v\f"); i >= 0 {
		return nil, Syntax_Error{i, "unexpected character"}
	}
	r := Json_Reader {
		data      = data,
		tokenizer = json.make_tokenizer(data, .JSON, parse_integers = true),
	}
	advance(&r) or_return
	value = read_value(&r) or_return
	if r.token.kind != .EOF {
		return nil, Syntax_Error{r.token.offset, "unexpected text after the JSON value"}
	}
	return
}

@(private = "file")
advance :: proc(r: ^Json_Reader) -> Maybe(Syntax_Error) {
	token, err := json.get_token(&r.tokenizer)
	r.token = token
	what: string
	#partial switch err {
	case .None:
		return nil
	case .EOF:
		// The tokenizer ends at a NUL byte too.
		if token.offset == len(r.data) {
			return nil
		}
		what = "unexpected NUL byte"
	case .Invalid_Number:
		what = "invalid number"
	case .String_Not_Terminated:
		what = "unterminated string"
	case .Invalid_String:
		what = "invalid string"
	case .Invalid_Rune:
		what = "invalid UTF-8"
	case:
		what = "unexpected character"
	}
	return Syntax_Error{token.offset, what}
}

@(private = "file")
expected :: proc(r: ^Json_Reader, what: string) -> Syntax_Error {
	if r.token.kind == .EOF {
		return {r.token.offset, "unexpected end of file"}
	}
	return {r.token.offset, what}
}

@(private = "file")
read_value :: proc(r: ^Json_Reader) -> (value: Json_Value, err: Maybe(Syntax_Error)) {
	token := r.token
	#partial switch token.kind {
	case .Open_Brace:
		return read_object(r)
	case .Open_Bracket:
		return read_array(r)
	case .Null:
		value = Json_Null{}
	case .True:
		value = true
	case .False:
		value = false
	case .Integer:
		// parse_i64 wraps on overflow, so a number that doesn't round-trip is kept as a float.
		n, _ := strconv.parse_i64_of_base(token.text, 10)
		if fmt.tprint(n) == token.text {
			value = n
		} else {
			value, _ = strconv.parse_f64(token.text)
		}
	case .Float:
		value, _ = strconv.parse_f64(token.text)
	case .String:
		value, _ = json.unquote_string(token, .JSON)
	case:
		return nil, expected(r, "expected a value")
	}
	advance(r) or_return
	return
}

@(private = "file")
read_object :: proc(r: ^Json_Reader) -> (value: Json_Value, err: Maybe(Syntax_Error)) {
	object := make(Json_Object)
	advance(r) or_return
	if r.token.kind == .Close_Brace {
		advance(r) or_return
		return object, nil
	}
	for {
		key_token := r.token
		if key_token.kind != .String {
			return nil, expected(r, "expected a quoted key")
		}
		key, _ := json.unquote_string(key_token, .JSON)
		for member in object {
			if member.key == key {
				return nil, Syntax_Error{key_token.offset, fmt.aprintf("duplicate key '%s'", key)}
			}
		}
		advance(r) or_return
		if r.token.kind != .Colon {
			return nil, expected(r, "expected ':'")
		}
		advance(r) or_return
		member_value := read_value(r) or_return
		line, col := text_position(r.data, key_token.offset)
		append(&object, Json_Member{key, line, col, member_value})

		#partial switch r.token.kind {
		case .Close_Brace:
			advance(r) or_return
			return object, nil
		case .Comma:
			comma := r.token
			advance(r) or_return
			if r.token.kind == .Close_Brace {
				return nil, Syntax_Error{comma.offset, "trailing comma"}
			}
		case:
			return nil, expected(r, "expected ',' or '}'")
		}
	}
}

@(private = "file")
read_array :: proc(r: ^Json_Reader) -> (value: Json_Value, err: Maybe(Syntax_Error)) {
	array := make(Json_Array)
	advance(r) or_return
	if r.token.kind == .Close_Bracket {
		advance(r) or_return
		return array, nil
	}
	for {
		append(&array, read_value(r) or_return)
		#partial switch r.token.kind {
		case .Close_Bracket:
			advance(r) or_return
			return array, nil
		case .Comma:
			comma := r.token
			advance(r) or_return
			if r.token.kind == .Close_Bracket {
				return nil, Syntax_Error{comma.offset, "trailing comma"}
			}
		case:
			return nil, expected(r, "expected ',' or ']'")
		}
	}
}
