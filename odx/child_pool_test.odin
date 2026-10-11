package odx

import "base:runtime"
import "core:fmt"
import "core:os"
import "core:slice"
import "core:strings"
import "core:sync"
import "core:testing"
import "core:thread"
import "core:time"

@(private = "file")
exit_code_of :: proc(end: Child_End, allocator: runtime.Allocator) -> (code: int, stop: bool) {
	exited, has_code := end.status.(Exited)
	return exited.code if end.error == "" && !end.timed_out && has_code else -1, false
}

@(private = "file")
sleep_commands :: proc(count: int, seconds: string) -> [][]string {
	commands := make([][]string, count, context.temp_allocator)
	for &c in commands {
		c = slice.clone([]string{"/bin/sleep", seconds}, context.temp_allocator)
	}
	return commands
}

@(private = "file")
run_shell :: proc(script: string, limit := 10 * time.Second, captured := Streams{}) -> Child_End {
	end, ended := run_captured(
		{command = {"/bin/sh", "-c", script}},
		captured,
		limit,
		nil,
		context.temp_allocator,
	)
	ensure(ended, "a wait that nothing could kill reports a kill")
	return end
}

@(test)
kill_pool_ends_the_running_children_at_once :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	budget: Child_Budget
	init_child_budget(&budget, 2)
	pool: Pool(int)
	config := Pool_Config(int) {
		commands = sleep_commands(4, "5"),
		captured = .Stdout,
		read     = exit_code_of,
		timeout  = 10 * time.Second,
		budget   = &budget,
	}
	started := time.tick_now()
	start_pool(&pool, config, context.temp_allocator)
	// Long enough for both children to have started.
	time.sleep(200 * time.Millisecond)
	kill_pool(&pool)
	join_pool(&pool)
	took := time.tick_since(started)
	destroy_pool(&pool)

	testing.expectf(t, took < 2 * time.Second, "the pool took %v to end", took)
	testing.expect_value(t, fmt.tprint(pool.runs), "[0, 0, 0, 0]")
}

@(test)
a_stopped_worker_ends_without_a_slot :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	budget: Child_Budget
	init_child_budget(&budget, 1)
	// Another pool's hung child holds the only slot.
	sync.sema_wait(&budget.slots)
	pool: Pool(int)
	config := Pool_Config(int) {
		commands = sleep_commands(1, "0"),
		captured = .Stdout,
		read     = exit_code_of,
		timeout  = 10 * time.Second,
		budget   = &budget,
	}
	start_pool(&pool, config, context.temp_allocator)
	kill_pool(&pool)
	started := time.tick_now()
	for !thread.is_done(pool.threads[0]) && time.tick_since(started) < 2 * time.Second {
		time.sleep(time.Millisecond)
	}
	ended_without_a_slot := thread.is_done(pool.threads[0])
	sync.sema_post(&budget.slots)
	join_pool(&pool)
	destroy_pool(&pool)

	testing.expect(t, ended_without_a_slot, "the stopped worker waited for a slot")
}

@(test)
a_started_pool_holds_its_slots_before_a_later_pool_starts :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	budget: Child_Budget
	init_child_budget(&budget, 2)
	pool: Pool(int)
	config := Pool_Config(int) {
		commands = sleep_commands(2, "0.2"),
		captured = .Stdout,
		read     = exit_code_of,
		timeout  = 10 * time.Second,
		budget   = &budget,
	}
	start_pool(&pool, config, context.temp_allocator)
	slot_was_free := sync.sema_wait_with_timeout(&budget.slots, time.Nanosecond)
	if slot_was_free {
		sync.sema_post(&budget.slots)
	}
	join_pool(&pool)
	destroy_pool(&pool)

	testing.expect(t, !slot_was_free, "a slot was free after the pool started")
	testing.expect_value(t, fmt.tprint(pool.runs), "[0, 0]")
}

@(private = "file")
Retry_Run :: struct {
	status:    Child_Status,
	timed_out: bool,
	retried:   bool,
}

