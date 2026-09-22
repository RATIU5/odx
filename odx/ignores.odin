package odx

import "core:odin/ast"
import "core:strings"

Ignore :: struct {
	file:   string,
	line:   int,
	col:    int, // column of the `//`
	target: int, // line it applies to; 0 = whole file
	rule:   string,
	reason: string,
	used:   bool,
}

IGNORE_PREFIX :: "odx:ignore"
IGNORE_FILE_PREFIX :: IGNORE_PREFIX + "-file"

// Malformed directives become odx/bad-ignore violations.
collect_ignores :: proc(
	r: ^Report,
	rb: ^Rulebook,
	f: ^ast.File,
	rel: string,
	out: ^[dynamic]Ignore,
) {
	lines := strings.split_lines(f.src, context.temp_allocator)
	for g in f.comments {
		for tok in g.list {
			text := strings.trim_space(strings.trim_prefix(tok.text, "//"))
			if !strings.has_prefix(tok.text, "//") {continue}
			if !strings.has_prefix(text, IGNORE_PREFIX) {
				// a near miss (`odx: ignore`, `odx:Ignore`, `odx-ignore`) fails loudly, never silently
				if low := strings.to_lower(text, context.temp_allocator);
				   strings.has_prefix(low, "odx") && is_near_miss(low) {
					note(
						r,
						"odx/bad-ignore",
						"ignores",
						rel,
						tok.pos.line,
						tok.pos.column,
						"malformed directive; the form is `// odx:ignore <topic>/<R> reason: <text>`",
					)
				}
				continue
			}
			whole := strings.has_prefix(text, IGNORE_FILE_PREFIX)
			text = strings.trim_space(
				text[len(IGNORE_FILE_PREFIX) if whole else len(IGNORE_PREFIX):],
			)
			ruleid, _, rest := strings.partition(text, " ")
			reason := strings.trim_space(strings.trim_prefix(strings.trim_space(rest), "reason:"))
			bad: string
			switch {
			case whole && tok.pos.line > 3:
				bad = "odx:ignore-file must be on line 1-3"
			case strings.contains(rest, IGNORE_PREFIX):
				bad = "one odx:ignore per line"
			case len(reason) < 10:
				bad = "reason must be at least 10 characters"
			case find_rule(rb, ruleid) == nil:
				bad = strings.concatenate({"unknown rule ", ruleid})
			}
			if bad != "" {
				note(r, "odx/bad-ignore", "ignores", rel, tok.pos.line, tok.pos.column, bad)
				continue
			}
			append(
				out,
				Ignore {
					file = rel,
					line = tok.pos.line,
					col = tok.pos.column,
					rule = ruleid,
					reason = reason,
					target = ignore_target(lines, tok.pos.line, tok.pos.column, whole),
				},
			)
		}
	}
}

// An own-line directive with no code after it targets itself, so it reads as stale rather
// than silently widening to the whole file.
@(private = "file")
ignore_target :: proc(lines: []string, comment_line, col: int, whole: bool) -> int {
	if whole {return 0}
	if strings.trim_space(lines[comment_line - 1][:col - 1]) != "" {return comment_line}
	for l, i in lines[comment_line:] {
		t := strings.trim_space(l)
		if t != "" && !strings.has_prefix(t, "//") {return comment_line + 1 + i}
	}
	return comment_line
}

// An ignore for a rule that did not run, or in a package family C could not type-check, is
// never stale: a transient compile error must not report a suppression as stale.
apply_ignores :: proc(c: ^Ctx, igs: []Ignore, ran: map[string]bool) {
	r := c.r
	unchecked := make(map[string]bool, context.temp_allocator)
	for p in c.pkgs {if p.doc_skipped {unchecked[p.rel] = true}}
	kept := make([dynamic]Violation)
	for v in r.violations {
		hit := false
		if v.ignorable {
			for &ig in igs {
				// a package-level finding (v.file is a directory) takes a file-wide ignore in that package
				if ig.rule == v.rule &&
				   ((ig.file == v.file && (ig.target == 0 || ig.target == v.line)) ||
						   (ig.target == 0 && pkg_of(ig.file) == v.file)) {
					ig.used = true
					hit = true
				}
			}
		}
		if hit {r.summary.ignored += 1} else {append(&kept, v)}
	}
	r.violations = kept
	for ig in igs {
		if ig.used || ig.rule not_in ran {continue}
		unchecked_rule := false
		for entry in r.coverage.checks {
			if entry.package_dir == dir_of(ig.file) &&
			   entry.rule == ig.rule &&
			   entry.status != .complete {
				unchecked_rule = true
				break
			}
		}
		if unchecked_rule {continue}
		if rule := find_rule(c.rb, ig.rule);
		   rule != nil && is_family_c(rule.check.kind) && dir_of(ig.file) in unchecked {continue}
		note(
			r,
			"odx/stale-ignore",
			"ignores",
			ig.file,
			ig.line,
			ig.col,
			strings.concatenate({"ignore of ", ig.rule, " suppressed nothing"}),
		)
	}
}

// "" for a root-level file.
dir_of :: proc(rel: string) -> string {
	i := strings.last_index(rel, "/")
	return "" if i < 0 else rel[:i]
}

// `odx:ignore` misspelt by spacing, case or punctuation (`odx: ignore`, `odx-ignore`), not
// prose that mentions both words.
is_near_miss :: proc(low: string) -> bool {
	rest := strings.trim_left(low[len("odx"):], ":- ")
	if len(low) - len("odx") - len(rest) > 2 {return false}
	word, _, _ := strings.partition(rest, " ")
	return word == "ignore" || word == "ignore-file"
}

// pkg_of: the package directory as violations name it ("." for the root package).
pkg_of :: proc(rel: string) -> string {
	d := dir_of(rel)
	return "." if d == "" else d
}
