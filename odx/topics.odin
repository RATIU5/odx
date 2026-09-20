package odx

import "core:encoding/json"
import "core:os"
import "core:slice"
import "core:strings"

TOPIC_FILE :: "topic.json5"
PROSE_FILE :: "topic.md"
PROJECT_TOPICS_DIR :: ".odx/topics"

Topic :: struct {
	name:              string,
	summary:           string,
	tags:              []string,
	aliases:           []string,
	example_questions: []string,
	applies_to:        struct {
		roles: []string,
	},
	related:           []string,
	example_roles:     map[string]string,
	rules:             []Rule,
	// runtime only (not in topic.json5; TOPIC_KEYS rejects them there)
	prose:             string, // topic.md
	source:            string, // "builtin" or the directory it came from
	overrides:         bool, // project topic shadowing a builtin of the same name
}

// Rule is one entry of a topic's frontmatter, the only registry of rule metadata (20.4).
// Enum fields unmarshal from their lowercase names; validate_rule checks presence and spelling
// against the parsed tree because json.unmarshal leaves an unknown name at the zero value.
Rule :: struct {
	id:           string,
	statement:    string,
	why:          string,
	severity:     Severity, // mandatory
	class:        string, // stable greppable name, e.g. "layering_hidden_state"
	fix:          Fix_Mode,
	ignorable:    bool, // default true; set at load when absent
	baselineable: bool, // 20.5: has a stable subject
	retired:      bool,
	check:        Check_Spec, // mandatory; `{ kind: "manual" }` for reviewer-only rules
}

Fix_Mode :: enum {
	none,
	safe,
}

Check_Kind :: enum {
	manual,
	path_role,
	banned_import,
	banned_construct,
	banned_call,
	vet_tag,
	require_attribute,
}

Construct :: enum {
	mutable_global,
	foreign_decl,
	using_stmt,
	no_bounds_check,
}

// Check_Spec is one field bag for every kind because core:encoding/json cannot pick a union
// variant by a discriminator field. validate_rule enforces the per-kind shape at load time.
Check_Spec :: struct {
	kind:               Check_Kind,
	attribute:          string, // require_attribute
	on:                 string, // require_attribute: "" | "exported_procs"
	result_type_suffix: []string, // require_attribute; defaults to ["Error"]
	from:               string, // banned_import: documentation only
	construct:          Construct, // banned_construct
	names:              []string, // banned_call
	roles:              []string, // only these roles
	except_roles:       []string, // all but these roles
}

TOPIC_KEYS := []string {
	"name",
	"summary",
	"tags",
	"aliases",
	"example_questions",
	"applies_to",
	"related",
	"example_roles",
	"rules",
}
RULE_KEYS := []string {
	"id",
	"statement",
	"why",
	"severity",
	"class",
	"fix",
	"ignorable",
	"baselineable",
	"retired",
	"check",
}
DEFAULT_RESULT_SUFFIX := []string{"Error"}

Rulebook :: struct {
	topics: [dynamic]Topic, // sorted by name
}

// load_rulebook layers built-ins, then <root>/.odx/topics/* (17.17). root may be "".
load_rulebook :: proc(root: string, errs: ^[dynamic]string) -> (rb: Rulebook) {
	for b in BUILTIN_TOPICS {
		js, md: string
		for f in b.files {
			switch f.name {
			case TOPIC_FILE:
				js = string(f.data)
			case PROSE_FILE:
				md = string(f.data)
			}
		}
		add_topic(&rb, "builtin", b.name, js, md, errs)
	}
	for e in project_subdirs(root, PROJECT_TOPICS_DIR) {
		js, _ := os.read_entire_file(join({e.fullpath, TOPIC_FILE}), context.allocator)
		md, _ := os.read_entire_file(join({e.fullpath, PROSE_FILE}), context.allocator)
		add_topic(&rb, join({PROJECT_TOPICS_DIR, e.name}), e.name, string(js), string(md), errs)
	}
	slice.sort_by(rb.topics[:], proc(a, b: Topic) -> bool {return a.name < b.name})
	return
}

