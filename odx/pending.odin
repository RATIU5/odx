package odx

import "base:runtime"
import "core:fmt"
import "core:os"

// Allocates the findings and their messages with `allocator`.
stale_pending :: proc(
	entries: []Pending_Entry,
	packages: []Package,
	findings: []Finding,
	allocator: runtime.Allocator,
) -> []Finding {
	owners := make(map[string]bool, context.temp_allocator)
	for f in findings {
		owners[f.owner_dir] = true
	}
	stale := make([dynamic]Finding, allocator)
	for entry in entries {
		dir, _ := os.clean_path(entry.dir, context.temp_allocator)
		message: string
		switch {
		case !has_package(packages, dir):
			message = fmt.aprintf(
				"'%s' is not a package odx checks, so remove it from pending",
				entry.dir,
				allocator = allocator,
			)
		case !owners[dir]:
			message = fmt.aprintf(
				"'%s' has no findings as strict, so remove it from pending",
				entry.dir,
				allocator = allocator,
			)
		case:
			continue
		}
		append(
			&stale,
			Finding {
				path = CONFIG_FILE,
				line = entry.line,
				col = entry.col,
				rule = .Pending_Stale,
				message = message,
			},
		)
	}
	return stale[:]
}

@(private = "file")
has_package :: proc(packages: []Package, dir: string) -> bool {
	for p in packages {
		if p.dir == dir {
			return true
		}
	}
	return false
}
