# The `format` rule uses OLS's printer, vendored

odx checks format against OLS's odinfmt printer, vendored into odx at a pinned commit with a fixed config, rather than writing its own printer or calling the team's odinfmt. The team formats with odinfmt, so both must produce the same output, and CI results must not depend on which odinfmt a machine has installed. odx reports differences and never rewrites code, so there is no `odx fmt`.
