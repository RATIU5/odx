// Prints the files odx predicts `odin check` compiles, one line per package and target:
// `<package dir> <target> <file name>...`, with the names sorted. `diff.sh` compares it with the
// compiler.
package selection

import "core:fmt"
import "core:os"
import "core:slice"

import "../../odx"

main :: proc() {
	if len(os.args) != 2 {
		fmt.eprintln("usage: selection <repo dir>")
		os.exit(2)
	}
	result: odx.Result
	packages := odx.discover(os.args[1], {}, &result, context.allocator)
	for pkg in packages {
		for t in odx.Target {
			names := make([dynamic]string, context.temp_allocator)
			for file in pkg.files {
				if !file.is_test && t in file.targets {
					append(&names, os.base(file.path))
				}
			}
			slice.sort(names[:])
			fmt.print(pkg.dir, odx.TARGETS[t].name)
			for name in names {
				fmt.print("", name)
			}
			fmt.println()
		}
	}
}
