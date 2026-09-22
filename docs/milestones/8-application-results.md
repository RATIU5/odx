# Milestone 8: supplementary local application pilot

This pilot applies the fixed milestone 6 minimal and strict examples to the
local Plastella application at tracked commit
`78961ae1cce507b9673d98eba908c656eb92f4b3`. It is real application code beyond odx,
but a local evaluation, not evidence of independent external adoption. No
application source, assets, or native binaries are included in this repository.
The original checkout remained unchanged, including its existing untracked
`AUDIT.md`, which was excluded from the snapshot.

## Protocol and setup

The source checkout was inspected read-only for instructions, configuration, and
package layout. No applicable `AGENTS.md` or `CLAUDE.md` was found in its ancestry
or project. `ODIN_STYLE.md` describes project preferences and was reviewed; it
was not substituted for either fixed example policy. Tracked files from
`git archive HEAD`, including the vendored Clay binding/native artifacts and
resources, were extracted into two temporary directories. There were 41 Odin
files, 5 packages, 7,021 lines, and 189,713 source bytes in each copy.

Before the first scan, the following mapping was chosen as a deliberately strict
challenge to a GUI application, not a claim that it already has a pure domain:

| Role | Package paths |
| --- | --- |
| domain | `source/app`, descendants |
| adapters | `source/platform`, `vendor/clay`, descendants |
| app | `source/host`, `source/release`, descendants |

The minimal configuration and `.odx` tree were copied unchanged. The strict
configuration and `.odx` tree were copied with only the role path arrays changed
to the mapping above. Rule selectors, dependency allow/deny lists, error suffixes,
and compiler/tag settings were unchanged. Vendor source was included because the
fixed example excludes do not exclude it. No baseline or suppression was added,
and no application source was repaired to improve the result.

The preregistered [pilot budgets](8-pilot-research.md) apply: setup within 15
minutes per policy, fast median within 2 seconds and complete median within 10
seconds for fewer than 50 source files. Setup was finished by 04:53:57 UTC on
2026-09-22 after inspection and mapping; a recorded checkpoint at 04:53:09 preceded
snapshot creation. Initial inspection was not separately timed, so no precise
first-time authoring time is claimed. This reuse of existing rules took a few
minutes, but setup-budget compliance was not independently established and this
does not measure writing novel rules.
Minimal used 4 policy/config files and 62 nonblank lines; strict used 9 and 154.
One extraction attempt failed because the host Python lacks the newer tar
`filter` argument; the retry validated archive paths and succeeded. No failed
rule-authoring attempt occurred.

Both snapshots have source digest
`acef78b9ba9dfe0a51d185fb98268f260b6584fb4c157948de7f6749582003d3`, computed as SHA-256
over sorted relative Odin paths and bytes, with a NUL after each path and each
file's bytes. Temporary reports and measurement rows were retained locally during
the investigation; the private source is required to reproduce them.

## Compiler, outcomes, and latency

The application pins `dev-2026-07a`; this pilot used the freshly rebuilt odx and
the exact supported compiler
`/Users/ratiu5/.local/share/mise/installs/odin/dev-2026-09/odin` through `ODX_ODIN`.
All full checks completed native and required compiler evidence on this host.
No July-to-September incompatibility or missing native dependency was observed
by these checks. This is not a successful application build, link, test run, or
runtime test. None was performed. Effective compiler flags were
`-vet-packages:app,clay,main,platform`; the example's configured flag array was
empty.

For each configuration and scope, the command was:

```sh
ODX_ODIN=/Users/ratiu5/.local/share/mise/installs/odin/dev-2026-09/odin \
  build/odx check --root <temporary-policy-copy> --ci --json [--fast] [source/app]
```

Measurements were serialized with the other milestone pilot and parent builds.
Each row used one first-process measurement, one discarded warmup, then five
measured warm processes. “First” does not mean an OS cache flush. Times include
process startup and JSON capture; host filesystem caches were uncontrolled.

