package odx

import "base:runtime"
import "core:fmt"
import "core:mem/virtual"
import "core:odin/ast"
import "core:odin/parser"
import "core:odin/tokenizer"
import "core:os"
import "core:strconv"
import "core:strings"
import "core:sync"
import si "core:sys/info"
import "core:thread"
import "core:time"

CHECK_TIMEOUT :: 120 * time.Second

STDERR_LINES_SHOWN :: 40

@(private = "file")
Check_Job :: struct {
	pkg:    int,
	target: Target,
}

@(private = "file")
Check_Run :: struct {
	outcome:   Check_Outcome,
	timed_out: bool,
}

// Each worker writes only its own arena and the `runs` slots of the jobs it takes, so `next` and
// `stop` are the only shared state.
@(private = "file")
Pool :: struct {
	commands: [][]string,
	runs:     []Check_Run,
	arenas:   []virtual.Arena,
	temp_dir: string,
	timeout:  time.Duration,
	next:     int,
	stop:     bool,
}

// Runs one `odin check` per package and target per Appendix E.4, then adds the `odin` findings and
// held-back warnings to `result` and marks muted packages. An untrusted check adds `compiler-output`
// instead. `odin` is the compiler's path, `odin_root` what `odin root` printed and `root` the repo
// root. Allocates what it adds with `allocator`.
compile :: proc(
	odin, odin_root, root: string,
	config: Config,
	packages: []Package,
	result: ^Result,
	allocator: runtime.Allocator,
) {
	jobs := make([dynamic]Check_Job, context.temp_allocator)
	for p, i in packages {
		for t in Target {
			if t in p.check_targets {
				append(&jobs, Check_Job{i, t})
			}
		}
	}
	if len(jobs) == 0 {
		return
	}

	work: virtual.Arena
	ensure(virtual.arena_init_growing(&work) == nil, "out of memory")
	defer virtual.arena_destroy(&work)
	scratch := virtual.arena_allocator(&work)

	code := make_code_map(root, odin_root, packages, config.vendored[:], scratch)

	temp_dir, temp_err := os.make_directory_temp("", "odx-check-*", scratch)
	if temp_err != nil {
		message := fmt.aprintf(
			"could not make a temp dir for compiler output: %s",
			os.error_string(temp_err),
			allocator = allocator,
		)
		append(&result.errors, Error{.Compiler_Output, message})
		return
	}
	defer os.remove_all(temp_dir)

	pool := Pool {
		commands = make([][]string, len(jobs), scratch),
		runs     = make([]Check_Run, len(jobs), scratch),
		arenas   = make([]virtual.Arena, worker_count(len(jobs)), scratch),
		temp_dir = temp_dir,
		timeout  = check_timeout(),
	}
	for job, i in jobs {
		dir := code.repo_root
		if packages[job.pkg].dir != "." {
			dir = fmt.aprintf("%s/%s", code.repo_root, packages[job.pkg].dir, allocator = scratch)
		}
		pool.commands[i] = check_command(odin, dir, packages[job.pkg], job.target, config, scratch)
	}
	run_pool(&pool)
	defer for &arena in pool.arenas {
		virtual.arena_destroy(&arena)
	}

	for run, i in pool.runs {
		if u, untrusted := run.outcome.(Untrusted); untrusted {
			job := jobs[i]
			message := compiler_output_message(
				packages[job.pkg].dir,
				job.target,
				u,
				run.timed_out,
				pool.timeout,
				allocator,
			)
			append(&result.errors, Error{.Compiler_Output, message})
			return
		}
	}

	foreign_decls := make(map[string][]Position, 0, scratch)
	redeclarations := make([dynamic]Redeclaration, scratch)
	for run, i in pool.runs {
		diagnostics, has := run.outcome.(Diagnostics)
		if !has {
			continue
		}
		checked := &packages[jobs[i].pkg]
		for entry in diagnostics.entries {
			if clashes_with_foreign_procedure(entry, &foreign_decls, scratch) {
				continue
			}
			placed := normalize(entry, code, checked^, scratch)
			if reports_name_conflict(entry, placed, packages) {
				continue
			}
			if mutes(entry.kind, placed, checked^) {
				checked.muted = true
			}
			if r, ok := read_redeclaration(entry, placed, code, scratch); ok {
				append(&redeclarations, r)
				continue
			}
			add_odin_finding(result, entry.kind, placed, code, allocator)
		}
	}
	for placed in settle_redeclarations(redeclarations[:], scratch) {
		add_odin_finding(result, .Error, placed, code, allocator)
	}
}

@(private = "file")
add_odin_finding :: proc(
	result: ^Result,
	kind: Entry_Kind,
	placed: Placed,
	code: Code_Map,
	allocator: runtime.Allocator,
) {
	placement := place(kind, placed.path, code)
	if placement == .Dropped {
		return
	}
	finding := Finding {
		path      = strings.clone(placed.path, allocator),
		line      = placed.line,
		col       = placed.col,
		rule      = .Odin,
		message   = strings.clone(placed.message, allocator),
		held_back = placement == .Held_Back,
	}
	append(&result.findings, finding)
}

