
## odx

- Before writing Odin code run `odx for <path>` and `odx explain <topic>`; `odx check` must pass before you stop.
- Never edit rules/, .odx/, odx.json5, mise.toml, tests/fixtures/ or .claude/settings.json without asking.
  They are hash-locked; `odx doctor --verify-rulebook` names any change and a human approves it with `ODX_ALLOW_PROTECTED=1 odx doctor --relock`.
- Reviewing a diff: `odx explain --checklist` lists the rules only a reader can check.
