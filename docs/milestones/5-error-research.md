# Milestone 5 error-policy research

Research performed 2026-09-21 using `/opt/homebrew/bin/odin version dev-2026-09:a2fb372b7` and the existing `build/odx` binary. This is a research record; the final milestone decision record owns implementation and acceptance status.

## Observed contract and failures

`odx/docfmt.odin:last_result_error` classifies only a **named final result**, first by configured type-name suffix, then by enum `None`/`Ok` or a union admitting nil. `errors.types` is a suffix list, not exact semantic identities; an empty list does not disable structural inference. Compiler-selected exported procedure entities are checked, excluding test procedures. The compiler determines visibility, not uppercase spelling. Only one underlying named type layer is structurally examined.

The built-in R3 statement obscures suffix matching and structural intent; its rationale/evidence incorrectly says the attribute rejects `x, _ := f()`. The errors topic also promises that failures cannot be dropped and promotes blanket anti-bool, exactly-one-domain, and stylistic propagation rules without a machine contract.

Actual compiler-backed `odx check --ci --json --topic errors` probes, with `odin.flags: []`, reported complete evidence:

| Valid source | `errors.types: []` | `errors.types: ["Error"]` |
| --- | --- | --- |
| Predicate returning plain `bool` | Silent | Silent |
| Map lookup returning `(int, bool)` | Silent | Silent |
| `Error :: enum {None, Bad}` | Finding | Finding |
| `Alias :: Error`, final result `Alias` | Finding reporting canonical `Error` | Same |
| `Distinct :: distinct Error` | Finding reporting `Distinct` | Same |
| `Status :: enum {Ok, Pending}` | Finding | Finding |
| `Maybe :: union {int, string}` | Finding | Finding |
| `Nonoptional :: union #no_nil {int, string}` | Silent | Silent |
| `Read_Error` and `Write_Error`, each enum `{Done, Bad}` | Both silent | Both findings |
| `@(private)` / `@(private="file")` error procedures | Silent | Silent |
| File-wide `#+private` error procedure | Silent | Silent |
| `@(require_results)` error procedure | Silent | Silent |

Additional counterexamples: `Status :: enum {Ready, Busy}; AliasError :: Status` returns canonical `Status`, so the alias spelling does not activate the Error suffix. `Issue :: distinct int` is valid and silent without a matching suffix. An anonymous final `union {int,string}` is valid and silent even though nil-able: this implementation requires a named result. `@(require_results=false)` is invalid Odin, so mere attribute presence does not hide that particular case; compiler checking fails.

## Exact compiler guarantee

Independent `odin check <case>.odin -file -no-entry-point -vet -vet-cast` probes used attributed `f :: proc() -> Error` and `g :: proc() -> (int, Error)`:

| Caller body | Compiler result |
| --- | --- |
| `f()` | Rejected: results must be handled |
| `defer f()` | Rejected: results must be handled |
| `_ = f()` | Accepted |
| `_, _ = g()` | Accepted |
| `x, _ := g(); _ = x` | Accepted |
| `e := f(); _ = e` | Accepted |

The attribute requires acknowledgement of results; explicit discard and retaining without inspecting an error remain valid. R3 establishes declaration attribute presence, not correct error handling, logging, propagation, or successful recovery. Neither compiler acceptance nor odx silence establishes those behaviors.

The [official attribute documentation](https://odin-lang.org/docs/overview/#require_results) explicitly permits storing results or discarding through `_`. The current [compiler statement checker](https://raw.githubusercontent.com/odin-lang/Odin/master/src/check_stmt.cpp) consults the procedure type flag in call-expression statements; it also handles the flag in iterator result arity checks. The [official package visibility documentation](https://odin-lang.org/docs/overview/#exported-names) identifies package declarations as public by default, with private attributes controlling exports. These sources explain the bounded declaration policy; they do not establish error intent from type shape.

## Recommended choice and alternatives

1. Preserve existing matching by default and add `errors.structural: false` to disable shape inference. Keep `types` as explicitly documented **canonical named-result suffixes**, including aliases resolving to their underlying name and distinct types retaining their own name. With both structural false and empty types, nothing is classified; disabling R3 also remains available. This is the smallest compatible correction and lets a project opt out of optional/status false positives. Default true must be documented as compatibility behavior and a project heuristic, not semantic error discovery.
2. Replace inference with exact package-qualified type identities. This makes explicit intent stronger and reduces coincidental name matches, but adds configuration, compiler-identity matching, alias rules, migration costs, and substantially more tests. Revisit when a real project needs disambiguation that suffix-only selection cannot provide.
3. Retain structural inference only with suppression escape hatches. Smallest implementation, but makes projects suppress repeated legitimate optional/status declarations and does not satisfy a useful project-wide opt-out. Reject.

Rewrite reader guidance as contextual questions: are bools predicates/lookup presence or do callers need detailed failure information; are domain types suitable for caller decisions (several domains per package are valid); is handling or propagation clear (explicit branches and `or_return` are both legitimate)? Remove universal exact-one-error and propagation-style expectations. Examples should visibly demonstrate valid counterexamples and keep review advice separate from enforced outcomes.

## Implementation acceptance to retain

Add externally exercised enabled/disabled structural cases, empty suffixes, suffix-only coincidental names, canonical aliases versus distinct names, named versus anonymous unions, nil versus no-nil unions, private attributes/file tags, several legitimate domains, and final-result-only scope. Include explicit-discard compiler acceptance as an adversarial example against the old overclaim. Verify configuration validation, effective-config/guidance fingerprint inclusion, generated wording, and executable examples. Unsupported or failed compiler export must retain existing non-clean coverage behavior. This research has not validated foreign-block attribute inheritance, generic procedure specialization, or all compiler flag combinations; avoid broadening the claim to them.
