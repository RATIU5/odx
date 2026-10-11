package odx

import "core:fmt"
import "core:mem/virtual"
import "core:os"
import "core:slice"
import "core:strings"
import "core:testing"

@(test)
check_command_scopes_strict_flags_by_package_name :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	config: Config
	config.collections = make([dynamic]Collection, context.temp_allocator)
	config.defines = make([dynamic]Define, context.temp_allocator)
	append(&config.collections, Collection{"libs", "/repo/libs"})
	append(&config.defines, Define{"DEBUG", "true"})
	base := []string {
		"/bin/odin",
		"check",
		"/repo/foo",
		"-json-errors",
		"-max-error-count:1000000",
		"-thread-count:1",
		"-ignore-unused-defineables",
	}
	strict_flags := []string {
		"-no-entry-point",
		"-collection:libs=/repo/libs",
		"-define:DEBUG=true",
		"-vet",
		"-vet-cast",
		"-strict-style",
		"-vet-packages:bar",
		"-strict-style-packages:bar",
	}

	cases := []struct {
		name:   string,
		pkg:    Package,
		strict: bool,
		target: Target,
		want:   []string,
	} {
		{
			"strict, named by its package clause",
			Package{dir = "foo", name = "bar", status = .Strict},
			true,
			.Linux_Amd64,
			slice.concatenate(
				[][]string{{"-target:linux_amd64"}, strict_flags},
				context.temp_allocator,
			),
		},
		{
			"pending, without strict flags and without warnings",
			Package{dir = "foo", name = "bar", status = .Pending},
			false,
			.Darwin_Arm64,
			{
				"-target:darwin_arm64",
				"-no-entry-point",
				"-collection:libs=/repo/libs",
				"-define:DEBUG=true",
				"-ignore-warnings",
			},
		},
		{
			"pending, with strict flags",
			Package{dir = "foo", name = "bar", status = .Pending},
			true,
			.Darwin_Arm64,
			slice.concatenate(
				[][]string{{"-target:darwin_arm64"}, strict_flags},
				context.temp_allocator,
			),
		},
		{
			"package main, which keeps its entry point",
			Package{dir = "foo", name = "main", status = .Pending},
			false,
			.Darwin_Arm64,
			{
				"-target:darwin_arm64",
				"-collection:libs=/repo/libs",
				"-define:DEBUG=true",
				"-ignore-warnings",
			},
		},
	}
	for c in cases {
		got := check_command(
			"/bin/odin",
			"/repo/foo",
			c.pkg,
			c.target,
			c.strict,
			config,
			context.temp_allocator,
		)
		want := slice.concatenate([][]string{base, c.want}, context.temp_allocator)
		testing.expectf(
			t,
			slice.equal(got, want),
			"%s:\ngot  %s\nwant %s",
			c.name,
			strings.join(got, " ", context.temp_allocator),
			strings.join(want, " ", context.temp_allocator),
		)
	}
}

// The compiler answers an empty name with `Flag missing for 'vet-packages'` and reads no file.
@(test)
check_command_leaves_out_the_package_flags_for_a_package_without_a_name :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	got := check_command(
		"/bin/odin",
		"/repo/foo",
		Package{dir = "foo", status = .Strict},
		.Darwin_Arm64,
		true,
		{},
		context.temp_allocator,
	)
	want := []string {
		"/bin/odin",
		"check",
		"/repo/foo",
		"-json-errors",
		"-max-error-count:1000000",
		"-thread-count:1",
		"-ignore-unused-defineables",
		"-target:darwin_arm64",
		"-no-entry-point",
		"-vet",
		"-vet-cast",
		"-strict-style",
	}
	testing.expectf(
		t,
		slice.equal(got, want),
		"got  %s\nwant %s",
		strings.join(got, " ", context.temp_allocator),
		strings.join(want, " ", context.temp_allocator),
	)
}

@(test)
link_name_clash_drops_only_a_foreign_procedure_at_the_other_position :: proc(t: ^testing.T) {
	arena: virtual.Arena
	testing.expect(t, virtual.arena_init_growing(&arena) == nil)
	defer virtual.arena_destroy(&arena)
	allocator := virtual.arena_allocator(&arena)

	dir, err := os.make_directory_temp("", "odx-link-name-*", allocator)
	testing.expect_value(t, err, nil)
	defer os.remove_all(dir)
	path := fmt.aprintf("%s/decls.odin", dir, allocator = allocator)
	src := `package decls

foreign import libc "system:c"

foreign libc {
	top :: proc() -> i32 ---
}

when ODIN_OS == .Darwin {
	foreign libc {
		nested :: proc() -> i32 ---
		nested_var: i32
	}
} else {
	foreign libc {
		in_else :: proc() -> i32 ---
	}
}

@(export, link_name="defined")
defined :: proc "c" () {}
`
	testing.expect_value(t, os.write_entire_file(path, src), nil)
	foreign_decls := make(map[string][]Position, 0, allocator)

	cases := []struct {
		name:     string,
		other_at: string,
		want:     bool,
	} {
		{"a top-level foreign procedure", "(6:2)", true},
		{"a foreign procedure in a when block", "(11:3)", true},
		{"a foreign procedure in an else block", "(16:3)", true},
		{"a foreign variable", "(12:3)", false},
		{"a definition", "(21:1)", false},
		{"no declaration at the position", "(6:3)", false},
	}
	for c in cases {
		entry := Compiler_Entry {
			kind = .Error,
			file = "/elsewhere/a.odin",
			line = 1,
			col  = 1,
			msgs = {
				"Non unique linking name for procedure 'x'",
				fmt.tprintf("\tother at %s%s", path, c.other_at),
			},
		}
		got := clashes_with_foreign_procedure(entry, &foreign_decls, allocator)
		testing.expectf(t, got == c.want, "%s: got %v, want %v", c.name, got, c.want)
	}
	other := Compiler_Entry {
		kind = .Error,
		file = "/elsewhere/a.odin",
		line = 1,
		col  = 1,
		msgs = {"Cannot convert", fmt.tprintf("\tother at %s(6:2)", path)},
	}
	testing.expect(t, !clashes_with_foreign_procedure(other, &foreign_decls, allocator))
	free_all(context.temp_allocator)
}

@(test)
write_stderr_tail_quotes_the_last_lines_of_what_the_child_wrote :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	quote :: proc(stderr: string) -> string {
		b := strings.builder_make(context.temp_allocator)
		write_stderr_tail(&b, stderr)
		return strings.to_string(b)
	}
	numbered :: proc(count: int) -> string {
		b := strings.builder_make(context.temp_allocator)
		for i in 1 ..= count {
			fmt.sbprintf(&b, "line %d\n", i)
		}
		return strings.to_string(b)
	}
	testing.expect_value(t, quote(""), "; stderr was empty")
	testing.expect_value(t, quote("\r\n\n"), "; stderr was empty")
	testing.expect_value(t, quote("a\nb\n"), "; stderr:\n\ta\n\tb")
	testing.expect_value(
		t,
		len(strings.split_lines(quote(numbered(40)), context.temp_allocator)),
		41,
	)
	testing.expect(t, strings.has_prefix(quote(numbered(40)), "; stderr:\n\tline 1\n"))

	many := quote(numbered(41))
	testing.expect(
		t,
		strings.has_prefix(many, "; the last 40 of its 41 stderr lines:\n\tline 2\n\tline 3\n"),
		many[:min(len(many), 80)],
	)
	testing.expect(t, strings.has_suffix(many, "\n\tline 41"), "the last line is missing")
}
