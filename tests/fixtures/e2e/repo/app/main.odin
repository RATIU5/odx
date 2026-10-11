package main

import "core:fmt"
import "core:os"
import "../geometry"

main :: proc() {
	shapes := []geometry.Shape {
		{kind = .Circle, width = 1, name = "unit"},
		{kind = .Rect, width = 2, height = 3, name = "door"},
	}
	for s in shapes {
		text := geometry.describe(s)
		defer delete(text)
		fmt.println(text)
	}
	count: int = "two"
	fmt.println("total:", geometry.totalArea(shapes), count)
	if len(os.args) > 1 do fmt.println("args ignored")
}
