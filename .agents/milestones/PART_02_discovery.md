# Part 2: Package discovery

Status: tracked in the Parts table in README.md.

## Goal

Find every package in the repository, parse every file in it, and check that each package has a role or is external and that package names are unique. Parts 3–8 all run over this package list, so it has to be complete and match what the compiler would see as a package.

## Done when

- `odx check` walks the root, skipping excluded directories, and finds every package.
- Every file of every package is parsed with `core:odin/parser`, whatever its build tags.
- A package with no role and not listed as external is a `package-role` finding. Two packages with the same name are a `duplicate-package` finding for each.
- A role or `external` entry that doesn't name a package, or a package listed twice, exits 2.
- `mise run test` passes the golden cases below and Part 1's.

## Decisions

Proposed. The ones marked with a question number wait on the answers under Open questions.

### What a package is

- A package is a directory under the root holding at least one `.odin` file, after skipping:
  - files whose name starts with `.` (the compiler skips them);
  - whitespace-only files (`core:odin/parser` skips them, and they declare no package).
- Its path is relative to the root, uses `/`, and is `.` for the root itself. The same form is used in odx.json and in findings.
- Its name comes from the `package` line of its files. Files the host build tags leave out still count.
- A file whose name starts with `_` is still read. The compiler rejects it, and reporting that is Part 3's job.
- Directories are walked in full, except excluded ones, hidden ones (Q4) and symlinks (Q4).

### Roles and exclude

- A role or `external` entry names exactly one package directory. Whether it also covers the packages under it is Q1.
- `exclude` matches whole path components: `tests/golden` excludes `tests/golden` and `tests/golden/x`, not `tests/golden2`.
- An external package gets no odx rules, but it is still discovered and still counts for `duplicate-package` (Q5).

### Findings

One finding per package, with no line:

```
app/util: package-role: package "util" has no role
a/geom: duplicate-package: package "geom" is also at b/geom
b/geom: duplicate-package: package "geom" is also at a/geom
```

With three or more packages of the same name, each finding lists the others, comma-separated, sorted.

### Exit 2 (Q2)

A config entry that can't be applied means the run isn't fully checked, the same reasoning as Part 1's unknown key. Each is reported on stderr as `odx: odx.json: …`:

- `"<path>" is not a package` (missing, not a directory, or no `.odin` files)
- `"<path>" is listed more than once` (twice in one role, in two roles, or in a role and `external`)
- `"<path>" is excluded`

## Golden cases

- `p02-clean`: one package per role plus one external, all listed. Exit 0.
- `p02-root-package`: an `.odin` file in the root, listed as `"."`. Exit 0.
- `p02-no-role`: one unlisted package. `package-role` finding, exit 1.
- `p02-nested-no-role`: `app` listed, `app/sub` not. Finding for `app/sub`, if Q1 is "exact".
- `p02-duplicate-package`: `a/geom` and `b/geom`, both `package geom`. Two findings, exit 1.
- `p02-duplicate-external`: the same, with one of them external (Q5).
- `p02-exclude`: an unlisted package under an excluded directory, and a near-miss `tests/golden2` that isn't excluded. One finding, for the near-miss.
- `p02-hidden`: an unlisted package in a `.hidden/` directory, and a `.x.odin` file with another package name in a listed package. Exit 0 (Q4).
- `p02-non-host-file`: a listed package with `b_windows.odin` and a `#+build ignore` file, same package name. Exit 0.
- `p02-mixed-names`: a package whose non-host file declares a different package name (Q6).
- `p02-syntax-error`: a file with a syntax error after its `package` line, and one with no `package` line (Q3).
- `p02-config-not-package`: a role entry naming a directory with no `.odin` files. Exit 2.
- `p02-config-missing-path`: a role entry naming a path that doesn't exist. Exit 2.
- `p02-config-listed-twice`: one package in `pure` and `service`. Exit 2.
- `p02-config-excluded`: a role entry under an excluded directory. Exit 2.
- `p02-json`: `p02-duplicate-package` with `--json`. Exit 1.

## Facts for this part (dev-2026-09-nightly:a2fb372, verified 2026-09-27)

- `odin check <dir>` doesn't descend into subdirectories: a syntax error in `rec/sub` doesn't fail `odin check rec` (probe, exit 0). So odx has to find packages itself.
- The compiler ignores files whose name starts with `.`: `.hidden.odin` with another package name passed `odin check` (probe). It rejects names starting with `_`: `Syntax Error: Files cannot start with '_'` (probe).
- Two host files in one directory with different package names: `Syntax Error: Different package name, expected 'b', got 'a'` (probe). This includes `_test.odin` files: `package t_test` next to `package t` fails the same way (probe).
- When the differing file is left out by build tags (`b_windows.odin`, `#+build windows` or `#+build ignore`), `odin check` passes on macOS (probe). Only odx sees these mismatches.
- Importing two packages with the same name into one program is a compiler error, `Duplicate declaration of 'package same'` (probe). Unimported duplicates pass, so repo-wide uniqueness is odx's job.
- `parser.parse_file` returns `true` on a syntax error after the `package` line and counts it in `file.syntax_error_count`. It returns `false` with an empty `pkg_name` when the `package` line is missing (probe). The default error handler prints to stderr, so odx sets `Parser.err` to collect errors (`core/odin/parser/parser.odin:76`).
- `parser.collect_package` skips whitespace-only files and gets its file list from a `*.odin` glob (`core/odin/parser/parse_files.odin:40`, `:19`). odx walks directories itself, because it needs `exclude`, the relative paths and all subdirectories.
- `os.read_directory_iterator` gives a `File_Info` whose `type` distinguishes `.Directory`, `.Regular` and `.Symlink` (`core/os/file.odin:36`, `core/os/dir.odin:198`).

## Open questions

1. **Nested packages**: does `"app"` in a role cover `app/sub`, or does every package need its own entry? Proposed: exact only. Roles are about import limits per package, and a parent entry would silently give new subpackages a role nobody chose.
2. **Bad config entries**: exit 2 as above, or findings under `package-role`? Proposed: exit 2, for the same reason as Part 1's unknown key.
3. **Syntax errors**: the compiler reports them for host files (Part 3), but odx's rules can't read a file that doesn't parse, including non-host files the compiler never sees. Options:
   - (a) exit 2: `odx: app/a.odin:3: syntax error: expected ';', got :`, proposed;
   - (b) a new rule name, e.g. `syntax`, as findings.

   Either way, a file with no `package` line can't join a package.
4. **Hidden directories and symlinks**: skip directories whose name starts with `.` (`.git`, `.agents`), and don't follow symlinked directories? Proposed: skip both. Hidden directories are the dot-file rule applied to directories. Following symlinks can loop, and can reach outside the root.
5. **Duplicates and externals**: do external packages count toward `duplicate-package`? Proposed: yes, since vet and style are scoped by package name whatever odx's roles say. And do names that clash with core packages (a user package named `fmt`) count? Proposed: no; SCOPE says "package names are unique", which reads as within the repository.
6. **Mixed package names in one directory**, visible only through non-host files: which rule, or exit 2? Proposed: a `package-role` finding on the directory, `package "a" has files declaring "b"`, since the directory can't be given one role.

## Out of scope

- Running `odin check` and reporting its errors, including `_` file names (Part 3).
- Ignores. A `package-role` or `duplicate-package` finding has no line, so how `// odx:ignore` reaches it is Part 4's question.
- Resolving imports and collections (Part 6), and the format of `error_types` (Part 7).
