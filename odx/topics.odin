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

Rule :: struct {
	id:        string,
	statement: string,
	why:       string,
	severity:  string, // "" = error (17.11)
	retired:   bool,
	check:     Check, // "manual" or a spec
}

Check :: union {
	string,
	Check_Spec,
}

// Check_Spec is intentionally loose: kind picks the implementation (M2), the rest is per-kind.
Check_Spec :: struct {
	kind:               string,
	attribute:          string,
	on:                 string,
	result_type_suffix: []string,
	from:               string,
	construct:          string,
	names:              []string,
	roles:              []string,
	except_roles:       []string,
}

TOPIC_KEYS :: []string{"name", "summary", "tags", "aliases", "example_questions", "applies_to", "related", "example_roles", "rules"}
RULE_KEYS :: []string{"id", "statement", "why", "severity", "retired", "check"}

Rulebook :: struct {
	topics: [dynamic]Topic, // sorted by name
	errs:   [dynamic]string,
}

// load_rulebook layers built-ins, then <root>/.odx/topics/* (17.17). root may be "".
load_rulebook :: proc(root: string) -> (rb: Rulebook) {
	for b in BUILTIN_TOPICS {
		t: Topic
		t.source = "builtin"
		js, md: string
		for f in b.files {
			switch f.name {
			case TOPIC_FILE:
				js = string(f.data)
			case PROSE_FILE:
				md = string(f.data)
			}
		}
		add_topic(&rb, &t, b.name, js, md)
	}
	if root != "" {
		dir := join({root, PROJECT_TOPICS_DIR})
		if os.is_directory(dir) {
			entries, _ := os.read_all_directory_by_path(dir, context.allocator)
			slice.sort_by(entries, proc(a, b: os.File_Info) -> bool {return a.name < b.name})
			for e in entries {
				if e.type != .Directory {continue}
				t: Topic
				t.source = join({PROJECT_TOPICS_DIR, e.name})
				js, _ := os.read_entire_file(join({e.fullpath, TOPIC_FILE}), context.allocator)
				md, _ := os.read_entire_file(join({e.fullpath, PROSE_FILE}), context.allocator)
				add_topic(&rb, &t, e.name, string(js), string(md))
			}
		}
	}
	slice.sort_by(rb.topics[:], proc(a, b: Topic) -> bool {return a.name < b.name})
	return
}

@(private = "file")
add_topic :: proc(rb: ^Rulebook, t: ^Topic, dir_name, js, md: string) {
	at := strings.concatenate({t.source, "/", dir_name, "/", TOPIC_FILE})
	if js == "" {
		append(&rb.errs, strings.concatenate({at, ": missing"}))
		return
	}
	if err := json.unmarshal_string(js, t, spec = .JSON5); err != nil {
		append(&rb.errs, fmt_err(at, err))
		return
	}
	if v, perr := json.parse_string(js, spec = .JSON5); perr == nil {
		check_keys(&rb.errs, at, v, TOPIC_KEYS)
		if obj, ok := v.(json.Object); ok {
			if rules, has := obj["rules"]; has {
				if arr, isarr := rules.(json.Array); isarr {
					for r in arr {check_keys(&rb.errs, strings.concatenate({at, " rule"}, context.temp_allocator), r, RULE_KEYS)}
				}
			}
		}
	}
	if t.name != dir_name {
		append(&rb.errs, strings.concatenate({at, ": name ", t.name, " does not match directory"}))
	}
	if t.summary == "" {append(&rb.errs, strings.concatenate({at, ": summary is required"}))}
	if md == "" {append(&rb.errs, strings.concatenate({at, ": ", PROSE_FILE, " is missing or empty"}))}
	t.prose = md
	seen := make(map[string]bool, context.temp_allocator)
	for r in t.rules {
		if !strings.has_prefix(r.id, "R") || r.id in seen {
			append(&rb.errs, strings.concatenate({at, ": bad or duplicate rule id ", r.id}))
		}
		seen[r.id] = true
		if r.retired {continue}
		if r.statement == "" {append(&rb.errs, strings.concatenate({at, " ", r.id, ": statement is required"}))}
		if r.severity != "" && r.severity != "error" && r.severity != "warning" {
			append(&rb.errs, strings.concatenate({at, " ", r.id, ": severity must be error or warning"}))
		}
		switch c in r.check {
		case string:
			if c != "manual" {append(&rb.errs, strings.concatenate({at, " ", r.id, ": check must be \"manual\" or an object"}))}
		case Check_Spec:
			if c.kind == "" {append(&rb.errs, strings.concatenate({at, " ", r.id, ": check.kind is required"}))}
		case nil:
			append(&rb.errs, strings.concatenate({at, " ", r.id, ": check is required"}))
		}
	}
	// same name later in the layer order overrides (17.17)
	for &old, i in rb.topics {
		if old.name == t.name {
			t.overrides = true
			rb.topics[i] = t^
			return
		}
	}
	append(&rb.topics, t^)
}

find_topic :: proc(rb: ^Rulebook, name: string) -> ^Topic {
	for &t in rb.topics {
		if t.name == name {return &t}
	}
	return nil
}

// validate_disabled checks every odx.json5 disabled id names a real rule.
validate_disabled :: proc(rb: ^Rulebook, cfg: ^Config) {
	ids, _ := slice.map_keys(cfg.disabled, context.temp_allocator)
	slice.sort(ids)
	for id in ids {
		topic, _, rule := strings.partition(id, "/")
		t := find_topic(rb, topic)
		ok := false
		if t != nil {
			for r in t.rules {if r.id == rule {ok = true}}
		}
		if !ok {append(&rb.errs, strings.concatenate({CONFIG_FILE, ": disabled ", id, " is not a known rule"}))}
	}
}
