# layering

Three roles, one direction of dependency:

| role    | may import                          | may hold           |
| ------- | ----------------------------------- | ------------------ |
| pure    | pure, `core:*` (no os/net/thread)   | constants only     |
| service | pure, service, `core:*`             | state via params   |
| edge    | anything, `vendor:*`, `foreign`     | process-wide state |

Roles are assigned per package directory in `odx.json5`; a package is never annotated in
source (the `#+` tag set is closed, and custom attributes force a flag on every consumer).

## Do

```odin
// core/ (pure): data + logic, takes everything it needs as arguments
step :: proc(w: World, input: Input) -> World { ... }

// platform/ (edge): owns the window, the clock, the OS
main :: proc() { w := core.step(w, poll()) }
```

## Don't

```odin
// core/ (pure)
import "core:os"          // R2: I/O in a pure package
frame_count: int          // R3: mutable global in a pure package
foreign import lib "..."  // R4: foreign outside edge
```
