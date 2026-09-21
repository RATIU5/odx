// Redundancy audit: the compiler must keep rejecting this with no flags. If it ever
// compiles, `using` as a statement is no longer compiler-owned and odx needs a rule again.
package compiler_owned

P :: struct {
	x: int,
}

f :: proc() -> int {
	p := P{1}
	using p
	return x
}
