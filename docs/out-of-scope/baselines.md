# Baselines

odx has no baseline file or violation store that records existing findings as accepted.

## Why this is out of scope

Baselines drift, and a fixed violation can be swapped for a new one without anyone noticing. Unfinished packages go under `pending` instead, which grows only when the rule set or compiler pin is raised (principle 5, `docs/adr/0004-principles.md`).
