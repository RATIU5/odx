package odx

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:slice"
import "core:strings"

// load_all loads rulebook + config (config only when a root exists). Config/topic errors exit 2.
load_all :: proc(o: Opts, need_config: bool) -> (rb: Rulebook, cfg: Config, root: string) {
	root = find_root(o.root)
	if root == "" && need_config {fail("no %s found here or in any parent (use --root or `odx init`)", CONFIG_FILE)}
	rb = load_rulebook(root)
	if root != "" {
		errs: [dynamic]string
		cfg, errs = load_config(root)
		append(&rb.errs, ..errs[:])
		validate_disabled(&rb, &cfg)
	}
	slice.sort(rb.errs[:])
	if len(rb.errs) > 0 {
		for e in rb.errs {fmt.eprintln("odx:", e)}
		os.exit(EXIT_TOOL)
	}
	return
}

print_json :: proc(v: any) {
	out, err := json.marshal(v, {pretty = true, sort_maps_by_key = true})
	if err != nil {fail("json: %v", err)}
	fmt.println(string(out))
}

cmd_topics :: proc(o: Opts) {
	rb, _, _ := load_all(o, false)
	if o.json {
		print_json(rb.topics[:])
		return
	}
	w := 0
	for t in rb.topics {w = max(w, len(t.name))}
	for t in rb.topics {
		fmt.printf("%-*s  %s", w, t.name, t.summary)
		if t.source != "builtin" {fmt.printf("  [%s]", t.source)}
		fmt.println()
	}
}

cmd_explain :: proc(o: Opts) {
	if len(o.args) != 1 {fail("usage: odx explain <topic> [--rule R3]")}
	rb, cfg, _ := load_all(o, false)
	t := find_topic(&rb, o.args[0])
	if t == nil {fail("unknown topic %q (see `odx topics`)", o.args[0])}
	if o.json {
		print_json(t^)
		return
	}
	fmt.printfln("%s: %s", t.name, t.summary)
	if len(t.related) > 0 {fmt.printfln("related: %s", strings.join(t.related, ", ", context.temp_allocator))}
	fmt.println()
	shown := 0
	for r in t.rules {
		if r.retired || (o.rule != "" && r.id != o.rule) {continue}
		shown += 1
		id := strings.concatenate({t.name, "/", r.id}, context.temp_allocator)
		fmt.printfln("%-14s %s", id, r.statement)
		fmt.printfln("%-14s why: %s", "", r.why)
		how := "check: manual (reviewer checklist)"
		if c, ok := r.check.(Check_Spec); ok {
			how = strings.concatenate({"check: ", c.kind}, context.temp_allocator)
		}
		if reason, dis := cfg.disabled[id]; dis {
			how = strings.concatenate({how, "  DISABLED: ", reason}, context.temp_allocator)
		}
		fmt.printfln("%-14s %s", "", how)
	}
	if o.rule != "" {
		if shown == 0 {fail("no rule %s in topic %s", o.rule, t.name)}
		return
	}
	fmt.println()
	fmt.print(t.prose)
}

cmd_for :: proc(o: Opts) {
	if len(o.args) != 1 {fail("usage: odx for <path>")}
	rb, cfg, root := load_all(o, true)
	abs, _ := filepath.abs(o.args[0], context.allocator)
	dir := abs if os.is_directory(abs) else filepath.dir(abs)
	rel, rerr := filepath.rel(root, dir, context.allocator)
	if rerr != nil || strings.has_prefix(rel, "..") {fail("%s is outside the project root %s", o.args[0], root)}
	if rel == "." {rel = ""}
	if is_excluded(&cfg, rel) {fail("%s is excluded by odx.json5", rel)}
	role, n := role_of(&cfg, rel)
	if n > 1 {fail("%s matches more than one role in odx.json5", rel)}
	matched: [dynamic]Topic
	for t in rb.topics {
		if len(t.applies_to.roles) == 0 || slice.contains(t.applies_to.roles, role) {append(&matched, t)}
	}
	if o.json {
		print_json(struct {
			package_dir: string,
			role:        string,
			topics:      []Topic,
		}{rel, role, matched[:]})
		return
	}
	if n == 0 {
		fmt.printfln("%s: no role (layering/R1: add it to roles in %s)", rel if rel != "" else ".", CONFIG_FILE)
	} else {
		fmt.printfln("%s: role %s", rel if rel != "" else ".", role)
	}
	for t in matched {fmt.printfln("  %-12s %s", t.name, t.summary)}
	if n == 0 {os.exit(EXIT_VIOLATION)}
}

