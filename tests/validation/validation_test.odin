package validation

import crypto_hash "core:crypto/hash"
import "core:encoding/hex"
import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:slice"
import "core:strings"
import "core:testing"
import "core:time"

MINIMAL :: `{
 version:1, exclude:[".odx/**","cases/**","build/**"],
 disabled:{"errors/R3":"This pilot selects only two native source restrictions."},
 odin:{explicit_allocators:"off",audit_file_tags:false},
}`
STRICT :: `{
 version:1, roles:{domain:["domain","domain/**"]},
 dependencies:{domain:{may_import:["domain","core:*"],deny:["core:os","core:os/*","core:net","core:net/*","core:sys/*"]}},
 exclude:[".odx/**","cases/**","build/**"],
 errors:{types:["Error"],structural:false},
 odin:{flags:[],forbidden_flags:[],explicit_allocators:"all"},
}`
Sample :: struct {
	name, path, digest: string,
}
SAMPLES := []Sample {
	{
		"demo",
		"examples/demo/demo.odin",
		"716c752d843c434bd626f6703fa9c8a791a4090f26b2efe3a0cac3333e4afef4",
	},
	{
		"queue",
		"core/container/queue/queue.odin",
		"f1809a37d6b4ec1f9d383a2fc357a7bbf4d666b2ac4eb109d065f6279dc53ab6",
	},
}
Finding :: struct {
	rule, file, message, subject: string,
	line, col:                    int,
	baselined:                    bool,
}
Report :: struct {
	schema:      int,
	rules:       map[string]struct {
		fix_hint, evidence, boundary: string,
	},
	coverage:    struct {
		complete:  bool,
		selection: string,
		checks:    []struct {
			rule, status, reason: string,
		},
	},
	summary:     struct {
		errors, warnings, baselined, files: int,
	},
	violations:  []Finding,
	tool_errors: []string,
}
Timing :: struct {
	mode:                                                         string,
	cold_seconds, warmup_seconds, median_seconds, budget_seconds: f64,
	measured_seconds:                                             []f64,
	budget_met:                                                   bool,
}
Outcome :: struct {
	sample, policy, source_path, source_sha256, project_root: string,
	source_bytes, source_lines, authored_nonblank_lines:      int,
	automated_setup_seconds:                                  f64,
	full:                                                     Report,
	timings:                                                  []Timing,
}
Probe :: struct {
	t:                                 ^testing.T,
	bin, root, artifacts, last_report: string,
	passed, failed, sequence:          int,
}
Summary :: struct {
	compiler,
	compiler_version,
	odin_root,
	odx_binary,
	odx_sha256,
	odx_revision,
	host,
	artifacts: string,
	outcomes:                                                                                     [dynamic]Outcome,
	passed,
	failed:                                                                               int,
}
read :: proc(path: string) -> string {
	data, err := os.read_entire_file(path, context.allocator)
	if err != nil {panic(fmt.tprintf("read %s: %v", path, err))}
	return string(data)
}
write :: proc(path, text: string) {
	if err := os.make_directory_all(filepath.dir(path));
	   err != nil && err != .Exist {panic(fmt.tprintf("mkdir: %v", err))}
	if err := os.write_entire_file(path, text);
	   err != nil {panic(fmt.tprintf("write %s: %v", path, err))}
}
encoded :: proc(value: any) -> string {
	data, err := json.marshal(value, {pretty = true})
	if err != nil {panic(fmt.tprintf("JSON: %v", err))}
	return string(data)
}
digest :: proc(text: string) -> string {
	bytes := crypto_hash.hash_bytes(.SHA256, transmute([]byte)text, context.allocator)
	return string(hex.encode(bytes, context.allocator))
}
expect :: proc(p: ^Probe, ok: bool, name: string, loc := #caller_location) {
	if ok {p.passed += 1} else {p.failed += 1}
	testing.expect(p.t, ok, name, loc = loc)
}
process :: proc(args: []string) -> (out: string, code: int) {
	state, stdout, stderr, err := os.process_exec({command = args}, context.allocator)
	if err != nil {panic(fmt.tprintf("spawn %v: %v", args, err))}
	if state.exit_code != 0 && len(stderr) > 0 {fmt.eprintln(string(stderr))}
	return strings.trim_space(string(stdout)), state.exit_code
}
run :: proc(p: ^Probe, label: string, args: []string) -> (out: string, code: int, seconds: f64) {
	command := make([dynamic]string)
	append(&command, p.bin); append(&command, ..args); append(&command, "--root", p.root)
	start := time.tick_now()
	state, stdout, stderr, err := os.process_exec({command = command[:]}, context.allocator)
	seconds = f64(time.tick_since(start)) / 1e9
	if err != nil {panic(fmt.tprintf("spawn odx: %v", err))}
	out = string(stdout); code = state.exit_code
	p.sequence += 1
	prefix := fmt.tprintf("%s/%03d-%s", p.artifacts, p.sequence, label)
	write(strings.concatenate({prefix, ".stdout"}), out)
	write(strings.concatenate({prefix, ".stderr"}), string(stderr))
	write(strings.concatenate({prefix, ".invocation.json"}), encoded(struct {
			command:   []string,
			exit_code: int,
			seconds:   f64,
		}{command[:], code, seconds}))
	return
}
check :: proc(
	p: ^Probe,
	label: string,
	args: []string = nil,
) -> (
	report: Report,
	code: int,
	seconds: f64,
) {
	command := make([dynamic]string)
	append(&command, "check", "--json"); append(&command, ..args)
	out: string
	out, code, seconds = run(p, label, command[:])
	p.last_report = out
	if err := json.unmarshal_string(out, &report);
	   err != nil {panic(fmt.tprintf("check report %s: %v", label, err))}
	expect(p, report.schema == 2, fmt.tprintf("%s report schema", label))
	return
}
report_findings :: proc(raw: string) -> string {
	value, _ := json.parse_string(raw)
	obj, _ := value.(json.Object)
	text, err := json.unparse(obj["violations"], {sort_maps_by_key = true})
	if err != nil {panic("cannot canonicalize findings")}
	return text
}
copy_topics :: proc(policy, root: string) -> int {
	source := fmt.tprintf("examples/policies/%s/.odx", policy)
	_, code := process({"cp", "-R", source, fmt.tprintf("%s/.odx", root)})
	if code != 0 {panic("copy policy")}
	lines := 0
	paths: []string
	if policy == "minimal" {
		paths = {"library/topic.md", "library/R1.odx.md", "library/R2.odx.md"}
	} else {
		paths = {
			"dependencies/topic.md",
			"dependencies/R2.odx.md",
			"dependencies/R3.odx.md",
			"dependencies/R4.odx.md",
			"allocators/topic.md",
			"allocators/R1.odx.md",
			"errors/topic.md",
			"errors/R3.odx.md",
		}
		path := fmt.tprintf("%s/.odx/topics/errors/R3.odx.md", root)
		text := read(path)
		text, _ = strings.replace_all(text, "Domain_Failure or Storage_Failure", "Error")
		text, _ = strings.replace_all(text, "Domain_Failure", "Domain_Error")
		text, _ = strings.replace_all(text, "Storage_Failure", "Storage_Error")
		write(path, text)
		topic_path := fmt.tprintf("%s/.odx/topics/errors/topic.md", root)
		topic_text, _ := strings.replace_all(
			read(topic_path),
			"two chosen failure-name suffixes",
			"the chosen Error suffix",
		)
		write(topic_path, topic_text)
	}
	for path in paths {for line in strings.split_lines(read(fmt.tprintf("%s/.odx/topics/%s", root, path))) {if strings.trim_space(line) != "" {lines += 1}}}
	return lines
}
measure :: proc(p: ^Probe, mode: string) -> (timing: Timing, first: Report) {
	timing.mode = mode; timing.budget_seconds = 2 if mode == "fast" else 10
	args: []string
	if mode == "fast" {args = {"--fast"}}
	valid := proc(p: ^Probe, r: Report, code: int, mode: string) {
		expected := 1 if r.summary.errors > 0 else 0
		expect(
			p,
			code == expected && len(r.tool_errors) == 0,
			fmt.tprintf("%s expected policy exit without tool error", mode),
		)
		expect(
			p,
			r.coverage.complete == (mode == "full"),
			fmt.tprintf("%s coverage matches requested evidence", mode),
		)
	}
	code: int
	first, code, timing.cold_seconds = check(p, fmt.tprintf("%s-cold", mode), args)
	valid(p, first, code, mode)
	reference := p.last_report
	warmup: Report
	warmup, code, timing.warmup_seconds = check(p, fmt.tprintf("%s-warmup", mode), args)
	valid(p, warmup, code, mode)
	expect(
		p,
		p.last_report == reference,
		fmt.tprintf("%s warmup complete JSON deterministic", mode),
	)
	timing.measured_seconds = make([]f64, 5)
	for i in 0 ..< 5 {
		r, exit_code, elapsed := check(p, fmt.tprintf("%s-measured-%d", mode, i + 1), args)
		valid(p, r, exit_code, mode)
		timing.measured_seconds[i] = elapsed
		expect(
			p,
			p.last_report == reference,
			fmt.tprintf("%s repeat %d complete JSON deterministic", mode, i + 1),
		)
	}
	sorted := slice.clone(timing.measured_seconds)
	slice.sort(sorted)
	timing.median_seconds = sorted[2]
	timing.budget_met = timing.median_seconds <= timing.budget_seconds
	expect(p, timing.budget_met, fmt.tprintf("%s preregistered latency budget", mode))
	fmt.printfln(
		"TIMING %s median %.3fs budget %.1fs met=%v",
		mode,
		timing.median_seconds,
		timing.budget_seconds,
		timing.budget_met,
	)
	return
}
@(test)
test_public_source_policies :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	defer free_all(context.temp_allocator)
	compiler := os.get_env("ODX_ODIN", context.allocator)
	if compiler == "" {panic("set ODX_ODIN to the pinned dev-2026-09 compiler")}
	version, version_code := process({compiler, "version"})
	if version_code != 0 ||
	   !strings.contains(version, "dev-2026-09") ||
	   !strings.contains(
			   version,
			   "a2fb372",
		   ) {panic(fmt.tprintf("unsupported pilot compiler: %s", version))}
	odin_root, root_code := process({compiler, "root"})
	if root_code != 0 {panic("compiler root unavailable")}
	bin := os.get_env("ODX_PILOT_BIN", context.allocator)
	if bin == "" {bin, _ = filepath.abs("build/odx")}
	output := os.get_env("ODX_PILOT_OUT", context.allocator)
	if output == "" {output = "build/validation"}
	if err := os.make_directory_all(output);
	   err != nil && err != .Exist {panic(fmt.tprintf("%v", err))}
	base, err := os.make_directory_temp(output, "run-*", context.allocator)
	if err != nil {panic(fmt.tprintf("%v", err))}
	base, _ = filepath.abs(base)
	revision, _ := process({"git", "rev-parse", "HEAD"})
	host, _ := process({"uname", "-srm"})
	summary := Summary {
		compiler         = compiler,
		compiler_version = version,
		odin_root        = odin_root,
		odx_binary       = bin,
		odx_sha256       = digest(read(bin)),
		odx_revision     = revision,
		host             = host,
		artifacts        = base,
	}
	p := Probe {
		t   = t,
		bin = bin,
	}
	for sample in SAMPLES {
		source := read(fmt.tprintf("%s/%s", odin_root, sample.path))
		if digest(source) !=
		   sample.digest {panic(fmt.tprintf("source fingerprint mismatch for %s; review and preregister new input before measuring", sample.path))}
		for policy in ([]string{"minimal", "strict"}) {
			name := fmt.tprintf("%s-%s", sample.name, policy)
			fmt.printfln("PILOT %s", name)
			start := time.tick_now()
			p.root = fmt.tprintf("%s/projects/%s", base, name)
			p.artifacts = fmt.tprintf("%s/invocations/%s", base, name)
			config := MINIMAL if policy == "minimal" else STRICT
			write(fmt.tprintf("%s/odx.json5", p.root), config)
			write(fmt.tprintf("%s/domain/input.odin", p.root), source)
			authored := copy_topics(policy, p.root)
			for line in strings.split_lines(config) {if strings.trim_space(line) != "" {authored += 1}}
			outcome := Outcome {
				sample                  = sample.name,
				policy                  = policy,
				source_path             = sample.path,
				source_sha256           = sample.digest,
				project_root            = p.root,
				source_bytes            = len(source),
				source_lines            = strings.count(source, "\n"),
				authored_nonblank_lines = authored,
				automated_setup_seconds = f64(time.tick_since(start)) / 1e9,
			}
			outcome.timings = make([]Timing, 2)
			outcome.timings[0], outcome.full = measure(&p, "full")
			full_findings := report_findings(p.last_report)
			fast: Report
			outcome.timings[1], fast = measure(&p, "fast")
			expect(
				&p,
				outcome.full.coverage.complete,
				fmt.tprintf("%s full evidence complete", name),
			)
			expect(
				&p,
				!fast.coverage.complete,
				fmt.tprintf("%s fast evidence explicitly partial", name),
			)
			scoped, scoped_code, _ := check(&p, "scoped", {"domain"})
			expect(
				&p,
				scoped.coverage.complete && scoped_code == (1 if scoped.summary.errors > 0 else 0),
				"scoped check has complete evidence and expected exit",
			)
			expect(
				&p,
				report_findings(p.last_report) == full_findings,
				fmt.tprintf("%s scoped findings equal full", name),
			)
			_, write_code, _ := run(&p, "guidance-write", {"policy", "--write", "AGENTS.md"})
			_, fresh_code, _ := run(&p, "guidance-check", {"policy", "--verify", "AGENTS.md"})
			expect(
				&p,
				write_code == 0 && fresh_code == 0,
				fmt.tprintf("%s guidance generated and current", name),
			)
			if policy == "minimal" {
				for v in outcome.full.violations {expect(&p, strings.has_prefix(v.rule, "library/") || strings.has_prefix(v.rule, "odin/"), "minimal findings contain only selected policies or compiler diagnostics")}
			}
			maintenance(&p, policy, source, outcome.full)
			append(&summary.outcomes, outcome)
		}
	}
	summary.passed = p.passed; summary.failed = p.failed
	write(fmt.tprintf("%s/summary.json", base), encoded(summary))
	write(fmt.tprintf("%s/latest-summary.json", output), encoded(summary))
	fmt.printfln("%d assertions passed; %d failed; artifacts: %s", p.passed, p.failed, base)
}
