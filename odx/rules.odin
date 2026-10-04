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
	Block_Comment,
	One_Line_Block,
	Auto_Cast,
	Do_Stmt,
	Fallthrough,
	Bounds_Check_Directive,
	Vet_Disabled,
	Feature_Relaxed,
	Transmute,
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
	needs_parse:     bool,
}

// IDs are permanent and never reused.
@(rodata)
RULES := [Rule]Rule_Info {
	.Odin                   = {"odin", false, true, .Strict_Only, false},
	.Parse_Unsupported      = {"parse-unsupported", false, true, .No, false},
	.Import_Escape          = {"import-escape", false, true, .No, true},
	.Path_Case              = {"path-case", false, true, .No, true},
	.Line_Length            = {"line-length", true, false, .Yes, false},
	.Ignore_Invalid         = {"ignore-invalid", false, true, .Yes, false},
	.Ignore_Unused          = {"ignore-unused", false, false, .Yes, false},
	.Pending_Stale          = {"pending-stale", false, true, .No, false},
	.Block_Comment          = {"block-comment", false, false, .Yes, true},
	.One_Line_Block         = {"one-line-block", false, false, .Yes, true},
	.Auto_Cast              = {"auto-cast", false, false, .Yes, true},
	.Do_Stmt                = {"do-stmt", false, false, .Yes, true},
	.Fallthrough            = {"fallthrough", true, false, .Yes, true},
	.Bounds_Check_Directive = {"bounds-check-directive", true, false, .Yes, true},
	.Vet_Disabled           = {"vet-disabled", false, false, .Yes, false},
	.Feature_Relaxed        = {"feature-relaxed", true, false, .Yes, false},
	.Transmute              = {"transmute", true, false, .Yes, true},
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
	Dir_Unreadable,
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
	.Dir_Unreadable       = "dir-unreadable",
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
