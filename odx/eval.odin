package odx

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:slice"
import "core:strconv"
import "core:strings"
import "core:time"

// `odx eval` (M6.1): does any of this work? Each evals/<task>/ holds prompt.md, score_test.odin
// and an optional start/ tree. Every task runs under three conditions in a scratch project:
//   bare   the prompt alone
//   for    the prompt with `odx for task` output injected first
//   hook   the prompt with the odx hooks wired into .claude/settings.json (the loop)
// The model is `claude -p`; scoring is mechanical: compiles, tests pass, violations left, turns.
// Results append to evals/results.tsv; --report aggregates them per condition.
// ponytail: one model, one driver, one table. Enough to decide M6.2; not a benchmark suite.

EVALS_DIR :: "evals"
RESULTS_FILE :: "evals/results.tsv"
EVAL_PACKAGE :: "task"
CONDITIONS := []string{"bare", "for", "hook"}

Eval_Row :: struct {
	task, cond:           string,
	compiled, tests_pass: bool,
	violations, turns:    int,
	seconds:              int,
}

cmd_eval :: proc(o: Opts) {
	root := find_root(o.root)
	if root == "" {fail("no %s found; run from the odx repo", CONFIG_FILE)}
	if o.report {
		eval_report(root)
		return
	}
	odx_bin, _ := filepath.abs(os.args[0])
	tasks := project_subdirs(root, EVALS_DIR)
	if len(tasks) == 0 {fail("no tasks under %s", EVALS_DIR)}
	for want in o.args {
		known := false
		for t in tasks {known ||= t.name == want}
		if !known {fail("no task %q under %s", want, EVALS_DIR)}
	}
	conds := CONDITIONS
	if len(o.topics) > 0 {conds = o.topics[:]} 	// --topic reused as --condition (ponytail: one list flag)
	for t in tasks {
		if len(o.args) > 0 && !slice.contains(o.args[:], t.name) {continue}
		for cond in conds {
			if !slice.contains(
				CONDITIONS,
				cond,
			) {fail("unknown condition %q (bare, for, hook)", cond)}
			row := run_eval(root, odx_bin, t.fullpath, t.name, cond)
			line := fmt.tprintf(
				"%s\t%s\t%v\t%v\t%d\t%d\t%d",
				row.task,
				row.cond,
				row.compiled,
				row.tests_pass,
				row.violations,
				row.turns,
				row.seconds,
			)
			fmt.println(line)
			append_line(join({root, RESULTS_FILE}), line)
		}
	}
}