// An importer's check blames whichever file the compiler read first, which differs between
// filesystems, so odx keeps only its own finding at the first disagreeing file in path order.
@(private = "file")
reports_name_conflict :: proc(entry: Compiler_Entry, placed: Placed, packages: []Package) -> bool {
	if !strings.has_prefix(entry.msgs[0], "Syntax Error: Different package name") {
		return false
	}
	dir := package_dir(placed.path)
	for p in packages {
		if p.name_conflict && p.dir == dir {
			return true
		}
	}
	return false
}

// Appendix E.4's command line. The package-scoped flags take the package's name, never its directory
// (probe R-C). Allocates with `allocator`.
check_command :: proc(
	odin, dir: string,
	pkg: Package,
	target: Target,
	config: Config,
	allocator: runtime.Allocator,
) -> []string {
	context.allocator = allocator
	args := make([dynamic]string)
	append(
		&args,
		odin,
		"check",
		dir,
		"-json-errors",
		"-max-error-count:1000000",
		"-thread-count:1",
		"-ignore-unused-defineables",
		fmt.aprintf("-target:%s", TARGETS[target].name),
	)
	if pkg.name != "main" {
		append(&args, "-no-entry-point")
	}
	for c in config.collections {
		append(&args, fmt.aprintf("-collection:%s=%s", c.name, c.path))
	}
	for d in config.defines {
		append(&args, fmt.aprintf("-define:%s=%s", d.name, d.value))
	}
	if pkg.status == .Strict {
		append(
			&args,
			"-vet",
			"-vet-cast",
			"-strict-style",
			fmt.aprintf("-vet-packages:%s", pkg.name),
			fmt.aprintf("-strict-style-packages:%s", pkg.name),
		)
	}
	return args[:]
}

// One heavy check can peak at 600 MB (probe R-G), so the pool never runs more checks than there are
// gigabytes of RAM.
@(private = "file")
worker_count :: proc(jobs: int) -> int {
	n := os.get_processor_core_count()
	if total, _, _, _, ok := si.ram_stats(); ok {
		n = min(n, int(total / (1 << 30)))
	}
	return clamp(n, 1, jobs)
}

@(private = "file")
check_timeout :: proc() -> time.Duration {
	text := ""
	when ODIN_DEBUG {
		// Golden cases test the timeout without waiting two minutes. Release builds ignore this, so a
		// shipped result can't depend on the environment.
		text = os.get_env("ODX_CHECK_TIMEOUT_MS", context.temp_allocator)
	}
	if ms, ok := strconv.parse_int(text, 10); ok && ms > 0 {
		return time.Duration(ms) * time.Millisecond
	}
	return CHECK_TIMEOUT
}

@(private = "file")
run_pool :: proc(pool: ^Pool) {
	threads := make([]^thread.Thread, len(pool.arenas), context.temp_allocator)
	for &arena, i in pool.arenas {
		ensure(virtual.arena_init_growing(&arena) == nil, "out of memory")
		threads[i] = thread.create_and_start_with_poly_data2(pool, i, check_worker)
	}
	thread.join_multiple(..threads)
	for t in threads {
		thread.destroy(t)
	}
}

// Takes jobs in order, so every job before the last one started has run. An untrusted outcome stops
// new checks and lets the running ones finish.
@(private = "file")
check_worker :: proc(pool: ^Pool, worker: int) {
	allocator := virtual.arena_allocator(&pool.arenas[worker])
	for !sync.atomic_load(&pool.stop) {
		job := sync.atomic_add(&pool.next, 1)
		if job >= len(pool.commands) {
			break
		}
		stderr_path := fmt.aprintf("%s/%d.stderr", pool.temp_dir, job, allocator = allocator)
		run := run_check(pool.commands[job], stderr_path, pool.timeout, allocator)
		pool.runs[job] = run
		if _, untrusted := run.outcome.(Untrusted); untrusted {
			sync.atomic_store(&pool.stop, true)
		}
	}
}

// Stderr goes to a named file, because `os.create_temp_file` captured nothing in the reader probe
// (Appendix C).
@(private = "file")
run_check :: proc(
	command: []string,
	stderr_path: string,
	timeout: time.Duration,
	allocator: runtime.Allocator,
) -> (
	run: Check_Run,
) {
	file, create_err := os.create(stderr_path)
	if create_err != nil {
		reason := fmt.aprintf(
			"couldn't capture stderr: %s",
			os.error_string(create_err),
			allocator = allocator,
		)
		return {outcome = Untrusted{reason, ""}}
	}
	process, start_err := os.process_start({command = command, stderr = file})
	os.close(file)
	if start_err != nil {
		reason := fmt.aprintf(
			"couldn't start: %s",
			os.error_string(start_err),
			allocator = allocator,
		)
		return {outcome = Untrusted{reason, ""}}
	}
	state, wait_err := os.process_wait(process, timeout)
	if wait_err == os.General_Error.Timeout {
		run.timed_out = true
		_ = os.process_kill(process)
		state, wait_err = os.process_wait(process)
	}
	if wait_err != nil {
		reason := fmt.aprintf(
			"couldn't be waited for: %s",
			os.error_string(wait_err),
			allocator = allocator,
		)
		return {outcome = Untrusted{reason, ""}, timed_out = run.timed_out}
	}
	stderr, read_err := os.read_entire_file(stderr_path, allocator)
	if read_err != nil {
		reason := fmt.aprintf(
			"couldn't read its stderr: %s",
			os.error_string(read_err),
			allocator = allocator,
		)
		return {outcome = Untrusted{reason, ""}, timed_out = run.timed_out}
	}
	run.outcome = read_check(state.exit_code, run.timed_out, string(stderr), allocator)
	return
}

