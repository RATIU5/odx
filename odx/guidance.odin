package odx

import crypto_hash "core:crypto/hash"
import "core:encoding/hex"
import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:slice"
import "core:strings"

// Bump when interpreter semantics change without changing serialized policy.
GUIDANCE_REVISION :: 3

Guidance_Package :: struct {
	path: string,
	role: string,
}

guidance_json :: proc(value: any) -> string {
	data, err := json.marshal(value, {sort_maps_by_key = true, use_enum_names = true})
	if err != nil {fail("guidance JSON: %v", err)}
	return string(data)
}

guidance_block :: proc(p: ^Project, rels: []string, scoped: bool) -> string {
	packages := make([]Guidance_Package, len(rels), context.temp_allocator)
	for rel, i in rels {
		role, _ := role_of(&p.cfg, rel)
		packages[i] = {rel, role}
	}
	// Exemplar concatenation follows filesystem walk order and is not used by guidance.
	topics := slice.clone(p.rb.topics[:], context.temp_allocator)
	for &t in topics {
		t.exemplar = ""
		t.source = ""
		t.rules = slice.clone(t.rules, context.temp_allocator)
		for &r in t.rules {r.file = ""}
	}
	snapshot := guidance_json(struct {
		revision: int,
		scoped:   bool,
		config:   Config,
		packages: []Guidance_Package,
		topics:   []Topic,
	}{GUIDANCE_REVISION, scoped, p.cfg, packages, topics})
	digest := crypto_hash.hash_bytes(.SHA256, transmute([]byte)snapshot, context.temp_allocator)
	encoded := hex.encode(digest, context.temp_allocator)
	b := strings.builder_make(context.temp_allocator)
	fmt.sbprintfln(
		&b,
		"%s\n## odx\n\nPolicy fingerprint (generation %d): `%s`",
		GUIDANCE_BEGIN,
		GUIDANCE_REVISION,
		string(encoded),
	)
	fmt.sbprintfln(
		&b,
		"\nScope: %s. Rules below are the union applicable to this selection; each rule retains its own scope.",
		"one selected package" if scoped else "all discovered project packages",
	)
	for pkg in packages {fmt.sbprintfln(&b, "- Package `%s`: role `%s`", pkg.path if pkg.path != "" else ".", pkg.role if pkg.role != "" else "(unmapped)")}
	strings.write_string(
		&b,
		"\nRun `odx check --json` for findings and coverage. Warnings fail with `--strict`; baselines soften findings and suppressions remove accepted findings. Exit 0 alone does not prove complete analysis. Guidance freshness checks policy synchronization, not source compliance. Baselines accept occurrences in unchanged source snapshots; checks never rewrite them. Use `odx baseline add`, `prune`, or `regen` for explicit maintenance.\n\nUse `odx guidance check <markdown-file> [package-path]` to check this section and `odx guidance write <markdown-file> [package-path]` to regenerate it. Repeat the same scope. Rebuild after changing embedded builtin rules; project overrides load directly.\n\nConfigured policy (effective defaults included; no compiler run is implied):\n\n",
	)
	fmt.sbprintfln(&b, "```json\n%s\n```", guidance_json(p.cfg))
	strings.write_string(&b, claude_md(p, applicable_topics(p, rels, len(p.dirs) == 0)))
	fmt.sbprintfln(&b, "\n%s", GUIDANCE_END)
	block := strings.to_string(b)
	region, err := guidance_region(block)
	if err != "" || !region.found || region.start != 0 || region.end != len(block) {
		fail("policy text cannot be rendered as managed Markdown: %s", err)
	}
	return block
}

cmd_guidance :: proc(o: Opts) {
	if len(o.args) < 2 || len(o.args) > 3 || (o.args[0] != "check" && o.args[0] != "write") {
		fail("usage: odx guidance check|write <markdown-file> [package-path]")
	}
	p := must_load(o, true)
	rels := p.dirs
	scoped := len(o.args) == 3
	if scoped {
		rels = select_packages(p.root, p.dirs, o.args[2:])
		if len(rels) !=
		   1 {fail("guidance scope requires exactly one included package (selected %d)", len(rels))}
	}
	path := o.args[1]
	if !filepath.is_abs(path) {path = join({p.root, path})}
	status, message := guidance_sync(path, guidance_block(&p, rels, scoped), o.args[0] == "write")
	if status == 2 {fmt.eprintln(message)} else {fmt.println(message)}
	os.exit(status)
}