run_eval :: proc(root, odx_bin, task_dir, task, cond: string) -> (row: Eval_Row) {
	row.task, row.cond = task, cond
	work := join({root, ".odx", "cache", "eval", task, cond})
	os.remove_all(work)
	os.make_directory_all(join({work, EVAL_PACKAGE}))
	copy_dir(join({task_dir, "start"}), join({work, EVAL_PACKAGE}))
	// an empty directory is not a package: the role glob would match nothing and every odx
	// call in the work tree would fail. Seed the package clause; the model overwrites it.
	if !os.exists(join({work, EVAL_PACKAGE, EVAL_PACKAGE + ".odin"})) {
		if werr := os.write_entire_file(
			join({work, EVAL_PACKAGE, EVAL_PACKAGE + ".odin"}),
			transmute([]byte)string("package " + EVAL_PACKAGE + "\n"),
		); werr != nil {fail("write: %v", werr)}
	}
	cfg, cerr := os.read_entire_file(join({task_dir, CONFIG_FILE}), context.allocator)
	if cerr != nil {cfg = transmute([]byte)string(EVAL_CONFIG)}
	if werr := os.write_entire_file(join({work, CONFIG_FILE}), cfg);
	   werr != nil {fail("write: %v", werr)}
	prompt_b, perr := os.read_entire_file(join({task_dir, "prompt.md"}), context.allocator)
	if perr != nil {fail("%s: no prompt.md", task_dir)}
	prompt := fmt.tprintf(
		"Work in the directory %s. Write the package `%s` in ./%s/ as specified. Do not write tests. When done, stop.\n\n%s",
		work,
		EVAL_PACKAGE,
		EVAL_PACKAGE,
		string(prompt_b),
	)
	switch cond {
	case "for":
		st, out, eb, _ := os.process_exec(
			{command = {odx_bin, "for", join({work, EVAL_PACKAGE}), "--root", work}},
			context.allocator,
		)
		if st.exit_code !=
		   0 {fail("%s/%s: `odx for` failed; the condition would be bare plus an error line: %s%s", task, cond, string(out), string(eb))}
		prompt = fmt.tprintf(
			"%s\n\nConventions that apply to this package (from `odx for`):\n%s",
			prompt,
			string(out),
		)
	case "hook":
		os.make_directory_all(join({work, ".claude"}))
		if werr := os.write_entire_file(
			join({work, ".claude", "settings.json"}),
			transmute([]byte)eval_hooks(odx_bin),
		); werr != nil {fail("write: %v", werr)}
	}
	start := time.now()
	state, out, errb, err := os.process_exec(
		{
			command = {
				"claude",
				"-p",
				prompt,
				"--output-format",
				"json",
				"--dangerously-skip-permissions",
			},
			working_dir = work,
		},
		context.allocator,
	)
	row.seconds = int(time.duration_seconds(time.since(start)))
	_ = errb
	res: struct {
		num_turns:       int,
		terminal_reason: string,
	}
	_ = json.unmarshal(out, &res)
	row.turns = res.num_turns
	if err != nil || state.exit_code != 0 || res.terminal_reason == "hook_stopped" {
		fail(
			"%s/%s: the session did not finish (%v, exit %d, terminal_reason %q); no row written",
			task,
			cond,
			err,
			state.exit_code,
			res.terminal_reason,
		)
	}
	if werr := os.write_entire_file(join({work, "transcript.json"}), out);
	   werr != nil {fail("write: %v", werr)}
	// score: odx's count first, on the model's files only (the scoring test is copied in after
	// and would otherwise be counted against the model); then compile, then tests. The seeded
	// placeholder, if the model wrote a differently named file and left it, is not the model's.
	if ph := join({work, EVAL_PACKAGE, EVAL_PACKAGE + ".odin"}); os.exists(ph) {
		if data, rerr := os.read_entire_file(ph, context.allocator);
		   rerr == nil && string(data) == "package " + EVAL_PACKAGE + "\n" {os.remove(ph)}
	}
	_, vout, _, _ := os.process_exec(
		{command = {odx_bin, "check", "--json", "--root", work}},
		context.allocator,
	)
	n, ok := parse_check_json(vout)
	if !ok {fail("%s/%s: `odx check --json` did not return a report (a tool error must never score as clean): %s", task, cond, string(vout))}
	row.violations = n
	pkg := join({work, EVAL_PACKAGE})
	copy_file(join({task_dir, "score_test.odin"}), join({pkg, "score_test.odin"}))
	cs, _, _, _ := os.process_exec(
		{
			command = {
				"odin",
				"check",
				pkg,
				"-no-entry-point",
				"-vet",
				"-vet-cast",
				"-strict-style",
			},
		},
		context.allocator,
	)
	row.compiled = cs.exit_code == 0
	if row.compiled {
		ts, _, _, _ := os.process_exec(
			{
				command = {
					"odin",
					"test",
					pkg,
					strings.concatenate({"-out:", work, "/eval_test"}, context.temp_allocator),
					"-define:ODIN_TEST_FAIL_ON_BAD_MEMORY=true",
				},
				working_dir = work,
			},
			context.allocator,
		)
		row.tests_pass = ts.exit_code == 0
	}
	return
}

