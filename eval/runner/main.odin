// Eval runner for HARNESS.md: one row per (task, condition, sample), appended as JSONL.
// Nothing aggregates here; analysis is a separate pass over raw rows (eval/PREREG.md).
package eval

import "core:encoding/json"
import "core:flags"
import "core:fmt"
import "core:mem/virtual"
import "core:os"
import "core:path/filepath"
import "core:slice"
import "core:strings"
import "core:time"

Condition :: enum {
	C0,
	C1,
	C2,
	C3,
	C4,
}

// Conditions differ only in these switches; one loop serves all five (HARNESS.md §2).
Traits :: struct {
	block:    bool, // `odx policy` text resident as the system prompt
	findings: bool, // `odx check` findings appended to each revision turn
	resample: bool, // repeat whole C0 episodes up to the matching C3 run's token spend
}

TRAITS :: [Condition]Traits {
	.C0 = {},
	.C1 = {block = true},
	.C2 = {findings = true},
	.C3 = {block = true, findings = true},
	.C4 = {resample = true},
}

REVISIONS :: 3 // fixed: every episode is one generation plus exactly this many revision turns
MAX_TOKENS :: 32000
TEST_TIMEOUT :: 60 * time.Second
API_URL :: "https://api.anthropic.com/v1/messages"

Options :: struct {
	model:     string `args:"required" usage:"pinned model ID, recorded in every row"`,
	condition: Condition `args:"required" usage:"C0, C1, C2, C3 or C4"`,
	tasks:     string `usage:"task family directory (default eval/tasks/a)"`,
	task:      string `usage:"run only this task id"`,
	samples:   int `usage:"samples per task (default 5)"`,
	effort:    string `usage:"output_config.effort (default high)"`,
	budget:    string `usage:"C3 results JSONL supplying C4 token budgets"`,
	agent:     string `usage:"api (default), or reference: replay solution.odin with no model, validating tasks and the pipeline"`,
	odx:       string `usage:"odx binary (default build/odx)"`,
	run_id:    string `usage:"default: unix time"`,
	out:       string `usage:"JSONL appended to (default eval/results/<run_id>.jsonl)"`,
	keep:      bool `usage:"keep worktrees for inspection"`,
}

Row :: struct {
	run_id, task, condition, model, effort, agent: string,
	odin_version, odx_commit:                      string,
	sample:                                        int,
	compiles, tests_pass, edit_applied:            bool,
	odx_errors, odx_warnings:                      int,
	tokens_in, tokens_out, turns, episodes:        int,
	budget_tokens:                                 int,
	wall_ms:                                       i64,
	tool_error:                                    string, // non-empty: excluded from analysis, never scored as failure
}

Task :: struct {
	id, dir, prompt, start, solution, test: string,
}

Agent :: struct {
	opts:                         Options,
	headers:                      string, // curl header file holding the API key
	scratch:                      string,
	system:                       string,
	messages:                     [dynamic]Message,
	tokens_in, tokens_out, turns: int,
}

Message :: struct {
	role:    string,
	content: json.Value, // assistant content goes back verbatim, thinking blocks included
}

Outcome :: struct {
	compiles, tests_pass, edit_applied: bool,
	odx_errors, odx_warnings:           int,
}

Error :: Maybe(string) // a tool error: the run is recorded but excluded

