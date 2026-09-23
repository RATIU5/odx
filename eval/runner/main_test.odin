package eval

import "core:encoding/json"
import "core:path/filepath"
import "core:strings"
import "core:testing"

@(test)
test_extract_odin :: proc(t: ^testing.T) {
	code, ok := extract_odin("draft\n```odin\nold\n```\nfinal:\n```odin\nnew\n```\n")
	testing.expect(t, ok && code == "new\n")
	_, ok = extract_odin("```odin\nunterminated")
	testing.expect(t, !ok)
}

// A wrong, policy-violating answer: compiles, fails tests, one odx finding, and that finding
// reaches the revision turn only when the condition feeds findings back.
@(test)
test_episode_scores_failures :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	odx, _ := filepath.abs("build/odx", context.allocator)
	dir, _ := filepath.abs("eval/tasks/a/sum_evens", context.allocator)
	task := load_tasks(filepath.dir(dir), "sum_evens")[0]
	task.solution = "package task\n\nsum_evens :: proc(xs: []int) -> int {return len(xs)}\n"

	for cond in ([]Condition{.C0, .C2}) {
		traits := TRAITS
		a := Agent {
			opts = {agent = "reference", odx = odx},
		}
		out, err := episode(&a, traits[cond], task)
		testing.expect(t, err == nil)
		testing.expect(t, out.compiles && !out.tests_pass && out.edit_applied)
		testing.expect_value(t, out.odx_errors, 1)
		testing.expect_value(t, a.turns, REVISIONS + 1)
		last := string(a.messages[len(a.messages) - 1].content.(json.String))
		testing.expect_value(t, strings.contains(last, "allocators/R1"), cond == .C2)
	}
}
