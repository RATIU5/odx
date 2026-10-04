package odx

RELEASE :: "0.1.0"

// The newest rule set this release runs, and the one used without `odx.json`.
RULE_SET :: 1

Rule :: enum u8 {
	Odin,
	Parse_Unsupported,
	Import_Escape,
	Path_Case,
	Line_Length,
	Ignore_Invalid,
	Ignore_Unused,
	Pending_Stale,
}

Held_Back :: enum u8 {
	No,
	Yes,
	Strict_Only,
}

Rule_Info :: struct {
	id:              string,
	ignorable:       bool,
	runs_when_muted: bool,
	held_back:       Held_Back,
}

// IDs are permanent and never reused.
@(rodata)
RULES := [Rule]Rule_Info {
	.Odin              = {"odin", false, true, .Strict_Only},
	.Parse_Unsupported = {"parse-unsupported", false, true, .No},
	.Import_Escape     = {"import-escape", false, true, .No},
	.Path_Case         = {"path-case", false, true, .No},
	.Line_Length       = {"line-length", true, false, .Yes},
	.Ignore_Invalid    = {"ignore-invalid", false, true, .Yes},
	.Ignore_Unused     = {"ignore-unused", false, false, .Yes},
	.Pending_Stale     = {"pending-stale", false, true, .No},
}

Error_Code :: enum u8 {
	Usage,
	Compiler_Mismatch,
	Compiler_Unsupported,
	Config_Invalid,
	Odin_Missing,
	Compiler_Output,
	Init_Exists,
	Init_Write,
}

// Codes are permanent and never reused.
@(rodata)
ERROR_CODES := [Error_Code]string {
	.Usage                = "usage",
	.Compiler_Mismatch    = "compiler-mismatch",
	.Compiler_Unsupported = "compiler-unsupported",
	.Config_Invalid       = "config-invalid",
	.Odin_Missing         = "odin-missing",
	.Compiler_Output      = "compiler-output",
	.Init_Exists          = "init-exists",
	.Init_Write           = "init-write",
}

// Adds `finding` as `pkg`'s. A nil `pkg` leaves it unowned and adds it as given, with no mute or
// hold-back. Otherwise it is dropped when `pkg` is muted and the rule doesn't run when muted, and
// held back in a pending package per the rule's row in `RULES`. A finding that arrives held back
// stays held back. `strict_only`, true for a finding only strict checking gives, matters only for
// `.Strict_Only` rules. The added finding borrows its strings and `pkg`'s dir.
add_rule_finding :: proc(result: ^Result, pkg: ^Package, finding: Finding, strict_only: bool) {
	info := RULES[finding.rule]
	if pkg == nil {
		append(&result.findings, finding)
		return
	}
	if pkg.muted && !info.runs_when_muted {
		return
	}
	held: bool
	switch info.held_back {
	case .No:
	case .Yes:
		held = true
	case .Strict_Only:
		held = strict_only
	}
	finding := finding
	finding.owner_dir = pkg.dir
	finding.held_back ||= pkg.status == .Pending && held
	append(&result.findings, finding)
}

// The added findings borrow their strings from `packages`.
add_file_findings :: proc(packages: []Package, result: ^Result) {
	for &pkg in packages {
		for file in pkg.files {
			for f in file.findings {
				add_rule_finding(result, &pkg, f, false)
			}
		}
	}
}