main :: proc() {
	o: Options
	flags.parse_or_exit(&o, os.args, .Unix)
	if o.tasks == "" {o.tasks = "eval/tasks/a"}
	if o.samples == 0 {o.samples = 5}
	if o.effort == "" {o.effort = "high"}
	if o.agent == "" {o.agent = "api"}
	if o.odx == "" {o.odx = "build/odx"}
	if o.run_id == "" {o.run_id = fmt.aprint(time.time_to_unix(time.now()))}
	if o.out == "" {o.out = fmt.aprintf("eval/results/%s.jsonl", o.run_id)}
	if o.agent != "api" && o.agent != "reference" {die("--agent must be api or reference")}
	odx, aerr := filepath.abs(o.odx, context.allocator)
	if aerr != nil || !os.exists(odx) {die("odx binary not found: %s (mise run build)", o.odx)}
	o.odx = odx
	traits := TRAITS
	tr := traits[o.condition]

	budgets: map[string]int
	if tr.resample {
		if o.budget == "" {die("C4 needs --budget <C3 results.jsonl>")}
		budgets = load_budgets(o.budget, o.model)
	}

	scratch, terr := os.make_directory_temp("", "odx-eval-*", context.allocator)
	if terr != nil {die("temp dir: %v", terr)}
	defer os.remove_all(scratch)
	a := Agent {
		opts    = o,
		scratch = scratch,
	}
	if o.agent == "api" {
		key := os.get_env("ANTHROPIC_API_KEY", context.allocator)
		if key == "" {die("ANTHROPIC_API_KEY is not set")}
		// A header file keeps the key out of the process list.
		a.headers = join(scratch, "headers")
		hdr := fmt.tprintf(
			"x-api-key: %s\ncontent-type: application/json\nanthropic-version: 2023-06-01\n",
			key,
		)
		if os.write_entire_file(a.headers, hdr, {.Read_User, .Write_User}) !=
		   nil {die("cannot write %s", a.headers)}
	}

	_, odin_version, _ := run("", "odin", "version")
	_, odx_commit, _ := run("", "git", "describe", "--always", "--dirty", "--abbrev=40")

	os.make_directory_all(filepath.dir(o.out)) // ponytail: an unwritable directory fails at open below
	out, oerr := os.open(o.out, {.Write, .Create, .Append})
	if oerr != nil {die("cannot open %s: %v", o.out, oerr)}
	defer os.close(out)

	base := context.allocator
	for t in load_tasks(o.tasks, o.task) {
		for sample in 0 ..< o.samples {
			arena: virtual.Arena
			_ = virtual.arena_init_growing(&arena)
			context.allocator = virtual.arena_allocator(&arena)

			row := Row {
				run_id       = o.run_id,
				task         = t.id,
				condition    = fmt.tprint(o.condition),
				model        = o.model,
				effort       = o.effort,
				agent        = o.agent,
				odin_version = strings.trim_space(odin_version),
				odx_commit   = strings.trim_space(odx_commit),
				sample       = sample,
			}
			start := time.now()
			a.tokens_in, a.tokens_out, a.turns = 0, 0, 0
			ok := true
			if tr.resample {
				row.budget_tokens, ok = budgets[fmt.tprintf("%s#%d", t.id, sample)]
				if !ok {row.tool_error = "no C3 row to match the budget against"}
			}
			// C4 resamples until an episode compiles or the budget is spent; the compiler is
			// available in every condition, so selecting on it adds no odx signal.
			for ok {
				outcome, err := episode(&a, tr, t)
				row.episodes += 1
				if e, failed := err.?; failed {
					row.tool_error = e
					break
				}
				row.compiles, row.tests_pass, row.edit_applied =
					outcome.compiles, outcome.tests_pass, outcome.edit_applied
				row.odx_errors, row.odx_warnings = outcome.odx_errors, outcome.odx_warnings
				if !tr.resample ||
				   outcome.compiles ||
				   a.tokens_in + a.tokens_out >= row.budget_tokens {break}
			}
			row.tokens_in, row.tokens_out, row.turns = a.tokens_in, a.tokens_out, a.turns
			row.wall_ms = i64(time.duration_milliseconds(time.since(start)))

			line, _ := json.marshal(row)
			os.write_string(out, string(line))
			os.write_string(out, "\n")
			fmt.eprintfln(
				"%s %s #%d compiles=%v tests=%v odx=%d %s",
				t.id,
				row.condition,
				sample,
				row.compiles,
				row.tests_pass,
				row.odx_errors,
				row.tool_error,
			)
			context.allocator = base
			virtual.arena_destroy(&arena)
		}
	}
}

