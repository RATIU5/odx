# errors

Failures are values. Every fallible procedure says so in its signature and the compiler refuses
to let a caller drop that value. Handle it where it occurs when you can; when a package's
operations genuinely chain, `or_return` carries it up to the one place that can act on it.

## Do

```odin
Error :: enum { None, Not_Found, Permission }

@(require_results)
open :: proc(path: string) -> (h: Handle, err: Error) { ... }

load :: proc(path: string) -> (cfg: Config, err: Error) {
	h := open(path) or_return
	defer close(h)
	...
}
```

## Don't

```odin
open :: proc(path: string) -> (Handle, bool)   // R1: what failed?
open(path)                                      // R3: result silently dropped (compiles without the attribute)
h, _ := open(path)                              // R4: error thrown away without a decision
if err != nil { return }                        // R4: hand-written propagation in a chained package; or_return says the same in one token
```

## Notes

- `_ = f()` is only acceptable at the top of a program where the error is logged and the
  process exits. Write the log line.
- `Error` may be a `union` when a package wraps errors from several dependencies.