// Names the package, the target and the exit code or the timeout, then the last lines of stderr,
// where a crash leaves its assertion.
@(private = "file")
compiler_output_message :: proc(
	dir: string,
	target: Target,
	u: Untrusted,
	timed_out: bool,
	timeout: time.Duration,
	allocator: runtime.Allocator,
) -> string {
	b := strings.builder_make(allocator)
	fmt.sbprintf(&b, "checking '%s' for %s ", dir, TARGETS[target].name)
	if timed_out {
		if timeout % time.Second == 0 {
			fmt.sbprintf(&b, "timed out after %d s", int(timeout / time.Second))
		} else {
			fmt.sbprintf(&b, "timed out after %d ms", int(timeout / time.Millisecond))
		}
	} else {
		strings.write_string(&b, u.reason)
	}
	text := strings.trim_right(u.stderr, "\r\n")
	if text == "" {
		strings.write_string(&b, "; stderr was empty")
		return strings.to_string(b)
	}
	lines := strings.split_lines(text, context.temp_allocator)
	if len(lines) > STDERR_LINES_SHOWN {
		fmt.sbprintf(&b, "; the last %d of its %d stderr lines:", STDERR_LINES_SHOWN, len(lines))
		lines = lines[len(lines) - STDERR_LINES_SHOWN:]
	} else {
		strings.write_string(&b, "; stderr:")
	}
	for line in lines {
		fmt.sbprintf(&b, "\n\t%s", line)
	}
	return strings.to_string(b)
}

Position :: struct {
	line: int,
	col:  int,
}

// A definition whose link name a foreign procedure also declares is not an error. The compiler
// reports it only when it happens to check the foreign declaration first (src/check_decl.cpp:1656
// and :1262), so odx drops it every time, using its own AST at the "other at" position. `foreign_decls`
// caches each file's foreign procedure names.
clashes_with_foreign_procedure :: proc(
	entry: Compiler_Entry,
	foreign_decls: ^map[string][]Position,
	allocator: runtime.Allocator,
) -> bool {
	if entry.kind != .Error || !strings.has_prefix(entry.msgs[0], "Non unique linking name") {
		return false
	}
	for m in entry.msgs[1:] {
		line := strings.trim_space(m)
		other, ok := split_located(strings.trim_prefix(line, "other at "))
		if !ok || !strings.has_prefix(line, "other at ") {
			continue
		}
		decls, cached := foreign_decls[other.path]
		if !cached {
			decls = foreign_procedure_names(other.path, allocator)
			foreign_decls[other.path] = decls
		}
		for d in decls {
			if d == {other.line, other.col} {
				return true
			}
		}
	}
	return false
}

// The position of each name a `foreign` block declares as a procedure, with code-point columns as
// the compiler counts them. Empty when the file can't be read.
@(private = "file")
foreign_procedure_names :: proc(path: string, allocator: runtime.Allocator) -> []Position {
	context.allocator = allocator
	data, err := os.read_entire_file(path, allocator)
	if err != nil {
		return nil
	}
	file := ast.File {
		src      = string(data),
		fullpath = path,
	}
	p := parser.default_parser()
	p.err = proc(pos: tokenizer.Pos, msg: string, args: ..any) {}
	p.warn = nil
	parser.parse_file(&p, &file)

	names := make([dynamic]Position)
	for decl in file.decls {
		collect_foreign_procedures(decl, file.src, false, &names)
	}
	return names[:]
}

// Foreign blocks often sit inside file-scope `when` statements, as in `core:c/libc`.
@(private = "file")
collect_foreign_procedures :: proc(
	stmt: ^ast.Stmt,
	src: string,
	in_foreign: bool,
	names: ^[dynamic]Position,
) {
	if stmt == nil {
		return
	}
	#partial switch s in stmt.derived_stmt {
	case ^ast.Foreign_Block_Decl:
		collect_foreign_procedures(s.body, src, true, names)
	case ^ast.Block_Stmt:
		for inner in s.stmts {
			collect_foreign_procedures(inner, src, in_foreign, names)
		}
	case ^ast.When_Stmt:
		collect_foreign_procedures(s.body, src, in_foreign, names)
		collect_foreign_procedures(s.else_stmt, src, in_foreign, names)
	case ^ast.Value_Decl:
		// In a foreign block, only a procedure declaration has a value.
		if !in_foreign || len(s.values) == 0 {
			return
		}
		for name in s.names {
			line, col := text_position(src, name.pos.offset)
			append(names, Position{line, col})
		}
	}
}
