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
}

// Runs `odin check` per package and target per Appendix E.4, twice for a pending package per
// Appendix E.7, then adds the `odin` findings to `result` and marks muted packages. An untrusted check
// adds `compiler-output` instead. `odin` is the compiler's path, `odin_root` what `odin root` printed
// and `root` the repo root. The checks' stderr goes to files in `temp_dir`, and they run within
// `budget`. Allocates what it adds with `allocator`.
compile :: proc(
	odin, odin_root, root, temp_dir: string,
	config: Config,
	packages: []Package,
	budget: ^Child_Budget,
	result: ^Result,
	allocator: runtime.Allocator,
) {
	jobs := make([dynamic]Check_Job, context.temp_allocator)
	for p, i in packages {
		for t in Target {
			if t in p.check_targets {
				if p.status == .Pending {
					append(&jobs, Check_Job{pkg = i, target = t, strict = false})
				}
				append(&jobs, Check_Job{pkg = i, target = t, strict = true})
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

	pool_config := Pool_Config(Check_Run) {
		commands = make([][]string, len(jobs), scratch),
		captured = .Stderr,
		read     = read_check_end,
		temp_dir = temp_dir,
		timeout  = debug_timeout("ODX_CHECK_TIMEOUT_MS", CHECK_TIMEOUT),
		budget   = budget,
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
	pool: Pool(Check_Run)
	start_pool(&pool, pool_config, scratch)
	join_pool(&pool)
	defer destroy_pool(&pool)

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
		pending_strict := jobs[i].strict && checked.status == .Pending
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
			owner, kept := owner_of(entry.kind, placed.path, code)
			if !kept {
				continue
			}
			if pending_strict && owner == nil {
				owner = checked
			}
			finding := odin_finding(placed, allocator)
			finding.held_back = pending_strict
			add_rule_finding(result, owner, finding, entry.kind == .Warning)
		}
	}
	for placed in settle_redeclarations(redeclarations[:], scratch) {
		owner, _ := owner_of(.Error, placed.path, code)
		add_rule_finding(result, owner, odin_finding(placed, allocator), false)
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
		append(
			&args,
			"-vet",
			"-vet-cast",
			"-strict-style",
			fmt.aprintf("-vet-packages:%s", pkg.name),
			fmt.aprintf("-strict-style-packages:%s", pkg.name),
		)
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
	run.timed_out = end.timed_out
	if end.failure != "" {
		run.outcome = Untrusted{end.failure, ""}
	} else {
		run.outcome = read_check(end.exit_code, end.timed_out, end.captured, allocator)
	}
	_, stop = run.outcome.(Untrusted)
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
		write_timeout(&b, timeout)
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
