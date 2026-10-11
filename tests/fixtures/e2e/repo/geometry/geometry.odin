package geometry

import "core:math"
import "core:fmt"

/*
	Shapes used by the app. Areas are in square units.
*/

Shape_Kind :: enum {
	Circle,
	Rect,
	Triangle,
}

Shape :: struct {
	kind:   Shape_Kind,
	width:  f64,
	height: f64,
	name: string,
}

// Display names, indexed by kind.
kind_names := [Shape_Kind]string {
	.Circle   = "circle",
	.Rect     = "rect",
	.Triangle = "triangle",
}

MaxShapes :: 64

area :: proc(s: Shape) -> f64 {
	switch s.kind {
	case .Circle:
		return math.PI * s.width * s.width
	case .Rect:
		return s.width * s.height
	case .Triangle:
		return 0.5 * s.width * s.height
	}
	return 0
}

totalArea :: proc(shapes: []Shape) -> (total: f64) {
	for s in shapes do total += area(s)
	return
}

describe :: proc(s: Shape, allocator := context.allocator) -> string {
	return fmt.aprintf("%s %s with width %.2f and height %.2f covering an area of %.3f square units", kind_names[s.kind], s.name, s.width, s.height, area(s), allocator = allocator)
}

scale :: proc(s: ^Shape, factor: f64) {
	if factor <= 0 { return }
	s.width  *= factor
	s.height *= factor
}
