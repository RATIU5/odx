package odx

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"

GUIDANCE_BEGIN :: "<!-- odx:begin v1 -->"
GUIDANCE_END :: "<!-- odx:end -->"

Guidance_Region :: struct {
	start, end:    int,
	found, legacy: bool,
}

guidance_region :: proc(text: string) -> (region: Guidance_Region, err: string) {
	opened := false
	fence: byte
	fence_len := 0
	for offset := 0; offset < len(text); {
		next := strings.index_byte(text[offset:], '\n')
		end := len(text) if next < 0 else offset + next + 1
		line := strings.trim_suffix(text[offset:end], "\n")
		line = strings.trim_suffix(line, "\r")
		if strings.contains(line, "<!-- odx:") {
			if fence != 0 || (line != GUIDANCE_BEGIN && line != GUIDANCE_END) {
				return region,
					"reserved odx markers must be exact standalone lines outside Markdown fences"
			}
			if line == GUIDANCE_BEGIN {
				if opened ||
				   region.found {return region, "duplicate or nested odx guidance markers"}
				region.start = offset
				opened = true
			} else {
				if !opened ||
				   region.found {return region, "odx guidance end marker has no matching begin marker"}
				region.end = end
				region.found = true
				opened = false
			}
		} else {
			trimmed := strings.trim_left_space(line)
			if len(trimmed) > 0 && (trimmed[0] == '`' || trimmed[0] == '~') {
				n := 0
				for n < len(trimmed) && trimmed[n] == trimmed[0] {n += 1}
				if fence == 0 && n >= 3 {
					fence = trimmed[0]
					fence_len = n
				} else if fence == trimmed[0] &&
				   n >= fence_len &&
				   strings.trim_space(trimmed[n:]) == "" {
					fence = 0
					fence_len = 0
				}
			}
			if fence == 0 && !opened && strings.trim_space(line) == "## odx" {region.legacy = true}
		}
		offset = end
	}
	if opened {return region, "odx guidance begin marker has no matching end marker"}
	if fence != 0 {return region, "unclosed Markdown fence prevents safe guidance placement"}
	return
}

guidance_sync :: proc(path, block: string, write: bool) -> (status: int, message: string) {
	generated, block_error := guidance_region(block)
	if block_error != "" ||
	   !generated.found ||
	   generated.start != 0 ||
	   generated.end != len(block) ||
	   generated.legacy {
		return 2, fmt.aprintf("invalid generated guidance block: %s", block_error)
	}
	info, stat_error := os.lstat(path, context.temp_allocator)
	missing := stat_error == .Not_Exist
	if stat_error != nil &&
	   !missing {return 2, fmt.aprintf("cannot inspect %s: %v", path, stat_error)}
	if !missing &&
	   info.type !=
		   .Regular {return 2, fmt.aprintf("%s must be a regular file, not a symlink or directory", path)}
	old: string
	if !missing {
		data, read_error := os.read_entire_file(path, context.temp_allocator)
		if read_error != nil {return 2, fmt.aprintf("cannot read %s: %v", path, read_error)}
		old = string(data)
	}
	region, region_error := guidance_region(old)
	if region_error != "" {return 2, fmt.aprintf("%s: %s", path, region_error)}
	if region.legacy {
		return 2, fmt.aprintf(
			"%s has an unmarked legacy ## odx section; manually place %s and %s around only the generated content, then retry",
			path,
			GUIDANCE_BEGIN,
			GUIDANCE_END,
		)
	}
	if region.found &&
	   old[region.start:region.end] ==
		   block {return 0, fmt.aprintf("%s: guidance is current", path)}
	if !write {return 1, fmt.aprintf("%s: guidance is %s", path, "stale" if region.found else "missing")}
	replacement: string
	if region.found {
		replacement = strings.concatenate(
			{old[:region.start], block, old[region.end:]},
			context.temp_allocator,
		)
	} else {
		separator := ""
		if len(old) > 0 {separator = "\n" if strings.has_suffix(old, "\n") else "\n\n"}
		replacement = strings.concatenate({old, separator, block}, context.temp_allocator)
	}
	mode := os.Permissions_Read_All + {.Write_User} if missing else info.mode
	if err := replace_file_atomic(path, replacement, mode);
	   err != nil {return 2, fmt.aprintf("cannot write %s: %v", path, err)}
	return 0, fmt.aprintf("%s: guidance written", path)
}

@(require_results)
replace_file_atomic :: proc(path, text: string, mode: os.Permissions) -> os.Error {
	f, create_error := os.create_temp_file(filepath.dir(path), ".odx-write-*")
	if create_error != nil {return create_error}
	temporary := strings.clone(os.name(f), context.temp_allocator)
	closed := false
	defer {
		if !closed {os.close(f)}
		os.remove(temporary)
	}
	if err := os.fchmod(f, mode); err != nil {return err}
	written, write_error := os.write(f, transmute([]byte)text)
	if write_error != nil {return write_error}
	if written != len(text) {return .Short_Write}
	if err := os.sync(f); err != nil {return err}
	close_error := os.close(f)
	closed = true
	if close_error != nil {return close_error}
	return os.rename(temporary, path)
}
