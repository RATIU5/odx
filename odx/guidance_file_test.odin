package odx

import "core:os"
import "core:strings"
import "core:testing"

GUIDANCE_TEST_BLOCK :: GUIDANCE_BEGIN + "\n## odx\n\nCurrent policy.\n" + GUIDANCE_END + "\n"

@(test)
test_guidance_preserves_human_bytes_and_detects_staleness :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	defer free_all(context.temp_allocator)
	root, err := os.make_directory_temp("", "odx-guidance-*", context.allocator)
	testing.expect(t, err == nil)
	defer os.remove_all(root)
	prefix := "# Human heading\r\nKeep whitespace.  \r\n\r\n"
	suffix := "\r\n# Human tail\r\nPreserve this without final newline"
	stale := GUIDANCE_BEGIN + "\n## odx\nOld policy.\n" + GUIDANCE_END + "\n"
	for name in ([]string{"AGENTS.md", "CLAUDE.md"}) {
		path := join({root, name})
		original := strings.concatenate({prefix, stale, suffix})
		testing.expect(t, os.write_entire_file(path, original) == nil)
		status, _ := guidance_sync(path, GUIDANCE_TEST_BLOCK, false)
		testing.expect_value(t, status, 1)
		unchanged, _ := os.read_entire_file(path, context.allocator)
		testing.expect_value(t, string(unchanged), original)
		status, _ = guidance_sync(path, GUIDANCE_TEST_BLOCK, true)
		testing.expect_value(t, status, 0)
		updated, _ := os.read_entire_file(path, context.allocator)
		testing.expect_value(
			t,
			string(updated),
			strings.concatenate({prefix, GUIDANCE_TEST_BLOCK, suffix}),
		)
		before, _ := os.stat(path, context.allocator)
		status, _ = guidance_sync(path, GUIDANCE_TEST_BLOCK, true)
		testing.expect_value(t, status, 0)
		after, _ := os.stat(path, context.allocator)
		testing.expect_value(t, after.inode, before.inode)
		status, _ = guidance_sync(path, GUIDANCE_TEST_BLOCK, false)
		testing.expect_value(t, status, 0)
	}
}

@(test)
test_guidance_rejects_ambiguous_ownership_without_mutation :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	defer free_all(context.temp_allocator)
	root, err := os.make_directory_temp("", "odx-guidance-*", context.allocator)
	testing.expect(t, err == nil)
	defer os.remove_all(root)
	path := join({root, "AGENTS.md"})
	invalid := []string {
		GUIDANCE_BEGIN + "\nmissing end",
		GUIDANCE_END + "\n" + GUIDANCE_BEGIN + "\n",
		GUIDANCE_TEST_BLOCK + GUIDANCE_TEST_BLOCK,
		GUIDANCE_BEGIN + "\n" + GUIDANCE_TEST_BLOCK + GUIDANCE_END + "\n",
		"prefix " + GUIDANCE_BEGIN + "\n" + GUIDANCE_END + "\n",
		"```markdown\n" + GUIDANCE_TEST_BLOCK + "```\n",
		"~~~markdown\n" + GUIDANCE_TEST_BLOCK + "~~~\n",
		"<!-- odx:begin v2 -->\nOld version\n" + GUIDANCE_END + "\n",
		"# Human intro\n## odx\nOld generated section\n# Human tail\n",
		"```\nUnclosed human fence",
	}
	for source in invalid {
		testing.expect(t, os.write_entire_file(path, source) == nil)
		for write in ([]bool{false, true}) {
			status, message := guidance_sync(path, GUIDANCE_TEST_BLOCK, write)
			testing.expect(t, status == 2, message)
			got, _ := os.read_entire_file(path, context.allocator)
			testing.expect_value(t, string(got), source)
		}
	}
}

@(test)
test_guidance_missing_append_and_destination_boundaries :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	defer free_all(context.temp_allocator)
	root, err := os.make_directory_temp("", "odx-guidance-*", context.allocator)
	testing.expect(t, err == nil)
	defer os.remove_all(root)
	path := join({root, "AGENTS.md"})
	status, _ := guidance_sync(path, GUIDANCE_TEST_BLOCK, false)
	testing.expect_value(t, status, 1)
	testing.expect(t, !os.exists(path))
	status, _ = guidance_sync(path, GUIDANCE_TEST_BLOCK, true)
	testing.expect_value(t, status, 0)
	got, _ := os.read_entire_file(path, context.allocator)
	testing.expect_value(t, string(got), GUIDANCE_TEST_BLOCK)
	human := "# Human policy\n```markdown\n## odx\n```\nNo final newline"
	testing.expect(t, os.write_entire_file(path, human) == nil)
	status, _ = guidance_sync(path, GUIDANCE_TEST_BLOCK, true)
	testing.expect_value(t, status, 0)
	got, _ = os.read_entire_file(path, context.allocator)
	testing.expect_value(t, string(got), strings.concatenate({human, "\n\n", GUIDANCE_TEST_BLOCK}))
	status, _ = guidance_sync(root, GUIDANCE_TEST_BLOCK, true)
	testing.expect_value(t, status, 2)
	status, _ = guidance_sync(join({root, "absent", "AGENTS.md"}), GUIDANCE_TEST_BLOCK, true)
	testing.expect_value(t, status, 2)
	when ODIN_OS != .Windows {
		mode := os.Permissions{.Read_User, .Write_User}
		testing.expect(t, os.chmod(path, mode) == nil)
		changed := GUIDANCE_BEGIN + "\n## odx\nChanged policy.\n" + GUIDANCE_END + "\n"
		status, _ = guidance_sync(path, changed, true)
		testing.expect_value(t, status, 0)
		info, _ := os.stat(path, context.allocator)
		testing.expect_value(t, info.mode, mode)
		link := join({root, "linked.md"})
		testing.expect(t, os.symlink(path, link) == nil)
		status, _ = guidance_sync(link, GUIDANCE_TEST_BLOCK, true)
		testing.expect_value(t, status, 2)
		got, _ = os.read_entire_file(path, context.allocator)
		testing.expect(t, strings.contains(string(got), "Changed policy."))
	}
}

@(test)
test_guidance_generated_marker_collision_is_rejected :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	defer free_all(context.temp_allocator)
	root, err := os.make_directory_temp("", "odx-guidance-*", context.allocator)
	testing.expect(t, err == nil)
	defer os.remove_all(root)
	path := join({root, "AGENTS.md"})
	malformed :=
		GUIDANCE_BEGIN +
		"\n## odx\nA rule quotes " +
		GUIDANCE_END +
		" inline.\n" +
		GUIDANCE_END +
		"\n"
	status, _ := guidance_sync(path, malformed, true)
	testing.expect_value(t, status, 2)
	testing.expect(t, !os.exists(path))
}
