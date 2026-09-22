package odx

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:slice"
import "core:strings"

Policy_Rule :: struct {
	id, statement, why, fix_hint: string,
	severity:                     Severity,
	check:                        json.Value,
	scope, evidence, boundary:    string,
	ignorable, baselineable:      bool,
}

Policy_Advice :: struct {
	topic:  string,
	roles:  []string,
	advice: string,
}

Policy_Context :: struct {
	schema:   int,
	catalog:  bool,
	packages: []Guidance_Package,
	rules:    []Policy_Rule,
	advice:   []Policy_Advice,
}

policy_context :: proc(
	p: ^Project,
	rels: []string,
	topics: []Topic,
	checklist := false,
	rule := "",
) -> Policy_Context {
	packages := make([]Guidance_Package, len(rels), context.temp_allocator)
	for rel, i in rels {
		role, _ := role_of(&p.cfg, rel)
		packages[i] = {rel, role}
	}
	rules := make([dynamic]Policy_Rule, context.temp_allocator)
	advice := make([dynamic]Policy_Advice, context.temp_allocator)
	for t in topics {
		if !checklist {
			for &r in t.rules {
				if r.retired || (rule != "" && r.id != rule) {continue}
				id := fmt.tprintf("%s/%s", t.name, r.id)
				if id in p.cfg.disabled {continue}
				check, err := json.parse_string(
					guidance_check_json(r.check),
					allocator = context.temp_allocator,
					parse_integers = true,
				)
				assert(err == nil)
				evidence, boundary := rule_evidence(r.check)
				append(
					&rules,
					Policy_Rule {
						id = id,
						statement = r.statement,
						why = r.why,
						fix_hint = rule_fix_hint(&r),
						severity = r.severity,
						check = check,
						scope = check_scope(&p.cfg, &r.check),
						evidence = evidence,
						boundary = boundary,
						ignorable = r.ignorable,
						baselineable = r.baselineable,
					},
				)
			}
		}
		if rule == "" {
			if rc := reader_checks(t);
			   rc !=
			   "" {append(&advice, Policy_Advice{t.name, t.applies_to.roles, strip_fences(rc)})}
		}
	}
	return {2, len(p.dirs) == 0, packages, rules[:], advice[:]}
}

policy_markdown :: proc(policy: Policy_Context) -> string {
	b := strings.builder_make(context.temp_allocator)
	if policy.catalog {strings.write_string(&b, "\nConditional rule catalog: no package applicability established.\n")}
	for r in policy.rules {
		fmt.sbprintfln(
			&b,
			"\n- **%s** [%v] %s\n  Scope: %s\n  Why: %s\n  Correction: %s\n  Evidence: %s; %s\n  Effective selector: `%s`",
			r.id,
			r.severity,
			r.statement,
			r.scope,
			r.why,
			r.fix_hint,
			r.evidence,
			r.boundary,
			guidance_json(r.check),
		)
	}
	for a in policy.advice {
		fmt.sbprintfln(&b, "\n### %s: reviewer advice (not mechanically enforced)", a.topic)
		if len(a.roles) > 0 {fmt.sbprintfln(&b, "Roles: %s", scope_roles(a.roles))}
		fmt.sbprintfln(&b, "\n%s", a.advice)
	}
	return strings.to_string(b)
}

cmd_policy :: proc(o: Opts) {
	if len(o.args) >
	   1 {fail("usage: odx policy [path] [--topic topic] [--rule Rn] [--checklist] [--json] [--write FILE | --verify FILE]")}
	if o.rule != "" &&
	   (len(o.topics) != 1 ||
			   o.checklist) {fail("--rule requires exactly one --topic and cannot be combined with --checklist")}
	if o.write != "" && o.verify != "" {fail("--write and --verify cannot be combined")}
	managed := o.write != "" || o.verify != ""
	if managed &&
	   (len(o.topics) > 0 ||
			   o.rule != "" ||
			   o.checklist) {fail("--write and --verify require the full policy; omit --topic, --rule and --checklist")}
	p := must_load(o, managed || len(o.args) > 0)
	rels := p.dirs
	if len(o.args) == 1 {
		selection_errors: [dynamic]string
		rels = select_packages(p.root, p.dirs, o.args[:], &selection_errors)
		if len(selection_errors) >
		   0 {fail("%s", strings.join(selection_errors[:], "; ", context.temp_allocator))}
		if len(rels) !=
		   1 {fail("policy scope requires exactly one included package (selected %d)", len(rels))}
	}
	if managed {
		path := o.write if o.write != "" else o.verify
		if !filepath.is_abs(path) {path = join({p.root, path})}
		status, message := guidance_sync(
			path,
			guidance_block(&p, rels, len(o.args) == 1),
			o.write != "",
		)
		if status == EXIT_TOOL {fail("%s", message)}
		if o.json {
			print_json(struct {
				schema:        int,
				status:        string,
				path, message: string,
			}{2, "current" if status == 0 else "stale", path, message})
		} else {fmt.println(message)}
		os.exit(status)
	}
	for name in o.topics {if find_topic(&p.rb, name) == nil {fail("unknown topic %q", name)}}
	topics := make([dynamic]Topic, context.temp_allocator)
	for t in applicable_topics(&p, rels, len(p.dirs) == 0) {
		if len(o.topics) == 0 || slice.contains(o.topics[:], t.name) {append(&topics, t)}
	}
	policy := policy_context(&p, rels, topics[:], o.checklist, o.rule)
	if o.rule != "" &&
	   len(policy.rules) == 0 {fail("no applicable active rule %s/%s", o.topics[0], o.rule)}
	if o.json {print_json(policy); return}
	for pkg in policy.packages {fmt.printfln("%s: role %s", pkg.path if pkg.path != "" else ".", pkg.role if pkg.role != "" else "(unmapped)")}
	fmt.print(policy_markdown(policy))
}
