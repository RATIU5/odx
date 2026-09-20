package odx

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:unicode"

// `odx new <template> <Name>` (17.16, 10a): built-in templates live in templates/<name>/ and are
// embedded; a project adds .odx/templates/<name>/ in the same format (same name overrides).
// The target directory is the template role's first literal glob in odx.json5, or --dir.
// Nothing is ever overwritten.

Template :: struct {
	name:    string,
	summary: string,
	role:    string,
	files:   map[string]string, // template file -> target path (with placeholders)
	// runtime only
	source:  string, // "builtin" or the directory
	texts:   map[string]string, // template file -> content
}

TEMPLATE_FILE :: "template.json5"
TEMPLATE_KEYS := []string{"name", "summary", "role", "files"}
PROJECT_TEMPLATES_DIR :: ".odx/templates"

BUILTIN_TEMPLATES := []Builtin{{"package", #load_directory("../templates/package")}}

load_templates :: proc(root: string, errs: ^[dynamic]string) -> []Template {
	out := make([dynamic]Template)
	for b in BUILTIN_TEMPLATES {
		t := Template {
			source = "builtin",
			texts  = make(map[string]string),
		}
		js: string
		for f in b.files {
			if f.name ==
			   TEMPLATE_FILE {js = string(f.data)} else {t.texts[f.name] = string(f.data)}
		}
		add_template(&out, t, b.name, js, errs)
	}
	for e in project_subdirs(root, PROJECT_TEMPLATES_DIR) {
		t := Template {
			source = join({PROJECT_TEMPLATES_DIR, e.name}),
			texts  = make(map[string]string),
		}
		js: string
		files, _ := os.read_all_directory_by_path(e.fullpath, context.allocator)
		for f in files {
			data, _ := os.read_entire_file(f.fullpath, context.allocator)
			if f.name == TEMPLATE_FILE {js = string(data)} else {t.texts[f.name] = string(data)}
		}
		add_template(&out, t, e.name, js, errs)
	}
	return out[:]
}

@(private = "file")
add_template :: proc(
	out: ^[dynamic]Template,
	t: Template,
	dir_name, js: string,
	errs: ^[dynamic]string,
) {
	t := t
	at := join(
		{t.source if t.source != "builtin" else join({"templates", dir_name}), TEMPLATE_FILE},
	)
	if js == "" {
		errf(errs, "%s: missing", at)
		return
	}
	if _, ok := unmarshal_json5(js, &t, at, TEMPLATE_KEYS, errs); !ok {return}
	if t.name != dir_name {errf(errs, "%s: name %s does not match directory", at, t.name)}
	if t.role == "" {errf(errs, "%s: role is required", at)}
	if len(t.files) == 0 {errf(errs, "%s: files is required", at)}
	for src in sorted_keys(t.files) {if src not_in t.texts {errf(errs, "%s: file %s does not exist", at, src)}}
	for &old in out {
		if old.name == t.name {
			old = t
			return
		}
	}
	append(out, t)
}

cmd_new :: proc(o: Opts) {
	p := must_load(o, !o.list)
	errs: [dynamic]string
	templates := load_templates(p.root, &errs)
	if len(errs) > 0 {
		for e in errs {fmt.eprintln("odx:", e)}
		os.exit(EXIT_TOOL)
	}
	if o.list {
		for t in templates {fmt.printfln("%-12s %s  [%s, role %s]", t.name, t.summary, t.source, t.role)}
		return
	}
	if len(o.args) != 2 {fail("usage: odx new <template> <Name> [--dir d]  (odx new --list)")}
	t: ^Template
	for &c in templates {if c.name == o.args[0] {t = &c}}
	if t == nil {fail("unknown template %q (odx new --list)", o.args[0])}
	name := o.args[1]
	if !valid_name(name) {fail("Name must match ^[A-Z][A-Za-z0-9_]*$, got %q", name)}
	dir := o.dir
	if dir == "" {dir = role_dir(&p.cfg, t.role)}
	written := render_template(t, name, join({p.root, dir}))
	for w in written {fmt.println("wrote", w)}
	fmt.printfln(
		"role %s; make sure %s is covered by roles.%s in %s",
		t.role,
		join({dir, snake(name)}),
		t.role,
		CONFIG_FILE,
	)
}

// role_dir: the role's first glob without wildcards, else the root.
role_dir :: proc(cfg: ^Config, role: string) -> string {
	for g in cfg.roles[role] {
		if !strings.contains_any(g, "*?[") {return g}
	}
	return "."
}

// render_template writes every file; refuses if any target exists (17.16).
render_template :: proc(t: ^Template, name, base: string) -> []string {
	targets := make([dynamic]string)
	for src in sorted_keys(t.files) {
		dst := join({base, expand(t.files[src], name)})
		if os.exists(dst) {fail("%s exists; odx new never overwrites", dst)}
		append(&targets, dst)
	}
	for src, i in sorted_keys(t.files) {
		dst := targets[i]
		os.make_directory_all(filepath.dir(dst))
		if err := os.write_entire_file(dst, expand(t.texts[src], name));
		   err != nil {fail("write %s: %v", dst, err)}
	}
	return targets[:]
}

expand :: proc(text, name: string) -> string {
	s, _ := strings.replace_all(text, "{{Name}}", name)
	s, _ = strings.replace_all(s, "{{name_snake}}", snake(name))
	s, _ = strings.replace_all(s, "{{name_upper}}", strings.to_upper(snake(name)))
	return s
}

valid_name :: proc(name: string) -> bool {
	if name == "" || !unicode.is_upper(rune(name[0])) {return false}
	for r in name {if !(unicode.is_letter(r) || unicode.is_digit(r) || r == '_') {return false}}
	return true
}

// snake: HttpServer -> http_server, Vec2D -> vec2_d.
snake :: proc(name: string) -> string {
	b := strings.builder_make()
	for r, i in name {
		if unicode.is_upper(r) && i > 0 && name[i - 1] != '_' {strings.write_byte(&b, '_')}
		strings.write_rune(&b, unicode.to_lower(r))
	}
	return strings.to_string(b)
}
