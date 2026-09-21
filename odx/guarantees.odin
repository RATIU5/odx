package odx

import "core:fmt"
import "core:os"
import "core:slice"
import "core:strings"

// Guarantees (M4.1): the checks the installed compiler can enforce that only an external tool
// can verify are switched on. Doctor reports; check enforces (allocators/R1, odx/feature-optout).
// The default set is what `odx init` writes into odin.flags; a project overrides by editing it.

DEFAULT_GUARANTEES := []string {
	"-vet",
	"-vet-tabs",
	"-vet-cast",
	"-strict-style",
	"-warnings-as-errors",
}

// compiler_guarantees: every -vet*/-strict-style/-warnings-as-errors flag `odin help check`
// lists, so doctor ratchets as the compiler grows. implied are the sub-flags of -vet.
compiler_guarantees :: proc(help: string) -> (flags, implied: []string) {
	out := make([dynamic]string, context.temp_allocator)
	imp := make([dynamic]string, context.temp_allocator)
	for line in strings.split_lines(help, context.temp_allocator) {
		t := strings.trim_left_space(line)
		if !(strings.has_prefix(t, "-vet") ||
			   strings.has_prefix(t, "-strict-style") ||
			   strings.has_prefix(t, "-warnings-as-errors")) {continue}
		name, _, _ := strings.partition(t, ":")
		if strings.contains(name, "-packages") {continue} 	// scoping, not a guarantee
		if strings.count(line, "\t") >
		   1 {append(&imp, name)} else if !slice.contains(out[:], name) {append(&out, name)}
	}
	return out[:], imp[:]
}

// report_guarantees prints on/off per compiler guarantee, the per-file opt-outs, and the
// explicit-allocators coverage. Missing defaults and un-adopted compiler flags are warnings:
// doctor never refuses (P5); check turns the per-file ones into violations.
report_guarantees :: proc(d: ^Doctor, c: ^Ctx, help: string) {
	flags, implied := compiler_guarantees(help)
	on := make(map[string]bool, context.temp_allocator)
	for f in c.cfg.odin.flags {
		name, _, _ := strings.partition(f, ":")
		on[name] = true
	}
	if on["-vet"] {for f in implied {on[f] = true}}
	fmt.println("guarantees (odin.flags):")
	for f in flags {
		state := "on " if on[f] else "off"
		fmt.printfln("  %s %s", state, f)
		if !on[f] {
			if slice.contains(DEFAULT_GUARANTEES, f) {
				warn(d, "default guarantee %s is not in odin.flags", f)
			} else if slice.contains(implied, f) {
			} else {
				warn(d, "the installed compiler offers %s and this project has not adopted it", f)
			}
		}
	}
	tagged, needed := 0, 0
	for p in c.pkgs {
		if c.cfg.odin.explicit_allocators == .off {break}
		if c.cfg.odin.explicit_allocators == .pure &&
		   p.role != "pure" &&
		   p.role != "service" {continue}
		for f in p.files {
			needed += 1
			if slice.contains(vet_tag_names(f), "explicit-allocators") {tagged += 1}
		}
	}
	if needed >
	   0 {fmt.printfln("  %s #+vet explicit-allocators: %d of %d pure/service files tagged (allocators/R1 names the rest)", "on " if tagged == needed else "off", tagged, needed)}
	for p in c.pkgs {
		for f in p.files {
			for tok in f.tags {
				t := strings.trim_space(strings.trim_prefix(tok.text, "#+"))
				if strings.has_prefix(t, "feature") || strings.contains(t, "!") {
					rel, _ := rel_of(c.root, f.fullpath)
					fmt.printfln("  opt-out %s:%d: %s", rel, tok.pos.line, tok.text)
				}
			}
		}
	}
	_ = os.exists
}
