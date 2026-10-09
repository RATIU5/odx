package odx

import "core:fmt"
import "core:mem/virtual"
import "core:os"
import "core:strings"
import "core:sys/posix"
import "core:testing"
import "core:time"

// git can't hold a FIFO, so no golden case can. Opening one waits for a writer that never comes,
// so each test here fails by its time limit when a site opens the path.
@(private = "file")
Fifo_Repo :: struct {
	arena: virtual.Arena,
	root:  string,
}

// Makes a temp directory with a FIFO at each of `fifos`, after the directories of `dirs`. The
// caller's `context.allocator` must be `virtual.arena_allocator(&repo.arena)`.
@(private = "file")
make_fifo_repo :: proc(t: ^testing.T, repo: ^Fifo_Repo, dirs, fifos: []string) {
	testing.set_fail_timeout(t, 20 * time.Second)
	root, err := os.make_directory_temp("", "odx-fifo-*", context.allocator)
	testing.expect_value(t, err, nil)
	repo.root = real_root(root, context.allocator)
	for dir in dirs {
		testing.expect_value(t, os.make_directory_all(at(repo, dir)), nil)
	}
	for fifo in fifos {
		path := strings.clone_to_cstring(at(repo, fifo))
		testing.expect_value(t, posix.mkfifo(path, {.IRUSR, .IWUSR}), posix.result.OK)
	}
}

@(private = "file")
destroy_fifo_repo :: proc(repo: ^Fifo_Repo) {
	os.remove_all(repo.root)
	virtual.arena_destroy(&repo.arena)
}

@(private = "file")
at :: proc(repo: ^Fifo_Repo, rel: string) -> string {
	return fmt.aprintf("%s/%s", repo.root, rel)
}

@(private = "file")
expect_quick :: proc(t: ^testing.T, started: time.Tick, what: string) {
	took := time.tick_since(started)
	testing.expectf(t, took < time.Second, "%s took %v", what, took)
}

@(test)
disk_kind_follows_links_and_never_opens :: proc(t: ^testing.T) {
	repo: Fifo_Repo
	testing.expect(t, virtual.arena_init_growing(&repo.arena) == nil)
	context.allocator = virtual.arena_allocator(&repo.arena)
	make_fifo_repo(t, &repo, {"dir"}, {"pipe"})
	defer destroy_fifo_repo(&repo)
	testing.expect_value(t, os.write_entire_file(at(&repo, "file"), "x"), nil)
	links := []struct {
		target, name: string,
	} {
		{"file", "to_file"},
		{"dir", "to_dir"},
		{"pipe", "to_pipe"},
		{"/dev/null", "to_device"},
		{"nowhere", "dangling"},
		{"loop", "loop"},
	}
	for link in links {
		testing.expect_value(t, os.symlink(link.target, at(&repo, link.name)), nil)
	}

	cases := []struct {
		name: string,
		want: Disk_Kind,
	} {
		{"file", .File},
		{"to_file", .File},
		{"dir", .Dir},
		{"to_dir", .Dir},
		{"pipe", .Special},
		{"to_pipe", .Special},
		{"to_device", .Special},
		{"dangling", .Missing},
		{"loop", .Missing},
		{"absent", .Missing},
		{"file/below", .Missing},
		{strings.repeat("long/", 400), .Missing},
	}
	started := time.tick_now()
	for c in cases {
		got := disk_kind(at(&repo, c.name))
		testing.expectf(
			t,
			got == c.want,
			"%s: got %v, want %v",
			c.name[:min(len(c.name), 20)],
			got,
			c.want,
		)
	}
	expect_quick(t, started, "disk_kind")
}

@(test)
load_config_never_opens_an_odx_json_that_is_not_a_regular_file :: proc(t: ^testing.T) {
	repo: Fifo_Repo
	testing.expect(t, virtual.arena_init_growing(&repo.arena) == nil)
	context.allocator = virtual.arena_allocator(&repo.arena)
	make_fifo_repo(t, &repo, {"fifo", "dir/odx.json", "device"}, {"fifo/odx.json"})
	defer destroy_fifo_repo(&repo)
	testing.expect_value(t, os.symlink("/dev/null", at(&repo, "device/odx.json")), nil)

	for root in ([]string{"fifo", "dir", "device"}) {
		started := time.tick_now()
		_, errors := load_config(at(&repo, root), context.allocator)
		expect_quick(t, started, root)
		testing.expect_value(t, len(errors), 1)
		if len(errors) == 1 {
			testing.expect_value(t, errors[0].code, Error_Code.Config_Invalid)
			testing.expect_value(t, errors[0].message, "odx.json isn't a regular file")
		}
	}
}

