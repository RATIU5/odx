# odx

A strict checker for Odin projects, written in Odin. The contract: @.agents/SCOPE.md. Items under "Later" and "Never" are out of scope unless the user says otherwise.

## Commands

- `mise run build`: debug build to `build/odx`
- `mise run test`: run the tests, golden cases included
- `mise run fmt`: format with odinfmt

The Odin version is pinned in `mise.toml`; core sources are at `$(odin root)`.

## Working rules

- Read `.agents/milestones/README.md` first every session. Work only on the current part's current step.
- Use the `odin` skill for Odin code, and check core signatures against `$(odin root)`; APIs changed a lot in 2025–2026.
- Verify claims about Odin with the source or a small program, and say which are verified.
- odx findings state what and where, never fixes or hints.
- Ask the user when SCOPE is silent or ambiguous. SCOPE changes only through the `scope` skill.
- `.gitignore` is an allow-list: new tracked paths need an entry.
