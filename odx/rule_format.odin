package odx

import "base:intrinsics"
import "base:runtime"
import "core:fmt"
import "core:mem/virtual"
import "core:odin/ast"
import "core:odin/parser"
import "core:odin/tokenizer"
import "core:os"
import "core:slice"
import "core:strconv"
import "core:strings"
import "core:sys/posix"
import "core:thread"
import "core:time"

import printer "ols_printer"

// The printer reads `core:odin` from the compiler that builds odx, so another compiler can change
// `format` results. `ols_printer/README.md` names the pin.
#assert(
	ODIN_VERSION + "-nightly:" + ODIN_VERSION_HASH == SUPPORTED_COMPILER,
	"odx's printer is pinned to the compiler SUPPORTED_COMPILER names",
)

FORMAT_TIMEOUT :: 120 * time.Second

// How long after the timeout a `__format` child ends itself, which is what stops it when odx was
// killed and can't.
FORMAT_ALARM_MARGIN :: 2 * time.Second

// How often a `__format` child counts down its own limit.
FORMAT_ALARM_POLL :: 250 * time.Millisecond

FORMAT_DIFFERS_MESSAGE :: "the file differs from the formatter's output"
FORMAT_REFUSED_MESSAGE :: "the formatter can't read the file"
FORMAT_CRASHED_MESSAGE :: "the formatter crashed, so odx can't check this file's format"

ODINFMT_FILE :: "odinfmt.json"

// The config the team's odinfmt reads, which `odx init` writes. A unit test holds it to
// `FORMAT_CONFIG` key by key, so the repo's file is the one copy that is edited by hand.
ODINFMT_JSON :: #load("../odinfmt.json", string)

// Appendix E.6. odx ignores any `odinfmt.json` in the checked repo.
FORMAT_CONFIG :: printer.Config {
	character_width              = 100,
	spaces                       = 4,
	newline_limit                = 1,
	tabs                         = true,
	tabs_width                   = 4,
	convert_do                   = false,
	brace_style                  = ._1TBS,
	indent_cases                 = false,
	newline_style                = .LF,
	sort_imports                 = true,
	inline_single_stmt_case      = false,
	spaces_around_colons         = false,
	space_single_line_blocks     = false,
	align_struct_fields          = true,
	align_struct_values          = true,
	align_struct_declarations    = false,
	align_constant_definitions   = false,
	align_comments               = false,
	multiline_composite_literals = false,
	preserve_struct_blank_lines  = false,
}

Formatted :: struct {}

Differs :: struct {
	first_differing_line: int,
}

Refused :: struct {}

Timed_Out :: struct {}

// The child couldn't read its file, which was there at discovery.
Unreadable :: struct {
	reason: string,
}

Crashed :: struct {}

// odx couldn't start the child, wait for it or read what it wrote.
Run_Failed :: struct {
	reason: string,
}

// What a `__format` child writes about its file, as one result line.
Print_Result :: union {
	Formatted,
	Differs,
	Refused,
	Unreadable,
}

// Nil for a file whose child never started.
Format_Outcome :: union {
	Formatted,
	Differs,
	Refused,
	Unreadable,
	Timed_Out,
	Crashed,
	Run_Failed,
}

// Allocates `out` with `context.allocator`. `ok` is false when the printer can't read `src`.
Print_Proc :: #type proc(src: string) -> (out: string, ok: bool)

// Prints `src` once and compares, per Appendix E.7. The print's memory stays with
// `context.allocator`, so the caller frees it in bulk.
print_result :: proc(src: string, print: Print_Proc) -> Print_Result {
	out, ok := print(src)
	switch {
	case !ok:
		return Refused{}
	case out == src:
		return Formatted{}
	}
	same := 0
	for same < len(src) && same < len(out) && src[same] == out[same] {
		same += 1
	}
	return Differs{1 + strings.count(src[:same], "\n")}
}

write_print_result :: proc(b: ^strings.Builder, result: Print_Result) {
	switch r in result {
	case Formatted:
		strings.write_string(b, "formatted\n")
	case Differs:
		fmt.sbprintf(b, "differs %d\n", r.first_differing_line)
	case Refused:
		strings.write_string(b, "refused\n")
	case Unreadable:
		fmt.sbprintf(b, "unreadable %s\n", r.reason)
	}
}

