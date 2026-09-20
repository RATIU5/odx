package odx

import "core:odin/ast"
import "core:strings"

// Ignore is one `// odx:ignore <topic>/<R> reason: <text>` comment (17.8).
Ignore :: struct {
	file:   string,
	line:   int, // comment line
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
			if !strings.has_prefix(tok.text, "//") ||
			   !strings.has_prefix(text, IGNORE_PREFIX) {continue}
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
			case len(reason) < 10:
				bad = "reason must be at least 10 characters"
			case find_rule(rb, ruleid) == nil:
				bad = strings.concatenate({"unknown rule ", ruleid})
			}
			if bad != "" {
				add(
					r,
					{
						rel,
						tok.pos.line,
						tok.pos.column,
						"odx/bad-ignore",
						"",
						"ignores",
						bad,
						false,
					},
				)
				continue
			}
			append(
				out,
				Ignore {
					file = rel,
					line = tok.pos.line,
					rule = ruleid,
					reason = reason,
					target = ignore_target(lines, tok.pos.line, whole),
				},
			)
		}
	}
}

// ignore_target: whole file = 0; end-of-line comment = that line; own line = next code line.
// ponytail: a `//` inside a string literal before the comment counts as code; good enough.
@(private = "file")
ignore_target :: proc(lines: []string, comment_line: int, whole: bool) -> int {
	if whole {return 0}
	own := lines[comment_line - 1]
	if before := own[:strings.index(own, "//")];
	   strings.trim_space(before) != "" {return comment_line}
	for l, i in lines[comment_line:] {
		t := strings.trim_space(l)
		if t != "" && !strings.has_prefix(t, "//") {return comment_line + 1 + i}
	}
	return 0
}

// apply_ignores drops suppressed violations and reports stale ignores (17.8).
apply_ignores :: proc(r: ^Report, igs: []Ignore) {
	kept := make([dynamic]Violation)
	for v in r.violations {
		hit := false
		if v.ignorable {
			for &ig in igs {
				if ig.file == v.file &&
				   ig.rule == v.rule &&
				   (ig.target == 0 || ig.target == v.line) {
					ig.used = true
					hit = true
				}
			}
		}
		if hit {r.summary.ignored += 1} else {append(&kept, v)}
	}
	r.violations = kept
	for ig in igs {
		if !ig.used {
			add(
				r,
				{
					ig.file,
					ig.line,
					1,
					"odx/stale-ignore",
					"",
					"ignores",
					strings.concatenate({"ignore of ", ig.rule, " suppressed nothing"}),
					false,
				},
			)
		}
	}
}
