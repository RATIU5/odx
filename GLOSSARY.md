# odx

One tool that solves two problems for Odin projects: strict, opinionated checking of code, and memory checking of code as it runs.

## Language

### Halves

**Checker**:
The half of odx that reads code without running it and enforces one standard for format, naming and syntax.
_Avoid_: linter, syntax checker, format checker, static analyzer

**Memory checker**:
The half of odx that runs code and reports memory and runtime faults, with enough site detail to act on them.
_Avoid_: debugger, sanitizer, runtime checker

### Results

**Finding**:
One reported violation: a place in the code, a rule, and a message saying what is wrong.
_Avoid_: warning, diagnostic, issue

**Rule**:
One named check with a permanent ID that produces findings.
_Avoid_: lint, check, inspection

**Ignore**:
An in-source comment that suppresses named rules for one statement or file, with a reason.
_Avoid_: suppression, waiver, exemption

**Error**:
A reason odx can't give a trustworthy result. Each has a permanent code, and any error means no result at all.
_Avoid_: failure, fatal finding

**Skipped**:
A package with no files for any target odx checks, so the compiler can't check it. odx's own rules still run on it. It is counted, never failed.
_Avoid_: excluded, ignored

**Held-back finding**:
A finding a pending package would have as strict. It is shown only on request and never changes the result.
_Avoid_: pending finding, hidden finding

### Package status

**Strict**:
The default status of a package: every checker rule applies, and any finding fails the run.
_Avoid_: enforced, checked

**Pending**:
A package listed as not yet strict, with a reason. It is debt scheduled for fixing, never accepted code. The list grows only in the commit that raises the rule set or the compiler pin.
_Avoid_: baseline, allowlist, legacy

**Vendored**:
A tree of third-party code in the repo that odx applies no rules to.
_Avoid_: external, third-party, dependency

**Pure package**:
A package with no global state that imports only other pure packages.
_Avoid_: stateless, library package

### Versions

**Rule set**:
The numbered set of rules in force for a project, pinned in its config. Any change to results ships under a higher rule set.
_Avoid_: config version, rules version

**Release**:
A version of the odx tool itself. It supports a range of rule sets and Odin compilers.
_Avoid_: version, build

### Formatting

**Formatter**:
The printer the team runs to lay out code; odx checks against the same printer.
_Avoid_: odx fmt, autofix

**Format**:
The layout the formatter produces under odx's fixed configuration; a file that differs has a `format` finding.
_Avoid_: style, prettify
