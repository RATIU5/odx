package odx

import "base:runtime"
import "core:fmt"
import "core:mem/virtual"
import "core:odin/ast"
import "core:odin/parser"
import "core:odin/tokenizer"
import "core:os"
import "core:strings"
import "core:time"

CHECK_TIMEOUT :: 120 * time.Second

// A message that quotes a child's stderr shows at most this much of its end, where a crash leaves
// its assertion.
STDERR_LINES_SHOWN :: 40

@(private = "file")
Check_Job :: struct {
	pkg:    int,
	target: Target,
	strict: bool,
}

@(private = "file")
Check_Run :: struct {
	outcome:   Check_Outcome,
	timed_out: bool,
	retried:   bool,
}

// Every check child of one `odx check`. The jobs, the code map and the pool's lists live in `work`.
Check_Jobs :: struct {
	jobs: []Check_Job,
	code: Code_Map,
	pool: Pool(Check_Run),
	work: virtual.Arena,
}

// Starts `odin check` per package and target per Appendix E.4, twice for a pending package per
// Appendix E.7, and returns without waiting. `finish_compile` must follow. `odin` is the compiler's
// path, `odin_root` what `odin root` printed and `root` the repo root. The checks run within
// `budget`, and a check that the compiler's own crash ended runs once more. Allocates the jobs with
// `allocator`.
start_compile :: proc(
	odin, odin_root, root: string,
	config: Config,
	packages: []Package,
	budget: ^Child_Budget,
	allocator: runtime.Allocator,
) -> ^Check_Jobs {
	checks := new(Check_Jobs, allocator)
	ensure(virtual.arena_init_growing(&checks.work) == nil, "out of memory")
	scratch := virtual.arena_allocator(&checks.work)

	jobs := make([dynamic]Check_Job, scratch)
	for p, i in packages {
		compiled, _ := p.compile.(Compiled)
		for t in Target {
			if t in compiled.targets {
				if p.status == .Pending {
					append(&jobs, Check_Job{pkg = i, target = t, strict = false})
				}
				append(&jobs, Check_Job{pkg = i, target = t, strict = true})
			}
		}
	}
	checks.jobs = jobs[:]
	if len(jobs) == 0 {
		return checks
	}

	code := make_code_map(root, odin_root, packages, config.vendored[:], scratch)
	checks.code = code

	pool_config := Pool_Config(Check_Run) {
		commands       = make([][]string, len(jobs), scratch),
		captured       = .Stderr,
		retry_signaled = true,
		read           = read_check_end,
		timeout        = debug_timeout("ODX_CHECK_TIMEOUT_MS", CHECK_TIMEOUT),
		budget         = budget,
	}
	for job, i in jobs {
		dir := code.repo_root
		if packages[job.pkg].dir != "." {
			dir = fmt.aprintf("%s/%s", code.repo_root, packages[job.pkg].dir, allocator = scratch)
		}
		pool_config.commands[i] = check_command(
			odin,
			dir,
			packages[job.pkg],
			job.target,
			job.strict,
			config,
			scratch,
		)
	}
	start_pool(&checks.pool, pool_config, scratch)
	return checks
}

// Waits for the checks, then adds the `odin` findings to `result`, counts the checks that ran
// twice and marks muted packages. An untrusted check adds `compiler-output` instead. `packages` is
// the slice `start_compile` took. Allocates what it adds with `allocator`.
finish_compile :: proc(
	checks: ^Check_Jobs,
	packages: []Package,
	result: ^Result,
	allocator: runtime.Allocator,
) {
	join_pool(&checks.pool)
	defer {
		destroy_pool(&checks.pool)
		virtual.arena_destroy(&checks.work)
	}
	jobs, code, pool := checks.jobs, checks.code, &checks.pool
	scratch := virtual.arena_allocator(&checks.work)

	// An untrusted check ends the run, and the runs before it still count.
	for run in pool.runs {
		result.compiler_retries += int(run.retried)
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
	duplicates := make([dynamic]Duplicate_Package, scratch)
	// The package whose check gave each of `duplicates`.
	duplicate_checks := make([dynamic]int, scratch)
	for run, i in pool.runs {
		outcome, has := run.outcome.(Entries)
		if !has {
			continue
		}
		checked := &packages[jobs[i].pkg]
		pending_strict := jobs[i].strict && checked.status == .Pending
		for entry in outcome.entries {
			if clashes_with_foreign_procedure(entry, &foreign_decls, scratch) {
				continue
			}
			placed := normalize(entry, code, checked^, scratch)
			if reports_name_conflict(entry, placed, packages) {
				continue
			}
			if d, ok := read_duplicate_package(entry, placed, code, scratch); ok {
				append(&duplicates, d)
				append(&duplicate_checks, jobs[i].pkg)
				continue
			}
			if mutes(entry.kind, placed, checked^) {
				checked.muted = true
			}
			if r, ok := read_redeclaration(entry, placed, code, scratch); ok {
				append(&redeclarations, r)
				continue
			}
			owner, kept := owner_of(entry.kind, placed.path, code)
			if !kept {
				continue
			}
			if pending_strict && owner == nil {
				owner = checked
			}
			finding := odin_finding(placed, allocator)
			// Only strict checking gives a warning, and `owner_of` keeps none without an owner.
			finding.held_back =
				pending_strict || (entry.kind == .Warning && owner.status == .Pending)
			add_rule_finding(result, owner, finding)
		}
	}
	for placed in settle_redeclarations(redeclarations[:], scratch) {
		owner, _ := owner_of(.Error, placed.path, code)
		add_rule_finding(result, owner, odin_finding(placed, allocator))
	}
	settled, settled_of := settle_duplicate_packages(duplicates[:], scratch)
	for placed in settled {
		owner, _ := owner_of(.Error, placed.path, code)
		add_rule_finding(result, owner, odin_finding(placed, allocator))
	}
	// A check mutes its package by the site odx reports, not the one the compiler happened to.
	for pkg, i in duplicate_checks {
		if mutes(.Error, settled[settled_of[i]], packages[pkg]) {
			packages[pkg].muted = true
		}
	}
}

@(private = "file")
odin_finding :: proc(placed: Placed, allocator: runtime.Allocator) -> Finding {
	return Finding {
		path = strings.clone(placed.path, allocator),
		line = placed.line,
		col = placed.col,
		rule = .Odin,
		message = strings.clone(placed.message, allocator),
	}
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
		if _, conflict := p.compile.(Name_Conflict); conflict && p.dir == dir {
			return true
		}
	}
	return false
}

