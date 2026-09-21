package odx

import "core:odin/ast"
import "core:strings"

// Ignore is one `// odx:ignore <topic>/<R> reason: <text>` comment (17.8).
Ignore :: struct {
	file:   string,
	line:   int, // comment line
	col:    int, // column of the `//`
	target: int, // line it applies to; 0 = whole file
	rule:   string,
	reason: string,
	used:   bool,
}

IGNORE_PREFIX :: "odx:ignore"
IGNORE_FILE_PREFIX :: IGNORE_PREFIX + "-file"

// collect_ignores scans a file's comment groups. Bad ones become odx/bad-ignore violations.
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
				// a near miss (`odx: ignore`, `odx:Ignore`, `odx-ignore`) fails loudly, never silently (M3.3)
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

// ignore_target: whole file = 0; end-of-line comment = that line; own line = next code line.
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

// apply_ignores drops suppressed violations and reports stale ignores (17.8). An ignore for a
// rule that did not run this pass, or in a package family C could not type-check, is not
// stale (20.2): a transient compile error must never report a suppression as stale.
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

// dir_of: the package directory of a root-relative file path ("" for a root-level file).
dir_of :: proc(rel: string) -> string {
	i := strings.last_index(rel, "/")
	return "" if i < 0 else rel[:i]
}

// is_near_miss: `odx:ignore` misspelt by spacing, case or punctuation (`odx: ignore`, `odx-ignore`,
// `odx Ignore`), not prose that happens to mention both words.
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