// project_subdirs lists the directories under <root>/<sub>, sorted by name; none if root is "".
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
add_topic :: proc(rb: ^Rulebook, source, dir_name, js, md: string, errs: ^[dynamic]string) {
	at := join({source if source != "builtin" else join({"rules", dir_name}), TOPIC_FILE})
	if js == "" {
		errf(errs, "%s: missing", at)
		return
	}
	t := Topic {
		source = source,
		prose  = md,
	}
	tree, ok := unmarshal_json5(js, &t, at, TOPIC_KEYS, errs)
	if !ok {return}
	if t.name != dir_name {errf(errs, "%s: name %s does not match directory", at, t.name)}
	if t.summary == "" {errf(errs, "%s: summary is required", at)}
	if md == "" {errf(errs, "%s: %s is missing or empty", at, PROSE_FILE)}
	// unmarshal keeps array order, so rules[i] and the i-th object in the tree agree
	objs := json_array(tree, "rules")
	seen := make(map[string]bool, context.temp_allocator)
	for &r, i in t.rules {
		if !strings.has_prefix(r.id, "R") ||
		   r.id in seen {errf(errs, "%s: bad or duplicate rule id %s", at, r.id)}
		seen[r.id] = true
		obj: json.Object
		if i < len(objs) {obj, _ = objs[i].(json.Object)}
		check_keys(errs, at, "rule.", obj, RULE_KEYS)
		if "ignorable" not_in obj {r.ignorable = true}
		if r.retired {continue}
		validate_rule(&r, obj, strings.concatenate({at, " ", r.id}, context.temp_allocator), errs)
	}
	// same name later in the layer order overrides (17.17)
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
	if r.why == "" {errf(errs, "%s: why is required (20.4)", at)}
	require_key(errs, at, obj, "severity")
	require_key(errs, at, obj, "check")
	check_enum(errs, at, obj, "severity", Severity)
	check_enum(errs, at, obj, "fix", Fix_Mode)
	spec, _ := obj["check"].(json.Object)
	check_enum(errs, at, spec, "kind", Check_Kind)
	c := &r.check
	switch c.kind {
	case .manual, .path_role, .banned_import, .vet_tag:
	case .banned_construct:
		require_key(errs, at, spec, "construct")
		check_enum(errs, at, spec, "construct", Construct)
	case .banned_call:
		if len(c.names) == 0 {errf(errs, "%s: check.names is required", at)}
	case .require_attribute:
		if c.attribute == "" {errf(errs, "%s: check.attribute is required", at)}
		if c.on != "" &&
		   c.on != "exported_procs" {errf(errs, "%s: check.on must be exported_procs", at)}
		if c.result_type_suffix == nil {c.result_type_suffix = DEFAULT_RESULT_SUFFIX}
	}
}

find_topic :: proc(rb: ^Rulebook, name: string) -> ^Topic {
	for &t in rb.topics {
		if t.name == name {return &t}
	}
	return nil
}

// find_rule resolves a "topic/Rn" id.
find_rule :: proc(rb: ^Rulebook, id: string) -> ^Rule {
	topic, _, rule := strings.partition(id, "/")
	if t := find_topic(rb, topic); t != nil {
		for &r in t.rules {if r.id == rule {return &r}}
	}
	return nil
}

// Active_Rule is a checkable rule after the retired / --topic / disabled filters (computed once).
Active_Rule :: struct {
	id:   string, // "topic/Rn"
	rule: ^Rule,
}

active_rules :: proc(p: ^Project, only_topics: []string) -> []Active_Rule {
	out := make([dynamic]Active_Rule)
	for &t in p.rb.topics {
		if len(only_topics) > 0 && !slice.contains(only_topics, t.name) {continue}
		for &r in t.rules {
			if r.check.kind == .manual || r.retired {continue}
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

// exemplar_config builds the config for `odx check --exemplar <topic>` (17.6): the topic's
// example/ directory is the root and example_roles supplies the role map.
exemplar_config :: proc(t: ^Topic, base: ^Config) -> (cfg: Config) {
	cfg = default_config()
	cfg.odin = base.odin
	if base.layering != nil {cfg.layering = base.layering}
	cfg.exclude = {}
	clear(&cfg.roles)
	for dir, role in t.example_roles {
		cfg.roles[role] = slice.concatenate(
			[][]string{cfg.roles[role], {strings.trim_prefix(dir, "example/")}},
		)
	}
	return
}
