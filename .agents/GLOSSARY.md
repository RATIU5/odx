# odx

One tool that solves two problems for Odin projects: strict, opinionated checking of code, and memory checking of code as it runs.

## Language

### Halves

**Checker**:
The static half of odx (`odx check`, `odx init`). It reads code and never runs it.
_Avoid_: linter, syntax checker, format checker, static analyzer

**Memory checker**:
The dynamic half of odx (`odx test`, `odx run`). It runs code and reports memory and runtime faults, with enough site detail to act on them.
_Avoid_: debugger, sanitizer, runtime checker

### Results

**Finding**:
One reported violation: a place in the code, a rule, and a message saying what is wrong.
_Avoid_: error, warning, diagnostic, issue

**Rule**:
One named check with a permanent ID that produces findings.
_Avoid_: lint, check, inspection

**Ignore**:
An in-source comment that suppresses named rules for one statement or file, with a reason.
_Avoid_: suppression, waiver, exemption

### Package status

**Strict**:
The default status of a package: every checker rule applies, and any finding fails the run.
_Avoid_: enforced, checked

**Pending**:
A package listed in `odx.json` as not yet strict, with a reason. It is debt scheduled for fixing, never accepted code, and the list only shrinks.
_Avoid_: baseline, allowlist, legacy

**Vendored**:
A tree of third-party code in the repo that odx applies no rules to.
_Avoid_: external, third-party, dependency

**Pure package**:
A package with no global state that imports only other pure packages (planned).
_Avoid_: stateless, library package

### Formatting

**Formatter**:
odinfmt, run by the team. odx checks against the same printer but never changes user code.
_Avoid_: odx fmt, autofix

**Format**:
The layout the formatter produces under odx's fixed configuration; a file that differs has a `format` finding.
_Avoid_: style, prettify
