package odx

import "core:encoding/json"
import "core:fmt"
import "core:strings"

print_json :: proc(v: any) {
	out, err := json.marshal(v, {pretty = false, sort_maps_by_key = true, use_enum_names = true})
	if err != nil {fail("json: %v", err)}
	fmt.println(string(out))
}

READER_CHECKS_HEADING :: "\n## Reader checks\n"

// reader_checks: the part of topic.md a reviewer enforces by hand; "" when the topic has none.
reader_checks :: proc(t: Topic) -> string {
	_, found, rest := strings.partition(t.prose, READER_CHECKS_HEADING)
	return strings.trim_space(rest) if found != "" else ""
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

// Parsed defaults for projects that omit optional configuration.
INIT_CONFIG_HEAD :: `{
  // Package roles: each glob is a directory path relative to this file (17.5).
  // Roles are optional; a package may match at most one role.
`
INIT_CONFIG_BODY :: `  version: 1,
  roles: {
    pure: [],    // project role with import, allocator-tag, and mutable-declaration policies
    service: [], // project role with import, allocator-tag, and mutable-declaration policies
    edge: [],    // project role with import policies
  },
  dependencies: {
    pure: { may_import: ["pure", "core:*"] },
    service: { may_import: ["pure", "service", "core:*"] },
    edge: { may_import: ["pure", "service", "edge", "core:*", "vendor:*"] },
  },
  exclude: [".odx/**", "rules/**", "vendor/**", "build/**"],
  // disabled: { "errors/R3": "reason of at least ten characters" },
  odin: {
    audit_file_tags: true, // require feature reasons and audit vet-disable allow-list
    flags: ["-vet", "-vet-tabs", "-vet-cast", "-strict-style", "-warnings-as-errors"],
    forbidden_flags: ["-no-bounds-check", "-disable-assert", "-no-type-assert", "-ignore-unknown-attributes"],
  },
  // Canonical named-result suffixes; structural inference also selects None/Ok enums
  // and nil-able named unions. Set structural:false for suffix-only classification.
  errors: { types: ["Error"], structural: true },
}
`

default_config :: proc() -> (cfg: Config) {
	err := json.unmarshal_string(INIT_CONFIG_HEAD + INIT_CONFIG_BODY, &cfg, spec = .JSON5)
	assert(err == nil, "INIT_CONFIG must parse")
	return
}

policy_topics_markdown :: proc(p: ^Project, topics: []Topic) -> string {
	return policy_markdown(policy_context(p, nil, topics))
}

indent :: proc(block: string) -> string {
	out := make([dynamic]string, context.temp_allocator)
	for l in strings.split_lines(block, context.temp_allocator) {append(&out, strings.concatenate({"    ", l}, context.temp_allocator))}
	return strings.join(out[:], "\n", context.temp_allocator)
}
