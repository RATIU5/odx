# Milestone 2 incremental selection research

Research date: 2026-09-21. This records behavior before milestone 2 implementation. Probes used the existing `build/odx`, a temporary Git repository, and `/Users/ratiu5/.local/share/mise/installs/odin/dev-2026-09/odin`. No Python or external parser was used.

## Reproduced failures

The repository contained `importer/main.odin`, importing `../service`, and `service/main.odin` plus an otherwise empty `service/keep.odin`. Both packages had explicit-allocator tags. The importer had role `pure`, the dependency role `service`; pure could import service and core packages but retained its default deny list. The initial dependency had no imports. Git committed that state, then only the dependency gained `import "core:os"`.

| Invocation/event | Observed pre-milestone result |
| --- | --- |
| Full `check --fast` after dependency edit | Exit 1, `pure package reaches core:os via service` at the unchanged importer. |
| `check --fast --since HEAD` after dependency edit | Exit 0, service alone selected, no dependency finding. |
| Rename dependency source after committing the edit | Changed scan selected service alone and exited 0. |
| Delete dependency source while keeping its package directory | Changed scan discarded the deleted filename and emitted an empty report, exit 0. |
| Modify only `odx.json5` | Changed scan emitted an empty report, exit 0. |
| File hook for `odx.json5` | Silent, exit 0. |
| File hook for the deleted source | Exit 0 as promised; full fallback happened because canonicalization could not resolve the missing filename, and compiler error reported the now-missing exported symbol. This accidental path should become an explicit contract. |

The empty changed reports correctly say `coverage.complete: false` since milestone 1, but do not perform architecture analysis. Editing the dependency can therefore omit a real finding on its unchanged importer.

The initial variant deleted the entire dependency package. Project validation rejected its now-stale exact role glob before scanning, exit 2. Keeping a second source file isolates selection behavior from that separate validation failure.

The reproduction script and raw reports were retained for this research session under `/private/tmp/odx-m2-incremental-probe.sh` and `/private/tmp/odx-m2-incremental.PcWXHs`; these are disposable local artifacts, not test dependencies.

## Selection alternatives

1. **Full current project reporting on relevant changes.** Treat Git as a trigger, then scan all current project packages whenever source or policy changed. This includes unchanged dependents, handles deletions without loading historical ASTs, and needs no cache invalidation. It can cost more for compiler checks in large repositories.
2. **Current graph reverse dependency closure.** Select modified packages and their transitive importers. A complete current graph is still needed. Deleted/renamed package identities and removed edges need explicit fallback or historical graph evidence. Policy changes must expand scope separately. More machinery does not currently have performance evidence to justify it.
3. **Changed packages only with an explicit disclosure.** A permitted roadmap contract, but an edit to a dependency can still omit the unchanged importer's architecture violation. Least useful feedback and easy to misunderstand.

Recommend option 1 for `--since`, batch hooks, and relevant file hooks. Keep explicit CLI file/package arguments as selected reporting over complete graph evidence. This cleanly separates a user's explicit reporting request from incremental change-impact promises.

## Proposed exact contract

- `--since REF` compares REF with the current worktree, including staged, unstaged, and untracked relevant files. It analyzes current contents, not the historical commit.
- Any `.odin` addition, modification, deletion, or rename triggers full current project reporting. Both rename endpoints matter, including rename from Odin to another suffix and the inverse.
- Policy inputs include root `odx.json5`, `odx.baseline`, and project rule files under `.odx/topics`. Conservatively triggering on every path under the topic directory avoids missing topic deletion or metadata changes. Built-in rules are embedded into the binary, so editing their repository sources only changes checks after rebuilding.
- Relevant file hooks trigger a full current project scan even when the file no longer exists. Config/topic/baseline changes receive the same treatment. Hook output remains advisory and exit 0.
- With no relevant changes, return a valid empty selection and explicitly incomplete coverage; do not claim project cleanliness. Non-policy documentation edits need not trigger checks.
- Outside Git, a batch hook falls back to full scanning. Explicit `--since` must report a tool error if Git is unavailable, REF is invalid, or discovery fails. Distinguish this from a successful empty diff.
- Full reporting caused by an incremental trigger does not authorize baseline shrinking: retain the existing `o.since != ""` guard and hook fast mode guard.
- A Git worktree can contain a nested odx project. Request paths relative to the project root and filter outside-project paths, rather than incorrectly joining repository-relative paths onto the project root.
- Changes in externally located collections, environment settings, or compiler versions are not discovered by project Git. Full CI checks remain authoritative for the stated current source/toolchain scope.

Use NUL-delimited Git paths, not line splitting: legal source filenames can contain spaces, tabs, Unicode, and newlines, while default Git quoting can turn valid filenames into nonexisting paths. `git diff --no-renames --name-only -z REF -- .` treats rename as deletion plus addition; `git ls-files --others --exclude-standard -z -- .` covers untracked files. Use `--relative` for diff paths when operating below repository root. Deduplicate and sort paths for stable evidence.

## Performance and regression requirements

On the two-package fixture, 20 full native scans took 0.12 seconds wall time in one local run. Twenty empty `--since` scans took 0.45 seconds because each invokes Git twice. This is only a small-project observation, not a large-repository benchmark; it supplies no justification for persisted graph state. Compiler check costs should be measured separately when implementing full hook fallback.

Regression coverage should assert the actual unchanged-importer finding after a dependency-only edit, then test source deletion, rename both across packages and across suffixes, config-only changes, topic-only changes, baseline changes, untracked sources, empty changes, malformed/invalid Git refs, nested-project paths, and path names requiring NUL handling. Compare full and incremental architecture finding identities, not merely their exit codes. Verify hooks still exit 0 and explain compiler/parser failures, and ensure partial/incremental commands preserve baseline bytes.
