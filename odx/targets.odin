package odx

import "core:odin/tokenizer"
import "core:strings"
import "core:unicode/utf8"

// A port of the compiler's file selection at the pinned commit. `mise run selection` diffs it
// against the compiler, so rerun that on every compiler bump. Line references are to the compiler's
// `src/`.

Target :: enum u8 {
	Darwin_Arm64,
	Linux_Amd64,
}

Targets :: bit_set[Target;u8]

ALL_TARGETS :: Targets{.Darwin_Arm64, .Linux_Amd64}

Target_Info :: struct {
	name: string,
	os:   Target_Os,
	arch: Target_Arch,
}

// ADR 0005 fixes these. Both select the default subtarget.
@(rodata)
TARGETS := [Target]Target_Info {
	.Darwin_Arm64 = {"darwin_arm64", .Darwin, .Arm64},
	.Linux_Amd64  = {"linux_amd64", .Linux, .Amd64},
}

// `target_os_names` in build_settings.cpp:33.
Target_Os :: enum u8 {
	Invalid,
	Windows,
	Darwin,
	Linux,
	Freebsd,
	Openbsd,
	Netbsd,
	Wasi,
	Js,
	Orca,
	Freestanding,
}

@(rodata)
TARGET_OS_NAMES := [Target_Os]string {
	.Invalid      = "",
	.Windows      = "windows",
	.Darwin       = "darwin",
	.Linux        = "linux",
	.Freebsd      = "freebsd",
	.Openbsd      = "openbsd",
	.Netbsd       = "netbsd",
	.Wasi         = "wasi",
	.Js           = "js",
	.Orca         = "orca",
	.Freestanding = "freestanding",
}

// `target_arch_names` in build_settings.cpp:63.
Target_Arch :: enum u8 {
	Invalid,
	Amd64,
	I386,
	Arm32,
	Arm64,
	Wasm32,
	Wasm64p32,
	Riscv64,
}

@(rodata)
TARGET_ARCH_NAMES := [Target_Arch]string {
	.Invalid   = "",
	.Amd64     = "amd64",
	.I386      = "i386",
	.Arm32     = "arm32",
	.Arm64     = "arm64",
	.Wasm32    = "wasm32",
	.Wasm64p32 = "wasm64p32",
	.Riscv64   = "riscv64",
}

// `subtarget_strings` in build_settings.cpp:180. `Invalid` comes last there too, as no real
// subtarget.
Subtarget :: enum u8 {
	Default,
	Iphone,
	Iphonesimulator,
	Android,
	Playdate,
	Invalid,
}

@(rodata)
SUBTARGET_NAMES := [Subtarget]string {
	.Default         = "",
	.Iphone          = "iphone",
	.Iphonesimulator = "iphonesimulator",
	.Android         = "android",
	.Playdate        = "playdate",
	.Invalid         = "",
}

// What the file's `#+` tags say, apart from the file name.
Tag_Verdict :: struct {
	targets: Targets,
	is_test: bool,
	// `#+ignore`, or a `#+build` tag that is exactly `ignore`. odx doesn't read such a file.
	ignored: bool,
}

// `project` is the name the compiler gives the build, the last element of the package directory's
// real path. `targets` is the set the compiler accepts under `odin test`, so `odin check` compiles
// the file exactly when it is in `targets` and isn't a test file.
judge_tags :: proc(tags: []File_Tag, project: string) -> (verdict: Tag_Verdict) {
	verdict.targets = ALL_TARGETS
	for raw in tags {
		tag := trim_tag_space(raw.body)
		switch {
		case strings.has_prefix(tag, "build-project-name"):
			if !parse_build_project_directory_tag(tag, project) {
				verdict.targets = {}
			}
		case strings.has_prefix(tag, "build"):
			if !build_require_space_after(tag, "build") &&
			   trim_tag_space(tag[len("build"):]) == "ignore" {
				verdict.ignored = true
			}
			for t in Target {
				if !parse_build_tag(tag, t) {
					verdict.targets -= {t}
				}
			}
		case strings.has_prefix(tag, "test"):
			verdict.is_test = true
		case strings.has_prefix(tag, "ignore"):
			verdict.ignored = true
			verdict.targets = {}
		}
	}
	return
}

