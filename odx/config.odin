package odx

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:reflect"
import "core:slice"
import "core:strings"

CONFIG_FILE :: "odx.json5"
CONFIG_VERSION :: 1

// Config mirrors odx.json5 exactly; nothing runtime-only lives here.
Config :: struct {
	version:      int,
	roles:        map[string][]string, // role -> dir globs, relative to root
	default_role: string, // ponytail: a map field cannot hold `roles.default`
	exclude:      []string,
	disabled:     map[string]string, // "topic/R2" -> reason
	dependencies: map[string]Layer,
	odin:         Odin_Cfg,
	errors:       Errors_Cfg,
}

// Classification uses canonical named-result suffixes and optional structural heuristics.
Errors_Cfg :: struct {
	types:      []string,
	structural: bool,
}

DEFAULT_ERROR_TYPES := []string{"Error"}
ERRORS_KEYS := []string{"types", "structural"}

Layer :: struct {
	may_import: []string, // roles or import globs (`core:*`)
	deny:       []string, // import globs; absent on pure = DEFAULT_DENY_PURE, filled at load
}

Odin_Cfg :: struct {
	flags:                []string,
	forbidden_flags:      []string,
	required_flags:       []string, // must appear in the mise.toml test task
	collections:          map[string]string,
	custom_attributes:    []string,
	allowed_vet_disables: []string,
	explicit_allocators:  Explicit_Allocators,
	declined:             map[string]string, // flag -> why this project considered and refused it
	tagged_files_min:     int, // floor for `#+vet explicit-allocators` coverage; doctor errors below it
	version:              string,
	path:                 string,
}

// Explicit_Allocators: which roles must carry `#+vet explicit-allocators` (allocators/R1).
Explicit_Allocators :: enum {
	pure, // pure and service packages (the default)
	all,
	off,
}

CONFIG_KEYS := []string {
	"version",
	"roles",
	"default_role",
	"exclude",
	"disabled",
	"dependencies",
	"odin",
	"errors",
}
ODIN_KEYS := []string {
	"flags",
	"forbidden_flags",
	"required_flags",
	"collections",
	"custom_attributes",
	"allowed_vet_disables",
	"explicit_allocators",
	"declined",
	"tagged_files_min",
	"version",
	"path",
}
LAYER_KEYS := []string{"may_import", "deny"}
DEFAULT_EXCLUDE := []string{".odx/**", "rules/**", "vendor/**", "build/**"}

errf :: proc(errs: ^[dynamic]string, f: string, args: ..any) {
	append(errs, fmt.aprintf(f, ..args))
}

// canonical: absolute with symlinks resolved, so every path compares textually against the
// root (macOS: /var and /tmp are symlinks into /private; the walker reports the real path).
canonical :: proc(path: string) -> string {
	if abs, err := os.get_absolute_path(path, context.allocator); err == nil {return abs}
	abs, _ := filepath.abs(path)
	return abs
}

// "" when no odx.json5 is found above cwd.
find_root :: proc(override: string) -> string {
	if override != "" {return canonical(override)}
	dir, _ := os.get_working_directory(context.allocator)
	for {
		if os.exists(join({dir, CONFIG_FILE})) {return dir}
		parent := filepath.dir(dir)
		if parent == dir {return ""}
		dir = parent
	}
}

load_config :: proc(root: string, errs: ^[dynamic]string) -> (cfg: Config) {
	path := join({root, CONFIG_FILE})
	data, rerr := os.read_entire_file(path, context.allocator)
	if rerr != nil {
		errf(errs, "%s: cannot read", path)
		return
	}
	tree, ok := unmarshal_json5(string(data), &cfg, path, CONFIG_KEYS, errs)
	if !ok {return}
	odin_obj, _ := tree["odin"].(json.Object)
	check_keys(errs, path, "odin.", odin_obj, ODIN_KEYS)
	check_enum(errs, path, odin_obj, "odin.explicit_allocators", Explicit_Allocators)
	errors_obj, _ := tree["errors"].(json.Object)
	check_keys(errs, path, "errors.", errors_obj, ERRORS_KEYS)
	// unmarshal leaves an empty array nil: presence in the tree is the real signal
	if "exclude" not_in tree {cfg.exclude = DEFAULT_EXCLUDE}
	if "types" not_in errors_obj {cfg.errors.types = DEFAULT_ERROR_TYPES}
	if "structural" not_in errors_obj {
		cfg.errors.structural = true
	} else if _, valid := errors_obj["structural"].(json.Boolean); !valid {
		errf(errs, "%s: errors.structural must be a boolean", path)
	}
	for suffix, i in cfg.errors.types {
		if strings.trim_space(suffix) == "" {
			errf(errs, "%s: errors.types[%d] must be a nonempty type-name suffix", path, i)
		}
	}
	for role in sorted_keys(cfg.roles) {
		if strings.trim_space(role) ==
		   "" {errf(errs, "%s: configured role names must not be empty; an empty selector role denotes unmapped packages", path)}
	}
	for flag, reason in cfg.odin.declined {
		if len(reason) <
		   10 {errf(errs, "%s: odin.declined %s needs a reason of 10+ characters", path, flag)}
	}
	dependencies_obj, _ := tree["dependencies"].(json.Object)
	for role in sorted_keys(cfg.dependencies) {
		obj, _ := dependencies_obj[role].(json.Object)
		check_keys(errs, path, fmt.tprintf("dependencies.%s.", role), obj, LAYER_KEYS)
		if "deny" not_in obj {
			l := &cfg.dependencies[role]
			l.deny = DEFAULT_DENY_PURE if role == "pure" else []string{}
		}
	}
	if cfg.version != CONFIG_VERSION {
		errf(
			errs,
			"%s: version must be %d (got %d); this odx supports only version %d",
			path,
			CONFIG_VERSION,
			cfg.version,
			CONFIG_VERSION,
		)
	}
	for role in sorted_keys(cfg.dependencies) {
		if role not_in
		   cfg.roles {errf(errs, "%s: dependencies.%s is not a declared role", path, role)}
		for m, i in cfg.dependencies[role].may_import {
			if !strings.contains(m, ":") && m not_in cfg.roles {
				errf(
					errs,
					"%s: dependencies.%s.may_import[%d] %q is neither a role nor a collection glob",
					path,
					role,
					i,
					m,
				)
			}
		}
	}
	if cfg.default_role != "" && cfg.default_role not_in cfg.roles {
		errf(errs, "%s: default_role %s is not a role", path, cfg.default_role)
	}
	for id, reason in cfg.disabled {
		if len(reason) <
		   10 {errf(errs, "%s: disabled %s needs a reason of 10+ characters", path, id)}
	}
	return
}

