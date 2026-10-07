package odx

import "core:strings"

Case :: enum u8 {
	Snake,
	Ada,
	Screaming,
}

@(rodata)
CASE_NAMES := [Case]string {
	.Snake     = "snake_case",
	.Ada       = "Ada_Case",
	.Screaming = "SCREAMING_CASE",
}

Name_Kind :: enum u8 {
	Type,
	Enum_Member,
	Poly_Type,
	Proc,
	Proc_Group,
	Value_Constant,
	Poly_Value,
	Package_Literal,
	Variable,
	Parameter,
	Result,
	Field,
	Label,
	Loop_Variable,
	Type_Switch_Variable,
	Import_Alias,
	Foreign_Import,
}

@(rodata)
NAME_CASES := [Name_Kind]Case {
	.Type                 = .Ada,
	.Enum_Member          = .Ada,
	.Poly_Type            = .Ada,
	.Proc                 = .Snake,
	.Proc_Group           = .Snake,
	.Value_Constant       = .Screaming,
	.Poly_Value           = .Screaming,
	.Package_Literal      = .Screaming,
	.Variable             = .Snake,
	.Parameter            = .Snake,
	.Result               = .Snake,
	.Field                = .Snake,
	.Label                = .Snake,
	.Loop_Variable        = .Snake,
	.Type_Switch_Variable = .Snake,
	.Import_Alias         = .Snake,
	.Foreign_Import       = .Snake,
}

@(rodata)
NAME_KIND_LABELS := [Name_Kind]string {
	.Type                 = "type",
	.Enum_Member          = "enum member",
	.Poly_Type            = "parametric type",
	.Proc                 = "procedure",
	.Proc_Group           = "procedure group",
	.Value_Constant       = "constant",
	.Poly_Value           = "parametric value",
	.Package_Literal      = "package-level literal variable",
	.Variable             = "variable",
	.Parameter            = "parameter",
	.Result               = "result",
	.Field                = "field",
	.Label                = "label",
	.Loop_Variable        = "loop variable",
	.Type_Switch_Variable = "type-switch variable",
	.Import_Alias         = "import alias",
	.Foreign_Import       = "foreign import name",
}

// The declaration kind whose case an alias takes, by the kind its right side resolves to. An alias
// of a variable doesn't compile, and an unresolved one is never a finding.
@(rodata)
ALIAS_NAME_KINDS := [Kind]Maybe(Name_Kind) {
	.Unknown   = nil,
	.Type      = .Type,
	.Poly_Type = .Type,
	.Proc      = .Proc,
	.Type_Proc = .Proc,
	.Value     = .Value_Constant,
	.Variable  = nil,
}

@(private = "file")
Char_Class :: enum u8 {
	Lower,
	Upper,
	Digit,
}

@(private = "file")
Char_Classes :: bit_set[Char_Class]

@(private = "file", rodata)
FIRST_CHAR := [Case]Char_Class {
	.Snake     = .Lower,
	.Ada       = .Upper,
	.Screaming = .Upper,
}

// A name is words of ASCII letters and digits joined by single underscores. A name with any other
// byte, or with an empty word, has no case, and a name can have more than one.
has_case :: proc(name: string, want: Case) -> bool {
	if name == "" || !all_in(name[:1], {FIRST_CHAR[want]}) {
		return false
	}
	rest := name
	is_first := true
	for {
		word := rest
		underscore := strings.index_byte(rest, '_')
		if underscore >= 0 {
			word = rest[:underscore]
		}
		if !word_has_case(word, want, is_first) {
			return false
		}
		if underscore < 0 {
			return true
		}
		rest = rest[underscore + 1:]
		is_first = false
	}
}

@(private = "file")
word_has_case :: proc(word: string, want: Case, is_first: bool) -> bool {
	if word == "" {
		return false
	}
	switch want {
	case .Snake:
		return all_in(word, {.Lower, .Digit})
	case .Screaming:
		return all_in(word, {.Upper, .Digit})
	case .Ada:
		if all_in(word, {.Upper, .Digit}) {
			return true
		}
		starts: Char_Classes = {.Upper} if is_first else {.Upper, .Digit}
		return all_in(word[:1], starts) && all_in(word[1:], {.Lower, .Digit})
	}
	return false
}

@(private = "file")
all_in :: proc(text: string, classes: Char_Classes) -> bool {
	for i in 0 ..< len(text) {
		class: Char_Class
		switch text[i] {
		case 'a' ..= 'z':
			class = .Lower
		case 'A' ..= 'Z':
			class = .Upper
		case '0' ..= '9':
			class = .Digit
		case:
			return false
		}
		if class not_in classes {
			return false
		}
	}
	return true
}
