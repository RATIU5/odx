package odx

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:slice"
import "core:strings"

CONFIG_FILE :: "odx.json5"

Config :: struct {
	roles:        map[string][]string, // role -> dir globs, relative to root (17.5)
	default_role: string, // ponytail: plan says roles.default; a map field cannot hold it
	exclude:      []string,
	disabled:     map[string]string, // "topic/R2" -> reason (17.17)
	layering:     map[string]Layer, // used by M2 import_graph; parsed now so init/validate cover it
	odin:         Odin_Cfg,
}

Layer :: struct {
	may_import: []string,
}

Odin_Cfg :: struct {
	flags:             []string,
	forbidden_flags:   []string,
	collections:       map[string]string,
	custom_attributes: []string,
	version:           string,
	path:              string,
}

CONFIG_KEYS :: []string{"roles", "default_role", "exclude", "disabled", "layering", "odin"}
ODIN_KEYS :: []string{"flags", "forbidden_flags", "collections", "custom_attributes", "version", "path"}
DEFAULT_EXCLUDE :: []string{".odx/**", "rules/**", "vendor/**", "build/**"}

// find_root walks up from cwd to the nearest odx.json5 (17.5). "" if none.
find_root :: proc(override: string) -> string {
	if override != "" {
		abs, _ := filepath.abs(override, context.allocator)
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

// load_config reads and validates <root>/odx.json5. errs is empty on success.
load_config :: proc(root: string) -> (cfg: Config, errs: [dynamic]string) {
	path := join({root, CONFIG_FILE})
	data, rerr := os.read_entire_file(path, context.allocator)
	if rerr != nil {
		append(&errs, strings.concatenate({path, ": cannot read"}))
		return
	}
	text := string(data)
	if uerr := json.unmarshal_string(text, &cfg, spec = .JSON5); uerr != nil {
		append(&errs, fmt_err(path, uerr))
		return
	}
	// unknown keys are silently skipped by unmarshal (17.20), so re-parse generically
	if v, perr := json.parse_string(text, spec = .JSON5); perr == nil {
		check_keys(&errs, path, v, CONFIG_KEYS)
		if obj, ok := v.(json.Object); ok {
			if od, has := obj["odin"]; has {check_keys(&errs, strings.concatenate({path, " odin"}, context.temp_allocator), od, ODIN_KEYS)}
		}
	}
	if cfg.exclude == nil {cfg.exclude = DEFAULT_EXCLUDE}
	if cfg.default_role != "" && cfg.default_role not_in cfg.roles {
		append(&errs, strings.concatenate({path, ": default_role ", cfg.default_role, " is not a role"}))
	}
	for id, reason in cfg.disabled {
		if len(reason) < 10 {append(&errs, strings.concatenate({path, ": disabled ", id, " needs a reason of 10+ characters"}))}
	}
	return
}

fmt_err :: proc(path: string, err: json.Unmarshal_Error) -> string {
	b := strings.builder_make()
	strings.write_string(&b, path)
	strings.write_string(&b, ": ")
	switch e in err {
	case json.Error:
		strings.write_string(&b, "parse error: ")
		strings.write_string(&b, json_error_name(e))
	case json.Unmarshal_Data_Error:
		strings.write_string(&b, "data error")
	case json.Unsupported_Type_Error:
		strings.write_string(&b, "unsupported type")
	}
	return strings.to_string(b)
}

json_error_name :: proc(e: json.Error) -> string {
	buf: [64]byte
	return strings.clone(fmt.bprint(buf[:], e))
}

// check_keys appends an error for every key of v (an object) not in allowed.
check_keys :: proc(errs: ^[dynamic]string, at: string, v: json.Value, allowed: []string) {
	obj, ok := v.(json.Object)
	if !ok {return}
	keys, _ := slice.map_keys(obj, context.temp_allocator)
	slice.sort(keys)
	for k in keys {
		if !slice.contains(allowed, k) {
			append(errs, strings.concatenate({at, ": unknown key ", k}))
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
