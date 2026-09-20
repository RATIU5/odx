// M0 spike: parse `odin doc <pkg>` text into (kind, name, signature, doc) entries.
// `-short` drops doc comments, so the full form is parsed. Layout (tab-indented):
//   package X / \tsection / \t\tNAME :: SIG [/* n!m */] / \t\t\tdoc line
package docshort

import "core:fmt"
import "core:os"
import "core:strings"

Entry :: struct {
	kind, name, sig, doc: string,
}

parse_doc :: proc(text: string, allocator := context.allocator) -> []Entry {
	out := make([dynamic]Entry, allocator)
	section := ""
	text := text
	for line in strings.split_lines_iterator(&text) {
		if strings.has_prefix(line, "\t\t\t") {
			// doc line, attach to last entry
			if len(out) > 0 {
				e := &out[len(out) - 1]
				d := strings.trim_space(line)
				e.doc = e.doc == "" ? d : strings.concatenate({e.doc, "\n", d}, allocator)
			}
		} else if strings.has_prefix(line, "\t\t") {
			l := strings.trim_space(line)
			if section == "fullpath:" || section == "files:" || l == "" {continue}
			// strip trailing `/* n!m */` marker
			if i := strings.last_index(l, " /* "); i >= 0 {l = l[:i]}
			name, _, sig := strings.partition(l, " :: ")
			if sig == "" {name, _, sig = strings.partition(l, ": ")}
			append(&out, Entry{kind = section, name = name, sig = strings.trim_space(sig)})
		} else if strings.has_prefix(line, "\t") {
			section = strings.trim_space(line)
		}
	}
	return out[:]
}

main :: proc() {
	if len(os.args) < 2 {
		fmt.eprintln("usage: spike_docshort <pkg-dir>")
		os.exit(2)
	}
	state, stdout, stderr, err := os.process_exec({command = {"odin", "doc", os.args[1]}}, context.allocator)
	if err != nil || state.exit_code != 0 {
		fmt.eprintfln("odin doc failed: %v %s", err, stderr)
		os.exit(2)
	}
	entries := parse_doc(string(stdout))
	for e in entries {
		fmt.printfln("%-10s %-8s %-45s %q", e.kind, e.name, e.sig, e.doc)
	}
	// self-check
	assert(len(entries) == 6, "expected 6 entries from sample/lib")
	assert(entries[3].name == "open" && entries[3].doc == "open opens a thing.")
}
