package odx

import "core:fmt"
import "core:odin/ast"
import "core:strings"

Evidence_Status :: enum {
	not_run,
	complete,
	skipped,
	failed,
	unsupported,
	not_applicable,
}

Evidence_Result :: struct {
	status: Evidence_Status,
	reason: string,
}

Check_Coverage :: struct {
	package_dir: string,
	rule:        string,
	evidence:    string,
	boundary:    string,
	status:      Evidence_Status,
	reason:      string,
	findings:    int,
}

Source_Coverage :: struct {
	package_dir: string,
	files:       []string,
}

Coverage :: struct {
	selection:      string,
	paths:          []string,
	since:          string,
	topics:         []string,
	exclude:        []string,
	source_scope:   string,
	compiler_scope: string,
	compiler:       string,
	compiler_flags: []string,
	complete:       bool,
	packages:       []Source_Coverage,
	checks:         [dynamic]Check_Coverage,
}

init_coverage :: proc(c: ^Ctx, o: Opts) {
	v := &c.r.coverage
	v.selection = "project"
	if len(c.paths) > 0 {v.selection = "paths"}
	if o.since != "" {v.selection = "since"}
	if o.exemplar != "" {v.selection = "exemplar"}
	v.paths = c.paths
	v.since = o.since
	v.topics = o.topics[:]
	v.exclude = c.cfg.exclude
	v.source_scope = "all nonempty *.odin files collected in selected package directories, including inactive, platform, generated, and test source; discovery skips excluded and symlink directories; native file collection may follow file symlinks"
	v.compiler_scope = "odin check/doc for the compiler-selected target and configured flags; host default; tests are not executed"
	v.compiler = odin_exe(c.cfg)
	v.compiler_flags = odin_flags(c)
	v.packages = make([]Source_Coverage, len(c.pkgs))
	for p, i in c.pkgs {
		v.packages[i].package_dir = p.rel
		v.packages[i].files = make([]string, len(p.files))
		for f, j in p.files {v.packages[i].files[j], _ = rel_of(c.root, f.fullpath)}
	}
}

rule_evidence :: proc(spec: Check_Spec) -> (source, boundary: string) {
	switch spec.kind {
	case .path_role:
		return "configuration", "selected package directories and configured role globs"
	case .vet_tag:
		return "native_tokens", "file tag presence only; no allocator behavior or lifetime proof"
	case .banned_import:
		return "source_import_graph",
			"direct file-level ordinary imports with test-specific allow exceptions; transitive traversal excludes *_test.odin; external/excluded packages are leaves; not a compiler-resolved or foreign graph"
	case .require_attribute:
		return "compiler_entities",
			"compiler-selected exported procedure declarations, excluding @(test); inferred final error-result types and attribute presence; no caller-handling proof"
	case .pattern:
		if spec.match == "call" {
			return "native_ast",
				"recursive syntactic calls in all branches; file import aliases normalized without lexical name resolution; indirect calls not resolved"
		}
		return "native_ast", fmt.tprintf(
			"direct file-level %s declarations only; declarations inside when/foreign blocks and nested procedures are outside this selector",
			spec.match,
		)
	}
	return
}

coverage_applies :: proc(c: ^Ctx, p: ^Package, spec: Check_Spec) -> bool {
	spec := spec
	if !role_applies(&spec, p.role) {return false}
	#partial switch spec.kind {
	case .vet_tag:
		return(
			c.cfg.odin.explicit_allocators == .all ||
			(c.cfg.odin.explicit_allocators == .pure &&
					(p.role == "pure" || p.role == "service")) \
		)
	case .banned_import:
		return p.role in c.cfg.dependencies
	case:
		return true
	}
}

add_coverage :: proc(
	c: ^Ctx,
	p: ^Package,
	rule, evidence, boundary: string,
	result: Evidence_Result,
) {
	entry := Check_Coverage {
		package_dir = p.rel,
		rule        = rule,
		evidence    = evidence,
		boundary    = boundary,
		status      = result.status,
		reason      = result.reason,
	}
	for v in c.r.violations {
		if (v.rule == rule || (rule == "odin/check" && v.check == "odin")) &&
		   (dir_of(v.file) == p.rel || v.file == p.rel || (p.rel == "" && v.file == ".")) {
			entry.findings += 1
		}
	}
	append(&c.r.coverage.checks, entry)
}

