# odx

A strict, opinionated checker for Odin projects: format, naming and syntax rules on top of pinned compiler flags, then memory-checked tests and runs. Terms: [GLOSSARY.md](GLOSSARY.md); principles: [docs/adr/0004-principles.md](docs/adr/0004-principles.md).

## Workflow

1. `odx check` on any repo.
2. `odx init` pins the release and compiler and lists failing packages as `pending`. Commit `odx.json`.
3. During development: format with odinfmt, then fix what `odx check` reports; use `odx test` and `odx run`.
4. CI installs the pinned odx release and runs `odx check && odx test`.
5. Remove `pending` entries as packages are fixed; `odx check --pending` shows what's left.
6. Upgrade: bump `version` or `odin` in `odx.json` in one commit.

## Development

```sh
mise install
mise run build   # build/odx
mise run test
```