// unmarshal_json5 fills v and returns the parsed tree for the checks unmarshal cannot do:
// unknown keys (silently skipped) and misspelt enum names (silently zero).
unmarshal_json5 :: proc(
	text: string,
	v: ^$T,
	at: string,
	keys: []string,
	errs: ^[dynamic]string,
) -> (
	tree: json.Object,
	ok: bool,
) {
	// The reference JSON decoder ignores integer parse overflow. Check token text
	// before conversion can turn an invalid policy number into a valid-looking int.
	tokens := json.make_tokenizer(text, spec = .JSON5, parse_integers = true)
	for {
		token, err := json.get_token(&tokens)
		if err == .EOF {break}
		if err != nil {
			errf(errs, "%s: %v", at, err)
			return
		}
		if token.kind == .EOF {break}
		if token.kind == .Integer {
			if !policy_integer_fits(token.text) {
				errf(
					errs,
					"%s: integer %s is outside the supported signed 64-bit range",
					at,
					token.text,
				)
				return
			}
		}
	}
	if uerr := json.unmarshal_string(text, v, spec = .JSON5); uerr != nil {
		errf(errs, "%s: %v", at, uerr)
		return
	}
	val, perr := json.parse_string(text, spec = .JSON5, parse_integers = true)
	if perr != nil {
		errf(errs, "%s: %v", at, perr)
		return
	}
	if tree, ok = val.(json.Object); !ok {
		errf(errs, "%s: top level must be an object", at)
		return
	}
	check_keys(errs, at, "", tree, keys)
	return
}

policy_integer_fits :: proc(text: string) -> bool {
	s := text
	limit := u64(max(i64))
	if strings.has_prefix(s, "-") {limit += 1}
	if strings.has_prefix(s, "-") || strings.has_prefix(s, "+") {s = s[1:]}
	base: u64 = 10
	if strings.has_prefix(s, "0x") || strings.has_prefix(s, "0X") {
		base = 16
		s = s[2:]
	}
	value: u64
	for c in s {
		digit: u64
		switch {
		case c >= '0' && c <= '9':
			digit = u64(c - '0')
		case c >= 'a' && c <= 'f':
			digit = u64(c - 'a') + 10
		case c >= 'A' && c <= 'F':
			digit = u64(c - 'A') + 10
		case:
			return false
		}
		if digit >= base || value > (limit - digit) / base {return false}
		value = value * base + digit
	}
	return len(s) > 0
}

check_keys :: proc(
	errs: ^[dynamic]string,
	at, section: string,
	obj: json.Object,
	allowed: []string,
) {
	keys, _ := slice.map_keys(obj, context.temp_allocator)
	slice.sort(keys)
	for k in keys {
		if !slice.contains(allowed, k) {errf(errs, "%s: unknown key %s%s", at, section, k)}
	}
}

require_key :: proc(errs: ^[dynamic]string, at: string, obj: json.Object, key: string) {
	if key not_in obj {errf(errs, "%s: %s is required", at, key)}
}

check_enum :: proc(errs: ^[dynamic]string, at: string, obj: json.Object, key: string, $E: typeid) {
	name := key[strings.last_index(key, ".") + 1:]
	v, present := obj[name]
	if !present {return}
	if s, is_str := v.(json.String); is_str {
		if _, found := reflect.enum_from_name(E, s); found {return}
	}
	errf(errs, "%s: %s must be one of %v", at, key, reflect.enum_field_names(E))
}

// rel_dir is relative to root with `/` separators. n counts matching roles: 0 = unmapped,
// >1 = config conflict.
role_of :: proc(cfg: ^Config, rel_dir: string) -> (role: string, n: int) {
	for name, globs in cfg.roles {
		for g in globs {
			if glob_match(g, rel_dir) {
				role = name
				n += 1
				break
			}
		}
	}
	if n == 0 && cfg.default_role != "" {
		return cfg.default_role, 1
	}
	return
}

is_excluded :: proc(cfg: ^Config, rel_dir: string) -> bool {
	for g in cfg.exclude {
		if glob_match(g, rel_dir) {return true}
	}
	return false
}

// join is filepath.join without the allocator error (ponytail: OOM is fatal anyway).
join :: proc(elems: []string) -> string {
	s, _ := filepath.join(elems)
	return s
}

// rel_of: "" for root itself; inside is false outside root.
rel_of :: proc(root, path: string) -> (rel: string, inside: bool) {
	r, err := filepath.rel(root, path)
	if err != nil || r == ".." || strings.has_prefix(r, "../") {return path, false}
	return "" if r == "." else r, true
}
