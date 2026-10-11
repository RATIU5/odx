package odx

import "core:fmt"
import "core:mem/virtual"
import "core:os"
import "core:strings"
import "core:sys/posix"
import "core:testing"
import "core:time"

// git can't hold a FIFO, so no golden case can. Opening one waits for a writer that never comes.
@(test)
discovery_never_opens_a_fifo :: proc(t: ^testing.T) {
	testing.set_fail_timeout(t, 20 * time.Second)
	arena: virtual.Arena
	testing.expect(t, virtual.arena_init_growing(&arena) == nil)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	root, err := os.make_directory_temp("", "odx-special-*", context.allocator)
	testing.expect_value(t, err, nil)
	defer os.remove_all(root)
	pkg_dir := fmt.aprintf("%s/pkg", root)
	testing.expect_value(t, os.make_directory(pkg_dir), nil)
	valid := fmt.aprintf("%s/a.odin", pkg_dir)
	testing.expect_value(t, os.write_entire_file(valid, "package pkg\n\nVALUE :: 1\n"), nil)
	mode := posix.mode_t{.IRUSR, .IWUSR}
	testing.expect_value(t, os.make_directory(fmt.aprintf("%s/only", root)), nil)
	for fifo in ([]string{"pkg/x.odin", "pkg/.hidden.odin", "pipe", "only/lone.odin"}) {
		path := strings.clone_to_cstring(fmt.aprintf("%s/%s", root, fifo))
		testing.expect_value(t, posix.mkfifo(path, mode), posix.result.OK)
	}
	testing.expect_value(t, os.symlink("../pipe", fmt.aprintf("%s/y.odin", pkg_dir)), nil)

	result: Result
	started := time.tick_now()
	packages := discover(root, {}, &result, context.allocator)
	took := time.tick_since(started)

	testing.expectf(t, took < time.Second, "discovery took %v", took)
	testing.expect_value(t, len(result.errors), 0)
	testing.expect_value(t, len(packages), 2)
	if len(packages) != 2 {
		return
	}
	// A package that holds nothing but the entry isn't skipped either, which is counted and never
	// failed.
	only, pkg := packages[0], packages[1]
	testing.expect_value(t, only.dir, "only")
	testing.expect_value(t, only.compile, Compile(Special_Entry{}))
	testing.expect_value(t, pkg.dir, "pkg")
	testing.expect_value(t, pkg.compile, Compile(Special_Entry{}))
	testing.expect_value(t, result.skipped, 0)
	testing.expect_value(t, len(result.notes), 0)

	got := strings.builder_make()
	for file in pkg.files {
		for f in file.findings {
			fmt.sbprintf(
				&got,
				"%s:%d:%d: %s: %s\n",
				f.path,
				f.line,
				f.col,
				RULES[f.rule].id,
				f.message,
			)
		}
	}
	want :=
		"pkg/x.odin:1:1: parse-unsupported: odx can't read this file: it isn't a regular file\n" +
		"pkg/y.odin:1:1: parse-unsupported: odx can't read this file: it isn't a regular file\n"
	testing.expect_value(t, strings.to_string(got), want)
}

@(test)
dir_entry_kind_follows_a_link_only_to_learn_its_kind :: proc(t: ^testing.T) {
	arena: virtual.Arena
	testing.expect(t, virtual.arena_init_growing(&arena) == nil)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	root, err := os.make_directory_temp("", "odx-kinds-*", context.allocator)
	testing.expect_value(t, err, nil)
	defer os.remove_all(root)
	at :: proc(root, name: string) -> string {
		return fmt.aprintf("%s/%s", root, name)
	}
	testing.expect_value(t, os.make_directory(at(root, "dir.odin")), nil)
	testing.expect_value(t, os.write_entire_file(at(root, "file.odin"), "package a\n"), nil)
	testing.expect_value(t, os.write_entire_file(at(root, ".hidden.odin"), "package a\n"), nil)
	testing.expect_value(t, os.write_entire_file(at(root, "notes.txt"), ""), nil)
	links := []struct {
		target, name: string,
	} {
		{"file.odin", "to_file.odin"},
		{"dir.odin", "to_dir.odin"},
		{"nowhere.odin", "dangling.odin"},
		{"/dev/null", "to_device.odin"},
		{"/dev/null", "to_device.txt"},
		{"/dev/null", ".hidden_device.odin"},
	}
	for link in links {
		testing.expect_value(t, os.symlink(link.target, at(root, link.name)), nil)
	}

	// In name order, as `list_dir` returns them.
	want := []struct {
		name: string,
		kind: Dir_Entry_Kind,
	} {
		{".hidden.odin", .Hidden_Source},
		{".hidden_device.odin", .Hidden_Source},
		{"dangling.odin", .Source},
		{"dir.odin", .Dir},
		{"file.odin", .Source},
		{"notes.txt", .Other},
		{"to_device.odin", .Special_Source},
		{"to_device.txt", .Other},
		{"to_dir.odin", .Other},
		{"to_file.odin", .Source},
	}
	entries, list_err := list_dir(root, context.allocator)
	testing.expect_value(t, list_err, nil)
	if !testing.expect_value(t, len(entries), len(want)) {
		return
	}
	for entry, i in entries {
		got := dir_entry_kind(entry)
		testing.expect_value(t, entry.name, want[i].name)
		testing.expectf(
			t,
			got == want[i].kind,
			"%s: got %v, want %v",
			entry.name,
			got,
			want[i].kind,
		)
	}
}
