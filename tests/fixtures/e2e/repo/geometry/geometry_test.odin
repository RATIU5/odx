package geometry

import "core:testing"

@(test)
test_rect_area :: proc(t: ^testing.T) {
	r := Shape{kind = .Rect, width = 2, height = 3}
	testing.expect_value(t, area(r), 6)
}

@(test)
test_total :: proc(t: ^testing.T) {
	shapes := []Shape{{kind = .Rect, width = 1, height = 1}, {kind = .Rect, width = 2, height = 2}}
	testing.expect_value(t, totalArea(shapes), 5)
}
