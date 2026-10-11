package odx

import "base:runtime"
import "core:fmt"
import "core:odin/ast"
import "core:odin/tokenizer"
import "core:slice"
import "core:strings"

AUTO_CAST_MESSAGE :: "'auto_cast' isn't allowed"
TRANSMUTE_MESSAGE :: "'transmute' isn't allowed"
FALLTHROUGH_MESSAGE :: "'fallthrough' isn't allowed"
BLOCK_COMMENT_MESSAGE :: "block comments aren't allowed"
ONE_LINE_BLOCK_MESSAGE :: "this block opens and closes on one line"
BOUNDS_CHECK_MESSAGE :: "'#bounds_check' isn't allowed"
NO_BOUNDS_CHECK_MESSAGE :: "'#no_bounds_check' isn't allowed"

// The `#+feature` items that turn off an error of the pinned compiler, per
// `get_feature_flag_from_name` in build_settings.cpp and the places the checker reads each flag.
// Reread them on a compiler bump.
@(private = "file", rodata)
RELAXING_FEATURES := [?]string{"using-stmt", "dynamic-literals", "global-context"}

check_block_comments :: proc(w: ^File_Walk, groups: []^ast.Comment_Group) {
	for group in groups {
		for comment in group.list {
			if strings.has_prefix(comment.text, "/*") {
				report(w, .Block_Comment, comment.pos, BLOCK_COMMENT_MESSAGE)
			}
		}
	}
}

// The parser wraps a `do` body in a block, which is no finding.
check_block :: proc(w: ^File_Walk, block: ^ast.Block_Stmt, is_proc_or_foreign_block_body: bool) {
	if block.uses_do ||
	   len(block.stmts) == 0 ||
	   block.pos.line != block.end.line ||
	   is_proc_or_foreign_block_body {
		return
	}
	report(w, .One_Line_Block, block.pos, ONE_LINE_BLOCK_MESSAGE)
}

// The parser sets the directive's flag on the statement or expression after it. A procedure
// literal's directive sits on its type too, as a tag, so the walk reports the type's tags and not
// the literal's.
check_bounds_check :: proc(w: ^File_Walk, pos: tokenizer.Pos, on, off: bool) {
	if on {
		report(w, .Bounds_Check_Directive, pos, BOUNDS_CHECK_MESSAGE)
	}
	if off {
		report(w, .Bounds_Check_Directive, pos, NO_BOUNDS_CHECK_MESSAGE)
	}
}

// Reports `vet-disabled` and `feature-relaxed` from the header's tags, so both also run on a file
// the parser can't read. Each message is allocated with `findings`' allocator, and the findings
// borrow `path`. `scratch` holds the working lists.
check_file_tags :: proc(
	findings: ^[dynamic]Finding,
	path, src: string,
	tags: []File_Tag,
	scratch: runtime.Allocator,
) {
	for tag in tags {
		text := trim_tag_space(tag.body)
		rule: Rule
		format: string
		switch {
		case is_spaced_tag(text, "vet"):
			rule, format = .Vet_Disabled, "this tag turns off vet checks: %s"
		case is_spaced_tag(text, "feature"):
			rule, format = .Feature_Relaxed, "this tag relaxes compiler checks: %s"
		case:
			continue
		}
		items := reported_tag_items(text, rule, scratch)
		if len(items) == 0 {
			continue
		}
		line, col := source_position(src, tag.pos)
		message := fmt.aprintf(
			format,
			strings.join(items, ", ", scratch),
			allocator = findings.allocator,
		)
		append(
			findings,
			Finding{path = path, line = line, col = col, rule = rule, message = message},
		)
	}
}

@(private = "file")
is_spaced_tag :: proc(text, name: string) -> bool {
	return strings.has_prefix(text, name) && !build_require_space_after(text, name)
}

// The items of a `#+vet` or `#+feature` tag that its rule reports, each once, read as
// `parse_vet_tag` and `parse_feature_tag` in parser.cpp read them. The names borrow from `text`,
// and the caller owns the slice, allocated with `allocator`.
@(private = "file")
reported_tag_items :: proc(text: string, rule: Rule, allocator: runtime.Allocator) -> []string {
	is_vet := rule == .Vet_Disabled
	names := make([dynamic]string, allocator)
	rest := text[len(is_vet ? "vet" : "feature"):]
	for len(rest) > 0 {
		item: string
		item, rest = tag_get_token(rest, is_vet ? "-" : "-:")
		name: string
		if !is_vet {
			if slice.contains(RELAXING_FEATURES[:], item) {
				name = item
			}
		} else if strings.has_prefix(item, "!") {
			name = item[1:]
		}
		if name != "" && !slice.contains(names[:], name) {
			append(&names, name)
		}
	}
	return names[:]
}
