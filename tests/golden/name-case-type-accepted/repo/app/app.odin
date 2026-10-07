package app

Http_Client :: struct {}

Handler :: proc(x: int)

Callback :: #type proc()

Byte_Ptr :: ^u8

Bytes :: [^]u8

Four_Ints :: [4]int

User_ID :: distinct int

Color :: enum {
	Red,
}

Colors :: bit_set[Color]

Shape :: union {
	int,
}

Lookup :: map[string]int

Nibbles :: bit_field u8 {
	low:  u8 | 4,
	high: u8 | 4,
}

Plain_Mat :: matrix[2, 2]f32

Row_Mat :: #row_major matrix[2, 2]f32

Either_Mat :: #row_major matrix[2, 2]f32 when ODIN_OS == .Windows else matrix[2, 2]f32