// Nil unless `text` is one whole result line, so a child that died while writing gives no result.
// An `Unreadable` borrows its reason from `text`.
read_print_result :: proc(text: string) -> Print_Result {
	line := strings.trim_suffix(text, "\n")
	if len(line) == len(text) || strings.contains_rune(line, '\n') {
		return nil
	}
	switch {
	case line == "formatted":
		return Formatted{}
	case line == "refused":
		return Refused{}
	case strings.has_prefix(line, "differs "):
		if n, is_number := strconv.parse_uint(line[len("differs "):], 10); is_number && n > 0 {
			return Differs{int(n)}
		}
	case strings.has_prefix(line, "unreadable ") && len(line) > len("unreadable "):
		return Unreadable{line[len("unreadable "):]}
	}
	return nil
}

// Prints `src` with the vendored printer and Appendix E.6's config, the way OLS's `format` does,
// except that any parser or tokenizer error refuses the print and none reaches stderr. Allocates
// the AST, the printer's state and `out` with `context.allocator`, which suits an arena.
@(require_results)
print_source :: proc(src: string) -> (out: string, ok: bool) {
	pkg := ast.Package {
		kind = .Normal,
	}
	file := ast.File {
		pkg = &pkg,
		src = src,
	}
	p := parser.default_parser({.Optional_Semicolons})
	p.warn = nil
	// The handler gets no user data, so the count travels in the context.
	p.err = proc(pos: tokenizer.Pos, msg: string, args: ..any) {
		(^int)(context.user_ptr)^ += 1
	}
	errors := 0
	context.user_ptr = &errors
	if !parser.parse_file(&p, &file) ||
	   errors > 0 ||
	   file.syntax_error_count > 0 ||
	   p.tok.error_count > 0 {
		return "", false
	}
	prnt := printer.make_printer(FORMAT_CONFIG, context.allocator)
	out = printer.print(&prnt, &file)
	return out, !prnt.errored_out
}

// Reads the file at `path` and prints it with `print`. Allocates with `context.allocator`, which
// suits an arena.
format_file :: proc(path: string, print: Print_Proc) -> Print_Result {
	if disk_kind(path) == .Special {
		return Unreadable{NOT_REGULAR_REASON}
	}
	data, err := os.read_entire_file(path, context.allocator)
	if err != nil {
		return Unreadable{os.error_string(err)}
	}
	return print_result(string(data), print)
}

// How much address space a `__format` child may add to what it has when it starts. The printer's
// memory doubles with each `proc() ->` in a row in a type: 0.7 GB for 18 and 2.9 GB for 20, in a
// file the compiler accepts. The largest file probed, 2 MB of generated tables, needs 0.2 GB.
FORMAT_MEMORY_GROWTH :: 2 << 30

// Makes every allocation fail once the process has grown by `growth` bytes of address space, which
// ends a print that would otherwise take the machine's memory. `RLIMIT_AS` bounds the whole
// address space, and the kernel rejects a limit below what the process already has, which on macOS
// is hundreds of gigabytes that are reserved and never used. So the limit is the smallest one the
// kernel accepts, found by bisection, plus `growth`. A kernel that accepts any limit, as Linux
// does, gets `growth` as the whole. Without a limit to read, there is no cap.
limit_own_growth :: proc(growth: uint) {
	limit: posix.rlimit
	if posix.getrlimit(.AS, &limit) != .OK {
		return
	}
	rejected, accepted := uint(0), uint(1) << 47
	for accepted - rejected > 1 << 20 {
		middle := rejected + (accepted - rejected) / 2
		limit.rlim_cur = posix.rlim_t(middle)
		if posix.setrlimit(.AS, &limit) == .OK {
			accepted = middle
		} else {
			rejected = middle
		}
	}
	limit.rlim_cur = posix.rlim_t(accepted + growth)
	posix.setrlimit(.AS, &limit)
}

