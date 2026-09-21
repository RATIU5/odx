package odx

import "base:runtime"

// One #load_directory per built-in topic (non-recursive; an empty dir is a compile error).
// Add a line here when adding a topic under rules/.
// ponytail: one example dir per topic; dependencies's platform example is not embedded.
BUILTIN_TOPICS := []Builtin {
	{
		"errors",
		#load_directory("../rules/errors"),
		#load_directory("../rules/errors/example/core"),
	},
	{
		"dependencies",
		#load_directory("../rules/dependencies"),
		#load_directory("../rules/dependencies/example/core"),
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
