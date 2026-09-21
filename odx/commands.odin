package odx

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:slice"
import "core:strings"

print_json :: proc(v: any) {
	out, err := json.marshal(v, {pretty = true, sort_maps_by_key = true, use_enum_names = true})
	if err != nil {fail("json: %v", err)}
	fmt.println(string(out))
}

list_topics :: proc(o: Opts, p: ^Project) {
	if o.json {
		print_json(p.rb.topics[:])
		return
	}
	w := 0
	for t in p.rb.topics {w = max(w, len(t.name))}
	for t in p.rb.topics {
		fmt.printf("%-*s  %s", w, t.name, t.summary)
		if t.source != "builtin" {fmt.printf("  [%s]", t.source)}
		fmt.println()
	}
}

cmd_explain :: proc(o: Opts) {
	if o.checklist {
		cmd_checklist(o)
		return
	}
	if len(o.args) > 1 {fail("usage: odx explain [<topic>] [--rule R3]")}
	p := must_load(o, false)
	if len(o.args) == 0 {
		list_topics(o, &p)
		return
	}
	t := find_topic(&p.rb, o.args[0])
	if t == nil {fail("unknown topic %q (see `odx explain`)", o.args[0])}
	if o.json {
		print_json(t^)
		return
	}
	fmt.printfln("%s: %s", t.name, t.summary)
	if len(t.related) >
	   0 {fmt.printfln("related: %s", strings.join(t.related, ", ", context.temp_allocator))}
	fmt.println()
	shown := 0
	for r in t.rules {
		if r.retired || (o.rule != "" && r.id != o.rule) {continue}
		shown += 1
		id := strings.concatenate({t.name, "/", r.id}, context.temp_allocator)
		how := fmt.tprintf("check: %v", r.check.kind)
		if reason, dis := p.cfg.disabled[id];
		   dis {how = strings.concatenate({how, "  DISABLED: ", reason}, context.temp_allocator)}
		fmt.printfln(
			"%-14s %s\n%-14s why: %s\n%-14s instead of: %s\n%-14s evidence: %s\n%-14s cost: %s\n%-14s %s",
			id,
			r.statement,
			"",
			r.why,
			"",
			r.instead_of,
			"",
			r.evidence,
			"",
			r.cost,
			"",
			how,
		)
		if r.prose != "" {fmt.printfln("\n%s", r.prose)}
		if r.fires != "" {fmt.printfln("\nfires:\n%s", indent(r.fires))}
		if r.silent != "" {fmt.printfln("\nsilent (compiles and passes):\n%s", indent(r.silent))}
		fmt.println()
	}
	if o.rule != "" {
		if shown == 0 {fail("no rule %s in topic %s", o.rule, t.name)}
		return
	}
	fmt.println()
	fmt.print(t.prose)
}

READER_CHECKS_HEADING :: "\n## Reader checks\n"

// reader_checks: the part of topic.md a reviewer enforces by hand; "" when the topic has none.
reader_checks :: proc(t: Topic) -> string {
	_, found, rest := strings.partition(t.prose, READER_CHECKS_HEADING)
	return strings.trim_space(rest) if found != "" else ""
}

cmd_checklist :: proc(o: Opts) {
	p := must_load(o, false)
	for t in p.rb.topics {
		if len(o.args) > 0 && !slice.contains(o.args[:], t.name) {continue}
		if rc := reader_checks(t); rc != "" {fmt.printfln("## %s\n\n%s\n", t.name, rc)}
	}
}

cmd_for :: proc(o: Opts) {
	if o.emit && len(o.args) == 0 {
		p := must_load(o, true)
		fmt.print(claude_md(&p, p.rb.topics[:]))
		return
	}
	if len(o.args) != 1 {fail("usage: odx for <path> | odx for --emit-claude-md [<path>]")}
	p := must_load(o, true)
	abs, _ := filepath.abs(o.args[0])
	rel, inside := rel_of(p.root, abs if os.is_directory(abs) else filepath.dir(abs))
	if !inside {fail("%s is outside the project root %s", o.args[0], p.root)}
	if is_excluded(&p.cfg, rel) {fail("%s is excluded by odx.json5", rel)}
	role, n := role_of(&p.cfg, rel)
	if n > 1 {fail("%s matches more than one role in odx.json5", rel)}
	matched: [dynamic]Topic
	for t in p.rb.topics {
		if len(t.applies_to.roles) == 0 ||
		   slice.contains(t.applies_to.roles, role) {append(&matched, t)}
	}
	if o.json {
		print_json(struct {
			package_dir: string,
			role:        string,
			topics:      []Topic,
		}{rel, role, matched[:]})
		return
	}
	if o.emit {
		fmt.print(claude_md(&p, matched[:]))
		return
	}
	shown := rel if rel != "" else "."
	if n == 0 {
		fmt.printfln(
			"%s: no role (roles are an optional preset; see `odx explain dependencies`)",
			shown,
		)
	} else {
		fmt.printfln("%s: role %s", shown, role)
	}
	if o.brief {
		for t in matched {fmt.printfln("  %-12s %s", t.name, t.summary)}
	} else {
		for t in matched {
			fmt.printfln("\n%s: %s", t.name, t.summary)
			for r in t.rules {
				if r.retired {continue}
				id := strings.concatenate({t.name, "/", r.id}, context.temp_allocator)
				if reason, dis := p.cfg.disabled[id]; dis {
					fmt.printfln("  %-14s disabled: %s", id, reason)
					continue
				}
				fmt.printfln("  %-14s %s\n  %-14s why: %s", id, r.statement, "", r.why)
			}
			if rc := reader_checks(t); rc != "" {fmt.printfln("\n  reader checks (odx explain --checklist %s):\n%s", t.name, indent(strip_fences(rc)))}
		}
	}
}

