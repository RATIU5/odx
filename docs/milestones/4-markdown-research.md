# Milestone 4 Markdown ownership research

Research performed before implementation on 2026-09-21 after reviewing the whole
roadmap. Reference compiler and library sources:
`/Users/ratiu5/.local/share/mise/installs/odin/dev-2026-09`,
`dev-2026-09-nightly:a2fb372`. No runtime implementation was changed in this work.

## Existing workflow and reproduced failure

`odx for --emit-claude-md [path]` prints Markdown to stdout. Without a path it
selects the union of rules applicable to discovered packages; with one path it
selects exactly one included package. Milestone 3 shares applicability with
runtime checking. Empty projects receive a conditional catalog notice.

`write_hooks` appends the generated section to root `CLAUDE.md` during
`odx init --hooks`. Its only ownership test is
`strings.contains(existing, "## odx")`. It has no freshness comparison, ignores
the instruction-file read error, and writes the whole file directly. The static
header says only to regenerate after changing `rules/`, overlooking local topics,
configuration, and package discovery. It embeds a project-edit approval rule
unrelated to mechanically enforced policy. Existing Markdown readers get text;
odx does not establish whether any particular agent read or followed it.

A fresh binary was built as `/tmp/odx-m4-markdown` with the reference compiler,
`-vet -strict-style`. A temporary project had one package with `value :: 1`, no
roles, `odin.explicit_allocators:"off"`, and this human-authored `CLAUDE.md`:

````markdown
# Human instructions
Keep these bytes.

```markdown
## odx examples do not identify an owned block
```

# Human tail
Keep this too.
````

`init --hooks` said the file already had an odx section and did not generate one.
This proves that heading substrings, including inside fenced examples, cannot
establish ownership. The existing global and package-scoped generation commands
produced byte-identical output for this one-package project (`cmp` exit 0): the
document does not preserve the requested generation scope. A later second package
could therefore require different instructions without telling a freshness
checker whether the old document was intentionally package-scoped. The neutral
spelling `--emit-markdown` is currently rejected.

The repository's current `CLAUDE.md` is an unmarked legacy generated section.
It must not be treated as evidence that arbitrary text after a `## odx` heading
is tool-owned.

## Recommended ownership and command contract

Use one exact, versioned, full-line HTML-comment marker pair around the generated
section, for example `<!-- odx:begin v1 -->` and `<!-- odx:end -->`. HTML comments
keep the surrounding content usable as ordinary Markdown without any agent API.
The tool owns the inclusive marker span only. Prefix and suffix are preserved
byte-for-byte, including their line endings, whitespace, and missing final
newline. Define the delimiter convention so insertion never repeatedly adds
blank lines. A second generation with equivalent inputs must be a no-op.

Separate operations: render to stdout, explicitly write/update a named Markdown
file, and non-mutating check of that file. A neutral command such as
`odx instructions print|write|check --file AGENTS.md [package]` is one credible
surface; equivalent flags on `for` would also work. Retain
`for --emit-claude-md` as a stdout compatibility alias. Do not imply different
policy enforcement for `AGENTS.md`, `CLAUDE.md`, or another Markdown filename.
Existing `init --hooks` can call the same writer for `CLAUDE.md`, keeping the
vendor hook separate from generic content generation.

Checking should return 0 when the owned block is current, 1 when missing or
stale, and 2 for malformed ownership, invalid policy, or I/O failure. Writing
must be opt-in and must not run during ordinary policy checks. Missing files
are distinguishable from unreadable files; never translate every read failure
into an empty file. A freshness command should not mutate baseline or source
files or invoke compiler checking merely to render policy.

Record selection identity in the generated block: global project versus the
canonical project-relative package path. File selection should canonicalize to
its package, so equivalent file/package paths produce equivalent output. A
freshness check should either derive selection from strictly parsed owned
metadata or require the same explicit selection and compare it. Never silently
compare a package block to global policy. Avoid timestamps, absolute workspace
paths, random IDs, filesystem iteration order, and executable install paths in
the canonical content.

## Ambiguity and adversarial cases

