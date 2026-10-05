package odx

import "base:runtime"
import "core:fmt"
import "core:mem/virtual"
import "core:os"
import "core:strconv"
import "core:strings"
import "core:sync"
import si "core:sys/info"
import "core:thread"
import "core:time"

// How often a worker that waits for its child looks for `kill_pool`.
KILL_POLL :: 20 * time.Millisecond

Stream :: enum u8 {
	Stdout,
	Stderr,
}

@(rodata)
STREAM_NAMES := [Stream]string {
	.Stdout = "stdout",
	.Stderr = "stderr",
}

// The children odx may run at once, over every pool that shares the budget. A worker takes a slot
// before it starts a child and gives it back after the reap. A budget must not move once a pool has
// started with it.
Child_Budget :: struct {
	limit: int,
	slots: sync.Sema,
	// The children started and not yet reaped, and the most there have been at once.
	live:  int,
	peak:  int,
}

init_child_budget :: proc(budget: ^Child_Budget, limit: int) {
	budget.limit = limit
	sync.sema_post(&budget.slots, limit)
}

// One heavy check can peak at 600 MB (probe R-G), so odx never runs more children at once than
// there are gigabytes of RAM.
worker_count :: proc() -> int {
	n := os.get_processor_core_count()
	if total, _, _, _, ok := si.ram_stats(); ok {
		n = min(n, int(total / (1 << 30)))
	}
	return max(n, 1)
}

// `failure` says why odx couldn't run the child or read what it wrote, and is "" otherwise. A child
// that a signal ended has the signal's number as its exit code.
Child_End :: struct {
	failure:   string,
	timed_out: bool,
	exit_code: int,
	captured:  string,
}

Pool_Config :: struct($Run: typeid) {
	commands:    [][]string,
	// "" is odx's own working directory.
	working_dir: string,
	// The child's other stream is discarded.
	captured:    Stream,
	// Decides a job's run from how its child ended, on a worker thread. `stop` true starts no more
	// children. The run may borrow `end` and allocates the rest with `allocator`, both of which live
	// until `destroy_pool`.
	read:        proc(end: Child_End, allocator: runtime.Allocator) -> (run: Run, stop: bool),
	// Where each child's captured stream is written. Two pools can share it when they capture
	// different streams.
	temp_dir:    string,
	timeout:     time.Duration,
	budget:      ^Child_Budget,
}

// Each worker writes only its own arena and the `runs` slots of the jobs it takes, so `next`, `stop`,
// `killed` and the budget are the only shared state. A pool must not move between `start_pool` and
// `join_pool`.
Pool :: struct($Run: typeid) {
	using config: Pool_Config(Run),
	// Indexed by command. A job that never started, or that `kill_pool` ended, keeps the zero value.
	runs:         []Run,
	arenas:       []virtual.Arena,
	threads:      []^thread.Thread,
	next:         int,
	stop:         bool,
	killed:       bool,
}

// Allocates the pool's lists with `allocator`.
start_pool :: proc(pool: ^Pool($Run), config: Pool_Config(Run), allocator: runtime.Allocator) {
	pool.config = config
	pool.runs = make([]Run, len(pool.commands), allocator)
	if len(pool.commands) == 0 {
		return
	}
	pool.arenas = make([]virtual.Arena, min(pool.budget.limit, len(pool.commands)), allocator)
	pool.threads = make([]^thread.Thread, len(pool.arenas), allocator)
	for &arena, i in pool.arenas {
		ensure(virtual.arena_init_growing(&arena) == nil, "out of memory")
		pool.threads[i] = thread.create_and_start_with_poly_data2(pool, i, pool_worker(Run))
	}
}

// Starts no more children and has each worker kill and reap the one it runs, within `KILL_POLL`.
// `join_pool` must follow.
kill_pool :: proc(pool: ^Pool($Run)) {
	sync.atomic_store(&pool.stop, true)
	sync.atomic_store(&pool.killed, true)
}

join_pool :: proc(pool: ^Pool($Run)) {
	if len(pool.threads) == 0 {
		return
	}
	thread.join_multiple(..pool.threads)
	for t in pool.threads {
		thread.destroy(t)
	}
	pool.threads = nil
}

// Frees what the runs borrow. Call it after `join_pool`.
destroy_pool :: proc(pool: ^Pool($Run)) {
	for &arena in pool.arenas {
		virtual.arena_destroy(&arena)
	}
	pool.arenas = nil
}

