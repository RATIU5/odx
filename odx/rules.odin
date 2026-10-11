package odx

import "core:fmt"

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
	Format,
	Proc_Length,
	Nesting_Depth,
	Name_Case,
	Package_Name,
	File_Name,
	Import_Alias,
	Import_Order,
}

Rule_Info :: struct {
	id:              string,
	ignorable:       bool,
	runs_when_muted: bool,
	// False for `odin`, whose warnings `finish_compile` holds back itself.
	held_back:       bool,
	needs_parse:     bool,
}

// IDs are permanent and never reused.
@(rodata)
RULES := [Rule]Rule_Info {
	.Odin                   = {"odin", false, true, false, false},
	.Parse_Unsupported      = {"parse-unsupported", false, true, false, false},
	.Import_Escape          = {"import-escape", false, true, false, true},
	.Path_Case              = {"path-case", false, true, false, true},
	.Line_Length            = {"line-length", true, false, true, false},
	.Ignore_Invalid         = {"ignore-invalid", false, true, true, false},
	.Ignore_Unused          = {"ignore-unused", false, false, true, false},
	.Pending_Stale          = {"pending-stale", false, true, false, false},
	.Block_Comment          = {"block-comment", false, false, true, true},
	.One_Line_Block         = {"one-line-block", false, false, true, true},
	.Auto_Cast              = {"auto-cast", false, false, true, true},
	.Do_Stmt                = {"do-stmt", false, false, true, true},
	.Fallthrough            = {"fallthrough", true, false, true, true},
	.Bounds_Check_Directive = {"bounds-check-directive", true, false, true, true},
	.Vet_Disabled           = {"vet-disabled", false, false, true, false},
	.Feature_Relaxed        = {"feature-relaxed", true, false, true, false},
	.Transmute              = {"transmute", true, false, true, true},
	.Format                 = {"format", false, false, true, true},
	.Proc_Length            = {"proc-length", true, false, true, true},
	.Nesting_Depth          = {"nesting-depth", true, false, true, true},
	.Name_Case              = {"name-case", true, false, true, true},
	.Package_Name           = {"package-name", false, false, true, false},
	.File_Name              = {"file-name", false, false, true, false},
	.Import_Alias           = {"import-alias", false, false, true, true},
	.Import_Order           = {"import-order", false, false, true, true},
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
	Format_Timeout,
	Format_Failed,
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
	.Format_Timeout       = "format-timeout",
	.Format_Failed        = "format-failed",
}

// Adds `finding` as `pkg`'s. A nil `pkg` leaves it unowned and adds it as given, with no mute or
// hold-back. Otherwise it is dropped when `pkg` is muted and the rule doesn't run when muted, and
// held back in a pending package per the rule's row in `RULES`. A dropped finding counts as hidden
// unless an ignore covers it, which uses the ignore as a shown finding would. So a muted package
// must get its findings before its unused ignores are looked for. A finding that arrives held back
// stays held back. The added finding borrows its strings and `pkg`'s dir.
add_rule_finding :: proc(result: ^Result, pkg: ^Package, finding: Finding) {
	info := RULES[finding.rule]
	if pkg == nil {
		append(&result.findings, finding)
		return
	}
	if pkg.muted && !info.runs_when_muted {
		if ignore := ignore_covering(pkg, finding); ignore != nil {
			ignore.used = true
		} else {
			pkg.hidden += 1
		}
		return
	}
	finding := finding
	finding.owner_dir = pkg.dir
	finding.held_back ||= pkg.status == .Pending && info.held_back
	append(&result.findings, finding)
}

// Notes the packages whose compile errors hid a finding, in the order of `packages`. A pending
// package's hidden findings are all held back, because every rule that a mute drops is. Allocates
// the lines with `context.allocator`.
note_hidden :: proc(packages: []Package, result: ^Result) {
	for p in packages {
		if p.hidden > 0 {
			append(&result.notes, Note{fmt.aprintf(HIDDEN_LINE, p.dir), p.status == .Pending})
		}
	}
}

// Notes the packages that hold a file tagged `#+test`, in the order of `packages`, with how many.
// It counts the files odx reads, so one that is also tagged `#+build ignore` doesn't count.
// Allocates the lines with `context.allocator`.
note_test_tagged :: proc(packages: []Package, result: ^Result) {
	for p in packages {
		files := 0
		for file in p.files {
			files += int(file.is_test)
		}
		if files > 0 {
			line := fmt.aprintf(TEST_TAGGED_LINE, p.dir, files)
			append(&result.notes, Note{line, p.status == .Pending})
		}
	}
}

// The added findings borrow their strings from `packages`.
add_file_findings :: proc(packages: []Package, result: ^Result) {
	for &pkg in packages {
		for file in pkg.files {
			for f in file.findings {
				add_rule_finding(result, &pkg, f)
			}
		}
	}
}