// Appendix E.4's command line. The package-scoped flags take the package's name, never its
// directory (probe R-C), and are left out for a package no file names. Allocates with `allocator`.
check_command :: proc(
	odin, dir: string,
	pkg: Package,
	target: Target,
	strict: bool,
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
	if strict {
		append(&args, "-vet", "-vet-cast", "-strict-style")
		// The compiler rejects either flag with an empty name before it reads a file.
		if pkg.name != "" {
			append(
				&args,
				fmt.aprintf("-vet-packages:%s", pkg.name),
				fmt.aprintf("-strict-style-packages:%s", pkg.name),
			)
		}
	} else {
		append(&args, "-ignore-warnings")
	}
	return args[:]
}

@(private = "file")
read_check_end :: proc(
	end: Child_End,
	allocator: runtime.Allocator,
) -> (
	run: Check_Run,
	stop: bool,
) {
	run.timed_out, run.retried = end.timed_out, end.retried
	if end.error != "" {
		run.outcome = Untrusted {
			reason = end.error,
			unread = true,
		}
	} else {
		run.outcome = read_check(
			end.status,
			end.timed_out,
			end.retried,
			end.captured[.Stderr],
			allocator,
		)
	}
	_, stop = run.outcome.(Untrusted)
	return
}

// Names the package, the target and the exit code, the signal or the timeout, then the last lines
// of stderr, where a crash leaves its assertion.
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
		write_timeout(&b, timeout)
	} else {
		strings.write_string(&b, u.reason)
	}
	if !u.unread {
		write_stderr_tail(&b, u.stderr)
	}
	return strings.to_string(b)
}

// Writes the end of what a child wrote to stderr, within `STDERR_LINES_SHOWN`, after a header that
// says how much came before it. This is the one place a message quotes a child's stream.
write_stderr_tail :: proc(b: ^strings.Builder, stderr: string) {
	text := strings.trim_right(stderr, "\r\n")
	if text == "" {
		strings.write_string(b, "; stderr was empty")
		return
	}
	start, line_count := 0, 1
	for i := len(text) - 1; i >= 0; i -= 1 {
		if text[i] == '\n' {
			if line_count == STDERR_LINES_SHOWN && start == 0 {
				start = i + 1
			}
			line_count += 1
		}
	}
	if start > 0 {
		fmt.sbprintf(b, "; the last %d of its %d stderr lines:", STDERR_LINES_SHOWN, line_count)
	} else {
		strings.write_string(b, "; stderr:")
	}
	for line in strings.split_lines(text[start:], context.temp_allocator) {
		fmt.sbprintf(b, "\n\t%s", line)
	}
}

Position :: struct {
	line: int,
	col:  int,
}

// A definition whose link name a foreign procedure also declares is not an error. The compiler
// reports it only when it happens to check the foreign declaration first (src/check_decl.cpp:1656
// and :1262), so odx drops it every time, using its own AST at the "other at" position.
// `foreign_decls` caches each file's foreign procedure names.
clashes_with_foreign_procedure :: proc(
	entry: Compiler_Entry,
	foreign_decls: ^map[string][]Position,
	allocator: runtime.Allocator,
) -> bool {
	if entry.kind != .Error || !strings.has_prefix(entry.msgs[0], "Non-unique linking name") {
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
	if disk_kind(path) == .Special {
		return nil
	}
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
