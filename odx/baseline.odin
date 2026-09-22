package odx

import crypto_hash "core:crypto/hash"
import "core:encoding/hex"
import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:slice"
import "core:strings"

BASELINE_FILE :: "odx.baseline"

Baseline_Entry :: struct {
	rule, file, subject, fingerprint: string,
	line, col:                        int,
	reason:                           string,
}
Baseline_Document :: struct {
	format_version: int,
	entries:        []Baseline_Entry,
}

baseline_file :: proc(root: string) -> (mode: os.Permissions, exists: bool, err: string) {
	path := join({root, BASELINE_FILE})
	info, stat_error := os.lstat(path, context.temp_allocator)
	if stat_error == .Not_Exist {return os.Permissions_Read_All + {.Write_User}, false, ""}
	if stat_error != nil {return {}, false, fmt.tprintf("cannot inspect %s: %v", path, stat_error)}
	if info.type !=
	   .Regular {return {}, true, fmt.tprintf("%s must be a regular file, not a symlink or directory", path)}
	return info.mode, true, ""
}

read_baseline :: proc(root: string) -> (out: []Baseline_Entry, exists: bool, err: string) {
	_, exists, err = baseline_file(root)
	if err != "" || !exists {return}
	data, read_error := os.read_entire_file(join({root, BASELINE_FILE}), context.allocator)
	if read_error !=
	   nil {return nil, true, fmt.tprintf("cannot read %s: %v", BASELINE_FILE, read_error)}
	text := string(data)
	if strings.has_prefix(strings.trim_space(text), "format_version: 1") {
		return nil,
			true,
			"odx.baseline version 1 cannot identify historical occurrences; review current findings and run `odx baseline regen` to explicitly accept them in version 2"
	}
	// Odin's JSON integer conversion can wrap before range validation.
	tokens := json.make_tokenizer(text, parse_integers = true)
	for {
		token, token_error := json.get_token(&tokens)
		if token_error == .EOF || token.kind == .EOF {break}
		if token_error !=
		   nil {return nil, true, fmt.tprintf("invalid odx.baseline: %v", token_error)}
		if token.kind == .Float ||
		   token.kind == .Integer &&
			   !policy_integer_fits(
					   token.text,
				   ) {return nil, true, "invalid odx.baseline number: expected a signed 64-bit integer"}
	}
	value, parse_error := json.parse_string(text)
	obj, is_object := value.(json.Object)
	if parse_error != nil ||
	   !is_object ||
	   len(obj) != 2 ||
	   "format_version" not_in obj ||
	   "entries" not_in obj {
		return nil, true, "invalid odx.baseline document: expected format_version and entries"
	}
	document: Baseline_Document
	if decode_error := json.unmarshal_string(text, &document); decode_error != nil {
		return nil, true, fmt.tprintf("invalid odx.baseline: %v", decode_error)
	}
	if document.format_version !=
	   2 {return nil, true, "unsupported odx.baseline format_version; version 2 is required"}
	values, is_array := obj["entries"].(json.Array)
	if !is_array {return nil, true, "invalid odx.baseline entries: expected an array"}
	for entry_value, i in values {
		fields, valid := entry_value.(json.Object)
		if !valid ||
		   len(fields) !=
			   7 {return nil, true, fmt.tprintf("invalid odx.baseline entry %d: expected seven identity/reason fields", i + 1)}
		for key in fields {
			if key != "rule" &&
			   key != "file" &&
			   key != "subject" &&
			   key != "fingerprint" &&
			   key != "line" &&
			   key != "col" &&
			   key != "reason" {
				return nil, true, fmt.tprintf("invalid odx.baseline entry field %q", key)
			}
		}
		for key in ([]string{"rule", "file", "subject", "fingerprint", "reason"}) {
			if _, valid_string := fields[key].(string);
			   !valid_string {return nil, true, fmt.tprintf("invalid odx.baseline %s: expected string", key)}
		}
		e := document.entries[i]
		line, line_number := fields["line"].(f64)
		col, col_number := fields["col"].(f64)
		if !line_number ||
		   !col_number ||
		   line != f64(e.line) ||
		   col != f64(e.col) {return nil, true, "invalid odx.baseline position: expected integers"}
		cleaned, _ := filepath.clean(e.file)
		if e.rule == "" ||
		   e.subject == "" ||
		   !strings.has_suffix(e.file, ".odin") ||
		   filepath.is_abs(e.file) ||
		   cleaned != e.file ||
		   strings.has_prefix(e.file, "../") ||
		   strings.contains(e.file, "\\") ||
		   e.line <= 0 ||
		   e.col <= 0 ||
		   len(e.fingerprint) != 64 {
			return nil, true, fmt.tprintf("invalid odx.baseline identity at entry %d", i + 1)
		}
		for ch in e.fingerprint {
			if !(ch >= '0' && ch <= '9' ||
				   ch >= 'a' &&
					   ch <= 'f') {return nil, true, "invalid odx.baseline SHA256 fingerprint"}
		}
	}
	return document.entries, true, ""
}

