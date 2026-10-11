package tinyfmt

/* third-party: left exactly as upstream ships it */
padLeft :: proc(s: string, n: int) -> int { if len(s) >= n do return 0; return n - len(s) }

DEFAULT_width := 8
doubleIt :: proc(x: int) -> int { unused := 3; return auto_cast (x * 2) }
