package odx

import "base:runtime"
import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:slice"
import "core:strings"
import "core:time"
import "core:time/timezone"

INIT_EXISTS :: "odx.json already exists, so odx init wrote nothing"

@(rodata)
VENDORED_NAMES := [?]string{"vendor", "third_party", "external"}

// What `odx init` decided for a repo without odx.json. Dirs are repo-relative with `/` and in path
// order.
Init_Report :: struct {
	odin:          string,
	pending:       []string,
	vendored:      []string,
	strict:        int,
	skipped:       int,
	not_compiling: []string,
	// Findings that pending can't hold back, other than the `odin` errors of packages that don't
	// compile.
	shown:         []Finding,
}

@(private = "file")
Dir_Fact :: enum {
	Is_Package,
	Has_Findings,
	Held_Back,
	Does_Not_Compile,
}

// Runs `odx init` in the working directory and returns the exit code. What it allocates with
// `context.allocator` lives until the process exits.
run_init :: proc() -> int {
	result := Result {
		rule_set = RULE_SET,
	}
	root, report := plan_init(&result)
	if len(result.errors) == 0 {
		text := render_config(report, today(context.allocator), context.allocator)
		write_config(root, text, &result)
	}
	if len(result.errors) > 0 {
		write_result(os.to_writer(os.stdout), os.to_writer(os.stderr), result, {})
		return 2
	}

	notes := strings.builder_make()
	for note in result.notes {
		fmt.sbprintf(&notes, "%s\n", note)
	}
	out := strings.builder_make()
	for dir in report.not_compiling {
		fmt.sbprintf(&out, "init: '%s' does not compile\n", dir)
	}
	for f in report.shown {
		render_finding_text(&out, f)
	}
	fmt.sbprintf(
		&out,
		"init: %d strict, %d pending, %d vendored, %d skipped\n",
		report.strict,
		len(report.pending),
		len(report.vendored),
		report.skipped,
	)
	if _, err := os.write_string(os.stderr, strings.to_string(notes)); err != nil {
		return 2
	}
	if _, err := os.write_string(os.stdout, strings.to_string(out)); err != nil {
		return 2
	}
	return 0
}

// Allocates the root and the report's slices with `context.allocator`. The report's findings borrow
// their strings from the packages of both passes, which are also allocated with `context.allocator`
// and never freed, so all of it lives until the process exits.
@(private = "file")
plan_init :: proc(result: ^Result) -> (root: string, report: Init_Report) {
	repo := locate_repo(result)
	if len(result.errors) > 0 {
		return
	}
	if repo.has_config {
		append(&result.errors, Error{.Init_Exists, INIT_EXISTS})
		return
	}
	_, odin := load(repo, result)
	if len(result.errors) > 0 {
		return
	}
	root = repo.root
	report.odin = result.odin
	config := Config {
		vendored = find_vendored_trees(root, context.allocator),
	}
	report.vendored = config.vendored[:]

	packages := discover(root, config, result, context.allocator)
	if len(result.errors) > 0 {
		return
	}
	check(odin, root, config, packages[:], result)
	if len(result.errors) > 0 {
		return
	}
	facts := make(map[string]bit_set[Dir_Fact])
	defer delete(facts)
	for p in packages {
		facts[p.dir] += {.Is_Package}
	}
	for f in result.findings {
		facts[package_dir(f.path)] += {.Has_Findings}
	}
	candidates := Config {
		vendored = config.vendored,
		pending  = make([dynamic]Pending_Entry),
	}
	defer delete(candidates.pending)
	for p in packages {
		if .Has_Findings in facts[p.dir] {
			append(&candidates.pending, Pending_Entry{dir = p.dir})
		}
	}
	findings := &result.findings
	recheck: Result
	if len(candidates.pending) > 0 {
		rediscovered := discover(root, candidates, &recheck, context.allocator)
		check(odin, root, candidates, rediscovered[:], &recheck)
		if len(recheck.errors) > 0 {
			append(&result.errors, ..recheck.errors[:])
			return
		}
		findings = &recheck.findings
	}
	sort_and_dedupe_findings(findings)

	shown := make([dynamic]Finding)
	for f in findings^ {
		dir := package_dir(f.path)
		switch {
		case f.held_back:
			facts[dir] += {.Held_Back}
		case f.rule == .Odin && .Is_Package in facts[dir]:
			facts[dir] += {.Does_Not_Compile}
		case:
			append(&shown, f)
		}
	}
	pending, not_compiling := make([dynamic]string), make([dynamic]string)
	for p in packages {
		switch {
		case .Held_Back in facts[p.dir]:
			append(&pending, p.dir)
		case is_skipped(p):
			report.skipped += 1
		case:
			report.strict += 1
		}
		if .Does_Not_Compile in facts[p.dir] {
			append(&not_compiling, p.dir)
		}
	}
	report.pending = pending[:]
	report.not_compiling = not_compiling[:]
	report.shown = shown[:]
	return
}

