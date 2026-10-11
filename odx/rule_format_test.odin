package odx

import "base:runtime"
import "core:encoding/json"
import "core:mem/virtual"
import "core:reflect"
import "core:slice"
import "core:strings"
import "core:testing"

import printer "ols_printer"

// The fake printer's script. Each test runs on one thread, so each sees its own copy.
@(thread_local)
fake_outs: []string
@(thread_local)
fake_ok: bool
@(thread_local)
fake_calls: int

@(private = "file")
fake_print :: proc(src: string) -> (out: string, ok: bool) {
	out = fake_outs[fake_calls % len(fake_outs)]
	fake_calls += 1
	return out, fake_ok
}

@(test)
print_result_prints_once_and_names_the_first_differing_line :: proc(t: ^testing.T) {
	SRC :: "package a\n\nA :: 1\nB :: 2\n"
	cases := []struct {
		name: string,
		src:  string,
		outs: []string,
		ok:   bool,
		want: Print_Result,
	} {
		{"the print equals the file", SRC, {SRC}, true, Formatted{}},
		{"the print changes line 3", SRC, {"package a\n\nA  :: 1\nB :: 2\n"}, true, Differs{3}},
		{
			"a second print would give the file back",
			SRC,
			{"package a\n\nA :: 1\nB  :: 2\n", SRC},
			true,
			Differs{4},
		},
		{"the printer refuses", SRC, {""}, false, Refused{}},
		{
			"CRLF line ends differ at line 1",
			"package a\r\n\r\nA :: 1\r\n",
			{"package a\n\nA :: 1\n"},
			true,
			Differs{1},
		},
		{
			"a missing final newline",
			"package a\n\nA :: 1",
			{"package a\n\nA :: 1\n"},
			true,
			Differs{3},
		},
		{
			"a second blank line",
			"package a\n\n\nA :: 1\n",
			{"package a\n\nA :: 1\n"},
			true,
			Differs{3},
		},
		{"blank lines at the end", "package a\n\n", {"package a\n"}, true, Differs{2}},
	}
	for c in cases {
		fake_outs, fake_ok, fake_calls = c.outs, c.ok, 0
		got := print_result(c.src, fake_print)
		testing.expectf(t, got == c.want, "%s: got %v, want %v", c.name, got, c.want)
		testing.expectf(t, fake_calls == 1, "%s: printed %d times, want 1", c.name, fake_calls)
	}
}

@(test)
print_source_aligns_and_refuses_what_the_parser_rejects :: proc(t: ^testing.T) {
	arena: virtual.Arena
	ensure(virtual.arena_init_growing(&arena) == nil, "out of memory")
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	out, ok := print_source("package a\n\nItem :: struct {\n\ta: int,\n\tlong_name: int,\n}\n")
	testing.expect(t, ok)
	testing.expect_value(
		t,
		out,
		"package a\n\nItem :: struct {\n\ta:         int,\n\tlong_name: int,\n}\n",
	)

	_, ok = print_source("package a\n\nf :: proc() {\n")
	testing.expect(t, !ok, "a syntax error must refuse the print")
	_, ok = print_source("package a\n\nA :: \"unterminated\n")
	testing.expect(t, !ok, "a tokenizer error must refuse the print")
}

@(test)
print_result_line_round_trips :: proc(t: ^testing.T) {
	results := []Print_Result {
		Formatted{},
		Differs{1},
		Differs{1234},
		Refused{},
		Unreadable{"file does not exist"},
	}
	for result in results {
		b := strings.builder_make()
		defer strings.builder_destroy(&b)
		write_print_result(&b, result)
		got := read_print_result(strings.to_string(b))
		testing.expectf(t, got == result, "%v: read back %v", result, got)
	}
}

@(test)
read_print_result_wants_one_whole_line :: proc(t: ^testing.T) {
	cases := []struct {
		name: string,
		text: string,
	} {
		{"a child that died before it wrote", ""},
		{"a line cut inside the word", "differ"},
		{"a line cut inside the number, where 12 was 123", "differs 12"},
		{"a whole word without its line end", "formatted"},
		{"a line number that isn't one", "differs x\n"},
		{"no line 0", "differs 0\n"},
		{"a negative line", "differs -3\n"},
		{"a missing line number", "differs \n"},
		{"an unknown word", "printed\n"},
		{"two lines", "formatted\nformatted\n"},
		{"a blank line", "\n"},
		{"text after the word", "refused app.odin\n"},
		{"CRLF", "formatted\r\n"},
		{"an unreadable file without its reason", "unreadable \n"},
	}
	for c in cases {
		got := read_print_result(c.text)
		testing.expectf(t, got == nil, "%s: got %v", c.name, got)
	}
}

