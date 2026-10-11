# Compiler flags that can't be scoped become odx rules

`-vet-using-param` and `-disallow-do` can't be limited to one package, and probes showed them reporting inside vendored code and the Odin root. So odx doesn't pass them to the compiler. odx has no rule for `do` either. `.out-of-scope/do-stmt.md` says why.

Amended 2026-10-04: odx has no `using-param` rule, which this ADR first named beside `do-stmt`. The pinned compiler rejects a `using` parameter unless the file has `#+feature using-stmt`, and the `feature-relaxed` rule reports that tag.