// Each command appends a line to its own file every time it runs, so the file counts its runs.
@(test)
a_pool_runs_a_command_once_more_only_when_a_signal_ended_it_on_its_own :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	dir, err := os.make_directory_temp("", "odx-pool-*", context.temp_allocator)
	testing.expect_value(t, err, nil)
	defer os.remove_all(dir)

	cases := []struct {
		name:   string,
		script: string,
		retry:  bool,
		want:   Retry_Run,
		runs:   int,
	} {
		{
			"a crash, then a clean run",
			`echo x >> "$0"; [ "$(wc -l < "$0")" -eq 2 ] || kill -SEGV $$`,
			true,
			{status = Exited{0}, retried = true},
			2,
		},
		{
			"a crash both times",
			`echo x >> "$0"; kill -SEGV $$`,
			true,
			{status = Signaled{11}, retried = true},
			2,
		},
		{
			"a kill from outside both times",
			`echo x >> "$0"; kill -KILL $$`,
			true,
			{status = Signaled{9}, retried = true},
			2,
		},
		{"exit code 11", `echo x >> "$0"; exit 11`, true, {status = Exited{11}}, 1},
		{
			"odx's own kill at the limit",
			`echo x >> "$0"; exec sleep 30`,
			true,
			{status = Signaled{9}, timed_out = true},
			1,
		},
		{
			"a crash in a pool that doesn't retry",
			`echo x >> "$0"; kill -SEGV $$`,
			false,
			{status = Signaled{11}},
			1,
		},
	}
	for c, i in cases {
		counter := fmt.tprintf("%s/%d", dir, i)
		budget: Child_Budget
		init_child_budget(&budget, 1)
		pool: Pool(Retry_Run)
		config := Pool_Config(Retry_Run) {
			commands = {{"/bin/sh", "-c", c.script, counter}},
			captured = .Stderr,
			retry_signaled = c.retry,
			read = proc(end: Child_End, allocator: runtime.Allocator) -> (Retry_Run, bool) {
				return {end.status, end.timed_out, end.retried}, false
			},
			timeout = 300 * time.Millisecond,
			budget = &budget,
		}
		start_pool(&pool, config, context.temp_allocator)
		join_pool(&pool)
		got := pool.runs[0]
		destroy_pool(&pool)

		lines, read_err := os.read_entire_file(counter, context.temp_allocator)
		testing.expect_value(t, read_err, nil)
		testing.expectf(t, got == c.want, "%s: got %v, want %v", c.name, got, c.want)
		testing.expectf(t, len(lines) == 2 * c.runs, "%s: ran %d times", c.name, len(lines) / 2)
	}
}

@(test)
died_on_its_own_is_a_signal_that_odx_didnt_send :: proc(t: ^testing.T) {
	cases := []struct {
		name: string,
		end:  Child_End,
		want: bool,
	} {
		{"SIGSEGV", {status = Signaled{11}}, true},
		{"SIGKILL from outside", {status = Signaled{9}}, true},
		{"SIGKILL from odx at the limit", {status = Signaled{9}, timed_out = true}, false},
		{"exit code 11", {status = Exited{11}}, false},
		{"exit code 0", {}, false},
		{"exit code 139, a shell's name for SIGSEGV", {status = Exited{139}}, false},
		{
			"a child odx killed because it lost the stream",
			{status = Signaled{9}, error = "started, but odx couldn't read its output"},
			false,
		},
	}
	for c in cases {
		testing.expectf(t, died_on_its_own(c.end) == c.want, "%s: want %v", c.name, c.want)
	}
}

@(test)
charge_poll_caps_what_one_poll_costs :: proc(t: ^testing.T) {
	LIMIT :: 120 * time.Second
	cases := []struct {
		name:              string,
		left, slice, want: time.Duration,
	} {
		{"a poll that took its length", LIMIT, KILL_POLL, LIMIT - KILL_POLL},
		{
			"a poll the scheduler held a little",
			LIMIT,
			KILL_POLL + 5 * time.Millisecond,
			LIMIT - KILL_POLL - 5 * time.Millisecond,
		},
		{
			"a poll the machine slept through for ten minutes",
			LIMIT,
			600 * time.Second,
			LIMIT - 2 * KILL_POLL,
		},
		{"the last poll", KILL_POLL, KILL_POLL, 0},
		{"a clock that went back", time.Second, -time.Second, time.Second},
	}
	for c in cases {
		got := charge_poll(c.left, c.slice, KILL_POLL)
		testing.expectf(t, got == c.want, "%s: got %v, want %v", c.name, got, c.want)
	}
}

@(test)
run_captured_tells_a_signal_from_an_exit_code :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	cases := []struct {
		script: string,
		want:   Child_Status,
	} {
		{"kill -SEGV $$", Signaled{11}},
		{"exit 11", Exited{11}},
		{"kill -KILL $$", Signaled{9}},
		{"kill -TRAP $$", Signaled{5}},
		{"exit 139", Exited{139}},
		{"exit 0", Exited{0}},
	}
	for c in cases {
		end := run_shell(c.script)
		testing.expectf(t, end.error == "", "%s: %s", c.script, end.error)
		testing.expectf(t, !end.timed_out, "%s: timed out", c.script)
		testing.expectf(
			t,
			end.status == c.want,
			"%s: got %v, want %v",
			c.script,
			end.status,
			c.want,
		)
	}
}

@(test)
run_captured_returns_the_captured_streams_and_drops_the_other :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	SCRIPT :: "printf out; printf err >&2; exit 3"
	both := run_shell(SCRIPT, captured = {.Stdout, .Stderr})
	testing.expect_value(t, both.error, "")
	testing.expect_value(t, both.status, Exited{3})
	testing.expect_value(t, both.captured, [Stream]string{.Stdout = "out", .Stderr = "err"})

	one := run_shell(SCRIPT, captured = {.Stderr})
	testing.expect_value(t, one.captured, [Stream]string{.Stdout = "", .Stderr = "err"})
}