write_baseline :: proc(root: string, es: []Baseline_Entry) -> string {
	mode, _, inspect_error := baseline_file(root)
	if inspect_error != "" {return inspect_error}
	slice.sort_by(es, proc(a, b: Baseline_Entry) -> bool {
		if a.file != b.file {return a.file < b.file}
		if a.line != b.line {return a.line < b.line}
		if a.col != b.col {return a.col < b.col}
		if a.rule != b.rule {return a.rule < b.rule}
		if a.subject != b.subject {return a.subject < b.subject}
		if a.fingerprint != b.fingerprint {return a.fingerprint < b.fingerprint}
		return a.reason < b.reason
	})
	data, encode_error := json.marshal(Baseline_Document{2, es}, {pretty = true})
	if encode_error != nil {return fmt.tprintf("cannot encode baseline: %v", encode_error)}
	if err := replace_file_atomic(
		join({root, BASELINE_FILE}),
		strings.concatenate({string(data), "\n"}),
		mode,
	); err != nil {return fmt.tprintf("cannot write baseline: %v", err)}
	return ""
}

// Hash parsed source, so accepted debt belongs to the evidence actually checked.
baseline_fingerprints :: proc(c: ^Ctx) -> map[string]string {
	out := make(map[string]string, context.temp_allocator)
	for p in c.pkgs {
		if p.parse_result.status != .complete {continue}
		for f in p.files {
			rel, ok := rel_of(c.root, f.fullpath)
			if !ok {continue}
			digest := crypto_hash.hash_bytes(
				.SHA256,
				transmute([]byte)f.src,
				context.temp_allocator,
			)
			out[rel] = string(hex.encode(digest, context.temp_allocator))
		}
	}
	return out
}

baseline_key :: proc(
	v: Violation,
	fingerprints: map[string]string,
) -> (
	e: Baseline_Entry,
	ok: bool,
) {
	fingerprint, found := fingerprints[v.file]
	if !found || v.subject == "" || v.line <= 0 || v.col <= 0 {return}
	return Baseline_Entry {
			rule = v.rule,
			file = v.file,
			subject = v.subject,
			fingerprint = fingerprint,
			line = v.line,
			col = v.col,
		},
		true
}

baseline_same :: proc(a, b: Baseline_Entry) -> bool {
	return(
		a.rule == b.rule &&
		a.file == b.file &&
		a.subject == b.subject &&
		a.fingerprint == b.fingerprint &&
		a.line == b.line &&
		a.col == b.col \
	)
}

baseline_match :: proc(c: ^Ctx, es: []Baseline_Entry) -> []bool {
	hit := make([]bool, len(es), context.temp_allocator)
	fingerprints := baseline_fingerprints(c)
	for &v in c.r.violations {
		if r := find_rule(c.rb, v.rule); r == nil || !r.baselineable {continue}
		key, eligible := baseline_key(v, fingerprints)
		if !eligible {continue}
		for e, i in es {
			if !hit[i] && baseline_same(e, key) {hit[i] = true; v.baselined = true; break}
		}
	}
	return hit
}

apply_baseline :: proc(c: ^Ctx, full: bool) {
	es, exists, err := read_baseline(c.root)
	if err != "" {tool_error(c.r, "%s", err); return}
	if !exists {return}
	hit := baseline_match(c, es)
	if !full {return}
	stale := 0
	for matched in hit {if !matched {stale += 1}}
	if stale >
	   0 {tool_error(c.r, "%s lists %d entries that no longer match; run `odx baseline prune` to remove resolved entries or review findings before `odx baseline regen`", BASELINE_FILE, stale)}
}
