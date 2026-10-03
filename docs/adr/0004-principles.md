# Principles, in order

When two goals conflict, the earlier principle wins. They come from the author's own standard for production Odin that has to last years; Ginger Bill's opinions are adopted only where the author agrees with them.

1. **One opinion.** No rule settings, no severities, no plugins.
2. **One way to write each thing.** Where Odin allows two forms, odx picks one.
3. **Every exception is visible.** An ignore or `pending` entry carries a reason and sits in the repo.
4. **Reproducible.** A result depends only on the code, `odx.json` and the odx release.
5. **Fix, don't accept.** Code that breaks the standard never passes. `pending` schedules a fix; it never accepts the code, and it only shrinks.
6. **Findings state what and where.** No hints, no fixes, and odx never changes user code.
7. **Odin compiler only.** No other toolchain; no patches to user code, the compiler or the runtime.
8. **Stop only when untrustworthy.** Exit 2 means no result; everything else runs.
