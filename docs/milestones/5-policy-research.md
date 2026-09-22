# Milestone 5: policy wording and declaration research

Research only, 2026-09-21. Implementation and final acceptance belong in the
milestone decision record. The supported compiler reports
`dev-2026-09-nightly:a2fb372` at
`/Users/ratiu5/.local/share/mise/installs/odin/dev-2026-09/odin`.

## Observed declaration gap

`odx/pattern.odin` iterates `f.decls` directly for `decl` and `foreign`.
`dependencies/R3` promises no mutable package-level variables, but package
`when` bodies and foreign-block variables evade it. Coverage currently admits
the narrower direct-file-level boundary; that does not repair the rule prose.

A temporary package at `/tmp/odx-m5-policy-research/sample/probe.odin` compiled
successfully with the supported compiler and `-no-entry-point`:

```odin
package sample
constant :: 42
direct: int
first, second: int
@(thread_local)
threaded: int
when true {
    conditional: int
    foreign import libc "system:c"
    foreign libc {
        getchar :: proc() -> i32 ---
        external: i32
    }
} else {
    inactive: int
}
outer :: proc() {
    local: int
    inner :: proc() {nested: int; _ = nested}
    _ = local
}
```

The existing `build/odx rule try` produced **3 matches** for
`{kind:"pattern",match:"decl",at:"package_scope",mutable:true}` and **0**
for `{kind:"pattern",match:"foreign"}`. Three means one per declaration,
including the grouped declaration, not one per variable. This binary was an
existing baseline; source inspection independently establishes why the misses
occur. Compilation is evidence of syntax/type validity, not runtime linkage or
effect behavior.

The installed native AST gives `When_Stmt.body/else_stmt`,
`Block_Stmt.stmts`, and `Foreign_Block_Decl.body`; the
[official AST documentation](https://pkg.odin-lang.org/core/odin/ast/) also
exposes these constructs. No new parser or semantic inference is needed.

Two credible choices are (1) narrow R3 to direct declarations and document the
easy conditional evasion, or (2) traverse only package declaration containers.
Recommend (2): recurse through when arms, blocks, and foreign blocks; stop at
value declarations, especially procedure values. A generic full AST walk
without scope tracking would incorrectly report locals and nested procedures.
Inactive arms remain included under the established source-policy contract.
If changing public selectors, align trial/permanent checks and update coverage.
Expect six mutable declaration findings in this example after expansion,
including `inactive`, but none for the constant or procedure-local declarations.
Foreign syntax should yield two findings. Grouped variables should retain one
finding for compatibility unless intentionally changed.

`dependencies/R4` is retired. Do not resurrect mandatory foreign placement:
keep `foreign` available for project-authored syntax restrictions. An ordinary
`core:c/libc` import and indirect foreign use remain outside that selector.
R2's current rule and topic prose accurately distinguish its ordinary source
graph from foreign restrictions and runtime effects; retain that boundary.

## Active policy and generated wording inventory

There are four active builtin rules: allocators/R1, dependencies/R2,
dependencies/R3, errors/R3. The other rule files are retirement records.

- R3's rationale quotes a preference as authority and suggests deterministic
  behavior from removing globals. Replace it with a project choice that makes
  mutable declarations visible and passes state explicitly. Say this establishes
  neither purity nor absence of side effects. A constant pointer/value, calls,
  implicit context, and imported state require separate reasoning.
- `INIT_CONFIG` in `odx/commands.odin` and repository `odx.json5` still say
  every package must have a role and `pure` means no OS/foreign/I/O. These
  contradict optional roles and the actual graph/default allow policies.
  Revise comments to describe optional project roles and chosen policies.
- Allocators/R1's rationale grants scratch/context-setting exemptions absent
  from its tag check. Its topic summary promises allocator signatures and
  allocation lifetimes. The topic references nonexistent R2 and describes
  intended lifetime as outside *any* static checker's reach. Narrow to odx's
  actual evidence, and mark signature/ownership choices as review advice.
- Errors/R3 describes structural error inference as semantic identity and its
  rationale implies the attribute prevents discarded failures. Its topic
  summary says "never discard a failure", conflating compiler result-use
  restrictions with actual handling. Reader prose rejects booleans broadly,
  claims callers cannot branch on them, and mandates one Error per package.
  Revise around deliberate error-domain conventions, legitimate predicates and
  lookup flags, multiple domains, and explicit discard boundaries. The separate
  allocator/error investigations supply compiler proofs for these changes.
- Dependency exemplars describe their particular pure function and edge package;
  clarify that their roles do not confer these properties universally.
- Review README active-rule table and boundaries after matcher/error decisions.

`claude_md` renders topic summaries, active statements, rationales, corrections,
selector scope/evidence, and reader checks. Fix source policy text, then rebuild
embedded rules and explicitly regenerate `CLAUDE.md`. Guidance snapshots include
config/topics but not executable interpreter semantics; increment
`GUIDANCE_REVISION` for matcher/classification changes as its comment requires.
Freshness checks synchronize policy; they cannot prove its prose.

## Acceptance gaps and maintenance

Add counterexample-driven assertions for direct/grouped/thread-local state,
both when arms including else-when, foreign variables, constants, procedure
locals, and nested procedures. Verify all findings retain source locations and
role applicability. Compile the foreign/when fixture with the pinned compiler.
Exercise custom foreign selection separately from active R2 to show that no
foreign prohibition leaks into ordinary import policy. Include `core:c/libc`
as a documented syntax boundary rather than claiming transitive foreign freedom.

Re-run rule/topic examples, generated guidance freshness, selector contracts,
and existing architecture probes after implementation. Expanded traversal is
linear in package declarations; no cache or new parser is justified. It may
produce additional findings in previously missed branches, an intentional bug
fix requiring a compatibility note. Revisit only if a real project needs
compiler-selected rather than all-source declaration policy, or resolved
behavior/foreign effects rather than syntax restrictions.

## Implementation acceptance

Implemented the package-container traversal in `pattern.odin` and applied it
consistently to declaration, foreign, procedure, and import syntax selectors.
Procedure `exported:true` remains a syntactic filter on the declaration's own
`@(private)` attribute; inherited privacy is explicitly outside its coverage.
Foreign procedure declarations now count in declaration/procedure selectors;
milestone 3 probe expectations were updated for that compatibility change.

The expanded unit fixture adds an else-when arm and direct/private procedures.
The supported compiler accepts the exact fixture with `-no-entry-point`.
An attempted ordinary import inside a when arm was rejected by the compiler
("Cannot use 'import' within a 'when' statement"); the final fixture uses an
ordinary top-level import. Foreign imports inside when arms remain valid.

Fresh strict compilation and all **34 unit tests** passed. A fresh binary's
trial reported seven mutable declarations at lines 4, 5, 7, 9, 13, 19, and 21,
and two foreign constructs. Permanent `dependencies/R3` reported exactly the
same subjects/locations for the pure role and zero for the edge role. Unit
tests separately establish constants and locals are excluded, grouped variables
produce one finding, direct/private/foreign procedure literals are selected as
documented, and ordinary import matching remains available. Full CI and guidance
regeneration are owned by the milestone integration pass.
