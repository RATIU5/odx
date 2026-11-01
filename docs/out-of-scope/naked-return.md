# A rule against naked returns

odx has no `naked-return` rule. A procedure with named results may end with a bare `return`, or with `return a, b`.

## Why this is out of scope

Principle 2 (`docs/adr/0004-principles.md`) picks one form where Odin allows two, and this is a place where odx doesn't. A bare `return` with named results is the idiom of the code the rule would check. odx's own sources held 44 of them when the rule was proposed, so the rule would have turned the team's normal form into 44 findings. It was dropped on 2026-10-04. `cast-style` was dropped the same day for the same reason.
