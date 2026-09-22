package odx

import "core:testing"

@(test)
test_classify_odin_message :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	defer free_all(context.temp_allocator)
	errs: [dynamic]string
	rb := load_rulebook("", &errs)
	testing.expect_value(t, len(errs), 0)
	c := Ctx {
		rb = &rb,
	}
	rule, msg := classify_odin_message(&c, "error", "x.odin(3:2) Error: 'old' is deprecated: errors/R3: add the attribute\n\tnote")
	testing.expect_value(t, rule, "errors/R3")
	testing.expect_value(t, msg, "add the attribute note")
	// an unknown rule id stays a compiler error; a warning stays a warning
	rule, _ = classify_odin_message(&c, "error", "'old' is deprecated: errors/R9: gone")
	testing.expect_value(t, rule, "odin/error")
	rule, _ = classify_odin_message(&c, "warning", "'old' is deprecated: use new")
	testing.expect_value(t, rule, "odin/warning")
}
