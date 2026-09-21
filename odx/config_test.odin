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
	// unknown key, top level and under odin
	e := config_errors(t, `{ version: 1, rolez: {}, odin: { flagz: [] } }`)
	testing.expect(t, strings.contains(e, "rolez"), e)
	testing.expect(t, strings.contains(e, "flagz"), e)
	// misspelt enum is an error, never silently the zero value
	e = config_errors(t, `{ version: 1, odin: { explicit_allocators: "pur" } }`)
	testing.expect(t, strings.contains(e, "explicit_allocators"), e)
	// dependencies naming a role that is not declared, and may_import naming neither a role nor a glob
	e = config_errors(t, `{ version: 1, roles: { pure: [] }, dependencies: { edge: { may_import: ["nope"] } } }`)
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
	_ = os.write_entire_file(join({tmp, CONFIG_FILE}), transmute([]byte)string(`{ version: 1, roles: { pure: [] }, dependencies: { pure: { may_import: ["core:*"] } } }`))
	errs: [dynamic]string
	cfg := load_config(tmp, &errs)
	testing.expect_value(t, len(errs), 0)
	testing.expect(t, len(cfg.dependencies["pure"].deny) > 0)
}
