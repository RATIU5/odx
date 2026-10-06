package golden_runner

import "core:testing"

@(test)
rerun_only_for_an_unexpected_compiler_crash :: proc(t: ^testing.T) {
	CRASH ::
		"--- stderr\n" +
		"odx: error: compiler-output: checking 'lib' for darwin_arm64 ended with exit code 11; stderr was empty\n" +
		"--- exit 2\n"
	CLEAN :: "--- stdout\nodx: 1 package checked\n--- stderr\n--- exit 0\n"
	cases := []struct {
		name:     string,
		expected: string,
		actual:   string,
		rerun:    bool,
	} {
		{"crash where a pass was expected", CLEAN, CRASH, true},
		{"crash where a crash was expected", CRASH, CRASH, false},
		{
			"crash where a crash in another package was expected",
			"odx: error: compiler-output: checking 'app' for darwin_arm64 ended with exit code 11; stderr was empty\n",
			CRASH,
			false,
		},
		{"plain mismatch", CLEAN, "--- stdout\n--- stderr\n--- exit 1\n", false},
		{"pass where a crash was expected", CRASH, CLEAN, false},
		{
			"another exit code",
			CLEAN,
			"odx: error: compiler-output: checking 'lib' for darwin_arm64 ended with exit code 5; stderr was empty\n",
			false,
		},
		{
			"exit 11 with stderr",
			CLEAN,
			"odx: error: compiler-output: checking 'lib' for darwin_arm64 ended with exit code 11; stderr:\n\tboom\n",
			false,
		},
		{
			"the crash text under another error code",
			CLEAN,
			"odx: error: dir-unreadable: ended with exit code 11; stderr was empty\n",
			false,
		},
	}
	for c in cases {
		testing.expectf(
			t,
			should_rerun(c.expected, c.actual) == c.rerun,
			"%s: want rerun %v",
			c.name,
			c.rerun,
		)
	}
}
