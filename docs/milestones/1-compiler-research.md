# Milestone 1 compiler evidence

Research used `/Users/ratiu5/.local/share/mise/installs/odin/dev-2026-09/odin`, reporting `dev-2026-09-nightly:a2fb372`, on macOS. The installed `core/odin/doc-format/doc_format.odin` is the primary format reference. Commands below used `-thread-count:1`; this avoids introducing the previously observed intermittent threaded crashes into the evidence. No claim is made about other compiler releases.

## Observed exports and limits

A scratch package imported a local dependency as `renamed`, declared `Alias :: renamed.Error`, an `@(require_results)` procedure returning that alias, `@(test)` procedures, a `when ODIN_OS == .Darwin` declaration, and two calls spelled `renamed.exit()` (one package call, one to a locally shadowing struct field). An Odin reader traversed the resulting format tables.

| Probe | Observed result |
| --- | --- |
| `odin doc <pkg> -doc-format -out:<file>.odin-doc` | Header version 0.3.2. Procedure attributes, type references, alias flag, declaration line/column/offset, and declaration initializers were exported. |
| Procedure initializer | Contains signature and `{...}`, not body syntax, call sites, or resolved callees. Both differently resolved `renamed.exit()` calls disappeared. |
| Imported alias | The target package's scope entries omitted the import name. The format has an `Import_Name` enum, but its existence does not establish a usable dependency graph export. |
| Host versus `-target:windows_amd64` | Host export contained `Darwin_Only`, excluded `only_windows.odin`; Windows export contained `Other_Only` and `Windows_File`. Both exports were read successfully. |
| `extra_test.odin` | Its ordinary declaration appeared in normal doc output. The `_test` suffix alone does not exclude a file from normal compiler checks. |
| `@(test)` | Procedure and its attribute appeared in normal doc output. This does not mean its test ran. odx currently explicitly excludes these procedures from its entity rule. |
| `odin check <pkg> -no-entry-point -show-import-graph` | Produced DOT edges containing absolute package paths, including renamed local dependency and transitive core dependencies. |
| `odin check ... -export-dependencies:json -export-dependencies-file:<file>` | Rejected both flags: supported by build/run/test, despite appearing in `check -help`. |

The installed compiler resolves calls internally, but the inspected doc interface does not export those resolutions. Native AST call spelling must remain explicitly syntactic. A compiler fork or another checked semantic interface would be additional machinery requiring its own investigation.

## Failure probes

The following ordinary procedure body was placed first in `broken.odin`, then in `broken_test.odin`:

```odin
package sample
broken :: proc() { nonexistent() }
```

Both `odin check <pkg> -no-entry-point -json-errors` and `odin doc <pkg> -doc-format -out:<fresh-output>.odin-doc` exited 1 for both filenames, reporting the undeclared identifier. No doc artifact was written. Doc therefore does check this body; it does not merely collect declarations.

A directory containing only `empty_windows.odin` on the macOS host produced exit 1 for both commands. The check JSON contained `error_count: 1`, an entry whose `type` was **warning**, and `pos: null`. Exit status must independently prevent reporting complete compiler evidence; counting only error-severity entries is insufficient.

After removing the bad body, check succeeded. Doc with output under a nonexistent directory failed with exit 1 and `Failed to write .odin-doc ...`. Thus successful check does not establish successful doc collection. No real compiler success-without-artifact case was observed; a fake compiler is appropriate to test that defensive boundary. Missing/unreadable output, incompatible format, unreported doc failure, and failed process startup must be explicit unavailable evidence, never a clean rule result.

## Format compatibility and bounds

The installed reader requires **exact** `Version_Type_Default == 0.3.2`. It does not document an additive-minor compatibility guarantee. odx's old newer-minor raw cast bypassed that deliberate check without evidence. Reject any mismatch and request a matching compiler/rebuild; broadening support requires fixture evidence for each version.

`read_from_bytes` only checks the base-header length, magic, declared total size against available bytes, and exact version. It then returns a cast pointer. It does not check full header size, array offsets/lengths, nested arrays, entity/type/file indices, or strings. `from_array` performs pointer arithmetic directly. A malformed file with the right base header can therefore pass the native reader.

The least expensive safe boundary is to validate the full header and every slice/index/string actually consumed by odx before dereferencing it, using overflow-safe range comparisons. Reusing the native reader alone is not sufficient. A complete independent decoder would be more expensive and unnecessary for the present narrow consumer, but validation must expand when consumption expands.

## Decision and remaining proof limits

Keep native parsing for source structure and compiler doc for the narrow checked attributes/types already used. Report source scanning and compiler-selected configuration as separate coverage. Do not infer whole-source semantic checks from a target-specific successful doc export. Keep source dependency checks explicitly source based until milestone 2 chooses and validates compiler graph handling.

Compared with replacing the existing mechanism with compiler-only checks, this preserves inactive-source structural policy and incomplete-source diagnostics. Compared with trusting the old permissive decoder and implicit skip behavior, explicit evidence status and strict format validation cost some bookkeeping but prevent false clean results and unsafe reads.

Host and Windows doc exports were probed, but cross-platform test execution, every target, all flags, older compiler compatibility, and stable semantic-call interfaces were not established. The compiler source entry point for this revision is available at [src/main.cpp](https://github.com/odin-lang/Odin/blob/a2fb372/src/main.cpp); local installed sources and executable observations take precedence over generic current documentation here.
