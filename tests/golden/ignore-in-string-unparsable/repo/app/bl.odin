// odx:ignore line-length a generated file
package app

A :: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

f :: proc() {
	s := """
// odx:ignore line-length text, not an ignore
// odx:bogus
//odx:ignore line-length r
x := 1 // odx:ignore line-length r
an escaped quote run \"""
// odx:ignore line-length still text
"""
	_ = s
	defer _ = #branch_location
}

// odx:ignore line-length a statement ignore after the string
B :: 1
