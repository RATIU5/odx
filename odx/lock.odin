package odx

import "core:crypto/hash"
import "core:encoding/hex"
import "core:fmt"
import "core:os"
import "core:slice"
import "core:strings"

// Protected paths (17.9, 20.3): a sorted `sha256  path` manifest in .odx/lock over every file
// the rulebook and its enforcement depend on. Editing them is allowed; doing it invisibly is
// not. `odx doctor --verify-rulebook` names every changed file; a human rewrites the lock with
// ODX_ALLOW_PROTECTED=1 `odx doctor --relock`, and that diff is the approval record.

LOCK_FILE :: ".odx/lock"
PROTECTED := []string {
	"rules/**",
	".odx/**",
	"odx.json5",
	"tests/fixtures/**",
	"mise.toml",
	".claude/settings.json",
	"CLAUDE.md",
}
LOCK_SKIP := []string{LOCK_FILE, ".odx/cache/**"}

// lock_manifest hashes every protected file under root.
lock_manifest :: proc(root: string) -> string {
	lines := make([dynamic]string)
	w := os.walker_create_path(root)
	defer os.walker_destroy(&w)
	for fi in os.walker_walk(&w) {
		rel, _ := rel_of(root, fi.fullpath)
		switch {
		case fi.type == .Symlink || (fi.type == .Directory && (rel == ".git" || rel == "build")):
			os.walker_skip_dir(&w)
		case fi.type == .Regular && matches_glob(PROTECTED, rel) && !matches_glob(LOCK_SKIP, rel):
			data, err := os.read_entire_file(fi.fullpath, context.allocator)
			if err != nil {fail("%s: cannot read", fi.fullpath)}
			sum := hex.encode(hash.hash_bytes(.SHA256, data))
			append(&lines, fmt.aprintf("%s  %s", string(sum), rel))
		}
	}
	slice.sort(lines[:])
	return strings.concatenate({strings.join(lines[:], "\n"), "\n"})
}

matches_glob :: proc(globs: []string, rel: string) -> bool {
	for g in globs {if glob_match(g, rel) {return true}}
	return false
}

// verify_lock returns the changed, added and removed protected paths. has_lock is false when
// no lock exists yet (nothing to verify against).
verify_lock :: proc(root: string) -> (diff: []string, has_lock: bool) {
	old, err := os.read_entire_file(join({root, LOCK_FILE}), context.allocator)
	if err != nil {return nil, false}
	want := make(map[string]string, context.temp_allocator)
	for l in strings.split_lines(string(old), context.temp_allocator) {
		sum, _, path := strings.partition(l, "  ")
		if path != "" {want[path] = sum}
	}
	out := make([dynamic]string)
	seen := make(map[string]bool, context.temp_allocator)
	for l in strings.split_lines(lock_manifest(root), context.temp_allocator) {
		sum, _, path := strings.partition(l, "  ")
		if path == "" {continue}
		seen[path] = true
		if w, ok := want[path]; !ok {
			append(&out, strings.concatenate({"added   ", path}))
		} else if w != sum {
			append(&out, strings.concatenate({"changed ", path}))
		}
	}
	for path in sorted_keys(want) {if path not_in seen {append(&out, strings.concatenate({"removed ", path}))}}
	return out[:], true
}

write_lock :: proc(root: string) {
	if os.get_env("ODX_ALLOW_PROTECTED", context.temp_allocator) != "1" {
		fail("--relock needs ODX_ALLOW_PROTECTED=1 in the environment (a human's approval)")
	}
	os.make_directory_all(join({root, ".odx"}))
	write_atomic(join({root, LOCK_FILE}), lock_manifest(root))
	fmt.println("wrote", LOCK_FILE)
}

// write_atomic: temp then rename, because two hooks may run at once (17.10).
write_atomic :: proc(path, text: string) {
	tmp := strings.concatenate({path, ".tmp"}, context.temp_allocator)
	if err := os.write_entire_file(tmp, text); err != nil {fail("write %s: %v", tmp, err)}
	if err := os.rename(tmp, path); err != nil {fail("rename %s: %v", path, err)}
}
