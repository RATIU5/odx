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
		{{"check", "--max-findings", "2"}, Check_Command{max_findings = 2}},
		{{"check", "--max-findings", "1"}, Check_Command{max_findings = 1}},
		{{"check", "--max-findings", "1000000000"}, Check_Command{max_findings = 1_000_000_000}},
		{
			{"check", "--pending", "--max-findings", "3"},
			Check_Command{pending = true, max_findings = 3},
		},
		{
			{"check", "--max-findings", "3", "--pending"},
			Check_Command{pending = true, max_findings = 3},
		},
		{
			{"check", "--max-findings", "9223372036854775807"},
			Check_Command{max_findings = max(int)},
		},
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
		{
			{"check", "--max-findings"},
			"'--max-findings' for 'check' needs a number; run 'odx --help'",
		},
		{
			{"check", "--max-findings", "two"},
			"'--max-findings' for 'check' needs a positive number, not 'two'; run 'odx --help'",
		},
		{
			{"check", "--max-findings", "0"},
			"'--max-findings' for 'check' needs a positive number, not '0'; run 'odx --help'",
		},
		{
			{"check", "--max-findings", "-3"},
			"'--max-findings' for 'check' needs a positive number, not '-3'; run 'odx --help'",
		},
		{
			{"check", "--max-findings", "+3"},
			"'--max-findings' for 'check' needs a positive number, not '+3'; run 'odx --help'",
		},
		{
			{"check", "--max-findings", "9223372036854775808"},
			"'--max-findings' for 'check' needs a positive number, not " +
			"'9223372036854775808'; run 'odx --help'",
		},
		{
			{"check", "--max-findings", "1_000"},
			"'--max-findings' for 'check' needs a positive number, not '1_000'; run 'odx --help'",
		},
		{
			{"check", "--max-findings", "99999999999999999999"},
			"'--max-findings' for 'check' needs a positive number, not '99999999999999999999'; " +
			"run 'odx --help'",
		},
		{
			{"check", "--max-findings", "2", "--json"},
			"'--max-findings' can't be combined with '--json'; run 'odx --help'",
		},
		{
			{"check", "--json", "--max-findings", "2"},
			"'--max-findings' can't be combined with '--json'; run 'odx --help'",
		},
		{
			{"check", "--max-findings", "2", "--max-findings", "3"},
			"'--max-findings' given twice for 'check'; run 'odx --help'",
		},
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
