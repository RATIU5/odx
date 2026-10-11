package odx

import "base:runtime"
import "core:fmt"
import "core:mem/virtual"
import "core:os"
import "core:strconv"
import "core:strings"
import "core:sync"
import si "core:sys/info"
import "core:sys/posix"
import "core:thread"
import "core:time"

// How often a worker that waits for a slot or for its child looks for a stop.
KILL_POLL :: 20 * time.Millisecond

Stream :: enum u8 {
	Stdout,
	Stderr,
}

Streams :: bit_set[Stream;u8]

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

Exited :: struct {
	code: int,
}

Signaled :: struct {
	signal: int,
}

// How a child ended. `os.process_wait` gives a signal's number as an exit code, so odx asks the
// system itself.
Child_Status :: union #no_nil {
	Exited,
	Signaled,
}

// `error` says why odx couldn't run the child or can't believe what it read of the child's
// streams, and is "" otherwise. With an error, nothing is captured.
Child_End :: struct {
	error:     string,
	// odx killed the child at its limit.
	timed_out: bool,
	// The pool ran the command a second time, and this is how that run ended.
	retried:   bool,
	status:    Child_Status,
	captured:  [Stream]string,
}

Pool_Config :: struct($Run: typeid) {
	commands:       [][]string,
	// "" is odx's own working directory.
	working_dir:    string,
	// The child's other stream is discarded.
	captured:       Stream,
	// Runs a command once more, in the same slot, when its child `died_on_its_own`.
	retry_signaled: bool,
	// Decides a job's run from how its child ended, on a worker thread. `stop` true starts no more
	// children. The run may borrow `end` and allocates the rest with `allocator`, both of which
	// live until `destroy_pool`.
	read:           proc(end: Child_End, allocator: runtime.Allocator) -> (run: Run, stop: bool),
	timeout:        time.Duration,
	budget:         ^Child_Budget,
}