| Policy / scope | Mode | First seconds | Warm median | Warm maximum |
| --- | --- | --- | --- | --- |
| minimal / full | complete | 0.758 | 0.545 | 0.551 |
| minimal / app | complete | 0.177 | 0.175 | 0.178 |
| strict / full | complete | 0.686 | 0.700 | 0.725 |
| strict / app | complete | 0.329 | 0.329 | 0.341 |
| minimal / full | fast | 0.036 | 0.033 | 0.034 |
| minimal / app | fast | 0.030 | 0.030 | 0.030 |
| strict / full | fast | 0.041 | 0.041 | 0.041 |
| strict / app | fast | 0.039 | 0.039 | 0.039 |

The discarded warmup and all five measured warm samples, in seconds, are
preserved here so the aggregate result does not depend on retained private JSON:

| Policy / scope / mode | Warmup | Five measured warm processes |
| --- | --- | --- |
| minimal / full / complete | 0.549796 | 0.533090, 0.537760, 0.544652, 0.551113, 0.544662 |
| minimal / app / complete | 0.175671 | 0.174536, 0.171392, 0.174923, 0.177586, 0.172406 |
| strict / full / complete | 0.696857 | 0.697456, 0.724753, 0.707471, 0.699721, 0.693370 |
| strict / app / complete | 0.326911 | 0.327483, 0.322340, 0.331554, 0.328870, 0.340500 |
| minimal / full / fast | 0.035856 | 0.034061, 0.033758, 0.033257, 0.032500, 0.032475 |
| minimal / app / fast | 0.029862 | 0.029704, 0.029643, 0.029723, 0.029695, 0.029505 |
| strict / full / fast | 0.040294 | 0.040212, 0.040637, 0.040663, 0.041339, 0.040579 |
| strict / app / fast | 0.038847 | 0.038467, 0.038756, 0.038689, 0.038507, 0.038829 |

All runtime budgets passed on this sample. All seven JSON outputs within each
row were byte-identical. Every invocation exited 1 for policy findings, with no
tool errors. Complete runs reported `coverage.complete: true`; fast runs
correctly reported incomplete coverage. Full and scoped finding tuples for
`source/app` agreed exactly for each policy. Scoped reporting covered 32 files
while full reporting covered 41.

| Policy | Full findings | App-scoped findings |
| --- | --- | --- |
| minimal | 15 `library/R1`, 7 `library/R2` | 13 `library/R1` |
| strict | 32 `allocators/R1`, 39 `dependencies/R2`, 13 `dependencies/R3` | Same 84 findings |

## Manual review and actionable costs

All 22 minimal findings were reviewed against their declaration and surrounding
source. The 15 variable findings occur at:

- `source/app/app.odin:43`; `assets_fonts.odin:31,40`;
  `assets_textures.odin:20`; `editor_statusbar.odin:10`;
  `gfx_clay.odin:39,44`; `ui_button.odin:29`; `ui_image.odin:31`;
  `ui_segmented_control.odin:31`; `ui_text_input.odin:76,628`;
  `ui_tooltip.odin:22` (all latter files in `source/app`).
- `source/platform/cursor.odin:16` and `window_darwin.odin:54`.

Ten of these fifteen declarations have `@(rodata)`. They still match the declared
AST `mutable: true` selector, but this is substantial policy-fit friction for
read-only lookup/style tables. It is misleading to turn this into a claim that
all fifteen represent mutable runtime state. The diagnostic's “mutable
package-level variable” wording and the repair to move it into caller-owned
state are less actionable for these tables. The metadata correctly discloses
syntax-only evidence; that does not eliminate the practical wording cost.

