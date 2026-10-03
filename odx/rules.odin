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
	Warnings_Only,
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
	.Odin              = {"odin", false, true, .Warnings_Only},
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
}
