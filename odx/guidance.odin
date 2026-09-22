package odx

import crypto_hash "core:crypto/hash"
import "core:encoding/hex"
import "core:encoding/json"
import "core:fmt"
import "core:slice"
import "core:strings"

// Bump when interpreter semantics change without changing serialized policy.
GUIDANCE_REVISION :: 5

Guidance_Package :: struct {
	path: string,
	role: string,
}

guidance_json :: proc(value: any) -> string {
	data, err := json.marshal(value, {sort_maps_by_key = true, use_enum_names = true})
	if err != nil {fail("guidance JSON: %v", err)}
	return string(data)
}

guidance_check_json :: proc(spec: Check_Spec) -> string {
	value, err := json.parse_string(guidance_json(spec), parse_integers = true)
	if err != nil {fail("guidance selector JSON: %v", err)}
	values := value.(json.Object)
	fields := make(json.Object, context.temp_allocator)
	for key in check_fields(spec) {
		field := values[key]
		#partial switch value in field {
		case json.String:
			if value == "" {continue}
		case json.Array:
			if len(value) == 0 {continue}
		case json.Boolean:
			if !value {continue}
		case json.Object:
			if key == "requires_param" && spec.requires_param.type_suffix == "" {continue}
		}
		fields[key] = field
	}
	return guidance_json(fields)
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
		"\nRun `odx check --json` for findings and coverage. Exit 0 alone does not establish complete analysis. Use `odx policy --verify <file>` to check freshness or `odx policy --write <file>` to regenerate; repeat the selected package path.\n",
	)
	strings.write_string(&b, policy_topics_markdown(p, applicable_topics(p, rels, len(p.dirs) == 0)))
	fmt.sbprintfln(&b, "\n%s", GUIDANCE_END)
	block := strings.to_string(b)
	region, err := guidance_region(block)
	if err != "" || !region.found || region.start != 0 || region.end != len(block) {
		fail("policy text cannot be rendered as managed Markdown: %s", err)
	}
	return block
}
