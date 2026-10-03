# Compiler flags that can't be scoped become odx rules

`-vet-using-param` and `-disallow-do` can't be limited to one package, and probes showed them reporting inside vendored code and the Odin root. So odx doesn't pass them to the compiler; it checks the same things itself as the rules `using-param` and `do-stmt`, which run only where odx's rules apply.
