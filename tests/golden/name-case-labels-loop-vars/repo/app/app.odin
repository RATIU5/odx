package app

Shape :: union {
	int,
	f32,
}

walk :: proc(items: []int, shape: Shape) -> (sum: int) {
	Outer: for Item, Index in items {
		if Item < 0 {
			break Outer
		}
		sum += Item + Index
	}
	rows: for item, index in items {
		if item < 0 {
			break rows
		}
		sum += item + index
	}
	copies := [3]int{1, 2, 3}
	for &Elem in copies {
		Elem += 1
	}
	for I := 0; I < 3; I += 1 {
		sum += copies[I]
	}
	#unroll for Step in 0 ..< 2 {
		sum += Step
	}
	Pick: switch Value in shape {
	case int:
		sum += Value
		break Pick
	case f32:
		sum += int(Value)
	}
	switch value in shape {
	case int:
		sum += value
	case f32:
		sum += int(value)
	}
	Scope: {
		if sum > 10 {
			break Scope
		}
		sum = 10
	}
	Check: if sum > 20 {
		if sum > 30 {
			break Check
		}
		sum = 20
	}
	return
}
