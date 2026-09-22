package odx

import "core:strings"
import "core:testing"

@(test)
test_optional_rule_repair_validation :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	defer free_all(context.temp_allocator)
	for field, i in ([]string{"", `fix_hint:"Pass state explicitly.",`, `fix_hint:"   ",`, `fix_hint:42,`, `fix_hint:null,`}) {
		src := strings.concatenate(
			{
				`{id:"R1",statement:"No globals.",why:"Explicit state.",instead_of:"Globals.",evidence:"Probe",cost:"Parameters",severity:"warning",`,
				field,
				`check:{kind:"pattern",match:"decl",at:"package_scope",mutable:true}}`,
			},
		)
		r: Rule
		errs: [dynamic]string
		obj, ok := unmarshal_json5(src, &r, "probe", RULE_KEYS, &errs)
		if ok {validate_rule(&r, obj, "probe", &errs)}
		testing.expect_value(t, len(errs) == 0, i < 2)
		if i == 0 {testing.expect_value(t, rule_fix_hint(&r), "No globals.")}
		if i == 1 {testing.expect_value(t, rule_fix_hint(&r), "Pass state explicitly.")}
	}
}
