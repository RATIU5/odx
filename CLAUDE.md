# odx

A strict checker for Odin projects, written in Odin. What it is and isn't: @docs/SCOPE.md. SCOPE is the contract; items under "Later" and "Never" are out of scope unless the user says otherwise.

## Commands

- `mise run build`: debug build to `build/odx`
- `mise run test`: run the tests
- `mise run fmt`: format with odinfmt

Odin version is pinned in `mise.toml`. The compiler and core sources are at `$(odin root)`.

## Working rules

- Use the `odin` skill for any Odin code. Core APIs changed a lot in 2025–2026; check signatures against `$(odin root)` rather than memory.
- Plan and order of work: `docs/milestones/README.md`. Work only on the current part.
- odx findings state facts (what, where), never fixes or hints.
- Fact-check claims about Odin behavior by reading the source or running a small program. Say which claims are verified and which aren't.
- Ask the user when SCOPE is ambiguous or silent, rather than choosing.
- New tracked files need an entry in `.gitignore` (it's an allow-list).
