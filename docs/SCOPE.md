odx is a CI checker that enforces your project's own architecture rules on Odin code (which packages may import what, which APIs must force callers to check errors, where allocators must be explicit), because the compiler checks the language but not the decisions your project made.

Shorter tagline: Odin checks that it's valid Odin; odx checks that it follows your project's rules.

MVP: minimum essential features

1. Rules in the repository. One config file: odx.json.
2. Roles. Group packages by role (for example "pure", "service", "edge") and give each role its own rules.
3. A small set of built-in checks for things the compiler can't know:
   - import boundaries, followed through the whole dependency graph
   - no mutable global state in chosen roles
   - @(require_results) on procedures that return errors
   - the #+vet explicit-allocators tag
   - simple custom pattern rules
4. odx check, with one line per finding (file:line, rule, message, fix hint) and exit codes you can trust: 0 means clean and fully checked, 1 means findings, 2 means the check itself couldn't run.
5. --json so CI and other tools, agents included, can read the results.
6. Adoption on existing code: a baseline of accepted findings, and inline suppressions that must give a reason, so a legacy repository can turn rules on today and block only new violations.

Not now (non-goals)

- Autofix. Useful, but it comes after the checks are trusted.
- Generating agent instructions (the managed CLAUDE.md block). Agents consume the same check output as CI.
- Style and formatting rules. That's the job of odinfmt, -vet and -strict-style.
- Editor integration. That belongs to OLS, the Odin language server.
- Incremental or "changed files only" checks. Full checks first; add speed only when a real repository needs it.
- A large built-in rule catalogue. Every rule must answer "why can't the compiler do this?"
- Reviewer advice and checklists. If a rule can't be checked mechanically, it isn't a rule.
