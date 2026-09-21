package odx

import "core:encoding/json"
import "core:os"
import "core:slice"
import "core:strings"

TOPIC_FILE :: "topic.md"
RULE_SUFFIX :: ".odx.md"
PROJECT_TOPICS_DIR :: ".odx/topics"

Topic :: struct {
	name:              string,
	summary:           string,
	tags:              []string,
	aliases:           []string,
	applies_to:        struct {
		roles: []string,
	},
	related:           []string,
	example_roles:     map[string]string,
	rules:             []Rule,
	// runtime only, not frontmatter keys
	prose:             string,
	blocks:            []string, // fires/silent blocks in topic.md: reader checks, compiled by self-test
	exemplar:          string, // example .odin sources concatenated
	source:            string, // "builtin" or the directory it came from
	overrides:         bool,
}

// Metadata comes from the <id>.odx.md frontmatter. Enum fields unmarshal from lowercase names;
// validate_rule checks presence and spelling against the parsed tree because json.unmarshal
// leaves an unknown name at the zero value.
Rule :: struct {
	id:           string,
	statement:    string,
	why:          string,
	instead_of:   string,
	evidence:     string,
	cost:         string,
	severity:     Severity,
	class:        string, // stable greppable name, e.g. "dependencies_hidden_state"
	ignorable:    bool, // default true; set at load when absent
	baselineable: bool, // has a stable subject
	retired:      bool,
	role:         string, // role the fires/silent blocks are checked under (default edge)
	check:        Check_Spec,
	// runtime only, from the .odx.md body
	prose:        string,
	prelude:      string, // setup shared by fires and silent
	fires:        string, // must produce this rule and no other
	silent:       string, // must compile and produce nothing
	file:         string,
}

// Every kind runs and every finding blocks; conventions a reader enforces live as prose and
// compiled blocks in topic.md, not as rules.
Check_Kind :: enum {
	path_role,
	banned_import,
	vet_tag,
	require_attribute, // family C: needs the compiler's entity table (docfmt.odin)
	pattern, // a selector over the AST walk (pattern.odin); the open-ended kind
}

// ponytail: strings, because `import` and `proc` are keywords and cannot name enum variants.
PATTERN_MATCHES := []string {
	"call", // names: canonical `pkg.name` or bare `name` calls
	"import", // name: an import glob (`core:fmt`, `core:sys/*`)
	"proc", // exported / requires_param: package-level procedures
	"decl", // at: package_scope, mutable: package-level value declarations
	"foreign", // foreign import and foreign block declarations
}

Param_Req :: struct {
	index:       int,
	type_suffix: string,
}

// One field bag for every kind because core:encoding/json cannot pick a union variant by a
// discriminator field. validate_rule enforces the per-kind shape at load time.
Check_Spec :: struct {
	kind:               Check_Kind,
	attribute:          string, // require_attribute
	on:                 string, // require_attribute: "" | "exported_procs"
	from:               string, // banned_import: documentation only
	names:              []string, // call: canonical `pkg.name` or bare `name`
	roles:              []string,
	except_roles:       []string,
	// pattern
	match:              string, // one of PATTERN_MATCHES
	name:               string, // call: one name (sugar for names); import: an import glob
	exported:           bool, // proc: only exported (not @(private)) procedures
	requires_param:     Param_Req, // proc: report a proc whose param at index lacks type_suffix
	at:                 string, // decl: "package_scope" (the only scope today)
	mutable:            bool, // decl: only `x: T` / `x := v`, not `::`
}

TOPIC_KEYS := []string {
	"name",
	"summary",
	"tags",
	"aliases",
	"applies_to",
	"related",
	"example_roles",
}
RULE_KEYS := []string {
	"id",
	"statement",
	"why",
	"role",
	"instead_of",
	"evidence",
	"cost",
	"severity",
	"class",
	"ignorable",
	"baselineable",
	"retired",
	"check",
}
CHECK_KEYS := []string {
	"kind",
	"attribute",
	"on",
	"from",
	"names",
	"roles",
	"except_roles",
	"match",
	"name",
	"exported",
	"requires_param",
	"at",
	"mutable",
}

Rulebook :: struct {
	topics: [dynamic]Topic, // sorted by name
}

