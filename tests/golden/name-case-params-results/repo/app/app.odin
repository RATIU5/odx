package app

Handler :: proc(Value: int, index: int) -> (Ok: bool)

Unnamed :: proc(_: int, _: string) -> (int, bool)

scale :: proc(Count: int, userName := "x", factor: int = 2) -> (Total: int, ok: bool) {
	Total = Count * factor + len(userName)
	ok = true
	return
}

apply :: proc(items: []int, visit: proc(Item: int)) {
	for item in items {
		visit(item)
	}
}