// episode: fresh worktree, one generation, REVISIONS fixed revision turns, then scoring.
episode :: proc(a: ^Agent, tr: Traits, t: Task) -> (out: Outcome, err: Error) {
	wt := make_worktree(t) or_return
	defer if !a.opts.keep {os.remove_all(wt)}
	solution := join(wt, "task", "solution.odin")

	a.messages = {} // the previous run's arena is gone; never reuse its backing array
	a.system = ""
	if tr.block {
		code, policy, crashed := run(wt, a.opts.odx, "policy")
		if crashed || code != 0 {return out, fmt.aprintf("odx policy exited %d: %s", code, policy)}
		a.system = policy
	}

	out.edit_applied = true
	message := fmt.aprintf(
		"Task: %s\nWrite the complete Odin file `task/solution.odin` (package `task`). It starts as:\n\n```odin\n%s```\n\nReply with the complete file in one ```odin fenced block.",
		strings.trim_space(t.prompt),
		t.start,
	)
	for turn in 0 ..= REVISIONS {
		if turn > 0 {
			// Same schedule in every condition: revision never depends on whether findings exist.
			b := strings.builder_make()
			ok, diagnostics := compile(wt) or_return
			if ok {
				strings.write_string(&b, "`odin build` succeeded.\n\n")
			} else {
				fmt.sbprintf(&b, "`odin build` failed:\n%s\n\n", diagnostics)
			}
			if tr.findings {
				text, _, _ := odx_check(a.opts.odx, wt) or_return
				fmt.sbprintf(&b, "`odx check` findings:\n%s\n\n", text if text != "" else "none")
			}
			strings.write_string(
				&b,
				"Review your solution. Reply with the complete final `task/solution.odin` in one ```odin fenced block.",
			)
			message = strings.to_string(b)
		}
		reply := ask(a, message, t) or_return
		if code, found := extract_odin(reply); found {
			if os.write_entire_file(solution, code) != nil {return out, "cannot write solution"}
		} else {
			out.edit_applied = false
		}
	}

	out.compiles, _ = compile(wt) or_return
	_, out.odx_errors, out.odx_warnings = odx_check(a.opts.odx, wt) or_return
	if out.compiles {out.tests_pass = run_tests(wt, t) or_return}
	return
}

ask :: proc(a: ^Agent, message: string, t: Task) -> (reply: string, err: Error) {
	a.turns += 1
	append(&a.messages, Message{"user", json.String(message)})
	if a.opts.agent == "reference" {return fmt.aprintf("```odin\n%s```", t.solution), nil}

	body, merr := json.marshal(struct {
		model:         string,
		max_tokens:    int,
		system:        string `json:",omitempty"`,
		output_config: struct {
			effort: string,
		},
		messages:      []Message,
	}{a.opts.model, MAX_TOKENS, a.system, {a.opts.effort}, a.messages[:]})
	if merr != nil {return "", fmt.aprintf("marshal request: %v", merr)}
	request := join(a.scratch, "request.json")
	if os.write_entire_file(request, body) != nil {return "", "cannot write request"}
	// curl --retry covers 408/429/5xx; anything left is a tool error, not a model failure.
	code, response, _ := run(
		"",
		"curl",
		"-sS",
		"--retry",
		"6",
		"--retry-max-time",
		"600",
		"--max-time",
		"900",
		"-H",
		strings.concatenate({"@", a.headers}),
		"--data-binary",
		strings.concatenate({"@", request}),
		API_URL,
	)
	if code != 0 {return "", fmt.aprintf("curl exited %d: %s", code, response)}
	v, perr := json.parse(transmute([]byte)response, parse_integers = true)
	obj, is_obj := v.(json.Object)
	if perr != nil || !is_obj || str(obj["type"]) != "message" {
		return "", fmt.aprintf("api: %s", response)
	}
	usage, _ := obj["usage"].(json.Object)
	for k in ([]string{"input_tokens", "cache_creation_input_tokens", "cache_read_input_tokens"}) {
		a.tokens_in += int(usage[k].(json.Integer) or_else 0)
	}
	a.tokens_out += int(usage["output_tokens"].(json.Integer) or_else 0)
	append(&a.messages, Message{"assistant", obj["content"]})
	if str(obj["stop_reason"]) == "refusal" {return "", "refusal"}

	b := strings.builder_make()
	blocks, _ := obj["content"].(json.Array)
	for block in blocks {
		o, _ := block.(json.Object)
		if str(o["type"]) == "text" {strings.write_string(&b, str(o["text"]))}
	}
	return strings.to_string(b), nil
}