// `is_excluded_target_filename` in build_settings.cpp:1006, negated. It splits the name without its
// extension at its last two `_` and matches an OS and an architecture in either order.
file_name_targets :: proc(name: string) -> (targets: Targets) {
	if is_dot_file(name) {
		return {}
	}
	stem := remove_extension(name)
	n := strings.last_index_byte(stem, '_') + 1
	str1 := stem[n:]
	if str1 == stem {
		return ALL_TARGETS
	}
	str2 := stem[:max(n - 1, 0)]
	str2 = str2[strings.last_index_byte(str2, '_') + 1:]

	os1, _, _ := os_from_string(str1)
	arch1 := arch_from_string(str1)
	os2, _, _ := os_from_string(str2)
	arch2 := arch_from_string(str2)
	for t in Target {
		info := TARGETS[t]
		excluded: bool
		switch {
		case os1 != .Invalid && arch2 != .Invalid:
			excluded = os1 != info.os || arch2 != info.arch
		case arch1 != .Invalid && os2 != .Invalid:
			excluded = arch1 != info.arch || os2 != info.os
		case os1 != .Invalid:
			excluded = os1 != info.os
		case arch1 != .Invalid:
			excluded = arch1 != info.arch
		}
		if !excluded {
			targets += {t}
		}
	}
	return
}

// The compiler never compiles a name that starts with `.` once its extension is gone, so the file
// `.odin` itself does compile.
is_dot_file :: proc(name: string) -> bool {
	return strings.has_prefix(remove_extension(name), ".")
}

// `remove_extension_from_path` in path.cpp:8.
@(private = "file")
remove_extension :: proc(s: string) -> string {
	if strings.has_suffix(s, ".") {
		return s
	}
	if i := strings.last_index_byte(s, '.'); i >= 0 {
		return s[:i]
	}
	return s
}

// `parse_build_tag` in parser.cpp:6998. A tag the compiler calls a syntax error gets the compiler's
// verdict all the same, and the compiler's check reports the error.
@(private = "file")
parse_build_tag :: proc(tag: string, target: Target) -> bool {
	PREFIX :: "build"
	if build_require_space_after(tag, PREFIX) {
		return true
	}
	s := trim_tag_space(tag[len(PREFIX):])
	if len(s) == 0 {
		return true
	}
	info := TARGETS[target]
	// odx never builds for bedrock, and both targets select the default subtarget.
	BEDROCK :: false
	SELECTED_SUBTARGET :: Subtarget.Default

	any_correct := false
	for len(s) > 0 {
		this_kind_correct := true
		this_kind_os_seen := false
		this_kind_arch_seen := false
		num_tokens := 0
		for {
			p: string
			p, s = tag_get_token(s, ":")
			p = trim_tag_space(p)
			if len(p) == 0 || p == "," {
				break
			}
			is_notted := false
			if p[0] == '!' {
				is_notted = true
				p = p[1:]
				if len(p) == 0 {
					break
				}
			}
			if p == "ignore" {
				this_kind_correct = false
				continue
			}
			if p == "bedrock" {
				this_kind_correct = BEDROCK == !is_notted
				continue
			}

			os, subtarget, subtarget_str := os_from_string(p)
			arch := arch_from_string(p)
			num_tokens += 1
			if num_tokens > 2 ||
			   (this_kind_os_seen && os != .Invalid) ||
			   (this_kind_arch_seen && arch != .Invalid) {
				break
			}
			is_ios_subtarget := false
			if subtarget == .Invalid {
				if !equal_ignore_case(subtarget_str, "ios") {
					break
				}
				is_ios_subtarget = true
			}

			if os != .Invalid {
				this_kind_os_seen = true
				is_explicit_default_subtarget := equal_ignore_case(subtarget_str, "default")
				same_subtarget :=
					(subtarget == .Default && !is_explicit_default_subtarget) ||
					subtarget == SELECTED_SUBTARGET
				if is_ios_subtarget &&
				   (SELECTED_SUBTARGET == .Iphone || SELECTED_SUBTARGET == .Iphonesimulator) {
					same_subtarget = true
				}
				if is_notted {
					this_kind_correct = this_kind_correct && (os != info.os || !same_subtarget)
				} else {
					this_kind_correct = this_kind_correct && (os == info.os && same_subtarget)
				}
			} else if arch != .Invalid {
				this_kind_arch_seen = true
				if is_notted {
					this_kind_correct = this_kind_correct && arch != info.arch
				} else {
					this_kind_correct = this_kind_correct && arch == info.arch
				}
			}
			if os == .Invalid && arch == .Invalid {
				break
			}
			if len(s) == 0 {
				break
			}
		}
		any_correct = any_correct || this_kind_correct
	}
	return any_correct
}

