# Milestone 6 minimal-policy research

Research only, before implementation. Inspected milestone 0's minimal-library
contract, configuration, topic loading/applicability, guidance and rule examples.
Probes used the existing `build/odx` and Odin
`dev-2026-09-nightly:a2fb372` at the repository's pinned installation on macOS.
Scratch project: `/tmp/odx-m6-minimal-research`; no implementation changed.

## Demand and observed boundaries

Milestone 0 asks for exactly two project rules: no mutable package declarations
and no direct foreign declarations. Neither needs architecture roles. Existing
selectors already express these policies:

```json5
{kind:"pattern", match:"decl", at:"package_scope", mutable:true}
{kind:"pattern", match:"foreign"}
```

M5's recursive declaration traversal includes `when` branches and foreign
containers; it excludes procedure bodies. The declaration rule reports one
finding per declaration, including grouped variables. Constants, fields and
procedure-local variables are permitted. Foreign checking means direct syntax,
not the foreign implementation of an imported dependency. A private AST extension
or new built-in rule is not needed for these two requirements.

Observed current CLI behavior:

1. A no-role `{version:1}` project containing `Status :: enum {Ok, Bad}` and
   `Read :: proc() -> Status {return .Ok}` reports built-in `errors/R3`.
2. Adding `disabled:{"errors/R3":"Only two local syntax restrictions"}` removes
   that enforcement. Other current built-in mechanical rules are inapplicable
   without roles/dependency mappings. Generated Markdown then includes only the
   two local rules, with no allocator/error/dependency reviewer advice.
3. Even this configuration reports `odx/feature-optout` for a valid
   `#+feature using-stmt` directive without a reason, and `odx/vet-disable` for
   `#+vet !tabs`. These are unconditional checks in `check_vet_disables`, not
   loaded rules. Thus the requested two-policy experience remains impossible
   for otherwise permitted Odin source.
4. `rule test local/R1` passes the mutable fires block but rejects a silent block
   with the same ordinary `Status` procedure above as unexpected `errors/R3`.
   `run_block` constructs fresh configuration and copies only `base.rb`, ignoring
   project disabled rules, errors classification, compiler path and flags.
5. Guidance serializes inactive defaults (`explicit_allocators:"pure"`, structural
   error classification). This is not active rule/advice leakage, but the prose
   should clarify that configuration fields do not independently enable rules.

The supported compiler accepted the probe source containing both directives;
normal `check` completed compiler evidence and reported only the two unrelated
odx directive policies after disabling `errors/R3`.

## Alternatives and recommendation

- **Copyable local topics plus one explicit directive-audit opt-out.** Keep the
  existing roles/applicability system and disable `errors/R3`; add an Odin config
  switch such as `audit_file_tags:false` with default true. This is the smallest
  change that fulfills the demonstrated need while preserving existing checks.
  Coverage must call both checks not applicable when disabled; stale vet-disable
  allow-list diagnostics must not require a disabled audit to collect hits.
- **Explicit allow-list of built-in topics or preset selection.** Gives stronger
  independence from future added built-ins, but introduces selection, override,
  documentation and compatibility semantics. Current topic selection alone still
  leaves implicit directive checks active. Not justified for these examples.
- **Disable every current active built-in rule by ID.** More verbose, but makes
  later addition of role mappings less surprising. This remains tied to the
  current catalog and cannot stop future rules automatically. Viable, optional
  explicitness rather than new machinery.
- **Replace built-in topics with empty local overrides.** Existing override
  behavior allows it but requires multiple meaningless directories and knowledge
  of built-in names; weak authoring experience and no benefit over disabling.

Recommend a small no-role config disabling `errors/R3` and the directive audit.
Its README must state that it relies on the documented current built-in catalog
and should be reviewed on upgrade; changing roles changes applicability. Setting
`explicit_allocators:"off"` is useful clarity but not required mechanically.
No new AST capability or preset system is required for the minimal policy.
Compiler validity remains an explicit independent check; formatting stays with
odinfmt. The alternative-tool capability research is handled by the parallel
milestone research agent; no external-tool correctness claims are made here.

For project-owned rule tests, retain effective project configuration instead of
quietly restoring built-in policy. The scratch package still needs a deliberate
role assignment and synthetic import environment; avoid relocating relative
collection paths without preserving their meaning. Test this workflow with a
silent enum-return procedure and with a custom configured error suffix. Preserve
legacy built-in exemplar expectations through an explicit branch or equivalent
compatible scratch setup.

## Copyable fixture and acceptance plan

Use `examples/policies/minimal/odx.json5`, a project-owned
`.odx/topics/library/topic.md` and two `R*.odx.md` files. Put the passing library
in `parser/` and adversarial source under `cases/*.odin.txt`, excluded from normal
package discovery. Provide portable local guidance generated for this project;
keep toolchain paths out of committed config. Each rule has compiling fires and
silent blocks. A CLI acceptance program copies the policy to temporary roots and
replaces source with each case rather than checking deliberately failing source
inside the copyable project.

Required externally visible assertions:

- Passing parser library is clean with complete full-check coverage and no
  assigned role; an enum result and bool predicate acquire no error advice.
- Mutable package variables fail only library/R1, including inactive `when`
  declarations; constants, struct fields and local variables do not.
- Foreign imports and foreign blocks fail library/R2; strings/comments containing
  foreign-looking text do not. Include nested conditional foreign syntax.
- Imported code with foreign syntax stays outside the claimed direct package
  guarantee; check scoped reporting to prove that distinction.
- Both compiler-accepted directive opt-outs above remain permitted when auditing
  is disabled; audit defaults continue reporting them in a legacy config.
- Guidance contains exactly the intended rule statements, no built-in topic or
  reviewer-advice sections, accurate selector boundaries and unmapped scope.
- `guidance write/check` succeeds; policy edits make it stale.
- Both `rule test` commands pass under the same effective project settings,
  including a silent enum-return procedure that exposes the current bug.
- Full versus fast checks report compiler coverage honestly; omission of a
  compiler check never establishes language validity.

This is a synthetic usability proof, not external adoption evidence. Revisit
built-in selection only if maintaining explicit opt-outs becomes demonstrated
burden or added catalog defaults make independent policies fragile.
