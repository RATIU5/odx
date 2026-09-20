package odx

import "base:runtime"

// One #load_directory per built-in topic (17.20: non-recursive, empty dir is a
// compile error). Add a line here when adding a topic under rules/.
BUILTIN_TOPICS := []Builtin {
	{"errors", #load_directory("../rules/errors")},
	{"layering", #load_directory("../rules/layering")},
	{"allocators", #load_directory("../rules/allocators")},
}

Builtin :: struct {
	name:  string,
	files: []runtime.Load_Directory_File,
}