| Input | Safe behavior and reason |
| --- | --- |
| No markers, ordinary human content | Append one new owned block with a documented separator; preserve every existing byte. |
| One valid pair | Replace only that span; compare against the same canonical span for freshness. |
| Missing begin/end, end before begin, nested markers, two blocks | Tool error; no guessed range or mutation. |
| Unsupported marker version | Tool error with migration guidance, not an unowned-file append. |
| Marker substring inline or in ordinary prose | Must not create a replacement span. Exact reserved marker text in ambiguous contexts may fail closed. |
| Marker lines inside fenced examples | Avoid mistaking them for ownership. Either reject ambiguous reserved tokens without mutation, or explicitly parse fence context; document the reservation. |
| Rule or reader prose contains reserved marker text | Reject generation or escape the collision before writing; otherwise the tool can create a document it cannot subsequently validate. |
| Legacy `## odx` followed by human headings | Do not replace heading-to-EOF; no reliable historical end boundary exists. |
| Existing CRLF human text | Preserve human bytes; canonical owned block may use LF if specified. Test idempotence and clear stale behavior. |
| Symlink/nonregular destination | Define explicitly. Rejecting for writes is simpler than accidentally replacing a symlink or following it outside the intended document. |
| Read or rename failure | Exit 2 and retain the prior destination; no partial policy output should look current. |

Legacy migration has two credible options. An explicit human placement of markers
around the known generated section establishes ownership without guessing. An
explicit migration command can replace only a byte-exact recognizable legacy
span, but preserving stale output from previous versions requires maintaining
old renderers or matching brittle text. Prefer the marker-placement contract and
a clear diagnostic when a likely legacy section is found. Do not silently append
a second conflicting policy block to an identified legacy document. This is a
compatibility decision, not an extra approval requirement for already-authorized
repository implementation.

## Native Odin file-update evidence

Primary sources inspected in the installed toolchain:

- `core/os/file_util.odin:253`: `write_entire_file` opens with `O_TRUNC`, calls
  `write`, then closes; it is not an atomic replace abstraction.
- `core/os/temp_file.odin:17`: `create_temp_file(dir, pattern)` uses randomized
  names and exclusive creation and returns a file handle. Passing the target
  directory permits a same-filesystem replacement.
- `core/os/file.odin:208`: `os.name(f)` is valid only while the file handle lives;
  clone the temporary pathname before closing it if rename happens afterward.
- `core/os/file.odin` exposes `write`, `sync`, `close`, `fchmod`, and `rename`.
- `core/os/file_posix.odin:201` implements rename with POSIX `rename`.
- `core/os/file_windows.odin:608` uses `MoveFileExW` with
  `MOVEFILE_REPLACE_EXISTING`; Windows runtime behavior was not tested here.

Prefer computing the entire replacement in memory, writing a temporary file in
the destination directory, checking written byte count and close errors, then
renaming. Preserve existing permissions where supported, choose ordinary file
permissions for a new document, and clean the temporary file on failure. This
avoids truncating the user's file before a successful replacement. It does not
prove crash durability without stronger synchronization or resolve concurrent
editor races; disclose that limit rather than claiming transactional editing.

## Alternatives, cost, and acceptance evidence needed

On-demand output alone has no ownership complexity and remains useful, but cannot
meet the roadmap's stored-content freshness requirement. Full-file generation
is simple for a dedicated artifact, but cannot preserve mixed human content.
Automatic rewrite during `check` hides drift and creates surprising mutation.
Explicit marker-owned writes plus read-only comparison provide the required
behavior with a bounded parser and linear work in document size.

The existing sorted topic/rule/package discovery and shared applicability are a
useful base. Canonical generation should additionally represent relevant
configuration that is not rendered by today's generic rule statements, such as
dependency layers, error type conventions, excludes, compiler settings, and
enabled rules. Freshness must react to effective policy changes from local
overrides as well as built-ins. Changes irrelevant to output need not create
false staleness unless a deliberately broader source fingerprint is chosen.

Acceptance should include changed local statement/advice, disabled rules, role
mapping and default role, dependency policy, error conventions, added/removed
packages, empty projects, path-scoped blocks, and equivalent repeated runs.
Ownership tests must assert exact prefix/suffix bytes before and after writes,
including a human heading after the block, and unchanged files on malformed
markers or read failures. Test both `AGENTS.md` and `CLAUDE.md` through the same
engine. These establish deterministic rendering and safe ownership; they do not
establish an agent's obedience or the semantic truth of policy prose.
