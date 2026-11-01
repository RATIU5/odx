# Patching the compiler or the Odin runtime

odx never patches the compiler, the runtime or user code, including for the memory checker.

## Why this is out of scope

Every command needs only the stock Odin compiler (principle 7, `docs/adr/0004-principles.md`; `docs/adr/0002-memory-checking-with-tracking-allocator.md`).
