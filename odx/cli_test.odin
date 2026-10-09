package odx

import "core:testing"

@(test)
parse_args_accepts_each_command :: proc(t: ^testing.T) {
	cases := []struct {
		args: []string,
		want: Parsed_Args,
	} {
		{{"check"}, Check_Command{}},
		{{"check", "--json"}, Check_Command{json = true}},
		{{"check", "--pending"}, Check_Command{pending = true}},
		{{"check", "--pending", "--json"}, Check_Command{json = true, pending = true}},
		{{"init"}, Init_Command{}},
		{{"--help"}, Help_Command{}},
		{{"--version"}, Version_Command{}},
		{{"__format", "app/app.odin"}, Format_Child_Command{"app/app.odin"}},
		{{"__format", "--json"}, Format_Child_Command{"--json"}},
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
		{{}, "no command; run 'odx --help'"},
		{{"frob"}, "unknown command 'frob'; run 'odx --help'"},
		{{"--json"}, "unknown command '--json'; run 'odx --help'"},
		{{"check", "--nope"}, "unknown flag '--nope' for 'check'; run 'odx --help'"},
		{{"check", "src"}, "unexpected argument 'src' for 'check'; run 'odx --help'"},
		{{"init", "--json"}, "unknown flag '--json' for 'init'; run 'odx --help'"},
		{{"__format"}, "unknown command '__format'; run 'odx --help'"},
		{{"__format", "a.odin", "b.odin"}, "unknown command '__format'; run 'odx --help'"},
		{{"help"}, "unknown command 'help'; run 'odx --help'"},
		{{"-h"}, "unknown command '-h'; run 'odx --help'"},
		{{"version"}, "unknown command 'version'; run 'odx --help'"},
		{{"-V"}, "unknown command '-V'; run 'odx --help'"},
		{{"check", "--help"}, "unknown flag '--help' for 'check'; run 'odx --help'"},
		{{"init", "--version"}, "unknown flag '--version' for 'init'; run 'odx --help'"},
		{{"--help", "check"}, "unexpected argument 'check' for '--help'; run 'odx --help'"},
		{{"--version", "--json"}, "unknown flag '--json' for '--version'; run 'odx --help'"},
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