@(test)
a_collection_path_that_is_a_fifo_is_not_a_directory :: proc(t: ^testing.T) {
	repo: Fifo_Repo
	testing.expect(t, virtual.arena_init_growing(&repo.arena) == nil)
	context.allocator = virtual.arena_allocator(&repo.arena)
	make_fifo_repo(t, &repo, {}, {"pipe"})
	defer destroy_fifo_repo(&repo)

	text := fmt.aprintf(`{{"version": 1, "odin": "%s", "collections": ["lib=pipe"]}}`, PIN)
	started := time.tick_now()
	config, errors := parse_config(text, repo.root, context.allocator)
	expect_quick(t, started, "parse_config")
	testing.expect_value(t, len(config.collections), 0)
	testing.expect_value(t, len(errors), 1)
	if len(errors) == 1 {
		testing.expect_value(
			t,
			errors[0].message,
			"collection 'lib' path 'pipe' is not a directory",
		)
	}
}

@(test)
a_pending_entry_that_names_a_fifo_is_a_file :: proc(t: ^testing.T) {
	repo: Fifo_Repo
	testing.expect(t, virtual.arena_init_growing(&repo.arena) == nil)
	context.allocator = virtual.arena_allocator(&repo.arena)
	make_fifo_repo(t, &repo, {}, {"pipe"})
	defer destroy_fifo_repo(&repo)

	started := time.tick_now()
	stale := stale_pending(repo.root, {{"pipe", "r", 3, 5}}, {}, {}, context.allocator)
	expect_quick(t, started, "stale_pending")
	testing.expect_value(t, len(stale), 1)
	if len(stale) == 1 {
		testing.expect_value(t, stale[0].message, "'pipe' is a file, not a directory")
		testing.expect_value(t, stale[0].line, 3)
		testing.expect_value(t, stale[0].col, 5)
	}
}

@(test)
needs_odinfmt_never_opens_an_odinfmt_json_that_is_not_a_regular_file :: proc(t: ^testing.T) {
	repo: Fifo_Repo
	testing.expect(t, virtual.arena_init_growing(&repo.arena) == nil)
	context.allocator = virtual.arena_allocator(&repo.arena)
	make_fifo_repo(t, &repo, {}, {ODINFMT_FILE})
	defer destroy_fifo_repo(&repo)

	result: Result
	started := time.tick_now()
	needed := needs_odinfmt(repo.root, &result)
	expect_quick(t, started, "needs_odinfmt")
	testing.expect(t, !needed, "a FIFO must not be written over")
	testing.expect_value(t, len(result.errors), 1)
	if len(result.errors) == 1 {
		testing.expect_value(t, result.errors[0].code, Error_Code.Init_Exists)
		testing.expect_value(
			t,
			result.errors[0].message,
			"odinfmt.json already exists and odx can't read it (it isn't a regular file), so " +
			"odx init wrote nothing",
		)
	}
}

@(test)
find_on_path_passes_over_a_fifo :: proc(t: ^testing.T) {
	repo: Fifo_Repo
	testing.expect(t, virtual.arena_init_growing(&repo.arena) == nil)
	context.allocator = virtual.arena_allocator(&repo.arena)
	make_fifo_repo(t, &repo, {"first", "second", "third/odin"}, {"first/odin"})
	defer destroy_fifo_repo(&repo)
	real := at(&repo, "second/odin")
	testing.expect_value(t, os.write_entire_file(real, "#!/bin/sh\n"), nil)
	testing.expect_value(t, os.write_entire_file(at(&repo, "third/plain"), "#!/bin/sh\n"), nil)
	testing.expect_value(
		t,
		os.chmod(real, os.Permissions_Default_File + os.Permissions_Execute_All),
		nil,
	)

	dirs := strings.join({at(&repo, "first"), "", at(&repo, "third"), at(&repo, "second")}, ":")
	started := time.tick_now()
	found_path, found := find_on_path(dirs, "odin")
	_, found_plain := find_on_path(dirs, "plain")
	expect_quick(t, started, "find_on_path")
	testing.expect(t, found, "the executable after the FIFO wasn't found")
	testing.expect_value(t, found_path, real)
	testing.expect(t, !found_plain, "a file nobody may execute was found")
}

