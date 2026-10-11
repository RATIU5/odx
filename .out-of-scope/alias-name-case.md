# A case check on alias and call declarations

`name-case` gives no finding for a constant whose right side is another name or a call: `X :: Y`, `X :: pkg.Y`, `X :: Y(...)`, `X :: pkg.Y(...)`, or a `when` choice between such names. So `my_type :: int` passes. A typed constant such as `limit: int : LIMIT` is still checked, because its type says it is a value. An `odx:ignore name-case` above such a declaration has nothing to suppress, so it gets `ignore-unused`.

## Why this is out of scope

The declaration alone doesn't say whether `Y` is a type, a procedure or a value, and each takes a different case. Telling them apart needs a resolver that follows names through the file, its package, its imports and the compiler's built-in names. odx had one. With its generator and its tests it was about 2,100 lines. It gave 2.2% of the findings on Odin's `core` and `vendor` trees and none of the 223 findings on the team trial. A mechanism stays only when a measured problem pays for it, and this one didn't.

Reopen this only with findings a team's own code would have had.
