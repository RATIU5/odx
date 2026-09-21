---
name: "dependencies",
summary: "What each package reaches (OS, network, threads, foreign) is reported from the compiler's import graph; roles are an optional preset that turns a reach into a rule",
tags: ["dependencies", "imports", "globals", "foreign", "capabilities", "packages"],
aliases: ["package structure", "layering", "import rules", "modules", "what does this depend on"],
example_questions: ["which package should this code go in", "does this package reach the OS", "where do foreign bindings live"],
applies_to: { roles: ["pure", "service", "edge"] },
related: ["errors"],
example_roles: { "example/core": "pure", "example/platform": "edge" },
---

Know what you depend on. `odx doctor` and `odx for` report, for every package and with no
configuration, whether it transitively reaches the OS (`core:os`), the network (`core:net`),
threads (`core:thread`, `core:sync`) or a `foreign` block, and through which import. That is the
compiler's own import graph (`-show-import-graph`), not a taxonomy: "it is a very good idea that
you know what you are depending on in your project."

Turning a reach into a rule is opt-in. The preset is three roles assigned per package directory
in `odx.json5`:

| role    | may import                          | may hold           |
| ------- | ----------------------------------- | ------------------ |
| pure    | pure, `core:*` (no os/net/thread)   | constants only     |
| service | pure, service, `core:*`             | state via params   |
| edge    | anything, `vendor:*`, `foreign`     | process-wide state |

A package with no role gets the report and no rule. A package is never annotated in source.
