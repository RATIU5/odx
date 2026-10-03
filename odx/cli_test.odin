package odx

import "core:testing"

@(test)
parse_args_accepts_the_four_commands :: proc(t: ^testing.T) {
	cases := []struct {
		args: []string,
		want: Parsed_Args,
	} {
		{{"check"}, Check_Command{}},
		{{"check", "--json"}, Check_Command{json = true}},
		{{"check", "--pending"}, Check_Command{pending = true}},
		{{"check", "--pending", "--json"}, Check_Command{json = true, pending = true}},
		{{"init"}, Init_Command{}},
	}
	for c in cases {
		got := parse_args(c.args, context.allocator)
		testing.expectf(t, got == c.want, "%v: got %v, want %v", c.args, got, c.want)
	}
}

@(test)
parse_args_reports_usage :: proc(t: ^testing.T) {
	cases := []struct {
		args:    []string,
		message: string,
	} {
		{{}, "no command; run 'odx check' or 'odx init'"},
		{{"frob"}, "unknown command 'frob'"},
		{{"--json"}, "unknown command '--json'"},
		{{"check", "--nope"}, "unknown flag '--nope' for 'check'"},
		{{"check", "src"}, "unexpected argument 'src' for 'check'"},
		{{"init", "--json"}, "unknown flag '--json' for 'init'"},
	}
	for c in cases {
		got := parse_args(c.args, context.allocator)
		err, is_err := got.(Error)
		testing.expectf(
			t,
			is_err && err.code == .Usage,
			"%v: got %v, want a usage error",
			c.args,
			got,
		)
		testing.expect_value(t, err.message, c.message)
		delete(err.message)
	}
}
