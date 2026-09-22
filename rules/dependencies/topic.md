---
name: "dependencies",
summary: "Project-defined ordinary import boundaries, checked against the project source graph",
tags: ["dependencies", "imports", "globals", "foreign", "capabilities", "packages"],
aliases: ["package structure", "layering", "import rules", "modules", "what does this depend on"],
applies_to: { roles: ["pure", "service", "edge"] },
related: ["errors"],
example_roles: { "example/core": "pure", "example/platform": "edge" },
---

Assign project roles to package directories and configure their `may_import` and
`deny` entries in `odx.json5`. A direct ordinary import is permitted when its
target role or import path matches `may_import`, subject to `deny`. Import paths
match exactly, or by prefix when the entry ends in `*`. The built-in `base:*` and
`core:testing` allowances remain; test files additionally allow `core:log` and
`core:fmt`. Deny entries take precedence.

Import strings are decoded. Within unconfigured built-in collections, path dot
segments are normalized for matching too: `core:fmt/../os` matches `core:os`.
Configured collections take precedence over built-in names and resolve to
canonical project package paths. Escapes outside a built-in collection are
unavailable evidence.

Deny checks follow ordinary imports through included project packages, including
packages with no role. They inspect the selected package's own test imports but
exclude dependencies' `*_test.odin` files during transitive traversal. Platform,
build-tagged, generated, and inactive source remains in the source graph; this is
not a compiler-selected target graph.

Built-in `base:`, `core:`, and `vendor:` imports end traversal. Their import names
are checked, but their internal dependencies are outside the policy boundary.
Required excluded, missing, unknown-collection, or outside-project dependencies
produce unsupported evidence rather than a clean architecture result.

Selecting a file or package limits reported findings, not graph evidence.
Incremental and hook scans reconsider the full current project after relevant
source or policy changes, including deletion and rename. Empty change selections
do not establish project compliance.

Foreign imports and foreign blocks are separate constructs; this ordinary import
policy does not check them or establish absence of foreign access, side effects,
or mutable state. The `pure`, `service`, and `edge` names are optional project
roles, not language guarantees. Packages without applicable dependency policies
receive no dependency finding of their own, but remain traversable graph evidence.
