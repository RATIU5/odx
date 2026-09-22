package odx

import "core:os"
import "core:strings"
import "core:testing"

@(private = "file")
config_errors :: proc(t: ^testing.T, text: string) -> string {
	tmp, terr := os.make_directory_temp("", "odx-cfg-*", context.allocator)
	testing.expect(t, terr == nil)
	defer os.remove_all(tmp)
	testing.expect(t, os.write_entire_file(join({tmp, CONFIG_FILE}), transmute([]byte)text) == nil)
	errs: [dynamic]string
	_ = load_config(tmp, &errs)
	return strings.join(errs[:], "\n")
}

@(test)
test_config_validation :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	defer free_all(context.temp_allocator)
	// the default config loads clean
	testing.expect_value(t, config_errors(t, INIT_CONFIG_HEAD + INIT_CONFIG_BODY), "")
	testing.expect(t, strings.contains(config_errors(t, `{version:1,odin:{flags:["-no-bounds-check"],forbidden_flags:["-no-bounds-check"]}}`), "forbidden flag"))
	testing.expect(t, strings.contains(config_errors(t, `{version:1,odin:{flags:["-define:X=true"],forbidden_flags:["-define"]}}`), "forbidden flag"))
	testing.expect_value(t, config_errors(t, `{version:1,odin:{flags:["-define:Y=true"],forbidden_flags:["-define:X=true"]}}`), "")
	for field in ([]string{"required_flags:[]", "declined:{}", "tagged_files_min:0", `version:"dev-2026-09"`}) {
		testing.expect(t, config_errors(t, strings.concatenate({"{version:1,odin:{", field, "}}"})) != "", "removed task-audit fields must not be silently ignored")
	}
	// unknown key, top level and under odin
	e := config_errors(t, `{ version: 1, rolez: {}, odin: { flagz: [] } }`)
	testing.expect(t, strings.contains(e, "rolez"), e)
	testing.expect(t, strings.contains(e, "flagz"), e)
	// misspelt enum is an error, never silently the zero value
	e = config_errors(t, `{ version: 1, odin: { explicit_allocators: "pur" } }`)
	testing.expect(t, strings.contains(e, "explicit_allocators"), e)
	// dependencies naming a role that is not declared, and may_import naming neither a role nor a glob
	e = config_errors(
		t,
		`{ version: 1, roles: { pure: [] }, dependencies: { edge: { may_import: ["nope"] } } }`,
	)
	testing.expect(t, strings.contains(e, "dependencies.edge is not a declared role"), e)
	testing.expect(t, strings.contains(e, `"nope" is neither a role nor a collection glob`), e)
	// wrong version, bad default_role, short disabled reason
	e = config_errors(t, `{ version: 2, default_role: "x", disabled: { "errors/R3": "short" } }`)
	testing.expect(t, strings.contains(e, "version must be 1"), e)
	testing.expect(t, strings.contains(e, "default_role x"), e)
	testing.expect(t, strings.contains(e, "10+ characters"), e)
	// missing pure deny falls back to the default set
	tmp, _ := os.make_directory_temp("", "odx-cfg-*", context.allocator)
	defer os.remove_all(tmp)
	_ = os.write_entire_file(
		join({tmp, CONFIG_FILE}),
		transmute([]byte)string(
			`{ version: 1, roles: { pure: [] }, dependencies: { pure: { may_import: ["core:*"] } } }`,
		),
	)
	errs: [dynamic]string
	cfg := load_config(tmp, &errs)
	testing.expect_value(t, len(errs), 0)
	testing.expect(t, len(cfg.dependencies["pure"].deny) > 0)
}

@(test)
test_error_classification_config :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	defer free_all(context.temp_allocator)
	for source in ([]string{`{version:1,errors:{structural:"false"}}`, `{version:1,errors:{structural:0}}`, `{version:1,errors:{structural:null}}`, `{version:1,errors:{types:[""]}}`, `{version:1,errors:{types:["  "]}}`}) {
		testing.expect(t, config_errors(t, source) != "", source)
	}
	tmp, err := os.make_directory_temp("", "odx-error-cfg-*", context.allocator)
	testing.expect(t, err == nil)
	defer os.remove_all(tmp)
	for source, i in ([]string{`{version:1}`, `{version:1,errors:{types:[]}}`, `{version:1,errors:{types:[],structural:false}}`, `{version:1,errors:{types:["Failure"],structural:true}}`}) {
		testing.expect(t, os.write_entire_file(join({tmp, CONFIG_FILE}), source) == nil)
		errs: [dynamic]string
		cfg := load_config(tmp, &errs)
		testing.expect_value(t, len(errs), 0)
		testing.expect_value(t, cfg.errors.structural, i != 2)
		testing.expect_value(t, len(cfg.errors.types), 1 if i == 0 || i == 3 else 0)
	}
}

@(test)
test_file_tag_audit_config :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	defer free_all(context.temp_allocator)
	for value in ([]string{"null", "0", `"false"`}) {
		text := strings.concatenate({`{version:1,odin:{audit_file_tags:`, value, "}}"})
		testing.expect(t, config_errors(t, text) != "", text)
	}
	root, err := os.make_directory_temp("", "odx-tag-cfg-*", context.allocator)
	testing.expect(t, err == nil)
	defer os.remove_all(root)
	for text, i in ([]string{`{version:1}`, `{version:1,odin:{audit_file_tags:true}}`, `{version:1,odin:{audit_file_tags:false}}`}) {
		testing.expect(t, os.write_entire_file(join({root, CONFIG_FILE}), text) == nil)
		errs: [dynamic]string
		cfg := load_config(root, &errs)
		testing.expect_value(t, len(errs), 0)
		testing.expect_value(t, cfg.odin.audit_file_tags, i != 2)
	}
	defaults := default_config()
	testing.expect(t, defaults.odin.audit_file_tags)
	testing.expect(t, defaults.errors.structural)
}