@(test)
run_captured_reads_a_100_mb_stream_whole :: proc(t: ^testing.T) {
	SIZE :: 100 << 20
	started := time.tick_now()
	end, _ := run_captured(
		{command = {"/bin/sh", "-c", "head -c 104857600 /dev/zero | tr '\\0' x; printf end"}},
		{.Stdout},
		60 * time.Second,
		nil,
		context.allocator,
	)
	defer delete(end.captured[.Stdout])
	text := end.captured[.Stdout]
	testing.expect_value(t, end.error, "")
	testing.expect_value(t, end.status, Exited{0})
	testing.expect_value(t, len(text), SIZE + len("end"))
	testing.expect(t, strings.has_suffix(text, "xend"), "the stream's end is missing")
	testing.expect_value(t, strings.count(text, "x"), SIZE)
	// Reading it took 10 s when the buffer grew by one read at a time.
	took := time.tick_since(started)
	testing.expectf(t, took < 5 * time.Second, "the read took %v", took)
}

@(test)
run_captured_kills_a_child_that_writes_past_the_cap :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	CAP :: 1 << 20
	capped :: proc(script: string, stream: Stream) -> Child_End {
		end, ended := run_captured(
			{command = {"/bin/sh", "-c", script}},
			{stream},
			10 * time.Second,
			nil,
			context.temp_allocator,
			CAP,
		)
		ensure(ended, "a wait that nothing could kill reports a kill")
		return end
	}

	started := time.tick_now()
	endless := capped("exec yes flood >&2", .Stderr)
	took := time.tick_since(started)
	WANT :: "wrote more than 1 MB to its stderr, the most odx reads from one stream"
	testing.expect_value(t, endless.error, WANT)
	testing.expect_value(t, endless.status, Signaled{9})
	testing.expect(t, !endless.timed_out, "the cap was reported as a timeout")
	testing.expect_value(t, endless.captured[.Stderr], "")
	testing.expect(t, !died_on_its_own(endless), "a child odx killed at the cap would run again")
	testing.expectf(t, took < 2 * time.Second, "the kill took %v", took)

	at_cap := capped("head -c 1048576 /dev/zero", .Stdout)
	testing.expect_value(t, at_cap.error, "")
	testing.expect_value(t, at_cap.status, Exited{0})
	testing.expect_value(t, len(at_cap.captured[.Stdout]), CAP)

	// The child ends before odx has read it all, so the last bytes come from the closed pipe.
	one_over := capped("head -c 1048577 /dev/zero", .Stdout)
	testing.expect(
		t,
		strings.has_prefix(one_over.error, "wrote more than 1 MB to its stdout"),
		one_over.error,
	)
	testing.expect_value(t, one_over.captured[.Stdout], "")
}

@(test)
status_text_tells_a_signal_from_an_exit_code :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	cases := []struct {
		script: string,
		want:   string,
	} {
		{"kill -SEGV $$", "signal 11"},
		{"kill -KILL $$", "signal 9"},
		{"kill -HUP $$", "signal 1"},
		{"exit 11", "exit 11"},
		{"exit 139", "exit 139"},
	}
	for c in cases {
		end := run_shell(c.script)
		got := status_text(end.status, context.temp_allocator)
		testing.expectf(t, got == c.want, "%s: got %q, want %q", c.script, got, c.want)
	}
}

@(test)
run_captured_kills_a_child_at_its_limit_and_keeps_what_it_wrote :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	started := time.tick_now()
	end := run_shell("echo before; exec sleep 30", 200 * time.Millisecond, {.Stdout})
	took := time.tick_since(started)

	testing.expect_value(t, end.error, "")
	testing.expect(t, end.timed_out, "the child didn't time out")
	testing.expect_value(t, end.status, Signaled{9})
	testing.expect_value(t, end.captured[.Stdout], "before\n")
	testing.expectf(
		t,
		200 * time.Millisecond <= took && took < 2 * time.Second,
		"the wait took %v",
		took,
	)
}

// A killed wrapper script leaves such a process behind, and reading the pipe to its end would wait
// for it.
@(test)
run_captured_doesnt_wait_for_a_process_the_child_left_holding_the_pipe :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	started := time.tick_now()
	quiet := run_shell("sleep 3 & echo done", captured = {.Stdout})
	took := time.tick_since(started)
	testing.expect_value(t, quiet.error, "")
	testing.expect_value(t, quiet.status, Exited{0})
	testing.expect_value(t, quiet.captured[.Stdout], "done\n")
	testing.expectf(t, took < 2 * time.Second, "the wait took %v", took)

	// `yes` ends itself once odx closes the pipe.
	started = time.tick_now()
	loud := run_shell("yes & sleep 0.2", captured = {.Stdout})
	took = time.tick_since(started)
	testing.expect_value(t, loud.error, "")
	testing.expect_value(t, loud.status, Exited{0})
	testing.expectf(t, took < 2 * time.Second, "the wait took %v", took)
}

@(test)
run_captured_says_why_a_child_didnt_start :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	end, ended := run_captured(
		{command = {"/nonexistent/odx-test-binary", "check"}},
		{.Stderr},
		time.Second,
		nil,
		context.temp_allocator,
	)
	testing.expect(t, ended, "the wait reports a kill that nobody asked for")
	testing.expect(t, strings.has_prefix(end.error, "couldn't start: "), end.error)
	testing.expect_value(t, end.captured[.Stderr], "")
}