collect_coverage :: proc(c: ^Ctx, o: Opts) {
	for &p in c.pkgs {
		native := p.parse_result
		if !c.native_ran &&
		   native.status == .complete {native = {.skipped, "source rules were not executed"}}
		add_coverage(
			c,
			&p,
			"odin/syntax",
			"native_parser",
			c.r.coverage.source_scope,
			p.parse_result,
		)
		add_coverage(
			c,
			&p,
			"odx/feature-optout",
			"native_tokens",
			"file feature tags require a same-line reason comment",
			native,
		)
		add_coverage(
			c,
			&p,
			"odx/vet-disable",
			"native_tokens",
			"file vet-disable tags compared with configured allow-list",
			native,
		)
		compiler := p.compiler_result
		if compiler.status == .not_run {
			compiler = {.skipped, "compiler checks were not requested"}
			if o.fast {compiler.reason = "--fast omits compiler checks"}
		}
		add_coverage(
			c,
			&p,
			"odin/check",
			"compiler_diagnostics",
			c.r.coverage.compiler_scope,
			compiler,
		)
		for a in c.rules {
			spec := a.rule.check
			evidence, boundary := rule_evidence(spec)
			result := native
			switch {
			case !coverage_applies(c, &p, spec):
				result = {.not_applicable, "excluded by rule roles or check configuration"}
			case is_family_c(spec.kind):
				result = p.doc_result
				if result.status == .not_run {
					result = {.skipped, "compiler entity checks were not requested"}
					if o.fast {result.reason = "--fast omits compiler entity checks"}
				}
			case spec.kind == .banned_import &&
			     len(c.cfg.dependencies[p.role].deny) > 0 &&
			     result.status == .complete &&
			     (c.partial_graph || !import_evidence_available(c, &p)):
				result = {
					.unsupported,
					"project import graph is incomplete in this scan; transitive compliance is not established",
				}
				tool_error(c.r, "%s in %s: %s", a.id, p.rel, result.reason)
			}
			add_coverage(c, &p, a.id, evidence, boundary, result)
		}
	}
	refresh_coverage(c.r)
}

// Only reachable parser failures can invalidate a package's outbound reach check.
import_evidence_available :: proc(c: ^Ctx, start: ^Package) -> bool {
	queue := make([dynamic]^Package, context.temp_allocator)
	append(&queue, start)
	seen := make(map[string]bool, context.temp_allocator)
	for i := 0; i < len(queue); i += 1 {
		p := queue[i]
		if p.rel in seen {continue}
		seen[p.rel] = true
		if p.parse_result.status != .complete {return false}
		for f in p.files {
			if p != start && strings.has_suffix(f.fullpath, "_test.odin") {continue}
			for d in f.decls {
				imp, ok := d.derived.(^ast.Import_Decl)
				if !ok {continue}
				path := strings.trim(imp.relpath.text, `"`)
				label, role := import_target(c, p, path)
				if strings.contains(path, ":") && role == "" {continue}
				for &target in c.pkgs {
					if target.rel == label {append(&queue, &target)}
				}
			}
		}
	}
	return true
}

refresh_coverage :: proc(r: ^Report) {
	v := &r.coverage
	v.complete = len(v.packages) > 0 && len(r.tool_errors) == 0
	for entry in v.checks {
		if entry.status != .complete && entry.status != .not_applicable {v.complete = false}
	}
}

coverage_text :: proc(r: ^Report) -> string {
	if r.coverage.selection == "" {return ""}
	b := strings.builder_make(context.temp_allocator)
	fmt.sbprintfln(
		&b,
		"coverage: %s selection, %d packages; %s evidence within stated boundaries",
		r.coverage.selection,
		len(r.coverage.packages),
		"complete" if r.coverage.complete else "incomplete",
	)
	strings.write_string(
		&b,
		"  source: all nonempty package .odin files, including inactive/platform/generated/test source\n  compiler: selected target/configuration; tests not executed\n",
	)
	for entry in r.coverage.checks {
		if entry.status == .complete || entry.status == .not_applicable {continue}
		fmt.sbprintfln(
			&b,
			"  %s %s: %v (%s)",
			entry.package_dir if entry.package_dir != "" else ".",
			entry.rule,
			entry.status,
			entry.reason,
		)
	}
	return strings.to_string(b)
}