// Exits 0 when it wrote the file's result line.
run_format :: proc(cmd: Format_Child_Command) -> int {
	growth := uint(FORMAT_MEMORY_GROWTH)
	// A golden case reaches the cap without taking 2 GB, by naming megabytes.
	if mb, ok := strconv.parse_uint(debug_env("ODX_FORMAT_MEMORY_MB"), 10); ok && mb > 0 {
		growth = mb << 20
	}
	limit_own_growth(growth)
	// A thread counts the limit down as `wait_child` does, where `alarm` would leave it to the
	// platform whether a sleep counts. SIGALRM's default action ends the process.
	limit := debug_timeout("ODX_FORMAT_TIMEOUT_MS", FORMAT_TIMEOUT) + FORMAT_ALARM_MARGIN
	thread.create_and_start_with_poly_data(limit, proc(limit: time.Duration) {
			left := limit
			polled := time.tick_now()
			for left > 0 {
				time.sleep(min(left, FORMAT_ALARM_POLL))
				now := time.tick_now()
				left = charge_poll(left, time.tick_diff(polled, now), FORMAT_ALARM_POLL)
				polled = now
			}
			posix.kill(posix.getpid(), .SIGALRM)
		}, self_cleanup = true)

	arena: virtual.Arena
	ensure(virtual.arena_init_growing(&arena) == nil, "out of memory")
	context.allocator = virtual.arena_allocator(&arena)

	b := strings.builder_make()
	write_print_result(&b, format_file(cmd.file, format_printer()))
	if _, write_err := os.write_string(os.stdout, strings.to_string(b)); write_err != nil {
		return 2
	}
	return 0
}

Format_Job :: struct {
	pkg:        int,
	path:       string,
	size:       int,
	pool_index: int,
}

// Every format child of one `odx check`. The pool's lists and commands live in `work`.
Format_Jobs :: struct {
	by_path: []Format_Job,
	pool:    Pool(Format_Outcome),
	work:    virtual.Arena,
	// Why no child could start, and "" otherwise.
	error:   string,
}

// Starts one `__format` child per parsed file of `packages`, largest file first, and returns
// without waiting. A print that crashes or hangs then ends its child and never odx. `finish_format`
// or `abandon_format` must follow. `root` is the repo root, where the children run within `budget`.
// Allocates the jobs with `allocator`.
start_format :: proc(
	root: string,
	packages: []Package,
	budget: ^Child_Budget,
	allocator: runtime.Allocator,
) -> ^Format_Jobs {
	jobs := new(Format_Jobs, allocator)
	ensure(virtual.arena_init_growing(&jobs.work) == nil, "out of memory")
	work := virtual.arena_allocator(&jobs.work)

	odx, exe_err := os.get_executable_path(work)
	if exe_err != nil {
		jobs.error = fmt.aprintf(
			"odx can't find its own executable to run the formatter: %s",
			os.error_string(exe_err),
			allocator = work,
		)
		return jobs
	}
	by_path := make([dynamic]Format_Job, work)
	for p, i in packages {
		for f in p.files {
			if f.parsed {
				append(&by_path, Format_Job{pkg = i, path = f.path, size = f.size})
			}
		}
	}
	slice.sort_by(by_path[:], proc(a, b: Format_Job) -> bool {
		return a.path < b.path
	})
	jobs.by_path = by_path[:]
	largest_first := make([]int, len(by_path), work)
	for &slot, i in largest_first {
		slot = i
	}
	slice.sort_by_with_data(largest_first, proc(a, b: int, data: rawptr) -> bool {
			by_path := (^[]Format_Job)(data)
			size_a, size_b := by_path[a].size, by_path[b].size
			return size_a > size_b if size_a != size_b else a < b
		}, &jobs.by_path)

	config := Pool_Config(Format_Outcome) {
		commands    = make([][]string, len(by_path), work),
		working_dir = root,
		captured    = .Stdout,
		read        = read_format_end,
		timeout     = debug_timeout("ODX_FORMAT_TIMEOUT_MS", FORMAT_TIMEOUT),
		budget      = budget,
	}
	for job, pool_index in largest_first {
		jobs.by_path[job].pool_index = pool_index
		config.commands[pool_index] = slice.clone(
			[]string{odx, FORMAT_COMMAND, jobs.by_path[job].path},
			work,
		)
	}
	start_pool(&jobs.pool, config, work)
	return jobs
}

