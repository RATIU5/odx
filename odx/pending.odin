package odx

import "base:runtime"
import "core:fmt"
import "core:os"
import "core:slice"
import "core:strings"

@(private = "file")
NOT_A_DIRECTORY :: bit_set[Disk_Kind]{.File, .Special}

// Returns a `pending-stale` finding for each entry that Appendix E.7 calls stale. An entry's
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
	owners := make(map[string]bool, context.temp_allocator)
	for f in findings {
		owners[f.owner_dir] = true
	}
	dirs := make([]string, len(entries), context.temp_allocator)
	stale := make([dynamic]Finding, allocator)
	for entry, i in entries {
		dirs[i], _ = os.clean_path(entry.dir, context.temp_allocator)
		dir := dirs[i]
		earlier := slice.linear_search(dirs[:i], dir) or_else -1
		on_disk := package_dir_ignoring_case(packages, dir)
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
		case disk_kind(fmt.tprintf("%s/%s", repo_root, dir)) in NOT_A_DIRECTORY:
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