// strip_fences drops fenced code blocks: the prose keeps its statements, a summary its length.
strip_fences :: proc(md: string) -> string {
	b := strings.builder_make(context.temp_allocator)
	in_fence := false
	for l in strings.split_lines(md, context.temp_allocator) {
		if strings.has_prefix(l, "```") {
			in_fence = !in_fence
			continue
		}
		if in_fence {continue}
		strings.write_string(&b, l)
		strings.write_byte(&b, '\n')
	}
	return strings.trim_space(strings.to_string(b))
}

// INIT_CONFIG_HEAD + BODY is both what `odx init` writes and, parsed, the default Config.
INIT_CONFIG_HEAD :: `{
  // Package roles: each glob is a directory path relative to this file (17.5).
  // Every package must match exactly one role. Detected package directories:
`
INIT_CONFIG_BODY :: `  version: 1,
  roles: {
    pure: [],    // no os, no foreign, no I/O, no mutable globals
    service: [], // takes capabilities as parameters
    edge: [],    // os, foreign, I/O allowed
  },
  dependencies: {
    pure: { may_import: ["pure", "core:*"] },
    service: { may_import: ["pure", "service", "core:*"] },
    edge: { may_import: ["pure", "service", "edge", "core:*", "vendor:*"] },
  },
  exclude: [".odx/**", "rules/**", "vendor/**", "build/**"],
  // disabled: { "errors/R3": "reason of at least ten characters" },
  odin: {
    flags: ["-vet", "-vet-tabs", "-vet-cast", "-strict-style", "-warnings-as-errors"],
    forbidden_flags: ["-no-bounds-check", "-disable-assert", "-no-type-assert", "-ignore-unknown-attributes"],
    required_flags: ["-sanitize:address", "-define:ODIN_TEST_FAIL_ON_BAD_MEMORY=true"],
    // declined: { "-vet-style": "why this project considered the flag and refused it" },
    // tagged_files_min: 0, // #+vet explicit-allocators coverage may not drop below this; raise it as it grows
    version: "dev-2026-09",
  },
  // type-name suffixes errors/R3 treats as an error result, besides any enum with a None/Ok
  // variant or nil-able union, which need no name
  errors: { types: ["Error"] },
}
`

default_config :: proc() -> (cfg: Config) {
	err := json.unmarshal_string(INIT_CONFIG_HEAD + INIT_CONFIG_BODY, &cfg, spec = .JSON5)
	assert(err == nil, "INIT_CONFIG must parse")
	return
}

INIT_MISE :: `[tools]
odin = "dev-2026-09"

[env]
ODIN_VET = "-vet -vet-tabs -vet-cast -strict-style -warnings-as-errors"

[tasks.check]
description = "Rulebook + compiler checks"
alias = "c"
run = "odx doctor && odx check"

[tasks.test]
run = "odin test . $ODIN_VET -sanitize:address -define:ODIN_TEST_FAIL_ON_BAD_MEMORY=true -out:build/test"

[tasks.ci]
depends = ["check", "test"]
`