// Waits for the children, then adds each file's finding, or the error of the first file in path
// order that has one. A finding carries its note, so a held-back finding's note is held back too.
// The findings borrow their paths from `packages`. Allocates the notes and the error with
// `allocator`.
finish_format :: proc(
	jobs: ^Format_Jobs,
	packages: []Package,
	result: ^Result,
	allocator: runtime.Allocator,
) {
	join_pool(&jobs.pool)
	defer destroy_format(jobs)

	if jobs.error != "" {
		append(&result.errors, Error{.Format_Failed, strings.clone(jobs.error, allocator)})
		return
	}
	for job in jobs.by_path {
		finding := Finding {
			path = job.path,
			line = 1,
			col  = 1,
			rule = .Format,
		}
		switch outcome in jobs.pool.runs[job.pool_index] {
		case Formatted:
			continue
		case Differs:
			finding.line = outcome.first_differing_line
			finding.message = FORMAT_DIFFERS_MESSAGE
		case Refused:
			finding.message = FORMAT_REFUSED_MESSAGE
			finding.note = format_note(job.path, "formatter can't read the file", allocator)
		case Crashed:
			finding.message = FORMAT_CRASHED_MESSAGE
			finding.note = format_note(job.path, "formatter crashed", allocator)
		case Timed_Out:
			b := strings.builder_make(allocator)
			fmt.sbprintf(&b, "formatting '%s' ", job.path)
			write_timeout(&b, jobs.pool.timeout)
			append(&result.errors, Error{.Format_Timeout, strings.to_string(b)})
			return
		case Unreadable:
			message := fmt.aprintf(
				"odx can't read '%s' to check its format: %s",
				job.path,
				outcome.reason,
				allocator = allocator,
			)
			append(&result.errors, Error{.Format_Failed, message})
			return
		case Run_Failed:
			message := fmt.aprintf(
				"odx can't run the formatter process for '%s': %s",
				job.path,
				outcome.reason,
				allocator = allocator,
			)
			append(&result.errors, Error{.Format_Failed, message})
			return
		}
		add_rule_finding(result, &packages[job.pkg], finding)
	}
}

@(private = "file")
format_note :: proc(path, what: string, allocator: runtime.Allocator) -> string {
	return fmt.aprintf("odx: format: %s %s", path, what, allocator = allocator)
}

// Kills and reaps the running children instead of waiting for them, for a run that already has an
// error and so no use for a format result.
abandon_format :: proc(jobs: ^Format_Jobs) {
	kill_pool(&jobs.pool)
	join_pool(&jobs.pool)
	destroy_format(jobs)
}

@(private = "file")
destroy_format :: proc(jobs: ^Format_Jobs) {
	destroy_pool(&jobs.pool)
	virtual.arena_destroy(&jobs.work)
}

// A whole result line decides the outcome however the child then ended (Appendix E.7). Without one,
// a child that ended in any way is `Crashed`, except that one its own limit ended timed out: under
// load odx charges a slow poll less than it took, so the child's limit can run out first. A crash
// doesn't stop new prints. The outcomes that leave the run without a result do. The outcome may
// borrow from `end`.
read_format_end :: proc(
	end: Child_End,
	allocator: runtime.Allocator,
) -> (
	outcome: Format_Outcome,
	stop: bool,
) {
	if end.error != "" {
		return Run_Failed{end.error}, true
	}
	switch result in read_print_result(end.captured[.Stdout]) {
	case Formatted:
		return result, false
	case Differs:
		return result, false
	case Refused:
		return result, false
	case Unreadable:
		return result, true
	}
	if end.timed_out || end.status == (Signaled{int(posix.SIGALRM)}) {
		return Timed_Out{}, true
	}
	return Crashed{}, false
}

@(private = "file")
format_printer :: proc() -> Print_Proc {
	switch debug_env("ODX_FAKE_PRINTER") {
	case "slow":
		return proc(src: string) -> (out: string, ok: bool) {
				time.sleep(2 * time.Second)
				return print_source(src)
			}
	case "hang":
		return proc(src: string) -> (out: string, ok: bool) {
				for {
					time.sleep(time.Second)
				}
			}
	case "crash":
		return proc(src: string) -> (out: string, ok: bool) {
				intrinsics.trap()
			}
	}
	return print_source
}
