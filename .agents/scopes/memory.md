# Memory checker

`odx test` and `odx run` run code and report memory and runtime faults. Output, config, `pending` and ignores: `.agents/SCOPE.md`. It is built after the checker.

## Goals

1. Every `leak` and `bad-free` gives the allocation site with a backtrace; a double free gives both free sites.
2. `test` and `run` produce the same finding shapes.
3. One mechanism, needing only the Odin compiler: no runtime patch, no other toolchain, no changes to user code.
4. What it can't see is listed, so a clean run isn't read as more than it is.
5. Non-interactive: no breakpoints, stepping or replay.
6. A `leak`, `bad-free` or `panic` whose site is inside the Odin root is reported at the innermost frame in the repo.

## Draft design

Decided 2026-09-29; it becomes the contract when the memory checker's behavior is specified.

- **`odx test`** runs `odin test` for each package that has tests. Strict packages get the checker's scoped strict flags, so `#+test` files are checked too, with compiler findings under `odin`. Every run gets `-define:ODIN_TEST_FAIL_ON_BAD_MEMORY=true`, so the runner's tracking allocator reports per test.
- **`odx run [dir] [-- args]`** builds a generated wrapper package in a temp directory outside the repo, in debug mode, and runs it with `args`. The wrapper imports the package in `dir` (default: the current directory) and calls its `main` with a tracking allocator that records a backtrace per allocation as `context.allocator`, and with its own assertion failure handler. The temp directory is deleted afterwards. The program's own exit status goes to stderr.

| Rule | Command | Finding when | Reported at |
| --- | --- | --- | --- |
| `test-failed` | test | a test fails, by failed assert, panic, bounds failure or fatal signal | the test procedure |
| `leak` | both | memory is still allocated when a test or `main` ends or the program panics; the message gives the size | the allocation site |
| `bad-free` | both | a free of memory not allocated or already freed | the free site |
| `panic` | run | a panic, failed assert, failed type assertion or bounds failure | the location the runtime reports |
| `crash` | run | a fatal signal such as SIGSEGV or SIGBUS | the file declaring `main`, at 1:1 |

- `test-failed`, `bad-free` and `crash` can't be ignored. A `leak` ignore goes on the allocating statement; a `panic` ignore on the statement that panics or asserts. `check` validates their syntax only.
- **Not covered:**
    - use-after-free, and out-of-bounds access through raw pointers or `#no_bounds_check`;
    - allocations on threads the program starts, which begin with the default allocator;
    - memory allocated by C libraries, and allocations inside the program's own arenas or pools;
    - allocations made in `@(init)` procedures, which run before the wrapper's `main`;
    - leaks when the program ends through `os.exit`, a bounds failure or a fatal signal (the `panic` or `crash` itself is reported);
    - code paths that don't run.

## Not its job

- **Leak tracking for arenas and `temp_allocator`:** they free in bulk.

## Later

- **Checks beyond the tracking allocator:** use-after-free, other threads and C libraries, without adding a second mechanism.
- **`temp-use-after-reset`:** use of `temp_allocator` memory after `free_all`.

## Risks

- **Core dependencies:** `core:debug/trace`, `testing`'s memory report format and `ODIN_TEST_FAIL_ON_BAD_MEMORY` can change between releases; re-verify them for every supported compiler.
