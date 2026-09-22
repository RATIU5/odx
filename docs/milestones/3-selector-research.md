# Milestone 3 selector research

Research performed before implementation on 2026-09-21. The whole roadmap was
reviewed. Reference toolchain: `/Users/ratiu5/.local/share/mise/installs/odin/dev-2026-09`,
`dev-2026-09-nightly:a2fb372`. A fresh research binary was built with that compiler
using `odin build odx -out:/tmp/odx-m3-selector-binary -vet -strict-style`.

## Accepted fields and actual consumers before milestone 3

`CHECK_KEYS` currently accepts every field below for every kind. `validate_check`
checks a few mandatory values but never rejects fields belonging to another
kind/matcher. The following table records consumption, not proposed behavior.

| Kind / matcher | Fields actually consumed | Defaults and limits |
| --- | --- | --- |
| All kinds | `kind`, `roles`, `except_roles` | Empty inclusion means all roles, including unmapped packages. Exclusion wins. Explicit empty arrays behave like absent arrays. |
| `path_role` | No additional fields | Reports `role_count == 0`; role filters can prevent this from running on unmapped packages. |
| `banned_import` | No additional selector fields | Reads the package role's `dependencies` layer. `from` is accepted documentation only and has no effect even when misspelled. |
| `vet_tag` | No additional fields | Configuration `odin.explicit_allocators` determines off/pure/all scope. |
| `require_attribute` | `attribute` | `on` accepts absent, empty, or `exported_procs`, all with identical runtime behavior. Compiler package entries, non-test procedures, and last-result error classification restrict the check; this is not a generic check of every procedure. |
| `pattern/call` | `match`, `name`, `names` | `name` appends to `names`; their union uses exact spellings. Recursively visits calls; file import aliases canonicalize to the final import path component. No resolved callee identity or glob semantics. |
| `pattern/import` | `match`, `name` | Direct file-level ordinary imports only. Exact path or a trailing `*` prefix match. `names` is ignored. |
| `pattern/proc` | `match`, `exported`, `requires_param` | Direct file-level procedure literals only. `exported:false` means both private and nonprivate procedures. `requires_param` reports absence/mismatch rather than selecting matching parameters. `name` and `names` are ignored. |
| `pattern/decl` | `match`, `at`, `mutable` | `at` must equal `package_scope`. Direct file-level value declarations. `mutable:false` includes mutable and immutable declarations. `name` is ignored. |
| `pattern/foreign` | `match` | Direct file-level foreign import and foreign block declarations. All other matcher-specific fields are ignored. |

For a procedure requirement, `index` defaults to zero and counts each named
parameter separately (`a, b: T` counts twice). `type_suffix` matches the last
syntactic type identifier after peeling pointer types: `^pkg.MyCtx` can satisfy
`Ctx`; aliases, arrays, polymorphic types, and inferred default-parameter types
are not semantically resolved. An index beyond the signature is a violation.
Native `ast.Field.names` and `ast.Proc_Type.params` in the installed toolchain
support this existing implementation directly.

The README's phrase “name/names for calls and import globs” is broader than the
implementation: imports accept only singular `name`. Restrictions must be
documented with the selector, including false boolean meaning “do not narrow,”
not “select the opposite.”

## Reproduction

Temporary project `/tmp/odx-m3-selectors` used this configuration:

```json5
{version:1, roles:{edge:["**"]}, odin:{explicit_allocators:"off"}}
```

Package `p/p.odin`:

```odin
package p
Ctx :: struct {}
target :: proc(c: ^Ctx) {}
other :: proc(n: int) {}
```

The reference compiler accepted it with `odin check <package> -no-entry-point`.
Invocations used `odx rule try '<spec>' --root /tmp/odx-m3-selectors --count`.