@(test)
the_loader_never_opens_an_imported_fifo :: proc(t: ^testing.T) {
	repo: Fifo_Repo
	testing.expect(t, virtual.arena_init_growing(&repo.arena) == nil)
	context.allocator = virtual.arena_allocator(&repo.arena)
	make_fifo_repo(t, &repo, {"app"}, {"pipe"})
	defer destroy_fifo_repo(&repo)
	src := "package app\n\nimport \"../pipe\"\n\nAlias :: pipe.Thing\n"
	testing.expect_value(t, os.write_entire_file(at(&repo, "app/a.odin"), src), nil)

	resolver: Resolver
	resolver_init(&resolver, "", nil, {}, context.allocator)
	result: Result
	started := time.tick_now()
	packages := discover(repo.root, {}, &resolver, &result, context.allocator)
	expect_quick(t, started, "discovery")
	testing.expect_value(t, len(result.errors), 0)
	testing.expect_value(t, len(packages), 1)

	_, list_err := list_dir(at(&repo, "pipe"), context.allocator)
	testing.expect(t, list_err != nil, "a FIFO listed as a directory")
}

@(test)
check_paths_never_opens_a_fifo_on_a_path_a_file_names :: proc(t: ^testing.T) {
	repo: Fifo_Repo
	testing.expect(t, virtual.arena_init_growing(&repo.arena) == nil)
	context.allocator = virtual.arena_allocator(&repo.arena)
	make_fifo_repo(t, &repo, {"app"}, {"pipe"})
	defer destroy_fifo_repo(&repo)

	file := Source_File {
		path     = "app/a.odin",
		paths    = make([dynamic]Path_Ref),
		findings = make([dynamic]Finding),
	}
	append(
		&file.paths,
		Path_Ref{kind = .Import, written = "../pipe/sub", line = 3, col = 1},
		Path_Ref{kind = .Load, written = "../PIPE/data.txt", line = 5, col = 9},
	)
	packages := []Package{{dir = "app", files = make([dynamic]Source_File)}}
	append(&packages[0].files, file)

	started := time.tick_now()
	check_paths(packages, repo.root, "/nowhere", nil, context.allocator)
	expect_quick(t, started, "check_paths")
	// A path below a FIFO is one below a missing directory, which stays inside the repo.
	for f in packages[0].files[0].findings {
		testing.expectf(t, f.rule == .Path_Case, "got %s: %s", RULES[f.rule].id, f.message)
	}
}

@(test)
a_link_name_clash_at_a_fifo_is_no_foreign_procedure :: proc(t: ^testing.T) {
	repo: Fifo_Repo
	testing.expect(t, virtual.arena_init_growing(&repo.arena) == nil)
	context.allocator = virtual.arena_allocator(&repo.arena)
	make_fifo_repo(t, &repo, {}, {"x.odin"})
	defer destroy_fifo_repo(&repo)

	foreign_decls := make(map[string][]Position)
	entry := Compiler_Entry {
		kind = .Error,
		file = "/elsewhere/a.odin",
		line = 1,
		col  = 1,
		msgs = {
			"Non unique linking name for procedure 'x'",
			fmt.aprintf("\tother at %s(6:2)", at(&repo, "x.odin")),
		},
	}
	started := time.tick_now()
	clashes := clashes_with_foreign_procedure(entry, &foreign_decls, context.allocator)
	expect_quick(t, started, "clashes_with_foreign_procedure")
	testing.expect(t, !clashes, "a FIFO held a foreign procedure")
}

@(test)
the_format_child_never_opens_a_fifo :: proc(t: ^testing.T) {
	repo: Fifo_Repo
	testing.expect(t, virtual.arena_init_growing(&repo.arena) == nil)
	context.allocator = virtual.arena_allocator(&repo.arena)
	make_fifo_repo(t, &repo, {}, {"x.odin"})
	defer destroy_fifo_repo(&repo)

	started := time.tick_now()
	result := format_file(at(&repo, "x.odin"), print_source)
	expect_quick(t, started, "format_file")
	unreadable, is_unreadable := result.(Unreadable)
	testing.expectf(t, is_unreadable, "got %v", result)
	testing.expect_value(t, unreadable.reason, "it isn't a regular file")
}
