package odx

import "core:fmt"
import "core:os"
import "core:slice"
import "core:strings"

// Guarantee is one row of the ratchet, as `odx doctor --json` reports it.
Guarantee :: struct {
	flag:     string,
	on:       bool,
	declined: bool,
}

Guarantees_Report :: struct {
	flags:  [dynamic]Guarantee,
	tagged: int, // files carrying #+vet explicit-allocators
	needed: int, // files the policy says should
}

// Guarantees: the checks the installed compiler can enforce that only an external tool
// can verify are switched on. Doctor reports; check enforces (allocators/R1, odx/feature-optout).
// The default set is what `odx init` writes into odin.flags; a project overrides by editing it.

DEFAULT_GUARANTEES := []string {
	"-vet",
	"-vet-tabs",
	"-vet-cast",
	"-strict-style",
	"-warnings-as-errors",
}

// Help_Flags is `odin help check`, parsed once and shared by doctor's flag check and the
// guarantee ratchet. ok is false when the text yields implausibly few flags: a help reflow
// must never fail a build, so callers warn once and skip.
Help_Flags :: struct {
	flags:   map[string]bool, // top-level flag names, `:` suffix dropped
	implied: []string, // flags listed under -vet: on whenever -vet is
	ok:      bool,
}

MIN_HELP_FLAGS :: 5

// A flag line is one whose trimmed text is a single `-token`. Indentation is counted in
// characters, tabs or spaces alike, so the shallowest such lines are top-level and anything
// deeper is nested (the sub-flags under -vet). Nothing depends on tabs.
parse_help_flags :: proc(help: string) -> (hf: Help_Flags) {
	Line :: struct {
		depth: int,
		name:  string,
	}
	found := make([dynamic]Line, context.temp_allocator)
	top := max(int)
	for line in strings.split_lines(help, context.temp_allocator) {
		t := strings.trim_left_space(line)
		if !strings.has_prefix(t, "-") || strings.contains_any(t, " \t") {continue}
		name, _, _ := strings.partition(t, ":")
		depth := len(line) - len(t)
		top = min(top, depth)
		append(&found, Line{depth, name})
	}
	hf.flags = make(map[string]bool)
	imp := make([dynamic]string)
	for l in found {
		if l.depth == top {hf.flags[l.name] = true} else {append(&imp, l.name)}
	}
	hf.implied = imp[:]
	hf.ok = len(hf.flags) >= MIN_HELP_FLAGS
	return
}

// compiler_guarantees: every -vet*/-strict-style/-warnings-as-errors flag the compiler lists,
// so doctor ratchets as the compiler grows. implied are the sub-flags of -vet.
compiler_guarantees :: proc(hf: Help_Flags) -> (flags, implied: []string) {
	is_guarantee :: proc(name: string) -> bool {
		if strings.contains(name, "-packages") {return false} 	// scoping, not a guarantee
		return(
			strings.has_prefix(name, "-vet") ||
			name == "-strict-style" ||
			name == "-warnings-as-errors" \
		)
	}
	out := make([dynamic]string, context.temp_allocator)
	imp := make([dynamic]string, context.temp_allocator)
	for name in sorted_keys(hf.flags) {if is_guarantee(name) {append(&out, name)}}
	for name in hf.implied {if is_guarantee(name) {append(&imp, name)}}
	return out[:], imp[:]
}

// Missing defaults and un-adopted compiler flags are warnings; `check` turns the per-file
// opt-outs into violations.
report_guarantees :: proc(d: ^Doctor, c: ^Ctx, hf: Help_Flags) {
	if !hf.ok {
		warn(d, "cannot read `odin help check` output; guarantee ratchet skipped")
		return
	}
	flags, implied := compiler_guarantees(hf)
	on := make(map[string]bool, context.temp_allocator)
	for f in c.cfg.odin.flags {
		name, _, _ := strings.partition(f, ":")
		on[name] = true
	}
	if on["-vet"] {for f in implied {on[f] = true}}
	say(d, "guarantees (odin.flags):")
	for f in flags {
		reason, declined := c.cfg.odin.declined[f]
		state := "on " if on[f] else "off"
		append(&d.guarantees.flags, Guarantee{f, on[f], declined})
		say(d, "  %s %s%s", state, f, fmt.tprintf("  declined: %s", reason) if declined else "")
		if !on[f] {
			if slice.contains(DEFAULT_GUARANTEES, f) {
				warn(d, "default guarantee %s is not in odin.flags", f)
			} else if slice.contains(implied, f) || declined {
				// implied by -vet, or considered and refused: not noise
			} else {
				warn(d, "the installed compiler offers %s and this project has not adopted it (odin.flags to adopt, odin.declined to refuse)", f)
			}
		}
	}
	for f in sorted_keys(c.cfg.odin.declined) {
		if f not_in hf.flags {warn(d, "odin.declined names %s, which this compiler does not offer", f)}
		if on[f] {warn(d, "odin.declined names %s, which odin.flags also turns on", f)}
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
	d.guarantees.tagged, d.guarantees.needed = tagged, needed
	if needed >
	   0 {say(d, "  %s #+vet explicit-allocators: %d of %d pure/service files tagged (allocators/R1 names the rest)", "on " if tagged == needed else "off", tagged, needed)}
	// the ratchet for the one per-file guarantee: coverage may not drop below the recorded floor
	if floor := c.cfg.odin.tagged_files_min; tagged < floor {
		err(d, "#+vet explicit-allocators coverage is %d files, below odin.tagged_files_min %d", tagged, floor)
	} else if tagged > floor && needed > 0 {
		warn(d, "#+vet explicit-allocators coverage is %d files; raise odin.tagged_files_min from %d so it cannot regress", tagged, floor)
	}
	for p in c.pkgs {
		for f in p.files {
			for tok in f.tags {
				t := strings.trim_space(strings.trim_prefix(tok.text, "#+"))
				if strings.has_prefix(t, "feature") || strings.contains(t, "!") {
					rel, _ := rel_of(c.root, f.fullpath)
					say(d, "  opt-out %s:%d: %s", rel, tok.pos.line, tok.text)
				}
			}
		}
	}
	_ = os.exists
}
