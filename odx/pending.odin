package odx

import "base:runtime"
import "core:fmt"
import "core:mem/virtual"
import "core:os"
import "core:strings"

@(private = "file")
NOT_A_DIRECTORY :: bit_set[Disk_Kind]{.File, .Special}

// Returns a `pending-stale` finding for each stale entry. An entry's
// findings are those whose `owner_dir` is its package, so a finding located in a package it imports
// never counts toward it. The caller owns the returned slice and its messages, both allocated with
// `allocator`.
stale_pending :: proc(
	repo_root: string,
	entries: []Pending_Entry,
	packages: []Package,
	findings: []Finding,
	allocator: runtime.Allocator,
) -> []Finding {
	scratch: virtual.Arena
	ensure(virtual.arena_init_growing(&scratch) == nil, "out of memory")
	defer virtual.arena_destroy(&scratch)
	temp := virtual.arena_allocator(&scratch)

	owners := make(map[string]bool, temp)
	for f in findings {
		owners[f.owner_dir] = true
	}
	package_dirs := make(map[string]struct{}, len(packages), temp)
	for p in packages {
		package_dirs[p.dir] = {}
	}
	first_with_dir := make(map[string]int, len(entries), temp)
	stale := make([dynamic]Finding, allocator)
	for entry, i in entries {
		dir, _ := os.clean_path(entry.dir, temp)
		earlier := first_with_dir[dir] or_else -1
		if earlier < 0 {
			first_with_dir[dir] = i
		}
		on_disk := dir if dir in package_dirs else package_dir_ignoring_case(packages, dir)
		message: string
		switch {
		case dir == ".." ||
		     strings.has_prefix(dir, "../") ||
		     (os.is_absolute_path(dir) && !is_within(dir, repo_root)):
			message = fmt.aprintf("'%s' is outside the repo", entry.dir, allocator = allocator)
		case os.is_absolute_path(dir):
			message = fmt.aprintf("'%s' is an absolute path", entry.dir, allocator = allocator)
		case earlier >= 0:
			message = fmt.aprintf(
				"'%s' names the same directory as '%s'",
				entry.dir,
				entries[earlier].dir,
				allocator = allocator,
			)
		case disk_kind(fmt.aprintf("%s/%s", repo_root, dir, allocator = temp)) in NOT_A_DIRECTORY:
			message = fmt.aprintf(
				"'%s' is a file, not a directory",
				entry.dir,
				allocator = allocator,
			)
		case on_disk == "":
			message = fmt.aprintf(
				"'%s' is not a package odx checks",
				entry.dir,
				allocator = allocator,
			)
		case on_disk != dir:
			message = fmt.aprintf(
				"'%s' differs in case from the directory '%s'",
				entry.dir,
				on_disk,
				allocator = allocator,
			)
		case !owners[dir]:
			message = fmt.aprintf(
				"'%s' has no findings as strict",
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
package_dir_ignoring_case :: proc(packages: []Package, dir: string) -> string {
	found := ""
	for p in packages {
		if p.dir == dir {
			return p.dir
		}
		if found == "" && strings.equal_fold(p.dir, dir) {
			found = p.dir
		}
	}
	return found
}