cmd_init :: proc(o: Opts) {
	root, _ := filepath.abs(o.root if o.root != "" else ".")
	cfg_path := join({root, CONFIG_FILE})
	if os.exists(cfg_path) {
		if !o.hooks {fail("%s already exists", cfg_path)}
		p := load_project(root)
		write_hooks(&p)
		return
	}

	b := strings.builder_make()
	strings.write_string(&b, INIT_CONFIG_HEAD)
	skip := Config {
		exclude = {".*", ".*/**", "build/**", "vendor/**"},
	}
	for d in package_dirs(root, &skip) {fmt.sbprintfln(&b, "  //   %s", d)}
	strings.write_string(&b, INIT_CONFIG_BODY)
	if err := os.write_entire_file(cfg_path, strings.to_string(b));
	   err != nil {fail("write %s: %v", cfg_path, err)}
	fmt.println("wrote", cfg_path)

	mise := join({root, "mise.toml"})
	if os.exists(mise) {
		fmt.printfln("%s exists; add these tasks:\n%s", mise, INIT_MISE)
	} else {
		if err := os.write_entire_file(mise, INIT_MISE);
		   err != nil {fail("write %s: %v", mise, err)}
		fmt.println("wrote", mise)
	}
	if o.hooks {
		p := load_project(root)
		write_hooks(&p)
	}
	if len(package_dirs(root, &skip)) > 0 {
		fmt.println(
			"existing packages found: after filling in roles, `odx baseline regen` freezes their current violations so unrelated edits are not blocked",
		)
	}
	gi := join({root, ".gitignore"})
	if data, rerr := os.read_entire_file(gi, context.allocator);
	   rerr == nil && !strings.contains(string(data), ".odx/cache/") {
		if err := os.write_entire_file(gi, strings.concatenate({string(data), "\n.odx/cache/\n"}));
		   err != nil {fail("write %s: %v", gi, err)}
		fmt.println("appended .odx/cache/ to", gi)
	}
}

// The only hook: it reports after an edit and exits 0. Nothing odx installs can block.
INIT_HOOKS :: `{
  "hooks": {
    "PostToolBatch": [{ "hooks": [{ "type": "command", "command": "odx hook edit" }] }]
  }
}
`
CLAUDE_MD_HEAD ::
	`
## odx

- ` +
	"`odx check`" +
	` must pass before you stop (` +
	"`--json`" +
	` gives a fix_hint and ignore_syntax per finding).
- Ask before editing rules/, odx.json5 or tests/fixtures/.
- Generated by ` +
	"`odx for --emit-claude-md`" +
	`; regenerate after editing rules/.
`

// claude_md renders topics as the CLAUDE.md section `odx for --emit-claude-md` prints and
// `odx init --hooks` writes: the rules sit inline where they cost nothing per turn.
claude_md :: proc(p: ^Project, topics: []Topic) -> string {
	b := strings.builder_make()
	strings.write_string(&b, CLAUDE_MD_HEAD)
	for t in topics {
		fmt.sbprintfln(&b, "\n### %s: %s", t.name, t.summary)
		if len(t.applies_to.roles) > 0 {
			fmt.sbprintfln(
				&b,
				"Applies to roles %s (odx.json5).",
				strings.join(t.applies_to.roles, ", ", context.temp_allocator),
			)
		}
		for r in t.rules {
			if r.retired {continue}
			id := strings.concatenate({t.name, "/", r.id}, context.temp_allocator)
			if id in p.cfg.disabled {continue}
			fmt.sbprintfln(
				&b,
				"- **%s** %s\n  Why: %s\n  Instead of: %s",
				id,
				r.statement,
				r.why,
				r.instead_of,
			)
		}
		if rc := reader_checks(t); rc != "" {
			fmt.sbprintfln(&b, "\nReader checks for %s (not enforced by `odx check`):\n\n%s", t.name, strip_fences(rc))
		}
	}
	return strings.to_string(b)
}

write_hooks :: proc(p: ^Project) {
	settings := join({p.root, ".claude", "settings.json"})
	if os.exists(settings) {
		fmt.printfln("%s exists; merge in:\n%s", settings, INIT_HOOKS)
	} else {
		os.make_directory_all(join({p.root, ".claude"}))
		if err := os.write_entire_file(settings, INIT_HOOKS);
		   err != nil {fail("write %s: %v", settings, err)}
		fmt.println("wrote", settings)
	}
	md := join({p.root, "CLAUDE.md"})
	data, _ := os.read_entire_file(md, context.allocator)
	if strings.contains(string(data), "## odx") {
		fmt.printfln("%s already has an odx section; refresh it with `odx for --emit-claude-md`", md)
		return
	}
	section := claude_md(p, p.rb.topics[:])
	if err := os.write_entire_file(md, strings.concatenate({string(data), section}));
	   err != nil {fail("write %s: %v", md, err)}
	fmt.println("appended odx section to", md)
}

indent :: proc(block: string) -> string {
	out := make([dynamic]string, context.temp_allocator)
	for l in strings.split_lines(block, context.temp_allocator) {append(&out, strings.concatenate({"    ", l}, context.temp_allocator))}
	return strings.join(out[:], "\n", context.temp_allocator)
}
