package odx

import "core:os"
import "core:slice"
import "core:strings"
import "core:testing"

// The scrapers are pure string functions; these pin the fallback, not just the happy path.

HELP_TABS :: "odin is a tool.\nUsage:\n\todin check [arguments]\n\n\tFlags\n\n\t-bedrock\n\t\tDisables things.\n\n\t-collection:<name>=<filepath>\n\t\tDefines a collection.\n\n\t-strict-style\n\t\tErrs on style.\n\n\t-vet\n\t\tDoes extra checks.\n\t\tExtra checks include:\n\t\t\t-vet-unused\n\t\t\t-vet-shadowing\n\n\t-vet-cast\n\t\tErrs on casts.\n\n\t-vet-packages:<comma-separated-strings>\n\t\tScopes vetting.\n\n\t-warnings-as-errors\n\t\tTreats warnings as errors.\n"

@(test)
test_parse_help_flags :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	defer free_all(context.temp_allocator)
	hf := parse_help_flags(HELP_TABS)
	testing.expect(t, hf.ok)
	testing.expect(t, "-vet" in hf.flags && "-collection" in hf.flags && "-vet-packages" in hf.flags)
	testing.expect(t, "-vet-unused" not_in hf.flags, "nested flags are implied, not top-level")
	testing.expect(t, slice.contains(hf.implied, "-vet-shadowing"))
	flags, implied := compiler_guarantees(hf)
	testing.expect_value(t, strings.join(flags, " "), "-strict-style -vet -vet-cast -warnings-as-errors")
	testing.expect_value(t, strings.join(implied, " "), "-vet-unused -vet-shadowing")

	// a whitespace reflow (tabs to spaces, different widths) must parse identically
	reflowed, _ := strings.replace_all(HELP_TABS, "\t", "    ")
	rf := parse_help_flags(reflowed)
	testing.expect(t, rf.ok)
	testing.expect_value(t, len(rf.flags), len(hf.flags))
	testing.expect_value(t, len(rf.implied), len(hf.implied))

	// truncated output yields too few flags: ok is false so callers warn and skip
	help := string(HELP_TABS)
	tr := parse_help_flags(help[:strings.index(help, "-strict-style")])
	testing.expect(t, !tr.ok)
	testing.expect_value(t, len(tr.flags), 2)
}

@(private = "file")
Scratch_File :: struct {
	name, text: string,
}

scratch_project :: proc(t: ^testing.T, files: []Scratch_File) -> (p: Project) {
	tmp, terr := os.make_directory_temp("", "odx-test-*", context.allocator)
	testing.expect(t, terr == nil)
	for f in files {
		path := join({tmp, f.name})
		os.make_directory_all(dir_of(path))
		testing.expect(t, os.write_entire_file(path, transmute([]byte)f.text) == nil)
	}
	p.root = tmp
	p.cfg = default_config()
	return
}

@(test)
test_check_task_files_reads_code_not_comments :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	defer free_all(context.temp_allocator)
	p := scratch_project(
		t,
		{
			// a `#` inside a string does not end the line; a `'''` block is scanned line by line;
			// a `//` comment in settings.json is not a hook
			{"mise.toml", "[tasks.test]\nrun = \"echo '#' && odin test . -sanitize:address -define:ODIN_TEST_FAIL_ON_BAD_MEMORY=true\"\n[tasks.check]\nrun = '''\nset -e\nodx check\n'''\n"},
			{".claude/settings.json", "{\n  // \"command\": \"odx hook edit\"\n  \"hooks\": {}\n}\n"},
		},
	)
	defer os.remove_all(p.root)
	d := Doctor {
		json = true,
	}
	check_task_files(&d, &p)
	testing.expect_value(t, len(d.errors), 0)
	testing.expect_value(t, len(d.warnings), 1)
	testing.expect(t, strings.contains(d.warnings[0], "hook edit"), d.warnings[0])

	// the forbidden flag only in a comment is not a use; in code it is an error
	p2 := scratch_project(
		t,
		{{"mise.toml", "# -no-bounds-check is banned\nrun = \"odin build . -no-bounds-check -sanitize:address -define:ODIN_TEST_FAIL_ON_BAD_MEMORY=true\"\n"}},
	)
	defer os.remove_all(p2.root)
	d2 := Doctor {
		json = true,
	}
	check_task_files(&d2, &p2)
	testing.expect_value(t, len(d2.errors), 1)
	testing.expect(t, strings.contains(d2.errors[0], "-no-bounds-check"))
	testing.expect_value(t, len(d2.warnings), 1) // no `odx check` task
}

@(test)
test_toml_code_and_uncommented_json :: proc(t: ^testing.T) {
	testing.expect_value(t, toml_code(`run = "a # b" # c`), `run = "a # b" `)
	testing.expect_value(t, toml_code(`run = 'x' # y`), `run = 'x' `)
	testing.expect_value(t, toml_code(`plain = 1`), `plain = 1`)
	context.allocator = context.temp_allocator
	defer free_all(context.temp_allocator)
	got := uncommented_json("a\n  // b\nc")
	testing.expectf(t, got == "a\nc\n", "got %q", got)
}

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
