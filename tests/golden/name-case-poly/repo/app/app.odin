package app

first :: proc(items: []$T) -> T {
	return items[0]
}

first_bad :: proc(items: []$elem) -> elem {
	return items[0]
}

zeroed :: proc($T: typeid, $N: int) -> (out: [N]T) {
	return
}

zeroed_bad :: proc($kind: typeid, $count: int) -> (out: [count]kind) {
	return
}

total :: proc(items: [$N]$E) -> (sum: E) {
	for item in items {
		sum += item
	}
	return
}

total_bad :: proc(items: [$n]$Elem_Type) -> (sum: Elem_Type) {
	for item in items {
		sum += item
	}
	return
}

keys :: proc(m: $M/map[$K]$V) -> int {
	return len(m)
}

trace :: proc(m: matrix[$R, $c]f32) -> f32 {
	return m[0, 0]
}

Buffer :: struct($T: typeid, $N: int) {
	items: [N]T,
}

Buffer_Bad :: struct($elem: typeid, $Size: int) {
	items: [Size]elem,
}

Plain :: struct(T: typeid, N: int) {
	items: [N]T,
}

Plain_Bad :: struct(elem: typeid, size: int) {
	items: [size]elem,
}

Either :: union($T: typeid, $other: typeid) {
	T,
	other,
}
