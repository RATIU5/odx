package runner

import "core:testing"

@(test)
rerun_only_for_an_unexpected_compiler_signal :: proc(t: ^testing.T) {
	TWICE ::
		"--- stderr\n" +
		"odx: error: compiler-output: checking 'lib' for darwin_arm64 " +
		"died by signal 11 twice; stderr was empty\n" +
		"--- exit 2\n"
	CLEAN :: "--- stdout\nodx: 1 package checked\n--- stderr\n--- exit 0\n"
	RETRIED ::
		"--- stdout\nodx: 1 package checked\n--- stderr\n" +
		"odx: the compiler died by a signal 1 times, and odx ran it again each time\n" +
		"--- exit 0\n"
	cases := []struct {
		name:     string,
		expected: string,
		actual:   string,
		rerun:    bool,
	} {
		{"a second death where a pass was expected", CLEAN, TWICE, true},
		{"a retry where a pass was expected", CLEAN, RETRIED, true},
		{"a second death where one was expected", TWICE, TWICE, false},
		{"a retry where one was expected", RETRIED, RETRIED, false},
		{"a retry where a second death was expected", TWICE, RETRIED, false},
		{"plain mismatch", CLEAN, "--- stdout\n--- stderr\n--- exit 1\n", false},
		{"pass where a second death was expected", TWICE, CLEAN, false},
		{
			"an exit code, which is no signal",
			CLEAN,
			"odx: error: compiler-output: checking 'lib' for darwin_arm64 " +
			"ended with exit code 11; stderr was empty\n",
			false,
		},
		{
			"the signal text under another error code",
			CLEAN,
			"odx: error: dir-unreadable: died by signal 11 twice; stderr was empty\n",
			false,
		},
		{
			"the retry line as a finding's message",
			CLEAN,
			"a.odin:1:1: odin: odx: the compiler died by a signal 1 times\n",
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
