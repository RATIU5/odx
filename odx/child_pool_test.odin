package odx

import "base:runtime"
import "core:fmt"
import "core:os"
import "core:slice"
import "core:sync"
import "core:sys/posix"
import "core:testing"
import "core:thread"
import "core:time"

@(private = "file")
exit_code_of :: proc(end: Child_End, allocator: runtime.Allocator) -> (code: int, stop: bool) {
	return end.exit_code if end.failure == "" && !end.timed_out else -1, false
}

@(private = "file")
sleep_commands :: proc(count: int, seconds: string) -> [][]string {
	commands := make([][]string, count, context.temp_allocator)
	for &c in commands {
		c = slice.clone([]string{"/bin/sleep", seconds}, context.temp_allocator)
	}
	return commands
}

@(test)
two_pools_share_one_budget_of_children :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	dir, err := os.make_directory_temp("", "odx-pool-*", context.temp_allocator)
	testing.expect_value(t, err, nil)
	defer os.remove_all(dir)

	LIMIT :: 3
	budget: Child_Budget
	init_child_budget(&budget, LIMIT)
	pools: [2]Pool(int)
	for &pool, i in pools {
		config := Pool_Config(int) {
			commands = sleep_commands(8, "0.05"),
			captured = Stream(i),
			read     = exit_code_of,
			temp_dir = dir,
			timeout  = 10 * time.Second,
			budget   = &budget,
		}
		start_pool(&pool, config, context.temp_allocator)
	}
	for &pool in pools {
		join_pool(&pool)
	}
	for &pool, i in pools {
		for code, job in pool.runs {
			testing.expectf(t, code == 0, "pool %d job %d ended with %d", i, job, code)
		}
		destroy_pool(&pool)
	}
	testing.expect_value(t, budget.peak, LIMIT)
	testing.expect_value(t, budget.live, 0)
}

@(test)
kill_pool_ends_the_running_children_at_once :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	dir, err := os.make_directory_temp("", "odx-pool-*", context.temp_allocator)
	testing.expect_value(t, err, nil)
	defer os.remove_all(dir)

	budget: Child_Budget
	init_child_budget(&budget, 2)
	pool: Pool(int)
	config := Pool_Config(int) {
		commands = sleep_commands(4, "5"),
		captured = .Stdout,
		read     = exit_code_of,
		temp_dir = dir,
		timeout  = 10 * time.Second,
		budget   = &budget,
	}
	started := time.tick_now()
	start_pool(&pool, config, context.temp_allocator)
	for budget.peak < 2 && time.tick_since(started) < 2 * time.Second {
		time.sleep(time.Millisecond)
	}
	kill_pool(&pool)
	join_pool(&pool)
	took := time.tick_since(started)
	destroy_pool(&pool)

	testing.expectf(t, took < 2 * time.Second, "the pool took %v to end", took)
	testing.expect_value(t, budget.live, 0)
	testing.expect_value(t, fmt.tprint(pool.runs), "[0, 0, 0, 0]")
}

@(test)
a_stopped_worker_ends_without_a_slot :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	dir, err := os.make_directory_temp("", "odx-pool-*", context.temp_allocator)
	testing.expect_value(t, err, nil)
	defer os.remove_all(dir)

	budget: Child_Budget
	init_child_budget(&budget, 1)
	// Another pool's hung child holds the only slot.
	sync.sema_wait(&budget.slots)
	pool: Pool(int)
	config := Pool_Config(int) {
		commands = sleep_commands(1, "0"),
		captured = .Stdout,
		read     = exit_code_of,
		temp_dir = dir,
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
	testing.expect_value(t, budget.peak, 0)
}

@(test)
a_started_pool_holds_its_slots_before_a_later_pool_starts :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	dir, err := os.make_directory_temp("", "odx-pool-*", context.temp_allocator)
	testing.expect_value(t, err, nil)
	defer os.remove_all(dir)

	budget: Child_Budget
	init_child_budget(&budget, 2)
	pool: Pool(int)
	config := Pool_Config(int) {
		commands = sleep_commands(2, "0.2"),
		captured = .Stdout,
		read     = exit_code_of,
		temp_dir = dir,
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
wait_child_kills_and_reaps_a_child_that_outruns_its_limit :: proc(t: ^testing.T) {
	process, err := os.process_start({command = {"/bin/sleep", "30"}})
	testing.expect_value(t, err, nil)
	started := time.tick_now()
	state, wait_err, timed_out, ended := wait_child(process, 200 * time.Millisecond)
	took := time.tick_since(started)

	testing.expect_value(t, wait_err, nil)
	testing.expect(t, timed_out, "the child didn't time out")
	testing.expect(t, ended, "the wait reports a kill that nobody asked for")
	testing.expect_value(t, state.exit_code, posix.SIGKILL)
	testing.expectf(
		t,
		200 * time.Millisecond <= took && took < 2 * time.Second,
		"the wait took %v",
		took,
	)
}

@(test)
wait_child_returns_how_a_child_within_its_limit_ended :: proc(t: ^testing.T) {
	process, err := os.process_start({command = {"/bin/sh", "-c", "exit 3"}})
	testing.expect_value(t, err, nil)
	state, wait_err, timed_out, ended := wait_child(process, 10 * time.Second)

	testing.expect_value(t, wait_err, nil)
	testing.expect(t, !timed_out, "the child timed out")
	testing.expect(t, ended, "the wait reports a kill that nobody asked for")
	testing.expect_value(t, state.exit_code, 3)
}
