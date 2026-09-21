package odx

import "base:runtime"

// One #load_directory per built-in topic (17.20: non-recursive, empty dir is a
// compile error). Add a line here when adding a topic under rules/.
// The example is what the stop hook shows on its second identical block (M2.3).
// ponytail: one example dir per topic; layering's platform example is not embedded.
BUILTIN_TOPICS := []Builtin {
	{
		"errors",
		#load_directory("../rules/errors"),
		#load_directory("../rules/errors/example/core"),
	},
	{
		"layering",
		#load_directory("../rules/layering"),
		#load_directory("../rules/layering/example/core"),
	},
	{
		"allocators",
		#load_directory("../rules/allocators"),
		#load_directory("../rules/allocators/example/core"),
	},
}

Builtin :: struct {
	name:    string,
	files:   []runtime.Load_Directory_File,
	example: []runtime.Load_Directory_File,
}
