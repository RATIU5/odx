# A rule against `do`

odx has no `do-stmt` rule. A body of one statement may use `do` on one line, as in `if !ok do return false`.

## Why this is out of scope

The standard the rule would enforce prescribes `do` itself, for a guard clause and for an assert implication. The rule gave 156 findings on the team trial, and 88 of them were guard clauses.

With `one-line-block` in force, `if !ok {return false}` is a finding. So without `do`, the only form left for a guard is three lines. The printer the `format` rule checks against keeps a `do` body as written, so it settles nothing here. `one-line-block` is the rule that picks, and with `do` allowed a one-line body has one form. A one-statement body still has two, `do` on one line or braces on three, which is an exception to principle 2 (`docs/adr/0004-principles.md`).

`nesting-depth` still counts a `do` body as a block.
