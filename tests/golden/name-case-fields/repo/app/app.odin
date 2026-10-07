package app

Base :: struct {
	id: int,
}

Point :: struct {
	x, Y:       int,
	userName:   string,
	user_name:  string,
	MAX:        int,
	using base: Base,
	using _:    struct {
		innerValue: int,
	},
}

Nibbles :: bit_field u8 {
	LowBits:   u8 | 4,
	high_bits: u8 | 4,
}
