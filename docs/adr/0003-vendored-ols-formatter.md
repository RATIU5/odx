# The `format` rule uses OLS's printer, vendored

odx checks format against OLS's odinfmt printer, vendored into odx at a pinned commit with a fixed config, rather than writing its own printer or calling the team's odinfmt. The team formats with odinfmt, so both must produce the same output, and CI results must not depend on which odinfmt a machine has installed. odx reports differences and never rewrites code, so there is no `odx fmt`.

Amended 2026-10-04: in the odx repo itself, `mise run fmt` prints with the vendored printer, so odx's self-check doesn't depend on the odinfmt a developer has installed. Teams that use odx still format with odinfmt at OLS commit `dd0f85d` and odx's fixed config, which `odinfmt.json` at the root of the odx repo holds for them to copy. odx still ships no format command.