// ponytail: a plain constant, not a format string: Odin's fmt treats `{` as a verb (the first
// pilot scored every row 0 violations against a config that read MISSING CLOSE BRACE).
EVAL_CONFIG :: `{ version: 1, roles: { pure: ["task"] }, dependencies: { pure: { may_import: ["pure", "core:*"] } },
  odin: { flags: ["-vet", "-vet-cast", "-strict-style"] } }
`

// eval_hooks: the Stop hook only. In headless `claude -p` a PostToolBatch exit 2 ends the
// session ("terminal_reason": "hook_stopped") instead of feeding the text back; the Stop hook
// blocks and continues, which is the loop M6 measures.
eval_hooks :: proc(odx_bin: string) -> string {
	return fmt.tprintf(
		`{"hooks": {"Stop": [{"hooks": [{"type": "command", "command": "%s hook stop"}]}]}}
`,
		odx_bin,
	)
}

// parse_check_json: the violation count from `odx check --json`; ok is false for anything
// that is not a report (a tool error on stderr/stdout, an empty run).
parse_check_json :: proc(out: []byte) -> (n: int, ok: bool) {
	rep: Report
	if json.unmarshal(out, &rep) != nil || rep.schema == 0 {return 0, false}
	return rep.summary.errors + rep.summary.warnings, true
}

eval_report :: proc(root: string) {
	data, err := os.read_entire_file(join({root, RESULTS_FILE}), context.allocator)
	if err != nil {fail("no %s yet; run `odx eval` first", RESULTS_FILE)}
	Agg :: struct {
		n, compiled, tests, violations, turns: int,
	}
	agg := make(map[string]Agg, context.temp_allocator)
	tasks := make(map[string]bool, context.temp_allocator)
	for line in strings.split_lines(string(data), context.temp_allocator) {
		f := strings.split(line, "\t", context.temp_allocator)
		if len(f) < 7 {continue}
		a := agg[f[1]]
		a.n += 1
		if f[2] == "true" {a.compiled += 1}
		if f[3] == "true" {a.tests += 1}
		a.violations += must_int(f[4])
		a.turns += must_int(f[5])
		agg[f[1]] = a
		tasks[f[0]] = true
	}
	fmt.printfln(
		"%d tasks, %s (latest row per task/condition is NOT deduplicated; regen the file for a clean run)\n",
		len(tasks),
		RESULTS_FILE,
	)
	fmt.println("| condition | runs | compiled | tests pass | violations/run | turns/run |")
	fmt.println("|---|---|---|---|---|---|")
	for cond in CONDITIONS {
		a, ok := agg[cond]
		if !ok || a.n == 0 {continue}
		fmt.printfln(
			"| %s | %d | %d | %d | %.1f | %.1f |",
			cond,
			a.n,
			a.compiled,
			a.tests,
			f64(a.violations) / f64(a.n),
			f64(a.turns) / f64(a.n),
		)
	}
}

copy_dir :: proc(src, dst: string) {
	w := os.walker_create_path(src)
	defer os.walker_destroy(&w)
	for fi in os.walker_walk(&w) {
		if fi.type != .Regular {continue}
		rel, _ := rel_of(src, fi.fullpath)
		copy_file(fi.fullpath, join({dst, rel}))
	}
}

copy_file :: proc(src, dst: string) {
	data, err := os.read_entire_file(src, context.allocator)
	if err != nil {return}
	os.make_directory_all(filepath.dir(dst))
	if werr := os.write_entire_file(dst, data); werr != nil {fail("write: %v", werr)}
}

must_int :: proc(s: string) -> int {
	n, _ := strconv.parse_int(s)
	return n
}

// append_line: read-modify-write; the results file is small and one eval runs at a time.
append_line :: proc(path, line: string) {
	old, _ := os.read_entire_file(path, context.allocator)
	if werr := os.write_entire_file(
		path,
		transmute([]byte)strings.concatenate({string(old), line, "\n"}),
	); werr != nil {fail("write %s: %v", path, werr)}
}
