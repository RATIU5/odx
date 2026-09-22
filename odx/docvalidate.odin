package odx

import "core:fmt"
import doc "core:odin/doc-format"

// The native reader validates only its base header. Check every field consumed by
// entity rules before allowing the format's unchecked pointer-based accessors.
read_doc_evidence :: proc(data: []byte) -> (h: ^doc.Header, reason: string, unsupported: bool) {
	derr: doc.Reader_Error
	h, derr = doc.read_from_bytes(data)
	if derr == .Invalid_Version {
		base := (^doc.Header_Base)(raw_data(data))
		got, want := base.version, doc.Version_Type_Default
		return nil, fmt.aprintf("unsupported doc-format %d.%d.%d; rebuild with matching compiler %d.%d.%d", got.major, got.minor, got.patch, want.major, want.minor, want.patch), true
	}
	if derr != nil {return nil, fmt.aprintf("invalid doc-format: %v", derr), false}
	if len(data) < size_of(doc.Header) || int(h.total_size) < size_of(doc.Header) ||
	   int(h.header_size) != size_of(doc.Header) || int(h.total_size) != len(data) {
		return nil, "invalid doc-format header size", false
	}
	if !doc_evidence_bounds(h) {return nil, "invalid doc-format evidence bounds or index", false}
	return h, "", false
}

doc_array_valid :: proc(h: ^doc.Header, a: $A/doc.Array($T)) -> bool {
	offset, count, size := u64(a.offset), u64(a.length), u64(h.total_size)
	return offset <= size && count <= (size - offset) / u64(size_of(T)) &&
	       (count == 0 || offset % u64(align_of(T)) == 0)
}

doc_evidence_bounds :: proc(h: ^doc.Header) -> bool {
	if !doc_array_valid(h, h.files) || !doc_array_valid(h, h.pkgs) ||
	   !doc_array_valid(h, h.entities) || !doc_array_valid(h, h.types) {return false}
	files := doc.from_array(h, h.files)
	pkgs := doc.from_array(h, h.pkgs)
	ents := doc.from_array(h, h.entities)
	types := doc.from_array(h, h.types)
	if len(files) == 0 || len(pkgs) == 0 || len(ents) == 0 || len(types) == 0 {return false}
	for file in files {if !doc_array_valid(h, file.name) {return false}}
	for pkg in pkgs {
		if !doc_array_valid(h, pkg.fullpath) || !doc_array_valid(h, pkg.entries) {return false}
		for entry in doc.from_array(h, pkg.entries) {
			if u64(entry.entity) >= u64(len(ents)) {return false}
		}
	}
	for e in ents {
		if !doc_array_valid(h, e.name) || !doc_array_valid(h, e.attributes) ||
		   u64(e.type) >= u64(len(types)) || u64(e.pos.file) >= u64(len(files)) {return false}
		for attr in doc.from_array(h, e.attributes) {
			if !doc_array_valid(h, attr.name) {return false}
		}
	}
	for t in types {
		if !doc_array_valid(h, t.name) || !doc_array_valid(h, t.types) ||
		   !doc_array_valid(h, t.entities) {return false}
		for ti in doc.from_array(h, t.types) {if u64(ti) >= u64(len(types)) {return false}}
		for ei in doc.from_array(h, t.entities) {if u64(ei) >= u64(len(ents)) {return false}}
	}
	return true
}