// Built-ins first, then <root>/.odx/topics/*; root may be "".
// A topic is a directory: topic.md plus one <id>.odx.md per rule.
load_rulebook :: proc(root: string, errs: ^[dynamic]string) -> (rb: Rulebook) {
	for b in BUILTIN_TOPICS {
		files := make(map[string]string, context.temp_allocator)
		for f in b.files {files[f.name] = string(f.data)}
		ex := make([dynamic]string)
		for f in b.example {if strings.has_suffix(f.name, ".odin") {append(&ex, string(f.data))}}
		add_topic(&rb, "builtin", b.name, files, strings.join(ex[:], "\n"), errs)
	}
	for e in project_subdirs(root, PROJECT_TOPICS_DIR) {
		files := make(map[string]string, context.temp_allocator)
		if entries, rerr := os.read_all_directory_by_path(e.fullpath, context.allocator);
		   rerr == nil {
			for fi in entries {
				if fi.type != .Regular {continue}
				if data, ferr := os.read_entire_file(fi.fullpath, context.allocator);
				   ferr == nil {files[fi.name] = string(data)}
			}
		}
		ex := make([dynamic]string)
		for d in project_subdirs(e.fullpath, "example") {
			w := os.walker_create_path(d.fullpath)
			defer os.walker_destroy(&w)
			for fi in os.walker_walk(&w) {
				if fi.type != .Regular || !strings.has_suffix(fi.name, ".odin") {continue}
				if src, rerr := os.read_entire_file(fi.fullpath, context.allocator);
				   rerr == nil {append(&ex, string(src))}
			}
		}
		add_topic(
			&rb,
			join({PROJECT_TOPICS_DIR, e.name}),
			e.name,
			files,
			strings.join(ex[:], "\n"),
			errs,
		)
	}
	slice.sort_by(rb.topics[:], proc(a, b: Topic) -> bool {return a.name < b.name})
	return
}

// Sorted by name; none if root is "".
project_subdirs :: proc(root, sub: string) -> []os.File_Info {
	if root == "" {return nil}
	entries, err := os.read_all_directory_by_path(join({root, sub}), context.allocator)
	if err != nil {return nil}
	dirs := make([dynamic]os.File_Info)
	for e in entries {if e.type == .Directory {append(&dirs, e)}}
	slice.sort_by(dirs[:], proc(a, b: os.File_Info) -> bool {return a.name < b.name})
	return dirs[:]
}

@(private = "file")
add_topic :: proc(
	rb: ^Rulebook,
	source, dir_name: string,
	files: map[string]string,
	exemplar: string,
	errs: ^[dynamic]string,
) {
	dir := source if source != "builtin" else join({"rules", dir_name})
	at := join({dir, TOPIC_FILE})
	md, has_md := files[TOPIC_FILE]
	if !has_md || md == "" {
		errf(errs, "%s: missing", at)
		return
	}
	tf, perr := parse_rule_file(md, keep_blocks = true)
	if perr != "" {
		errf(errs, "%s: %s", at, perr)
		return
	}
	t := Topic {
		source   = source,
		prose    = tf.prose,
		blocks   = tf.blocks[:],
		exemplar = exemplar,
	}
	if _, ok := unmarshal_json5(tf.frontmatter, &t, at, TOPIC_KEYS, errs); !ok {return}
	if t.name != dir_name {errf(errs, "%s: name %s does not match directory", at, t.name)}
	if t.summary == "" {errf(errs, "%s: summary is required", at)}
	if t.prose == "" {errf(errs, "%s: body prose is required", at)}
	names := make([dynamic]string, context.temp_allocator)
	for name in files {if strings.has_suffix(name, RULE_SUFFIX) {append(&names, name)}}
	slice.sort(names[:])
	rules := make([dynamic]Rule)
	seen := make(map[string]bool, context.temp_allocator)
	for name in names {
		rat := join({dir, name})
		rf, rerr := parse_rule_file(files[name])
		if rerr != "" {
			errf(errs, "%s: %s", rat, rerr)
			continue
		}
		r := Rule {
			prose   = rf.prose,
			prelude = rf.prelude,
			fires   = rf.fires,
			silent  = rf.silent,
			file    = rat,
		}
		obj, ok := unmarshal_json5(rf.frontmatter, &r, rat, RULE_KEYS, errs)
		if !ok {continue}
		if !strings.has_prefix(r.id, "R") ||
		   r.id in seen {errf(errs, "%s: bad or duplicate rule id %s", rat, r.id)}
		if strings.trim_suffix(name, RULE_SUFFIX) !=
		   r.id {errf(errs, "%s: file name does not match id %s", rat, r.id)}
		seen[r.id] = true
		if "ignorable" not_in obj {r.ignorable = true}
		if "baselineable" not_in obj {r.baselineable = true}
		if r.role == "" {r.role = "edge"}
		if !r.retired {validate_rule(&r, obj, rat, errs)}
		append(&rules, r)
	}
	t.rules = rules[:]
	for &old in rb.topics {
		if old.name == t.name {
			t.overrides = true
			old = t
			return
		}
	}
	append(&rb.topics, t)
}

