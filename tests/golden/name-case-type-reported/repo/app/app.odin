package app

HttpClient :: struct {}

handler_proc :: proc(x: int)

byte_ptr :: ^u8

four_ints :: [4]int

user_id :: distinct int

color :: enum {
	Red,
}

colors :: bit_set[color]

shape :: union {
	int,
}

lookup_table :: map[string]int