// Doesn't follow symlinks, since `os.read_directory_by_path` reports them as `.Symlink`. Allocates
// the dirs with `allocator`.
@(private = "file")
find_vendored_trees :: proc(root: string, allocator: runtime.Allocator) -> [dynamic]string {
	trees := make([dynamic]string, allocator)
	walk_for_vendored(&trees, root, ".")
	slice.sort(trees[:])
	return trees
}

// Appends each vendored tree under `rel` to `trees`, cloned with `trees`' allocator. Its listings use
// `context.temp_allocator`.
@(private = "file")
walk_for_vendored :: proc(trees: ^[dynamic]string, abs, rel: string) {
	entries, err := os.read_directory_by_path(abs, -1, context.temp_allocator)
	if err != nil {
		return
	}
	for entry in entries {
		if entry.type != .Directory || strings.has_prefix(entry.name, ".") {
			continue
		}
		child := entry.name if rel == "." else fmt.tprintf("%s/%s", rel, entry.name)
		switch {
		case !slice.contains(VENDORED_NAMES[:], entry.name):
			walk_for_vendored(trees, entry.fullpath, child)
		case holds_odin_file(entry.fullpath):
			append(trees, strings.clone(child, trees.allocator))
		}
	}
}

@(private = "file")
holds_odin_file :: proc(abs: string) -> bool {
	entries, err := os.read_directory_by_path(abs, -1, context.temp_allocator)
	if err != nil {
		return false
	}
	for entry in entries {
		switch {
		case entry.type == .Directory:
			if !strings.has_prefix(entry.name, ".") && holds_odin_file(entry.fullpath) {
				return true
			}
		case strings.has_suffix(entry.name, ".odin") && !is_hidden_file(entry.name):
			return true
		}
	}
	return false
}

// Allocates the text with `allocator`.
render_config :: proc(report: Init_Report, date: string, allocator: runtime.Allocator) -> string {
	b := strings.builder_make(allocator)
	fmt.sbprintf(&b, "{{\n\t\"version\": %d,\n\t\"odin\": ", RULE_SET)
	write_json_string(&b, report.odin)
	if len(report.pending) > 0 {
		reason := fmt.tprintf("odx init %s", date)
		strings.write_string(&b, ",\n\t\"pending\": {")
		for dir, i in report.pending {
			start_json_item(&b, i)
			write_json_string(&b, dir)
			strings.write_string(&b, ": ")
			write_json_string(&b, reason)
		}
		strings.write_string(&b, "\n\t}")
	}
	if len(report.vendored) > 0 {
		strings.write_string(&b, ",\n\t\"vendored\": [")
		for dir, i in report.vendored {
			start_json_item(&b, i)
			write_json_string(&b, dir)
		}
		strings.write_string(&b, "\n\t]")
	}
	strings.write_string(&b, "\n}\n")
	return strings.to_string(b)
}

@(private = "file")
start_json_item :: proc(b: ^strings.Builder, index: int) {
	strings.write_string(b, ",\n\t\t" if index > 0 else "\n\t\t")
}

@(private = "file")
write_json_string :: proc(b: ^strings.Builder, s: string) {
	options: json.Marshal_Options
	if err := json.marshal_to_builder(b, s, &options); err != nil {
		fmt.panicf("could not encode %q as JSON: %v", s, err)
	}
}

// Creates odx.json at `root` only when it doesn't exist, and removes a partly written one. Adds
// `init-exists` or `init-write` on failure, with the message allocated with `context.allocator`.
@(private = "file")
write_config :: proc(root, text: string, result: ^Result) {
	path := fmt.tprintf("%s/%s", root, CONFIG_FILE)
	file, err := os.open(path, {.Write, .Create, .Excl}, os.Permissions_Default_File)
	remove_err: os.Error
	if err == nil {
		_, err = os.write_string(file, text)
		if close_err := os.close(file); err == nil {
			err = close_err
		}
		if err != nil {
			remove_err = os.remove(path)
		}
	}
	switch {
	case err == os.General_Error.Exist:
		append(&result.errors, Error{.Init_Exists, INIT_EXISTS})
	case err != nil && remove_err != nil:
		message := fmt.aprintf(
			"could not write %s: %s, and could not remove the partly written file: %s",
			CONFIG_FILE,
			os.error_string(err),
			os.error_string(remove_err),
		)
		append(&result.errors, Error{.Init_Write, message})
	case err != nil:
		message := fmt.aprintf("could not write %s: %s", CONFIG_FILE, os.error_string(err))
		append(&result.errors, Error{.Init_Write, message})
	}
}

// Allocates the date with `allocator`.
@(private = "file")
today :: proc(allocator: runtime.Allocator) -> string {
	utc, in_range := time.time_to_datetime(time.now())
	ensure(in_range, "the clock is outside the range of a date")
	date := utc
	if zone, ok := timezone.region_load("local", context.temp_allocator); ok {
		if local, converted := timezone.datetime_to_tz(utc, zone); converted {
			date = local
		}
	}
	return fmt.aprintf("%04d-%02d-%02d", date.year, date.month, date.day, allocator = allocator)
}