All seven foreign findings are in `vendor/clay/clay.odin`: conditional foreign
imports at lines 6, 8, 11, 13, and 16, and separate foreign blocks at 481 and 521.
These are correct all-source matches, including inactive platform alternatives.
They are expected for a GUI library dependency, so a useful adoption decision
would narrow source ownership or use explicit exceptions. No such policy change
was made for this fixed comparison. Pre-fix diagnostics contained a blank role
in “foreign import in a  package”; source location, repair, and evidence metadata
were present, but the message had a readability defect reported for correction.

For strict, only the first 30 findings in stable report order received the
prespecified detailed review; no all-84 false-positive claim is made. That sample
contained 11 missing allocator tags, 14 dependency findings, and 5 variable
findings. In report order, the reviewed locations were:

| App source file | Reviewed rule/location pairs |
| --- | --- |
| `app.odin` | allocator:1; dependency:3,6; variable:43 |
| `assets.odin` | allocator:1; dependency:3,5,6 |
| `assets_fonts.odin` | allocator:1; dependency:3,5,6; variable:31,40 |
| `assets_textures.odin` | allocator:1; dependency:3,5,6; variable:20 |
| `assets_ui_icons.odin` | allocator:1; dependency:4 |
| `config.odin` | allocator:1 |
| `editor.odin` | allocator:1; dependency:7 |
| `editor_project.odin` | allocator:1; dependency:7 |
| `editor_statusbar.odin` | allocator:1; variable:10 |
| `editor_toolbar.odin` | allocator:1 |
| `gfx.odin` | allocator:1 |

The eleven reviewed headers lack the required leading tag. The fourteen imports
either use unallowed SDL collection paths or reach Foundation through the
allowed platform adapter; that is precisely the fixed strict dependency contract.
Three of the five reviewed variables carry `rodata`, repeating the policy-fit
issue. No mismatch with the precise syntactic or graph contract was found in
these reviewed samples. That conclusion is narrower than a semantic
false-positive-rate estimate or a suitability judgment for this application.

Every finding had nonempty repair and boundary fields. Representative repairs
identify adding a header and satisfying compiler checks, removing a denied import
chain and passing capabilities, moving state to the caller, and moving foreign
bindings outside the library. Import reports identify the intermediate platform
package, making the otherwise indirect violation explainable. Actually adopting
those repairs in this GUI architecture would require design work: this pilot
did not estimate or perform that refactor. The 84-finding strict result is an
adoption burden, not a sign that the application is defective.

## Known misses, maintenance, and decision

The fixed strict error rule selects `Domain_Failure` and `Storage_Failure`
canonical suffixes. Its clean completed result does not establish that this
application's other failure APIs carry attributes or handle failures correctly.
The app-scoped foreign check is also clean, but its imported Clay binding uses
FFI. Built-in SDL packages are opaque graph leaves. These are deliberate policy
boundaries; transitive FFI freedom, runtime I/O freedom, allocation lifetime,
test execution, and all-target compilation were not established.

The sample directly demonstrates maintenance costs: choosing role boundaries,
deciding whether to include vendored bindings, distinguishing `rodata` syntax
from runtime mutation, and interpreting platform-inclusive source findings.
Copying fixed policies was cheap; making the strict example an appropriate
application policy is not shown to be cheap. No novel selector was authored,
and no code repair or future upgrade was measured.

This supports an experimental release with explicit source/evidence limits and
policy authoring guidance, alongside the separate public-project pilot. It does
not support universal recommendations to impose either policy, independent-user
adoption claims, runtime safety claims, or AI-productivity claims. Retain the
measured pre-fix timings; a targeted diagnostic recheck is sufficient for a
wording-only correction.

After the final binary was rebuilt with the roleless-foreign wording correction
and the separate alias-deduplication fix, one untimed full check per policy
confirmed the same exact file/line/column/rule/subject tuples: 22 minimal and 84
strict findings, exit 1, complete evidence, and no tool errors. All seven minimal
foreign messages now read simply “foreign import” or “foreign block,” removing
the blank role. The latency tables above remain the original pre-correction
measurements; this final targeted recheck was not a latency rerun.
