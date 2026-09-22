package odx

import "core:strings"
import "core:testing"

@(test)
test_rendered_selectors_are_valid_policy_with_preserved_semantics :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	defer free_all(context.temp_allocator)
	sources := []string {
		`{kind:"path_role",roles:[""],except_roles:["edge"]}`,
		`{kind:"vet_tag"}`,
		`{kind:"banned_import"}`,
		`{kind:"banned_import",from:"dependencies.may_import"}`,
		`{kind:"require_attribute",attribute:"require_results"}`,
		`{kind:"require_attribute",attribute:"require_results",on:"exported_procs"}`,
		`{kind:"pattern",match:"call",name:"os.exit",names:["panic","os.exit"]}`,
		`{kind:"pattern",match:"import",name:"core:sys/*"}`,
		`{kind:"pattern",match:"proc",exported:false}`,
		`{kind:"pattern",match:"proc",exported:true,requires_param:{index:2,type_suffix:"Ctx"}}`,
		`{kind:"pattern",match:"proc",requires_param:{index:9007199254740993,type_suffix:"Ctx"}}`,
		`{kind:"pattern",match:"proc",requires_param:{type_suffix:"Ctx"}}`,
		`{kind:"pattern",match:"decl",at:"package_scope",mutable:false}`,
		`{kind:"pattern",match:"decl",at:"package_scope",mutable:true}`,
		`{kind:"pattern",match:"foreign",roles:["domain"],except_roles:["edge"]}`,
	}
	for source in sources {
		original: Check_Spec
		errs: [dynamic]string
		obj, ok := unmarshal_json5(source, &original, "original", CHECK_KEYS, &errs)
		if ok {validate_check(&original, obj, "original", &errs)}
		if !testing.expect(t, ok && len(errs) == 0, source) {continue}
		p := Project{}
		topics := []Topic{{name = "custom", rules = {{id = "R1", check = original}}}}
		markdown := claude_md(&p, topics)
		_, marker, rest := strings.partition(markdown, "Effective selector: `")
		if !testing.expect(t, marker != "", markdown) {continue}
		rendered, _, _ := strings.partition(rest, "`\n")
		decoded: Check_Spec
		obj, ok = unmarshal_json5(rendered, &decoded, "rendered", CHECK_KEYS, &errs)
		if ok {validate_check(&decoded, obj, "rendered", &errs)}
		testing.expect(t, ok && len(errs) == 0, strings.join(errs[:], "; "))
		testing.expect_value(t, guidance_json(decoded), guidance_json(original))
	}
}

@(test)
test_selector_contract_rejects_ignored_and_invalid_fields :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	defer free_all(context.temp_allocator)
	invalid := []string {
		`{kind:"path_role",name:"ignored"}`,
		`{kind:"vet_tag",mutable:false}`,
		`{kind:"banned_import",from:"unrelated"}`,
		`{kind:"require_attribute",attribute:"require_results",on:""}`,
		`{kind:"require_attribute",attribute:null}`,
		`{kind:"pattern",match:"proc",name:"target"}`,
		`{kind:"pattern",match:"proc",mutable:false}`,
		`{kind:"pattern",match:"proc",exported:null}`,
		`{kind:"pattern",match:"proc",requires_param:{index:-1,type_suffix:"Ctx"}}`,
		`{kind:"pattern",match:"proc",requires_param:{index:null,type_suffix:"Ctx"}}`,
		`{kind:"pattern",match:"proc",requires_param:{index:0.5,type_suffix:"Ctx"}}`,
		`{kind:"pattern",match:"proc",requires_param:{index:1e30,type_suffix:"Ctx"}}`,
		`{kind:"pattern",match:"proc",requires_param:{index:0x10000000000000000,type_suffix:"Ctx"}}`,
		`{kind:"pattern",match:"proc",requires_param:{index:0,type_suffix:"Ctx",typo:true}}`,
		`{kind:"pattern",match:"proc",requires_param:null}`,
		`{kind:"pattern",match:"proc",requires_param:{type_suffix:" "}}`,
		`{kind:"pattern",match:"call",names:[""]}`,
		`{kind:"pattern",match:"call",names:[null]}`,
		`{kind:"pattern",match:"import",name:"core:os",names:[]}`,
		`{kind:"pattern",match:"decl",at:"package_scope",name:"x"}`,
		`{kind:"pattern",match:"foreign",exported:false}`,
		`{kind:"pattern",match:"foreign",roles:null}`,
		`{kind:"pattern",match:"foreign",roles:[" "]}`,
	}
	for source in invalid {
		c: Check_Spec
		errs: [dynamic]string
		if obj, ok := unmarshal_json5(source, &c, "trial", CHECK_KEYS, &errs);
		   ok {validate_check(&c, obj, "trial", &errs)}
		testing.expect(t, len(errs) > 0, source)
	}
}

@(test)
test_selector_contract_preserves_defaults_and_public_matchers :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	defer free_all(context.temp_allocator)
	valid := []string {
		`{kind:"path_role"}`,
		`{kind:"vet_tag"}`,
		`{kind:"banned_import",from:"dependencies.may_import"}`,
		`{kind:"require_attribute",attribute:"require_results",on:"exported_procs"}`,
		`{kind:"pattern",match:"call",name:"os.exit",names:["os.exit","panic"]}`,
		`{kind:"pattern",match:"import",name:"core:sys/*"}`,
		`{kind:"pattern",match:"proc",exported:false,requires_param:{type_suffix:"Ctx"}}`,
		`{kind:"pattern",match:"proc",requires_param:{index:999,type_suffix:"Ctx"}}`,
		`{kind:"pattern",match:"decl",at:"package_scope",mutable:false}`,
		`{kind:"pattern",match:"foreign",roles:[],except_roles:[]}`,
		`{kind:"pattern",match:"foreign",roles:[""],except_roles:[""]}`,
	}
	for source in valid {
		c: Check_Spec
		errs: [dynamic]string
		obj, ok := unmarshal_json5(source, &c, "trial", CHECK_KEYS, &errs)
		if ok {validate_check(&c, obj, "trial", &errs)}
		testing.expect(
			t,
			ok && len(errs) == 0,
			strings.concatenate({source, " ", strings.join(errs[:], "; ")}),
		)
		if c.match == "call" {testing.expect_value(t, len(c.names), 2)}
		if c.match == "proc" &&
		   c.exported == false &&
		   !strings.contains(source, "999") {testing.expect_value(t, c.requires_param.index, 0)}
		if c.match == "foreign" &&
		   len(c.except_roles) > 0 {testing.expect(t, !role_applies(&c, ""))}
	}
}
