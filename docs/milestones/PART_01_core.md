# Part 1: Core

Status: tracked in the Parts table in README.md.

## Goal

The frame every later part plugs into: the CLI, reading odx.json, the finding model, sorted text and `--json` output, and exit codes. No rules yet, so `odx check` on a valid config reports clean.

## Done when

- `odx check` finds `odx.json` in the current directory, validates it, and exits 0 with an empty report.
- A missing, unreadable or invalid odx.json exits 2. When it's missing, odx also prints a minimal example.
- Findings print one per line, sorted and deduplicated; `--json` prints the same report as JSON. Unit tests cover this with synthetic findings, since no rule emits any yet.
- Exit codes are 0, 1 or 2, and 2 wins over 1: a run that finds problems and also couldn't check something exits 2 and still prints its findings.
- `mise run test` runs the golden cases listed below.

## Decisions

These are the user-facing contract that every later part inherits, so they are settled here.

### CLI

- `odx check [--json]`. `run` and `test` come in Parts 9 and 10; until then they exit 2 as unknown commands.
- No command, an unknown command or an unknown flag: usage on stderr, exit 2. `odx help` and `--help`: usage on stdout, exit 0.
- The repository root is the current directory, and odx.json must be there. Walking up to find it can come later if it's missed.

### odx.json

```json
{
  "pure": ["core/geom"],
  "service": ["store"],
  "edge": ["app"],
  "external": ["third_party/stb"],
  "error_types": ["store.Error"],
  "exclude": ["tests/golden"],
  "compiler_flags": ["-vet", "-strict-style", "-vet-using-param", "-disallow-do", "-warnings-as-errors"]
}
```

- Packages are directories relative to the root, using `/`. Paths are unambiguous even when two packages share a name, which Part 2 has to report.
- `exclude` holds directory prefixes, not globs.
- Every key is optional; `compiler_flags` defaults to SCOPE's list when it's absent.
- Part 1 checks only that the file is JSON, that every key is known and appears once, and that the value types are right. Whether the paths exist and each package has exactly one role is Part 2's job; the format of `error_types` is Part 7's.

### Report

- stdout carries the findings, one per line: `path:line: rule: message`. Paths are relative to the root and use `/`. A finding that isn't tied to a line, such as a package without a role, prints as `path: rule: message`.
- Sorting is by path (bytewise), then line as a number (so 9 comes before 10), then rule, then message. Identical findings print once.
- stderr carries everything else: the reasons for an exit 2, each as `odx: <what happened>`, then a summary line: `findings: N  ignores: M`. Ignores stay 0 until Part 4.
- Messages state facts only, with no fixes or hints. This applies to exit-2 reasons too.
- The summary line prints whenever `check` ran in text mode, including when odx.json couldn't be read. Usage errors print usage only.
- odx.json must be a single JSON object. A missing file is `not found`; unparseable input is `not valid JSON`, with no position; a repeated key is `repeated key`, with no name.
- `--json` writes one object to stdout and nothing to stderr, with the same sort and the same exit code:
  `{"findings": [{"file", "line", "rule", "message"}], "errors": ["..."], "ignores": 0}`. A finding with no line has `"line": 0`.

### Rule names

Reserved now, since they appear in the output and in `odx:ignore`:

| Rule | Part |
|---|---|
| `compiler` | 3, for every finding from `odin check` |
| `package-role`, `duplicate-package` | 2 |
| `unused-ignore` | 4 |
| `explicit-allocators`, `mutable-state` | 5 |
| `import-boundary` | 6 |
| `require-results` | 7 |
| `dynamic-allocator` | 8 |

### Golden cases

- Layout: `tests/golden/<pNN>-<behavior>/`. Each case is a repository root holding the inputs and a file named `expected`. `.gitignore` needs `!tests/` and `!tests/**`.
- `expected` format:

  ```
  $ odx check
  exit 2
  stdout:
  stderr:
  odx: odx.json: unknown key "exlcude"
  findings: 0  ignores: 0
  ```

  The first line is the command, run from the case directory. The runner compares the whole file, and trailing newlines count.

- Part 1 cases:
  - `p01-config-missing`: exit 2, with the example printed.
  - `p01-config-invalid-json`: truncated JSON, exit 2.
  - `p01-config-unknown-key`: exit 2.
  - `p01-config-duplicate-key`: `"pure"` twice, exit 2.
  - `p01-config-wrong-type`: `"pure": "a"`, exit 2.
  - `p01-clean`: a valid config and no packages, exit 0.
  - `p01-clean-json`: the same with `--json`, exit 0.
  - `p01-unknown-command`: exit 2.

## Facts for this part (verified 2026-09-24, dev-2026-09, scratch program)

- `json.unmarshal_string(s, &cfg, .JSON)` silently ignores unknown keys. Catching typos means reading into `json.Value` and checking the keys.
- Even with `.JSON`, a trailing comma is accepted, and for a repeated key the last value wins. `json.parse_string(s, .JSON)` instead returns `.Duplicate_Object_Key` (`core/encoding/json/parser.odin:305`), so parsing into `json.Value` catches both unknown and repeated keys.
- A type mismatch returns `Unsupported_Type_Error` with the line and column. Truncated input returns `Invalid_Data`, with no position.
- `json.marshal` writes struct fields in declaration order, with no spaces. Empty and nil slices both marshal as `[]`.
- `json.parse_string` gives no position or key name for its errors: truncated or empty input is `.Unexpected_Token`, and `.Duplicate_Object_Key` doesn't say which key. It also accepts trailing garbage (`{"a":1} x`) and a top-level array (`[]`), so odx has to reject a non-object itself.

## Out of scope

- Package discovery and applying `exclude` (Part 2), the compiler pass (Part 3), and any rule.
- Validating path existence, role overlap or the format of `error_types` (Part 2 and Part 7).
- Looking for odx.json in parent directories.