@(test)
read_format_end_takes_a_whole_result_line_however_the_child_ended :: proc(t: ^testing.T) {
	cases := []struct {
		name: string,
		end:  Child_End,
		want: Format_Outcome,
		stop: bool,
	} {
		{
			"a child that never started",
			{error = "couldn't start: Permission denied"},
			Run_Failed{"couldn't start: Permission denied"},
			true,
		},
		{
			"a child odx couldn't wait for",
			{error = "couldn't be waited for: No child processes"},
			Run_Failed{"couldn't be waited for: No child processes"},
			true,
		},
		{"a child that SIGKILL ended", {status = Signaled{9}}, Crashed{}, false},
		{
			"a child that wrote half a line",
			{captured = #partial [Stream]string{.Stdout = "differs 1"}},
			Crashed{},
			false,
		},
		{"a child that wrote nothing and exited 0", {}, Crashed{}, false},
		{
			"a child that outran the timeout",
			{timed_out = true, status = Signaled{9}},
			Timed_Out{},
			true,
		},
		{"a child that its own limit ended", {status = Signaled{14}}, Timed_Out{}, true},
		{"a child that exited 14", {status = Exited{14}}, Crashed{}, false},
		{
			"a child whose stream odx couldn't read",
			{error = "started, but odx couldn't read its output: Input/output error"},
			Run_Failed{"started, but odx couldn't read its output: Input/output error"},
			true,
		},
		{
			"a whole result line",
			{captured = #partial [Stream]string{.Stdout = "differs 3\n"}},
			Differs{3},
			false,
		},
		{
			"a whole result line, then a failing exit",
			{status = Exited{2}, captured = #partial [Stream]string{.Stdout = "differs 3\n"}},
			Differs{3},
			false,
		},
		{
			"a whole result line, then a signal",
			{status = Signaled{11}, captured = #partial [Stream]string{.Stdout = "formatted\n"}},
			Formatted{},
			false,
		},
		{
			"a whole result line from a child killed at the timeout",
			{
				timed_out = true,
				status = Signaled{9},
				captured = #partial [Stream]string{.Stdout = "refused\n"},
			},
			Refused{},
			false,
		},
		{
			"a file the child couldn't read",
			{captured = #partial [Stream]string{.Stdout = "unreadable file does not exist\n"}},
			Unreadable{"file does not exist"},
			true,
		},
	}
	for c in cases {
		got, stop := read_format_end(c.end, context.temp_allocator)
		testing.expectf(t, got == c.want, "%s: got %v, want %v", c.name, got, c.want)
		testing.expectf(t, stop == c.stop, "%s: stop is %v", c.name, stop)
	}
}

@(test)
finish_format_reports_the_first_error_in_path_order :: proc(t: ^testing.T) {
	arena: virtual.Arena
	ensure(virtual.arena_init_growing(&arena) == nil, "out of memory")
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	packages := []Package{{dir = "app"}}
	by_path := []Format_Job {
		{path = "app/a.odin", pool_index = 3},
		{path = "app/b.odin", pool_index = 2},
		{path = "app/c.odin", pool_index = 1},
		{path = "app/d.odin", pool_index = 0},
	}
	cases := []struct {
		name:  string,
		error: string,
		// In pool order, which is `by_path` reversed.
		runs:  []Format_Outcome,
		want:  Error,
	} {
		{
			"a file the child couldn't read",
			"",
			{Formatted{}, Unreadable{"file does not exist"}, Crashed{}, Differs{2}},
			{
				.Format_Failed,
				"odx can't read 'app/c.odin' to check its format: file does not exist",
			},
		},
		{
			"two timeouts and a file that never started",
			"",
			{Timed_Out{}, Timed_Out{}, nil, Formatted{}},
			{.Format_Timeout, "formatting 'app/c.odin' timed out after 120 s"},
		},
		{
			"a child that never started, before a timeout",
			"",
			{
				Timed_Out{},
				Formatted{},
				Run_Failed{"couldn't start: Permission denied"},
				Formatted{},
			},
			{
				.Format_Failed,
				"odx can't run the formatter process for 'app/b.odin': " +
				"couldn't start: Permission denied",
			},
		},
		{
			"no executable path",
			"odx can't find its own executable to run the formatter: file does not exist",
			{nil, nil, nil, nil},
			{
				.Format_Failed,
				"odx can't find its own executable to run the formatter: file does not exist",
			},
		},
	}
	for c in cases {
		jobs := Format_Jobs {
			by_path = by_path,
			error   = c.error,
		}
		jobs.pool.runs = c.runs
		jobs.pool.timeout = FORMAT_TIMEOUT
		result: Result
		finish_format(&jobs, packages, &result, context.allocator)
		testing.expectf(t, len(result.errors) == 1, "%s: %d errors", c.name, len(result.errors))
		if len(result.errors) == 1 {
			testing.expectf(t, result.errors[0] == c.want, "%s: got %v", c.name, result.errors[0])
		}
	}
}

// The keys on which `text`, an odinfmt.json, and `config` disagree: a key with another value, a
// field the file lacks, then a key the config lacks. Allocates with `allocator`.
config_disagreements :: proc(
	text: string,
	config: printer.Config,
	allocator: runtime.Allocator,
) -> [dynamic]string {
	keys := make([dynamic]string, allocator)
	value, err := json.parse_string(text, parse_integers = true, allocator = allocator)
	object, is_object := value.(json.Object)
	if err != nil || !is_object {
		append(&keys, "<not a JSON object>")
		return keys
	}
	config := config
	names := reflect.struct_field_names(printer.Config)
	for name in names {
		field := reflect.struct_field_value_by_name(config, name)
		same := false
		switch written in object[name] {
		case json.Integer:
			n, is_int := field.(int)
			same = is_int && i64(n) == written
		case json.Boolean:
			b, is_bool := field.(bool)
			same = is_bool && b == written
		case json.String:
			member, is_enum := reflect.enum_name_from_value_any(field)
			same = is_enum && member == written
		case json.Null, json.Float, json.Array, json.Object:
		}
		if !same {
			append(&keys, name)
		}
	}
	for key in object {
		if !slice.contains(names, key) {
			append(&keys, key)
		}
	}
	return keys
}

@(test)
odinfmt_json_agrees_with_the_format_config_on_every_key :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	keys := config_disagreements(ODINFMT_JSON, FORMAT_CONFIG, context.temp_allocator)
	testing.expectf(t, len(keys) == 0, "odinfmt.json and FORMAT_CONFIG disagree on %v", keys)
}

@(test)
config_disagreements_names_each_key_that_differs_or_is_missing :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	ta := context.temp_allocator
	cases := []struct {
		old, new: string,
		key:      string,
	} {
		{`"character_width": 100`, `"character_width": 80`, "character_width"},
		{`"tabs": true`, `"tabs": false`, "tabs"},
		{`"brace_style": "_1TBS"`, `"brace_style": "Allman"`, "brace_style"},
		{`"newline_style": "LF"`, `"newline_style": 1`, "newline_style"},
		{`"sort_imports": true,`, ``, "sort_imports"},
		{`"spaces": 4,`, `"spaces": 4, "line_width": 100,`, "line_width"},
	}
	for c in cases {
		testing.expectf(t, strings.contains(ODINFMT_JSON, c.old), "no %q in odinfmt.json", c.old)
		copy, _ := strings.replace(ODINFMT_JSON, c.old, c.new, 1, ta)
		keys := config_disagreements(copy, FORMAT_CONFIG, ta)
		testing.expectf(
			t,
			len(keys) == 1 && keys[0] == c.key,
			"%q became %q: got %v, want [%s]",
			c.old,
			c.new,
			keys,
			c.key,
		)
	}
	changed := FORMAT_CONFIG
	changed.align_comments = true
	keys := config_disagreements(ODINFMT_JSON, changed, ta)
	testing.expectf(
		t,
		len(keys) == 1 && keys[0] == "align_comments",
		"a changed config: got %v, want [align_comments]",
		keys,
	)
}
