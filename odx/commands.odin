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

// list_topics is `odx explain` with no topic (M0.3 folded `odx topics` in).
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
		if r.check.kind == .manual {how = "check: manual (reviewer checklist)"}
		if reason, dis := p.cfg.disabled[id];
		   dis {how = strings.concatenate({how, "  DISABLED: ", reason}, context.temp_allocator)}
		fmt.printfln("%-14s %s\n%-14s why: %s\n%-14s %s", id, r.statement, "", r.why, "", how)
	}
	if o.rule != "" {
		if shown == 0 {fail("no rule %s in topic %s", o.rule, t.name)}
		return
	}
	fmt.println()
	fmt.print(t.prose)
}

// cmd_checklist prints the manual rules (section 10): what a reviewer checks that odx check cannot.
cmd_checklist :: proc(o: Opts) {
	p := must_load(o, false)
	for t in p.rb.topics {
		if len(o.args) > 0 && !slice.contains(o.args[:], t.name) {continue}
		for r in t.rules {
			if r.retired || r.check.kind != .manual {continue}
			fmt.printfln("- [%s/%s] %s\n  why: %s", t.name, r.id, r.statement, r.why)
		}
	}
}

cmd_for :: proc(o: Opts) {
	if len(o.args) != 1 {fail("usage: odx for <path>")}
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
	shown := rel if rel != "" else "."
	if n == 0 {
		fmt.printfln("%s: no role (layering/R1: add it to roles in %s)", shown, CONFIG_FILE)
	} else {
		fmt.printfln("%s: role %s", shown, role)
	}
	for t in matched {fmt.printfln("  %-12s %s", t.name, t.summary)}
	if n == 0 {os.exit(EXIT_VIOLATION)}
}

// INIT_CONFIG is both what `odx init` writes and, parsed, the default Config.
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
  layering: {
    pure: { may_import: ["pure", "core:*"] },
    service: { may_import: ["pure", "service", "core:*"] },
    edge: { may_import: ["pure", "service", "edge", "core:*", "vendor:*"] },
  },
  exclude: [".odx/**", "rules/**", "vendor/**", "build/**"],
  // disabled: { "allocators/R2": "reason of at least ten characters" },
  odin: {
    flags: ["-vet", "-vet-tabs", "-vet-cast", "-strict-style", "-warnings-as-errors"],
    forbidden_flags: ["-no-bounds-check", "-disable-assert", "-no-type-assert", "-ignore-unknown-attributes"],
    required_flags: ["-sanitize:address", "-define:ODIN_TEST_FAIL_ON_BAD_MEMORY=true"],
    version: "dev-2026-09",
  },
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
		write_hooks(root) // existing project: --hooks adds only the hook files
		return
	}

	// the detected package directories go into the header comment as a hint for the human
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
	if o.hooks {write_hooks(root)}
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

// Claude Code hooks (17.10): the binary reads the hook JSON itself, so no jq and no wrapper script.
// The FileChanged matcher is PROTECTED verbatim, so the two can never drift.
INIT_HOOKS_HEAD :: `{
  "hooks": {
    "PostToolBatch": [{ "hooks": [{ "type": "command", "command": "odx hook edit" }] }],
    "FileChanged": [{ "matcher": "`
INIT_HOOKS_TAIL :: `", "hooks": [{ "type": "command", "command": "odx hook changed" }] }],
    "Stop": [{ "hooks": [{ "type": "command", "command": "odx hook stop" }] }]
  }
}
`
init_hooks :: proc() -> string {
	return strings.concatenate(
		{INIT_HOOKS_HEAD, strings.join(PROTECTED, "|", context.temp_allocator), INIT_HOOKS_TAIL},
	)
}
INIT_CLAUDE_MD ::
	`
## odx

- Before writing Odin code run ` +
	"`odx for <path>`" +
	` and ` +
	"`odx explain <topic>`" +
	`; ` +
	"`odx check`" +
	` must pass before you stop.
- Never edit rules/, .odx/, odx.json5, mise.toml, tests/fixtures/ or .claude/settings.json without asking.
  They are hash-locked; ` +
	"`odx doctor --verify-rulebook`" +
	` names any change and a human approves it with ` +
	"`ODX_ALLOW_PROTECTED=1 odx doctor --relock`" +
	`.
- Reviewing a diff: ` +
	"`odx explain --checklist`" +
	` lists the rules only a reader can check.
`

write_hooks :: proc(root: string) {
	settings := join({root, ".claude", "settings.json"})
	if os.exists(settings) {
		fmt.printfln("%s exists; merge in:\n%s", settings, init_hooks())
	} else {
		os.make_directory_all(join({root, ".claude"}))
		if err := os.write_entire_file(settings, init_hooks());
		   err != nil {fail("write %s: %v", settings, err)}
		fmt.println("wrote", settings)
	}
	md := join({root, "CLAUDE.md"})
	data, _ := os.read_entire_file(md, context.allocator)
	if strings.contains(string(data), "## odx") {return}
	if err := os.write_entire_file(md, strings.concatenate({string(data), INIT_CLAUDE_MD}));
	   err != nil {fail("write %s: %v", md, err)}
	fmt.println("appended odx section to", md)
}