// extract_odin: the last ```odin fenced block, the file the model settled on.
extract_odin :: proc(reply: string) -> (code: string, ok: bool) {
	FENCE :: "```odin\n"
	start := strings.last_index(reply, FENCE)
	if start < 0 {return}
	rest := reply[start + len(FENCE):]
	end := strings.index(rest, "```")
	if end < 0 {return}
	return rest[:end], true
}

// compile: plain `odin build`, no vet; vet flags are the compiler's business, not odx's.
compile :: proc(wt: string) -> (ok: bool, diagnostics: string, err: Error) {
	code, output, crashed := run(
		wt,
		"odin",
		"build",
		"task",
		"-build-mode:obj",
		"-out:build/task.o",
	)
	if crashed {return false, "", "odin build crashed"}
	return code == 0, output, nil
}

Odx_Report :: struct {
	rules:       map[string]struct {
		fix_hint: string,
	},
	violations:  []struct {
		file, rule, message, severity: string,
		line:                          int,
		baselined:                     bool,
	},
	tool_errors: []string,
}

// odx_check: odin/* findings are compiler output every condition already receives, so they
// are neither fed back nor counted; feeding them to C2/C3 alone would confound the loop.
odx_check :: proc(odx, wt: string) -> (text: string, errors, warnings: int, err: Error) {
	code, output, crashed := run(wt, odx, "check", "--json")
	if crashed || code == 2 {return "", 0, 0, fmt.aprintf("odx check exited %d: %s", code, output)}
	r: Odx_Report
	if uerr := json.unmarshal_string(output, &r);
	   uerr != nil {return "", 0, 0, fmt.aprintf("odx json: %v", uerr)}
	if len(r.tool_errors) > 0 {return "", 0, 0, strings.join(r.tool_errors, "; ")}
	b := strings.builder_make()
	for v in r.violations {
		if strings.has_prefix(v.rule, "odin/") || v.baselined {continue}
		if v.severity == "warning" {warnings += 1} else {errors += 1}
		fmt.sbprintf(&b, "%s:%d: %s [%s]: %s\n", v.file, v.line, v.rule, v.severity, v.message)
		if hint := r.rules[v.rule].fix_hint;
		   hint != "" {fmt.sbprintf(&b, "  Correction: %s\n", hint)}
	}
	return strings.to_string(b), errors, warnings, nil
}

// run_tests: the hidden tests join the worktree only now, after every model turn.
run_tests :: proc(wt: string, t: Task) -> (pass: bool, err: Error) {
	if os.write_entire_file(join(wt, "task", "solution_test.odin"), t.test) != nil {
		return false, "cannot write tests"
	}
	code, _, crashed := run(wt, "odin", "build", "task", "-build-mode:test", "-out:build/tests")
	if crashed {return false, "odin build -build-mode:test crashed"}
	if code != 0 {return false, nil} 	// tests referencing a changed signature fail, not error
	p, serr := os.process_start({command = {join(wt, "build", "tests")}, working_dir = wt})
	if serr != nil {return false, fmt.aprintf("cannot start tests: %v", serr)}
	state, werr := os.process_wait(p, TEST_TIMEOUT)
	if werr != nil {
		_ = os.process_kill(p)
		_, _ = os.process_wait(p)
		return false, nil // a hang is the solution's failure
	}
	return state.exit_code == 0, nil
}