// Takes a slot and then a job, so every job before the last one started has run.
@(private = "file")
pool_worker :: proc($Run: typeid) -> proc(pool: ^Pool(Run), worker: int) {
	return proc(pool: ^Pool(Run), worker: int) {
			allocator := virtual.arena_allocator(&pool.arenas[worker])
			for {
				sync.sema_wait(&pool.budget.slots)
				job := len(pool.commands)
				if !sync.atomic_load(&pool.stop) {
					job = sync.atomic_add(&pool.next, 1)
				}
				end: Child_End
				ended := false
				if job < len(pool.commands) {
					end, ended = run_child(pool, job, allocator)
				}
				sync.sema_post(&pool.budget.slots)
				if !ended {
					break
				}
				run, stop := pool.read(end, allocator)
				pool.runs[job] = run
				if stop {
					sync.atomic_store(&pool.stop, true)
				}
			}
		}
}

// `ended` is false when `kill_pool` ended the child, which then has no `end` to read. The captured
// stream goes to a named file, because `os.create_temp_file` captured nothing in the reader probe
// (Appendix C).
@(private = "file")
run_child :: proc(
	pool: ^Pool($Run),
	job: int,
	allocator: runtime.Allocator,
) -> (
	end: Child_End,
	ended: bool,
) {
	ended = true
	stream := STREAM_NAMES[pool.captured]
	path := fmt.aprintf("%s/%d.%s", pool.temp_dir, job, stream, allocator = allocator)
	file, create_err := os.create(path)
	if create_err != nil {
		end.failure = fmt.aprintf(
			"couldn't capture %s: %s",
			stream,
			os.error_string(create_err),
			allocator = allocator,
		)
		return
	}
	desc := os.Process_Desc {
		working_dir = pool.working_dir,
		command     = pool.commands[job],
	}
	switch pool.captured {
	case .Stdout:
		desc.stdout = file
	case .Stderr:
		desc.stderr = file
	}
	process, start_err := os.process_start(desc)
	os.close(file)
	if start_err != nil {
		end.failure = fmt.aprintf(
			"couldn't start: %s",
			os.error_string(start_err),
			allocator = allocator,
		)
		return
	}
	live := sync.atomic_add(&pool.budget.live, 1) + 1
	for peak := sync.atomic_load(&pool.budget.peak); live > peak; {
		seen, swapped := sync.atomic_compare_exchange_strong(&pool.budget.peak, peak, live)
		if swapped {
			break
		}
		peak = seen
	}
	started := time.tick_now()
	state: os.Process_State
	wait_err: os.Error
	for {
		left := pool.timeout - time.tick_since(started)
		ended = !sync.atomic_load(&pool.killed)
		end.timed_out = left <= 0
		if !ended || end.timed_out {
			_ = os.process_kill(process)
			state, wait_err = os.process_wait(process)
			break
		}
		// The wait reaps the child, so only the waiting thread can know its pid is still the child's.
		state, wait_err = os.process_wait(process, min(left, KILL_POLL))
		if wait_err != os.General_Error.Timeout {
			break
		}
	}
	sync.atomic_sub(&pool.budget.live, 1)
	if !ended {
		return
	}
	if wait_err != nil {
		end.failure = fmt.aprintf(
			"couldn't be waited for: %s",
			os.error_string(wait_err),
			allocator = allocator,
		)
		return
	}
	end.exit_code = state.exit_code
	captured, read_err := os.read_entire_file(path, allocator)
	if read_err != nil {
		end.failure = fmt.aprintf(
			"couldn't read its %s: %s",
			stream,
			os.error_string(read_err),
			allocator = allocator,
		)
		return
	}
	end.captured = string(captured)
	return
}

// The variable's value in a debug build, and "" in a release build, so a shipped result can't
// depend on the environment. Allocates with `context.temp_allocator`.
debug_env :: proc(name: string) -> string {
	when ODIN_DEBUG {
		return os.get_env(name, context.temp_allocator)
	} else {
		return ""
	}
}

// Golden cases test a timeout without waiting two minutes, by naming milliseconds in `variable`.
debug_timeout :: proc(variable: string, fallback: time.Duration) -> time.Duration {
	if ms, ok := strconv.parse_int(debug_env(variable), 10); ok && ms > 0 {
		return time.Duration(ms) * time.Millisecond
	}
	return fallback
}

write_timeout :: proc(b: ^strings.Builder, timeout: time.Duration) {
	if timeout % time.Second == 0 {
		fmt.sbprintf(b, "timed out after %d s", int(timeout / time.Second))
	} else {
		fmt.sbprintf(b, "timed out after %d ms", int(timeout / time.Millisecond))
	}
}
