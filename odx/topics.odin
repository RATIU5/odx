package odx

import "core:encoding/json"
import "core:os"
import "core:slice"
import "core:strings"

TOPIC_FILE :: "topic.md"
RULE_SUFFIX :: ".odx.md"
PROJECT_TOPICS_DIR :: ".odx/topics"

Topic :: struct {
	name:          string,
	summary:       string,
	tags:          []string,
	aliases:       []string,
	applies_to:    struct {
		roles: []string,
	},
	related:       []string,
	example_roles: map[string]string,
	rules:         []Rule,
	// runtime only, not frontmatter keys
	prose:         string,
	blocks:        []string, // fires/silent blocks in topic.md: reader checks, compiled by self-test
	exemplar:      string, // example .odin sources concatenated
	source:        string, // "builtin" or the directory it came from
	overrides:     bool,
}

// Metadata comes from the <id>.odx.md frontmatter. Enum fields unmarshal from lowercase names;
// validate_rule checks presence and spelling against the parsed tree because json.unmarshal
// leaves an unknown name at the zero value.
Rule :: struct {
	id:              string,
	statement:       string,
	why:             string,
	instead_of:      string,
	fix_hint:        string,
	evidence:        string,
	cost:            string,
	severity:        Severity,
	class:           string, // stable greppable name, e.g. "dependencies_hidden_state"
	ignorable:       bool, // default true; set at load when absent
	baselineable:    bool, // permits baselining when a source occurrence identity is available
	retired:         bool,
	role:            string, // role the fires/silent blocks are checked under (default edge)
	check:           Check_Spec,
	// runtime only, from the .odx.md body
	prose:           string,
	prelude:         string, // setup shared by fires and silent
	fires:           string, // must produce this rule and no other
	silent:          string, // must compile and produce nothing
	file:            string,
	scope:           string, // runtime description of effective selector/configuration scope
	disabled_reason: string, // runtime project disabling reason, empty when enabled
}

// Reviewer advice belongs in topic prose; these kinds require executable evidence.
Check_Kind :: enum {
	path_role,
	banned_import,
	vet_tag,
	require_attribute, // family C: needs the compiler's entity table (docfmt.odin)
	pattern,
}

// ponytail: strings, because `import` and `proc` are keywords and cannot name enum variants.
PATTERN_MATCHES := []string {
	"call", // names: syntactic `pkg.name` or bare `name`; aliases are best effort
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
	kind:           Check_Kind,
	attribute:      string, // require_attribute
	on:             string, // require_attribute: "" | "exported_procs"
	from:           string, // banned_import: documentation only
	names:          []string, // call: syntactic names with best-effort import aliases
	roles:          []string,
	except_roles:   []string,
	// pattern
	match:          string, // one of PATTERN_MATCHES
	name:           string, // call: one name (sugar for names); import: an import glob
	exported:       bool, // proc: only exported (not @(private)) procedures
	requires_param: Param_Req, // proc: report a proc whose param at index lacks type_suffix
	at:             string, // decl: "package_scope" (the only scope today)
	mutable:        bool, // decl: only `x: T` / `x := v`, not `::`
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
	"fix_hint",
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
				if fi.name != TOPIC_FILE && !strings.has_suffix(fi.name, RULE_SUFFIX) {continue}
				if data, ferr := os.read_entire_file(fi.fullpath, context.allocator); ferr == nil {
					files[fi.name] = string(data)
				} else {
					errf(errs, "%s: cannot read policy file (%v)", fi.fullpath, ferr)
				}
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
	topic_obj, topic_ok := unmarshal_json5(tf.frontmatter, &t, at, TOPIC_KEYS, errs)
	if !topic_ok {return}
	if value, present := topic_obj["applies_to"]; present {
		if advice, valid := value.(json.Object); valid {
			check_keys(errs, at, "applies_to.", advice, {"roles"})
			if roles, supplied := advice["roles"]; supplied {
				if items, roles_valid := roles.(json.Array); roles_valid {
					for item in items {
						if role, is_string := item.(json.String);
						   !is_string || (role != "" && strings.trim_space(role) == "") {
							errf(
								errs,
								"%s: applies_to.roles entries must be role strings (empty means unmapped)",
								at,
							)
						}
					}
				} else {errf(errs, "%s: applies_to.roles must be an array", at)}
			}
		} else {
			errf(errs, "%s: applies_to must be an object", at)
		}
	}
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
		default_rule_fields(&r, obj)
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

default_rule_fields :: proc(r: ^Rule, obj: json.Object) {
	if "ignorable" not_in obj {r.ignorable = true}
	if "baselineable" not_in obj {r.baselineable = true}
	if r.role == "" {r.role = "edge"}
}

validate_rule :: proc(r: ^Rule, obj: json.Object, at: string, errs: ^[dynamic]string) {
	if !strings.has_prefix(r.id, "R") {errf(errs, "%s: rule id must start with R", at)}
	if value, present := obj["fix_hint"]; present {
		hint, valid := value.(json.String)
		if !valid || strings.trim_space(string(hint)) == "" {
			errf(errs, "%s: fix_hint must be a nonempty string", at)
		}
	}
	for key in ([]string{"ignorable", "baselineable", "retired"}) {
		if value, present := obj[key]; present {
			if _, valid := value.(json.Boolean);
			   !valid {errf(errs, "%s: %s must be a boolean", at, key)}
		}
	}
	if r.statement == "" {errf(errs, "%s: statement is required", at)}
	if r.why == "" {errf(errs, "%s: why is required", at)}
	if r.instead_of == "" {errf(errs, "%s: instead_of is required (compared to what?)", at)}
	if r.evidence == "" {errf(errs, "%s: evidence is required (what hard evidence?)", at)}
	if r.cost == "" {errf(errs, "%s: cost is required (at what cost?)", at)}
	require_key(errs, at, obj, "severity")
	require_key(errs, at, obj, "check")
	check_enum(errs, at, obj, "severity", Severity)
	spec, _ := obj["check"].(json.Object)
	validate_check(&r.check, spec, at, errs)
}

rule_fix_hint :: proc(r: ^Rule) -> string {
	return r.fix_hint if r.fix_hint != "" else r.statement
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