// Each worker writes only its own arena and the `runs` slots of the jobs it takes, so `next`,
// `stop`, `killed` and the budget are the only shared state. A pool must not move between
// `start_pool` and `join_pool`.
Pool :: struct($Run: typeid) {
	using config: Pool_Config(Run),
	// Indexed by command. A job that never started, or that `kill_pool` ended, keeps the zero
	// value.
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
		// A slot that is free now goes to this worker, so a pool that starts later can't take it
		// first. A zero wait never takes a slot.
		has_slot := sync.sema_wait_with_timeout(&pool.budget.slots, time.Nanosecond)
		pool.threads[i] = thread.create_and_start_with_poly_data3(
			pool,
			i,
			has_slot,
			pool_worker(Run),
		)
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
pool_worker :: proc($Run: typeid) -> proc(pool: ^Pool(Run), worker: int, has_slot: bool) {
	return proc(pool: ^Pool(Run), worker: int, has_slot: bool) {
			allocator := virtual.arena_allocator(&pool.arenas[worker])
			has_slot := has_slot
			for {
				if !take_slot(pool.budget, &pool.stop, has_slot) {
					break
				}
				has_slot = false
				job := sync.atomic_add(&pool.next, 1)
				end: Child_End
				ended := false
				if job < len(pool.commands) {
					end, ended = run_child(pool, job, allocator)
					if ended && pool.retry_signaled && died_on_its_own(end) {
						end, ended = run_child(pool, job, allocator)
						end.retried = true
					}
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

// False when `stop` is set first. A stopped worker then ends without a slot, which another pool's
// child may hold for as long as its timeout. `held` says the worker has a slot already.
@(private = "file")
take_slot :: proc(budget: ^Child_Budget, stop: ^bool, held: bool) -> bool {
	held := held
	for {
		if sync.atomic_load(stop) {
			if held {
				sync.sema_post(&budget.slots)
			}
			return false
		}
		if held {
			return true
		}
		held = sync.sema_wait_with_timeout(&budget.slots, KILL_POLL)
	}
}

// What is left of a child's limit after a poll that took `slice`, where `poll` is the longest a
// poll waits. A poll is charged at most twice that. The clock that measures the slice may run
// while the machine sleeps, as `time.tick_now` does on macOS, so a sleep costs one capped slice
// and never its whole length.
charge_poll :: proc(left, slice, poll: time.Duration) -> time.Duration {
	return left - clamp(slice, 0, 2 * poll)
}

// True for a child that a signal ended and odx didn't send it, such as the compiler's own crash or
// a kill from outside. Only such a child is worth one more run. A limit that ran out, or a stream
// odx couldn't read, isn't known to pass the second time.
died_on_its_own :: proc(end: Child_End) -> bool {
	_, signaled := end.status.(Signaled)
	return signaled && !end.timed_out && end.error == ""
}

// `exit <n>` or `signal <n>`, so a message never calls a signal an exit code. Allocates with
// `allocator`.
status_text :: proc(status: Child_Status, allocator: runtime.Allocator) -> string {
	switch s in status {
	case Exited:
		return fmt.aprintf("exit %d", s.code, allocator = allocator)
	case Signaled:
		return fmt.aprintf("signal %d", s.signal, allocator = allocator)
	}
	unreachable()
}

@(private = "file")
CAPTURE_CHUNK :: 64 << 10

// The most odx reads from one stream of a child. A check with 900,000 errors writes about 200 MB,
// and a child that writes without end would otherwise fill odx's memory until its limit.
STREAM_CAP :: 512 << 20

// More than a pipe holds once its writer is gone, which is all odx reads after the child ended. A
// process the child left behind may hold the pipe and write on, and odx doesn't wait for it.
@(private = "file")
PIPE_CAPACITY :: 1 << 20

// How long odx first sleeps for a child that closed its streams and hasn't ended. The sleep doubles
// up to `KILL_POLL`.
@(private = "file")
END_POLL :: 50 * time.Microsecond

// Runs `desc.command` until it ends, until `limit` is used up per `charge_poll`, or until `killed`
// is set when one is given. It kills the child in the last two cases and reaps it in all three.
// `ended` is false only when `killed` ended the wait, and the child then has no `end` to read.
//
// The streams in `captured` come through pipes that this thread drains while it waits, so no disk
// stands between the child and odx. The child's other stream is discarded. This is the one place
// odx reads a child's stream, and `end.error` is the one answer to whether the stream can be
// believed: a pipe that odx can't make or read is an error, never an empty stream. So is a stream
// of more than `stream_cap` bytes, whose child odx kills. Allocates `end` with `allocator`.
run_captured :: proc(
	desc: os.Process_Desc,
	captured: Streams,
	limit: time.Duration,
	killed: ^bool,
	allocator: runtime.Allocator,
	stream_cap := STREAM_CAP,
) -> (
	end: Child_End,
	ended: bool,
) {
	close_all :: proc(files: ^[Stream]^os.File) {
		for &file in files {
			if file != nil {
				os.close(file)
				file = nil
			}
		}
	}
	ended = true
	desc := desc
	readers, writers: [Stream]^os.File
	defer close_all(&readers)
	for stream in captured {
		pipe_err: os.Error
		readers[stream], writers[stream], pipe_err = os.pipe()
		if pipe_err != nil {
			close_all(&writers)
			end.error = fmt.aprintf(
				"couldn't capture its %s: %s",
				STREAM_NAMES[stream],
				os.error_string(pipe_err),
				allocator = allocator,
			)
			return
		}
	}
	desc.stdout, desc.stderr = writers[.Stdout], writers[.Stderr]
	process, start_err := os.process_start(desc)
	close_all(&writers)
	if start_err != nil {
		end.error = fmt.aprintf(
			"couldn't start: %s",
			os.error_string(start_err),
			allocator = allocator,
		)
		return
	}

	pipes: Pipes
	defer for text in pipes.texts {
		delete(text)
	}
	for &fd, stream in pipes.fds {
		fd.fd = posix.FD(os.fd(readers[stream])) if stream in captured else -1
		fd.events = {.IN}
	}
	// Only this thread reaps the child, so the pid stays the child's until `os.process_wait` below.
	pid := posix.pid_t(process.pid)
	wait_errno, read_errno: posix.Errno
	left := limit
	polled := time.tick_now()
	sleep := END_POLL
	for child_ended := false; !child_ended; {
		ended = killed == nil || !sync.atomic_load(killed)
		end.timed_out = left <= 0
		_, over_cap := pipes.over.?
		if !ended || end.timed_out || over_cap || read_errno != nil || wait_errno != nil {
			posix.kill(pid, .SIGKILL)
			end.status, _, wait_errno = child_ending(pid, true)
			break
		}
		wait := min(left, KILL_POLL)
		if pipes_open(pipes) {
			_, read_errno = drain_pipes(&pipes, wait, stream_cap)
		} else {
			time.sleep(min(wait, sleep))
			sleep = min(2 * sleep, KILL_POLL)
		}
		end.status, child_ended, wait_errno = child_ending(pid, false)
		now := time.tick_now()
		left = charge_poll(left, time.tick_diff(polled, now), KILL_POLL)
		polled = now
	}
	// Reaps the child and frees what `core:os` holds for it.
	_, _ = os.process_wait(process)
	if !ended {
		return
	}
	for held := PIPE_CAPACITY; read_errno == nil && held > 0 && pipes_open(pipes); {
		read: int
		read, read_errno = drain_pipes(&pipes, 0, stream_cap)
		if read == 0 {
			break
		}
		held -= read
	}
	// A golden case loses the stream of the children that run the subcommand it names.
	lose := debug_env("ODX_LOSE_STREAM")
	if lose != "" && len(desc.command) > 1 && desc.command[1] == lose {
		read_errno = .EIO
	}
	end.error = capture_error(read_errno, wait_errno, pipes.over, stream_cap, allocator)
	if end.error == "" {
		for stream in captured {
			end.captured[stream] = strings.clone(string(pipes.texts[stream][:]), allocator)
		}
	}
	return
}

// Why odx can't believe what it read of a child's streams, as the rest of a sentence about the
// child, or "" when it can. The text never quotes the stream. Allocates with `allocator`.
@(private = "file")
capture_error :: proc(
	read_errno, wait_errno: posix.Errno,
	over: Maybe(Stream),
	stream_cap: int,
	allocator: runtime.Allocator,
) -> string {
	stream, over_cap := over.?
	switch {
	case read_errno != nil:
		return fmt.aprintf(
			"started, but odx couldn't read its output: %s",
			posix.strerror(read_errno),
			allocator = allocator,
		)
	case wait_errno != nil:
		return fmt.aprintf(
			"couldn't be waited for: %s",
			posix.strerror(wait_errno),
			allocator = allocator,
		)
	case over_cap:
		return fmt.aprintf(
			"wrote more than %d MB to its %s, the most odx reads from one stream",
			stream_cap >> 20,
			STREAM_NAMES[stream],
			allocator = allocator,
		)
	}
	return ""
}

// The read ends of a child's captured streams and what odx has read from each. A stream that isn't
// captured, or that reached its end, has the descriptor -1, which `poll` skips. `over` is the
// first stream that held more than the cap, after which odx reads no more.
@(private = "file")
Pipes :: struct {
	fds:   [Stream]posix.pollfd,
	texts: [Stream][dynamic]byte,
	over:  Maybe(Stream),
}

@(private = "file")
pipes_open :: proc(pipes: Pipes) -> bool {
	for fd in pipes.fds {
		if fd.fd >= 0 {
			return true
		}
	}
	return false
}

// Waits up to `wait` for any pipe to have text or reach its end, then reads once from each that
// does, until one holds more than `stream_cap` bytes. `read` counts the bytes. A pipe that can't be
// read is an `errno`, and its stream is lost.
@(private = "file")
drain_pipes :: proc(
	pipes: ^Pipes,
	wait: time.Duration,
	stream_cap: int,
) -> (
	read: int,
	errno: posix.Errno,
) {
	if pipes.over != nil {
		return
	}
	ms := i32((wait + time.Millisecond - 1) / time.Millisecond)
	if posix.poll(([^]posix.pollfd)(&pipes.fds), len(pipes.fds), ms) < 0 {
		errno = posix.errno()
		return 0, nil if errno == .EINTR else errno
	}
	for &fd, stream in pipes.fds {
		if fd.fd < 0 || fd.revents == {} {
			continue
		}
		text := &pipes.texts[stream]
		held := len(text)
		// One byte past the cap is enough to know that the child crossed it.
		room := min(CAPTURE_CHUNK, stream_cap + 1 - held)
		if cap(text^) - held < room {
			// Doubling keeps the copying linear in the stream's size. Growing by one read at a
			// time copies the whole text on every read.
			grown := min(max(2 * cap(text^), held + room), stream_cap + 1)
			ensure(non_zero_reserve(text, grown) == nil, "out of memory")
		}
		n := posix.read(fd.fd, raw_data(text^)[held:], uint(room))
		// The bytes are already there, and `resize` would zero them.
		non_zero_resize(text, held + max(n, 0))
		switch {
		case n > 0:
			read += n
			if len(text) > stream_cap {
				pipes.over = stream
				return
			}
		case n == 0:
			fd.fd = -1
		case posix.errno() != .EINTR && posix.errno() != .EAGAIN:
			return read, posix.errno()
		}
	}
	return
}

// How the child ended, without reaping it. Without `block`, `ended` is false for a child that still
// runs.
@(private = "file")
child_ending :: proc(
	pid: posix.pid_t,
	block: bool,
) -> (
	status: Child_Status,
	ended: bool,
	errno: posix.Errno,
) {
	flags := posix.Wait_Flags{.EXITED, .NOWAIT}
	if !block {
		flags += {.NOHANG}
	}
	for {
		info: posix.siginfo_t
		if posix.waitid(.P_PID, posix.id_t(pid), &info, flags) == -1 {
			if errno = posix.errno(); errno != .EINTR {
				return
			}
			continue
		}
		switch {
		case info.si_signo == nil:
			return
		case info.si_code.chld == .EXITED:
			return Exited{int(info.si_status)}, true, nil
		}
		return Signaled{int(info.si_status)}, true, nil
	}
}

// `ended` is false when `kill_pool` ended the child, which then has no `end` to read.
@(private = "file")
run_child :: proc(
	pool: ^Pool($Run),
	job: int,
	allocator: runtime.Allocator,
) -> (
	end: Child_End,
	ended: bool,
) {
	desc := os.Process_Desc {
		working_dir = pool.working_dir,
		command     = pool.commands[job],
	}
	return run_captured(desc, {pool.captured}, pool.timeout, &pool.killed, allocator)
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
