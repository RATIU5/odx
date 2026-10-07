package app

f :: proc($T: typeid) -> int {
	elem :: T
	Elem :: T
	return size_of(elem) + size_of(Elem)
}
