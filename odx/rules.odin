package odx

import "core:fmt"

RELEASE :: "0.4.0"

// The one rule set this release runs, with or without `odx.json`.
RULE_SET :: 2

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
	// What the rule protects, and what to change in the code. Findings carry neither (principle 6).
	why:             string,
	fix:             string,
}

// IDs are permanent and never reused.
@(rodata)
RULES := [Rule]Rule_Info {
	.Odin                   = {
		"odin",
		false,
		true,
		false,
		false,
		"Every package must compile under odx's strict flags, since odx's rules need valid Odin.",
		"Fix the compiler error or warning that the message quotes.",
	},
	.Parse_Unsupported      = {
		"parse-unsupported",
		false,
		true,
		false,
		false,
		"A file odx can't read or parse gets none of the rules that need its syntax tree.",
		"Make it a regular .odin file with a package clause that core:odin/parser can parse.",
	},
	.Import_Escape          = {
		"import-escape",
		false,
		true,
		false,
		true,
		"A result must depend only on the repo and the Odin root, not on code outside them.",
		"Bring the code into the repo, or import it from the Odin root's base, core or vendor.",
	},
	.Path_Case              = {
		"path-case",
		false,
		true,
		false,
		true,
		"A miscased path works on a case-insensitive disk and breaks on a case-sensitive one.",
		"Spell the path in the exact case of the entries on disk.",
	},
	.Line_Length            = {
		"line-length",
		true,
		false,
		true,
		false,
		"Lines stay within 100 columns, with a tab counted as 4, so code reads without wrapping.",
		"Break the line to fit 100 columns; an ignore with a reason is the exception.",
	},
	.Ignore_Invalid         = {
		"ignore-invalid",
		false,
		true,
		true,
		false,
		"An ignore odx can't apply looks like an exception while it suppresses nothing.",
		"Write // odx:ignore <rules> <reason> above the code, naming only ignorable rules.",
	},
	.Ignore_Unused          = {
		"ignore-unused",
		false,
		false,
		true,
		false,
		"An ignore that suppresses nothing is a stale exception that could hide a later finding.",
		"Delete the ignore, or move it directly above the code that has the finding.",
	},
	.Pending_Stale          = {
		"pending-stale",
		false,
		true,
		false,
		false,
		"Pending is debt to fix, so an entry with nothing left to fix leaves the list.",
		"Remove the entry from pending in odx.json, or correct it to name a package odx checks.",
	},
	.Block_Comment          = {
		"block-comment",
		false,
		false,
		true,
		true,
		"Line comments are the one comment form, so every comment reads the same way.",
		"Rewrite the comment as // line comments.",
	},
	.One_Line_Block         = {
		"one-line-block",
		false,
		false,
		true,
		true,
		"A short body has two forms only: do on one line, or braces on lines of their own.",
		"Write the body with do on one line, or put each brace on its own line.",
	},
	.Auto_Cast              = {
		"auto-cast",
		false,
		false,
		true,
		true,
		"auto_cast hides the target type, so a reader can't see what the conversion does.",
		"Name the type, as cast(T)x or T(x).",
	},
	.Fallthrough            = {
		"fallthrough",
		true,
		false,
		true,
		true,
		"Each switch case stands alone, so no case's code runs on into the next one.",
		"Share code via one case list or a procedure; an ignore with a reason is the exception.",
	},
	.Bounds_Check_Directive = {
		"bounds-check-directive",
		true,
		false,
		true,
		true,
		"Bounds checking follows the build's flags, not a directive that changes it for one block.",
		"Remove the directive; an ignore with a reason is the exception.",
	},
	.Vet_Disabled           = {
		"vet-disabled",
		false,
		false,
		true,
		false,
		"Every file gets the compiler's vet checks, so a #+vet tag can't turn one off for a file.",
		"Remove the items that turn checks off, and fix what the compiler then reports.",
	},
	.Feature_Relaxed        = {
		"feature-relaxed",
		true,
		false,
		true,
		false,
		"A #+feature tag turns off a compiler error that protects the file, such as using-stmt.",
		"Remove the tag and fix what it hid; the exception is a whole-file ignore with a reason.",
	},
	.Transmute              = {
		"transmute",
		true,
		false,
		true,
		true,
		"transmute reinterprets bits with no check that they make sense as the new type.",
		"Use a cast or a conversion; an ignore with a reason is the exception.",
	},
	.Format                 = {
		"format",
		false,
		false,
		true,
		true,
		"All code has the formatter's layout, so a diff shows only real changes.",
		"Run odinfmt with the odinfmt.json that odx init writes, and keep its output.",
	},
	.Proc_Length            = {
		"proc-length",
		true,
		false,
		true,
		true,
		"A procedure body of over 100 counted lines is too long to read as one unit.",
		"Split the procedure into smaller ones; an ignore with a reason is the exception.",
	},
	.Nesting_Depth          = {
		"nesting-depth",
		true,
		false,
		true,
		true,
		"Blocks nested more than 6 deep are hard to follow.",
		"Return early or extract a procedure; an ignore with a reason is the exception.",
	},
	.Name_Case              = {
		"name-case",
		true,
		false,
		true,
		true,
		"Each kind of name has one case, so a name shows if it is a type, procedure or constant.",
		"Rename it in the case the message names, using @(link_name) for a foreign symbol.",
	},
	.Package_Name           = {
		"package-name",
		false,
		false,
		true,
		false,
		"A package is named for its directory, in snake_case, so an import path shows its name.",
		"Rename the package or its directory to one snake_case name, or name the package main.",
	},
	.File_Name              = {
		"file-name",
		false,
		false,
		true,
		false,
		"File names are snake_case like package names, so every path in the repo has one form.",
		"Rename the file in snake_case, such as my_file.odin.",
	},
	.Import_Alias           = {
		"import-alias",
		false,
		false,
		true,
		true,
		"An alias equal to the import's own name is noise that looks like a rename.",
		"Remove the alias.",
	},
	.Import_Order           = {
		"import-order",
		false,
		false,
		true,
		true,
		"Imports keep one order, so a reader finds each one where the order puts it.",
		"Order imports base and core, vendor, collections, relative, a blank line between groups.",
	},
}

@(require_results)
rule_by_id :: proc(id: string) -> (rule: Rule, known: bool) {
	for info, r in RULES {
		if info.id == id {
			return r, true
		}
	}
	return
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
// held back in a pending package per the rule's row in `RULES`. A dropped finding is counted
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
			pkg.muted_count += 1
		}
		return
	}
	finding := finding
	finding.owner_dir = pkg.dir
	finding.held_back ||= pkg.status == .Pending && info.held_back
	append(&result.findings, finding)
}

// Notes the packages whose compile errors hid a finding, in the order of `packages`. A pending
// package's dropped findings are all held back, because every rule that a mute drops is. Allocates
// the lines with `context.allocator`.
note_muted :: proc(packages: []Package, result: ^Result) {
	for p in packages {
		if p.muted_count > 0 {
			append(&result.notes, Note{fmt.aprintf(MUTED_LINE, p.dir), p.status == .Pending})
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
