package parser

Status :: enum { Ready, End }
Cursor :: struct {
	text: string,
	offset: int,
}

Next :: proc(cursor: ^Cursor) -> (byte, Status) {
	if cursor.offset >= len(cursor.text) {
		return 0, .End
	}
	value := cursor.text[cursor.offset]
	cursor.offset += 1
	return value, .Ready
}

Has_More :: proc(cursor: Cursor) -> bool {
	return cursor.offset < len(cursor.text)
}