// `parse_build_project_directory_tag` in parser.cpp:7323. `project` is set in
// build_settings.cpp:2301.
@(private = "file")
parse_build_project_directory_tag :: proc(tag, project: string) -> bool {
	s := trim_tag_space(tag[len("build-project-name"):])
	if len(s) == 0 {
		return true
	}
	any_correct := false
	for len(s) > 0 {
		this_kind_correct := true
		for {
			p: string
			p, s = tag_get_token(s, ":")
			p = trim_tag_space(p)
			if len(p) == 0 || p == "," {
				break
			}
			is_notted := false
			if p[0] == '!' {
				is_notted = true
				p = p[1:]
				if len(p) == 0 {
					break
				}
			}
			if is_notted {
				this_kind_correct = this_kind_correct && p != project
			} else {
				this_kind_correct = this_kind_correct && p == project
			}
			if len(s) == 0 {
				break
			}
		}
		any_correct = any_correct || this_kind_correct
	}
	return any_correct
}

// `build_require_space_after` in parser.cpp. Returns true on the compiler's syntax error.
build_require_space_after :: proc(s, prefix: string) -> bool {
	if len(s) == len(prefix) {
		return false
	}
	return s[len(prefix)] != ' ' && len(trim_tag_space(s[len(prefix):])) != 0
}

// `build_tag_get_token` and `vet_tag_get_token` in parser.cpp.
tag_get_token :: proc(text, token_bytes: string) -> (token, rest: string) {
	s := trim_tag_space(text)
	n := 0
	for n < len(s) {
		r, width := utf8.decode_rune(s[n:])
		if n == 0 && r == '!' {
		} else if !tokenizer.is_letter(r) &&
		   !tokenizer.is_digit(r) &&
		   !strings.contains_rune(token_bytes, r) {
			k := max(n, width, 1)
			return s[:k], s[k:]
		}
		n += width
	}
	return s, ""
}

// `get_target_os_from_string` in build_settings.cpp:954. The subtarget follows the first `:`.
@(private = "file")
os_from_string :: proc(
	str: string,
) -> (
	os: Target_Os,
	subtarget: Subtarget,
	subtarget_str: string,
) {
	os_name := str
	if i := strings.index_byte(str, ':'); i >= 0 {
		os_name, subtarget_str = str[:i], str[i + 1:]
	}
	for name, kind in TARGET_OS_NAMES {
		if equal_ignore_case(name, os_name) {
			os = kind
			break
		}
	}
	switch {
	case len(subtarget_str) == 0:
		subtarget = .Default
	case equal_ignore_case(subtarget_str, "generic"), equal_ignore_case(subtarget_str, "default"):
		subtarget = .Default
	case:
		subtarget = .Invalid
		for name, kind in SUBTARGET_NAMES {
			if kind != .Default && kind != .Invalid && equal_ignore_case(name, subtarget_str) {
				subtarget = kind
				break
			}
		}
	}
	return
}

// `get_target_arch_from_string` in build_settings.cpp:997.
@(private = "file")
arch_from_string :: proc(str: string) -> Target_Arch {
	for name, kind in TARGET_ARCH_NAMES {
		if equal_ignore_case(name, str) {
			return kind
		}
	}
	return .Invalid
}

// `str_eq_ignore_case` in string.cpp folds ASCII only.
@(private = "file")
equal_ignore_case :: proc(a, b: string) -> bool {
	if len(a) != len(b) {
		return false
	}
	for i in 0 ..< len(a) {
		x, y := a[i], b[i]
		if 'A' <= x && x <= 'Z' {
			x += 'a' - 'A'
		}
		if 'A' <= y && y <= 'Z' {
			y += 'a' - 'A'
		}
		if x != y {
			return false
		}
	}
	return true
}

// `string_trim_whitespace` in string.cpp, which trims only these four and trailing NULs.
trim_tag_space :: proc(text: string) -> string {
	s := strings.trim_right(text, " \t\n\r")
	s = strings.trim_right(s, "\x00")
	return strings.trim_left(s, " \t\n\r")
}
