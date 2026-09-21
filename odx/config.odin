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
	version:      int, // must equal CONFIG_VERSION (20.7)
	roles:        map[string][]string, // role -> dir globs, relative to root (17.5)
	default_role: string, // ponytail: plan says roles.default; a map field cannot hold it
	exclude:      []string,
	disabled:     map[string]string, // "topic/R2" -> reason (17.17)
	layering:     map[string]Layer,
	odin:         Odin_Cfg,
}

Layer :: struct {
	may_import: []string, // roles or import globs (`core:*`)
	deny:       []string, // import globs; absent on pure = DEFAULT_DENY_PURE (17.3), filled at load
}

Odin_Cfg :: struct {
	flags:                []string,
	forbidden_flags:      []string,
	required_flags:       []string, // must appear in the mise.toml test task (17.15)
	collections:          map[string]string,
	custom_attributes:    []string,
	allowed_vet_disables: []string, // 17.2
	explicit_allocators:  Explicit_Allocators,
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
	"layering",
	"odin",
}
ODIN_KEYS := []string {
	"flags",
	"forbidden_flags",
	"required_flags",
	"collections",
	"custom_attributes",
	"allowed_vet_disables",
	"explicit_allocators",
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

// find_root walks up from cwd to the nearest odx.json5 (17.5). "" if none.
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

// load_config reads and validates <root>/odx.json5.
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
	// unmarshal leaves an empty array nil (17.20): presence in the tree is the real signal
	if "exclude" not_in tree {cfg.exclude = DEFAULT_EXCLUDE}
	layering_obj, _ := tree["layering"].(json.Object)
	for role in sorted_keys(cfg.layering) {
		obj, _ := layering_obj[role].(json.Object)
		check_keys(errs, path, fmt.tprintf("layering.%s.", role), obj, LAYER_KEYS)
		if "deny" not_in obj {
			l := &cfg.layering[role]
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
	// layering keys and may_import role names must be declared roles; collections are `x:*`
	for role in sorted_keys(cfg.layering) {
		if role not_in cfg.roles {errf(errs, "%s: layering.%s is not a declared role", path, role)}
		for m, i in cfg.layering[role].may_import {
			if !strings.contains(m, ":") && m not_in cfg.roles {
				errf(
					errs,
					"%s: layering.%s.may_import[%d] %q is neither a role nor a collection glob",
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
// unknown keys (silently skipped, 17.20) and misspelt enum names (silently zero).
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
	if uerr := json.unmarshal_string(text, v, spec = .JSON5); uerr != nil {
		errf(errs, "%s: %v", at, uerr)
		return
	}
	val, perr := json.parse_string(text, spec = .JSON5)
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

json_array :: proc(obj: json.Object, key: string) -> []json.Value {
	arr, _ := obj[key].(json.Array)
	return arr[:]
}

// check_keys appends an error for every key of obj not in allowed. A nil obj passes.
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

// check_enum: if obj[key] is present it must spell one of E's names.
check_enum :: proc(errs: ^[dynamic]string, at: string, obj: json.Object, key: string, $E: typeid) {
	name := key[strings.last_index(key, ".") + 1:]
	v, present := obj[name]
	if !present {return}
	if s, is_str := v.(json.String); is_str {
		if _, found := reflect.enum_from_name(E, s); found {return}
	}
	errf(errs, "%s: %s must be one of %v", at, key, reflect.enum_field_names(E))
}

// reflect_enum parses a lowercase enum name; the CLI's subcommand words are enums too.
reflect_enum :: proc($E: typeid, name: string) -> (E, bool) {
	return reflect.enum_from_name(E, name)
}

// role_of resolves the role of a package directory (relative to root, `/` separators).
// n is the number of matching roles: 0 = unmapped, >1 = config conflict (17.5).
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

// rel_of returns path relative to root with "" for root itself; inside is false outside root.
rel_of :: proc(root, path: string) -> (rel: string, inside: bool) {
	r, err := filepath.rel(root, path)
	if err != nil || r == ".." || strings.has_prefix(r, "../") {return path, false}
	return "" if r == "." else r, true
}
