package odx

import "base:runtime"
import "core:fmt"
import "core:os"
import "core:slice"
import "core:testing"
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