| Spec difference | Observed pre-implementation result |
| --- | --- |
| `kind:pattern, match:proc, name:"target"` | 2 matches, proving the name filter is silently ignored. |
| `match:proc, mutable:true` | 2 matches; irrelevant field accepted. |
| `requires_param:{index:-1,type_suffix:"Ctx"}` | 2 matches; an impossible negative index turns every procedure into a violation. |
| `requires_param:{type_suffix:"Ctx",typo:123}` | 1 match; missing index defaults to zero and unknown nested field is ignored. |
| `requires_param:{index:null,type_suffix:"Ctx"}` | 1 match; null becomes zero. |
| `requires_param:{index:0.5,type_suffix:"Ctx"}` | Tool error from core JSON's typed decoder. |
| `requires_param:{index:999999999999999999999999999999999999,type_suffix:"Ctx"}` | Accepted; integer overflow is not rejected by the decoder. |
| `requires_param:null` | Tool error only because resulting empty `type_suffix` fails validation. |
| `match:proc, exported:null` | 2 matches; null becomes false. |
| `match:proc, exported:"true"` | Tool error from typed decoding. |
| `match:call, names:[""]` | Accepted with 0 matches; silently useless selector. |
| `match:call, names:null` | Tool error because resulting empty names fails the required-name check. |
| `match:proc, roles:[]` | 2 matches. |
| `match:proc, roles:[""]` | 0 matches in this assigned-role project; empty string can select unmapped roles elsewhere. |
| `match:proc, roles:["edge"], except_roles:["edge"]` | Accepted with 0 matches; exclusions take precedence. |
| `kind:banned_import, from:"unrelated"` | Accepted; no change in configuration source. |
| Repeated JSON key `name` | Already rejected as `Duplicate_Object_Key`. |

Typed decoding alone is insufficient. Installed `core/encoding/json/unmarshal.odin`
zeros destinations for JSON null and ignores numeric parse success before assigning
integers. Default `parse_string` represents decimal numbers as Float, so a finite
range/integrality check catches huge decimals. Hexadecimal numbers use Integer:
a separate Odin probe observed `json.parse_string("0x10000000000000000",
spec=.JSON5)` returning Integer zero with no error; the same index in a trial
was accepted as index zero (one match). `parser.odin` ignores `strconv.parse_i64`
success on that path. Strict hexadecimal overflow validation therefore needs
numeric token text (or an equivalent checked parser), not only the already-decoded
integer. Distinguish
that defect from ordinary wrong primitive types, which the typed decoder rejects.

## Alternatives and recommendation

1. Keep the small selector vocabulary and enforce a discriminator-specific
   allowlist, nested keys, primitive types, and meaningful nonempty values. This
   preserves all five public matchers, has bounded maintenance cost, and repairs
   the actual authoring error. Reject `proc.name` explicitly rather than inventing
   a new matching feature during this milestone. Keep missing parameter index as
   an explicitly documented zero default, reject null/negative/overflow indices,
   and retain out-of-signature indices as meaningful violations. Keep call
   `name`/`names` union, documenting it. Preserve absent/empty role arrays as all
   roles and preserve exclusion precedence; explicitly retain the existing empty
   string role entry as the unmapped-role sentinel.
2. Decode into separate typed unions per matcher. This expresses legal fields
   more clearly inside Odin, but JSON discriminator dispatch still needs custom
   loading and public validation. It is credible if the vocabulary grows; for
   the existing small implementation it adds migration work without fixing
   applicability by itself.
3. Replace selectors with general structural templates or scripts. This can
   express additional idioms, but does not address ignored fields cheaply and
   introduces syntax, trust, distribution, and evidence contracts. Neither
   roadmap design case currently requires this expansion.

The minimal library's mutable-state and direct-foreign rules fit existing
selectors with no role filters. The stricter application fits architecture
configuration and selected structural checks; ownership and error intent still
require bounded contracts or review. Adding arbitrary procedure-name matching
would not prove those missing semantics.

For legacy fields with fixed meaning, either reject them with migration guidance
or validate a finite compatibility alias: `from:"dependencies.may_import"` and
`on:"exported_procs"` can remain if documented as aliases for existing behavior.
Arbitrary values must not continue to be accepted. Retired rules and file-based
trials need the same selector validation when a selector is present; otherwise
retirement can conceal malformed configuration until reactivation.

## Required implementation evidence

Exercise each public matcher positively and with an irrelevant field, including
an explicitly false or empty irrelevant value. A blanket ban only on nonzero
decoded fields misses null/false/empty adversarial cases. Check nested unknown
keys and nonobject parameter requirements. Compare inline trials, file trials,
and permanent rules on equivalent package-role scope. Preserve public matcher
behavior and explicitly test all-versus-filter booleans, call-name union,
default index, out-of-signature index, and exception precedence. These are
selector-contract proofs; matching strings still does not prove resolved calls,
behavioral purity, or semantic parameter types.

This research does not claim post-change acceptance, instruction freshness, or
cross-platform compiler support. No runtime source was edited during research.
