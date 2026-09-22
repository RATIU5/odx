package odx

import "core:fmt"
import doc "core:odin/doc-format"
import "core:os"
import "core:testing"

@(test)
test_doc_evidence_rejects_short_headers :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	defer free_all(context.temp_allocator)
	data := make([]byte, size_of(doc.Header_Base))
	base := (^doc.Header_Base)(raw_data(data))
	base.magic = doc.Magic_String
	base.version = doc.Version_Type_Default
	base.total_size = u32le(len(data))
	base.header_size = u32le(len(data))
	h, reason, unsupported := read_doc_evidence(data)
	testing.expect(t, h == nil && reason != "" && !unsupported)
	for n in 0 ..< len(data) {
		h, reason, unsupported = read_doc_evidence(data[:n])
		testing.expect(t, h == nil && reason != "" && !unsupported)
	}
}

@(test)
test_doc_evidence_export_and_corruption :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	defer free_all(context.temp_allocator)
	p := scratch_project(t, {{"main.odin", `package example
Error :: enum {None, Bad}
Alias :: Error
@(require_results)
checked :: proc() -> Alias {return .None}
unchecked :: proc() -> Alias {return .None}
`}})
	defer os.remove_all(p.root)
	out := join({p.root, "export.odin-doc"})
	cmd := []string{odin_exe(&p.cfg), "doc", p.root, "-doc-format", "-thread-count:1", fmt.aprintf("-out:%s", out)}
	state, _, stderr, err := os.process_exec({command = cmd}, context.allocator)
	if !testing.expect(t, err == nil && state.exit_code == 0, string(stderr)) {return}
	data, ferr := os.read_entire_file(out, context.allocator)
	if !testing.expect(t, ferr == nil) {return}
	h, reason, unsupported := read_doc_evidence(data)
	if !testing.expect(t, h != nil && reason == "" && !unsupported, reason) {return}
	checked_found := false
	for e in doc.from_array(h, h.entities) {
		if doc.from_string(h, e.name) != "checked" {continue}
		for attr in doc.from_array(h, e.attributes) {
			if doc.from_string(h, attr.name) == "require_results" {checked_found = true}
		}
	}
	testing.expect(t, checked_found, "valid compiler attributes survive validation")
	for mutation in 0 ..< 9 {
		bad := make([]byte, len(data))
		copy(bad, data)
		bh := (^doc.Header)(raw_data(bad))
		switch mutation {
		case 0: bh.version.minor += 1
		case 1: bh.entities.offset = u32le(len(bad) + 1)
		case 2: bh.types.length = max(u32le)
		case 3: doc.from_array(bh, bh.entities)[1].type = doc.Type_Index(bh.types.length)
		case 4: doc.from_array(bh, bh.types)[1].name = doc.String{offset = u32le(len(bad)), length = 1}
		case 5: bh.header_size = 0
		case 6: doc.from_array(bh, bh.entities)[1].pos.file = doc.File_Index(bh.files.length)
		case 7: doc.from_array(bh, bh.entities)[1].attributes = {offset = u32le(len(bad)), length = 1}
		case 8:
			pkg := doc.from_array(bh, bh.pkgs)[1]
			doc.from_array(bh, pkg.entries)[0].entity = doc.Entity_Index(bh.entities.length)
		}
		got, why, version := read_doc_evidence(bad)
		testing.expect(t, got == nil && why != "")
		testing.expect_value(t, version, mutation == 0)
	}
}

@(private = "file")
Scratch_File :: struct {
	name, text: string,
}

scratch_project :: proc(t: ^testing.T, files: []Scratch_File) -> (p: Project) {
	tmp, terr := os.make_directory_temp("", "odx-test-*", context.allocator)
	testing.expect(t, terr == nil)
	for f in files {
		path := join({tmp, f.name})
		os.make_directory_all(dir_of(path))
		testing.expect(t, os.write_entire_file(path, transmute([]byte)f.text) == nil)
	}
	p.root = tmp
	p.cfg = default_config()
	return
}