// run: combined output. crashed is the pinned nightly's intermittent segfault signature
// (nonzero exit, no output) persisting across three attempts; see odx/odincheck.odin.
run :: proc(dir: string, cmd: ..string) -> (code: int, output: string, crashed: bool) {
	for _ in 0 ..< 3 {
		state, stdout, stderr, err := os.process_exec(
			{command = cmd, working_dir = dir},
			context.allocator,
		)
		if err != nil {return -1, fmt.aprintf("cannot run %s: %v", cmd[0], err), true}
		code, output = state.exit_code, strings.concatenate({string(stdout), string(stderr)})
		if code == 0 || strings.trim_space(output) != "" {return code, output, false}
	}
	return code, output, true
}

load_tasks :: proc(root, only: string) -> []Task {
	entries, err := os.read_all_directory_by_path(root, context.allocator)
	if err != nil {die("cannot read %s: %v", root, err)}
	slice.sort_by(entries, proc(a, b: os.File_Info) -> bool {return a.name < b.name})
	tasks := make([dynamic]Task)
	for e in entries {
		if e.type != .Directory || (only != "" && e.name != only) {continue}
		read :: proc(dir, name: string) -> string {
			data, err := os.read_entire_file(join(dir, name), context.allocator)
			if err != nil {die("task %s: cannot read %s", dir, name)}
			return string(data)
		}
		append(
			&tasks,
			Task {
				id = e.name,
				dir = e.fullpath,
				prompt = read(e.fullpath, "prompt.md"),
				start = read(e.fullpath, "signature.odin"),
				solution = read(e.fullpath, "solution.odin"),
				test = read(e.fullpath, "test.odin"),
			},
		)
	}
	if len(tasks) == 0 {die("no tasks under %s", root)}
	return tasks[:]
}

// make_worktree: a fresh git repository holding the task's starting state and policy.
make_worktree :: proc(t: Task) -> (wt: string, err: Error) {
	dir, terr := os.make_directory_temp("", "odx-eval-wt-*", context.allocator)
	if terr != nil {return "", fmt.aprintf("temp dir: %v", terr)}
	if os.make_directory_all(join(dir, "task")) != nil ||
	   os.make_directory_all(join(dir, "build")) != nil ||
	   os.copy_file(join(dir, "odx.json5"), join(t.dir, "odx.json5")) != nil ||
	   os.write_entire_file(join(dir, "task", "solution.odin"), t.start) != nil ||
	   os.write_entire_file(join(dir, ".gitignore"), "build/\n") != nil {
		return "", "cannot populate worktree"
	}
	for cmd in ([][]string{{"git", "init", "-q"}, {"git", "add", "-A"}, {"git", "-c", "user.name=eval", "-c", "user.email=eval@localhost", "commit", "-qm", "start"}}) {
		if code, output, _ := run(dir, ..cmd);
		   code != 0 {return "", fmt.aprintf("git: %s", output)}
	}
	return dir, nil
}

load_budgets :: proc(path, model: string) -> map[string]int {
	data, err := os.read_entire_file(path, context.allocator)
	if err != nil {die("cannot read %s", path)}
	budgets := make(map[string]int)
	for line in strings.split_lines(string(data)) {
		if line == "" {continue}
		r: Row
		if json.unmarshal_string(line, &r) != nil {die("bad row in %s: %s", path, line)}
		if r.condition == "C3" && r.model == model && r.tool_error == "" {
			budgets[fmt.aprintf("%s#%d", r.task, r.sample)] = r.tokens_in + r.tokens_out
		}
	}
	return budgets
}

join :: proc(parts: ..string) -> string {
	p, _ := filepath.join(parts)
	return p
}

str :: proc(v: json.Value) -> string {
	s, _ := v.(json.String)
	return string(s)
}

die :: proc(f: string, args: ..any) -> ! {
	fmt.eprintfln(f, ..args)
	os.exit(2)
}
