package odx

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:slice"
import "core:strings"

CONFIG_FILE :: "odx.json5"

// Config mirrors odx.json5 exactly; nothing runtime-only lives here.
CONFIG_VERSION :: 1

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
	deny:       []string, // import globs; nil on pure = DEFAULT_DENY_PURE (17.3)
}

Odin_Cfg :: struct {
	flags:                []string,
	forbidden_flags:      []string,
	required_flags:       []string, // must appear in the mise.toml test task (17.15)
	collections:          map[string]string,
	custom_attributes:    []string,
	allowed_vet_disables: []string, // 17.2
	explicit_allocators:  string, // "pure" (default) | "all" | "off"
	version:              string,
	path:                 string,
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
EXPLICIT_ALLOCATOR_MODES := []string{"", "pure", "all", "off"}
DEFAULT_EXCLUDE := []string{".odx/**", "rules/**", "vendor/**", "build/**"}

errf :: proc(errs: ^[dynamic]string, f: string, args: ..any) {
	append(errs, fmt.aprintf(f, ..args))
}

// find_root walks up from cwd to the nearest odx.json5 (17.5). "" if none.
find_root :: proc(override: string) -> string {
	if override != "" {
		abs, _ := filepath.abs(override)
		return abs
	}
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
	if !unmarshal_json5(string(data), &cfg, path, CONFIG_KEYS, errs) {return}
	if v, perr := json.parse_string(string(data), spec = .JSON5); perr == nil {
		if od, has := v.(json.Object)["odin"]; has {check_keys(errs, path, "odin", od, ODIN_KEYS)}
	}
	if cfg.exclude == nil {cfg.exclude = DEFAULT_EXCLUDE}
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
	if !slice.contains(EXPLICIT_ALLOCATOR_MODES, cfg.odin.explicit_allocators) {
		errf(errs, "%s: odin.explicit_allocators must be pure, all or off", path)
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

// unmarshal_json5 fills v and reports unknown top-level keys, which unmarshal silently skips (17.20).
unmarshal_json5 :: proc(
	text: string,
	v: ^$T,
	at: string,
	keys: []string,
	errs: ^[dynamic]string,
) -> bool {
	if uerr := json.unmarshal_string(text, v, spec = .JSON5); uerr != nil {
		errf(errs, "%s: %v", at, uerr)
		return false
	}
	if val, perr := json.parse_string(text, spec = .JSON5); perr == nil {
		check_keys(errs, at, "", val, keys)
	}
	return true
}

// check_keys appends an error for every key of v (an object) not in allowed.
check_keys :: proc(errs: ^[dynamic]string, at, section: string, v: json.Value, allowed: []string) {
	obj, ok := v.(json.Object)
	if !ok {return}
	keys, _ := slice.map_keys(obj, context.temp_allocator)
	slice.sort(keys)
	for k in keys {
		if !slice.contains(allowed, k) {
			errf(
				errs,
				"%s: unknown key %s%s",
				at,
				section,
				k if section == "" else strings.concatenate({".", k}, context.temp_allocator),
			)
		}
	}
}

// role_of resolves the role of a package directory (relative to root, `/` separators).
// n is the number of matching roles: 0 = unmapped, >1 = config conflict (17.5).
role_of :: proc(cfg: ^Config, rel_dir: string) -> (role: string, n: int) {
	names, _ := slice.map_keys(cfg.roles, context.temp_allocator)
	slice.sort(names)
	for name in names {
		for g in cfg.roles[name] {
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
