#+feature dynamic-literals
package app

f :: proc() {
	s := """
hello
"""
	_ = s
}