cmd_ext :: proc(o: Opts) {
	if len(o.args) != 1 || (o.args[0] != "list" && o.args[0] != "validate") {fail("usage: odx ext list | odx ext validate")}
	root := find_root(o.root)
	rb := load_rulebook(root)
	cfg: Config
	if root != "" {
		errs: [dynamic]string
		cfg, errs = load_config(root)
		append(&rb.errs, ..errs[:])
		validate_disabled(&rb, &cfg)
	}
	// ext validate = the loader in dry-run mode, all errors listed (17.19)
	if o.args[0] == "validate" {
		if o.json {
			print_json(struct {
				ok:     bool,
				errors: []string,
			}{len(rb.errs) == 0, rb.errs[:]})
		} else {
			for e in rb.errs {fmt.println(e)}
			if len(rb.errs) == 0 {fmt.printfln("ok: %d topics, %d disabled rules", len(rb.topics), len(cfg.disabled))}
		}
		os.exit(EXIT_TOOL if len(rb.errs) > 0 else 0)
	}
	if o.json {
		print_json(struct {
			root:     string,
			topics:   []Topic,
			disabled: map[string]string,
			errors:   []string,
		}{root, rb.topics[:], cfg.disabled, rb.errs[:]})
		return
	}
	fmt.printfln("root: %s", root if root != "" else "(none)")
	for t in rb.topics {
		fmt.printf("  %-12s %s", t.name, t.source)
		if t.overrides {fmt.print("  (overrides builtin)")}
		fmt.println()
	}
	ids, _ := slice.map_keys(cfg.disabled, context.temp_allocator)
	slice.sort(ids)
	for id in ids {fmt.printfln("  disabled %-14s %s", id, cfg.disabled[id])}
	for e in rb.errs {fmt.printfln("  error: %s", e)}
	if len(rb.errs) > 0 {os.exit(EXIT_TOOL)}
}

INIT_CONFIG :: `{
  // Package roles: each glob is a directory path relative to this file (17.5).
  // Every package must match exactly one role. Detected package directories:
//DETECTED
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
    version: "dev-2026-09",
  },
}
`

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
	root := o.root if o.root != "" else "."
	root, _ = filepath.abs(root, context.allocator)
	cfg_path := join({root, CONFIG_FILE})
	if os.exists(cfg_path) {fail("%s already exists", cfg_path)}

	// list directories with .odin files as a hint for the human
	b := strings.builder_make()
	w := os.walker_create_path(root)
	defer os.walker_destroy(&w)
	dirs := make(map[string]bool)
	for fi in os.walker_walk(&w) {
		if fi.type == .Directory && (fi.name == "build" || fi.name == "vendor" || strings.has_prefix(fi.name, ".")) {
			os.walker_skip_dir(&w)
			continue
		}
		if fi.type == .Regular && strings.has_suffix(fi.name, ".odin") {
			rel, _ := filepath.rel(root, filepath.dir(fi.fullpath), context.allocator)
					dirs[rel] = true
		}
	}
	keys, _ := slice.map_keys(dirs, context.temp_allocator)
	slice.sort(keys)
	for k in keys {fmt.sbprintfln(&b, "  //   %s", k)}

	detected, _ := strings.replace_all(INIT_CONFIG, "//DETECTED\n", strings.to_string(b))
	if err := os.write_entire_file(cfg_path, detected); err != nil {
		fail("write %s: %v", cfg_path, err)
	}
	fmt.println("wrote", cfg_path)
	mise := join({root, "mise.toml"})
	if os.exists(mise) {
		fmt.printfln("%s exists; add these tasks:\n%s", mise, INIT_MISE)
	} else {
		if err := os.write_entire_file(mise, INIT_MISE); err != nil {fail("write %s: %v", mise, err)}
		fmt.println("wrote", mise)
	}
	gi := join({root, ".gitignore"})
	if data, rerr := os.read_entire_file(gi, context.allocator); rerr == nil {
		if !strings.contains(string(data), ".odx/cache/") {
			if err := os.write_entire_file(gi, strings.concatenate({string(data), "\n.odx/cache/\n"})); err != nil {fail("write %s: %v", gi, err)}
			fmt.println("appended .odx/cache/ to", gi)
		}
	}
}
