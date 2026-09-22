package compact

Braced_Return :: proc(ready: bool) -> int {
	if ready {return 1}
	return 0
}

Braced_Assign :: proc(ready: bool) -> int {
	value := 0
	if ready {
		// The diagnostic preserves this comment; it does not rewrite source.
		value = 1
	}
	return value
}

Braced_Call :: proc(ready: bool, value: ^int) {
	if ready {increment(value)}
}

increment :: proc(value: ^int) {value^ += 1}

Compact_Return :: proc(ready: bool) -> int {
	if ready do return 1
	return 0
}

Compact_Assign :: proc(ready: bool) -> int {
	value := 0
	if ready do value = 1
	return value
}

Compact_Call :: proc(ready: bool, value: ^int) {
	if ready do increment(value)
}

Multiple_Statements :: proc(ready: bool) -> int {
	value := 0
	if ready {
		value = 1
		value += 1
	}
	return value
}

With_Else :: proc(ready: bool) -> int {
	if ready {return 1} else {return 0}
}