@(private = "file")
validate_rule :: proc(r: ^Rule, obj: json.Object, at: string, errs: ^[dynamic]string) {
	if r.statement == "" {errf(errs, "%s: statement is required", at)}
	if r.why == "" {errf(errs, "%s: why is required", at)}
	// a rule cannot reach a user without its justification
	if r.instead_of == "" {errf(errs, "%s: instead_of is required (compared to what?)", at)}
	if r.evidence == "" {errf(errs, "%s: evidence is required (what hard evidence?)", at)}
	if r.cost == "" {errf(errs, "%s: cost is required (at what cost?)", at)}
	require_key(errs, at, obj, "severity")
	require_key(errs, at, obj, "check")
	check_enum(errs, at, obj, "severity", Severity)
	spec, _ := obj["check"].(json.Object)
	validate_check(&r.check, spec, at, errs)
}

// `odx rule try` runs this on an inline spec.
validate_check :: proc(c: ^Check_Spec, spec: json.Object, at: string, errs: ^[dynamic]string) {
	check_keys(errs, at, "check.", spec, CHECK_KEYS)
	require_key(errs, at, spec, "kind") // a missing kind would silently become the zero variant
	check_enum(errs, at, spec, "kind", Check_Kind)
	switch c.kind {
	case .pattern:
		if !slice.contains(PATTERN_MATCHES, c.match) {errf(errs, "%s: check.match must be one of %v", at, PATTERN_MATCHES)}
		if c.name != "" && c.match == "call" {c.names = slice.concatenate([][]string{c.names, {c.name}})}
		switch c.match {
		case "call":
			if len(c.names) == 0 {errf(errs, "%s: match: call needs name or names", at)}
		case "import":
			if c.name == "" {errf(errs, "%s: match: import needs name (an import glob)", at)}
		case "proc":
			if "requires_param" in spec && c.requires_param.type_suffix == "" {errf(errs, "%s: requires_param.type_suffix is required", at)}
		case "decl":
			if c.at != "package_scope" {errf(errs, "%s: match: decl needs at: package_scope", at)}
		case "foreign":
		}
	case .path_role, .banned_import, .vet_tag:
	case .require_attribute:
		if c.attribute == "" {errf(errs, "%s: check.attribute is required", at)}
		if c.on != "" &&
		   c.on != "exported_procs" {errf(errs, "%s: check.on must be exported_procs", at)}
	}
}

find_topic :: proc(rb: ^Rulebook, name: string) -> ^Topic {
	for &t in rb.topics {
		if t.name == name {return &t}
	}
	return nil
}

find_rule :: proc(rb: ^Rulebook, id: string) -> ^Rule {
	topic, _, rule := strings.partition(id, "/")
	if t := find_topic(rb, topic); t != nil {
		for &r in t.rules {if r.id == rule {return &r}}
	}
	return nil
}

// A rule that survives the retired / --topic / disabled filters.
Active_Rule :: struct {
	id:   string, // "topic/Rn"
	rule: ^Rule,
}

active_rules :: proc(p: ^Project, only_topics: []string) -> []Active_Rule {
	out := make([dynamic]Active_Rule)
	for &t in p.rb.topics {
		if len(only_topics) > 0 && !slice.contains(only_topics, t.name) {continue}
		for &r in t.rules {
			if r.retired {continue}
			id := strings.concatenate({t.name, "/", r.id})
			if id in p.cfg.disabled {continue}
			append(&out, Active_Rule{id, &r})
		}
	}
	return out[:]
}

role_applies :: proc(spec: ^Check_Spec, role: string) -> bool {
	if len(spec.roles) > 0 && !slice.contains(spec.roles, role) {return false}
	if len(spec.except_roles) > 0 && slice.contains(spec.except_roles, role) {return false}
	return true
}

// Config for `odx check --exemplar <topic>`: the topic's example/ directory is the root.
exemplar_config :: proc(t: ^Topic, base: ^Config) -> (cfg: Config) {
	cfg = default_config()
	cfg.odin = base.odin
	if base.dependencies != nil {cfg.dependencies = base.dependencies}
	cfg.exclude = {}
	clear(&cfg.roles)
	for dir, role in t.example_roles {
		cfg.roles[role] = slice.concatenate(
			[][]string{cfg.roles[role], {strings.trim_prefix(dir, "example/")}},
		)
	}
	return
}
