# Body Swap Royale

A Roblox party-elimination game built around forced body-swaps. Players are
periodically reshuffled into each other's avatars on a shrinking Hex-A-Gone
arena — the last surviving body wins the round.

- **Design intent:** [`docs/body-swap-royale-gdd.md`](docs/body-swap-royale-gdd.md)
- **Architecture / networking / perf:** [`docs/body-swap-royale-tdd.md`](docs/body-swap-royale-tdd.md)
- **Per-feature specs & plans:** [`docs/superpowers/`](docs/superpowers/)
- **Changelog:** [`CHANGELOG.md`](CHANGELOG.md)

## Quickstart

You need [Rokit](https://github.com/rojo-rbx/rokit), Roblox Studio, and the
Rojo Studio plugin. Full instructions, including troubleshooting, live in
[`docs/dev-environment/getting-started.md`](docs/dev-environment/getting-started.md).

```bash
git clone <repo-url> && cd body-swap-royale
rokit install                                # pulls rojo 7.6.1 + lune 0.10.4
export PATH="$HOME/.rokit/bin:$PATH"         # persist in your shell rc
rojo plugin install                          # once per machine
rojo build -o body-swap-royale.rbxlx         # generate the place
rojo serve                                   # then Connect from the Rojo plugin in Studio
```

## Tests

Pure-Luau logic (hex math, round state, telegraphs, etc.) is covered by Lune
specs under `tests/`. Run them all:

```bash
bash scripts/test.sh
```

Filter by substring:

```bash
bash scripts/test.sh hex     # only specs matching "hex"
```

Runtime behavior that touches Roblox APIs lives in manual procedures under
[`docs/smoke-tests/`](docs/smoke-tests/).

## Project layout

```
src/{client,server,shared}    Luau source — Rojo-mapped per default.project.json
tests/                        Lune spec files for shared/pure modules
docs/                         GDD, TDD, dev-environment, smoke tests, feature specs/plans
scripts/test.sh               Lune spec runner
rokit.toml                    Pinned tool versions
```

## Claude Code

This project uses Claude Code with the Roblox Studio MCP for some workflows.
See [`docs/dev-environment/mcp-configuration.md`](docs/dev-environment/mcp-configuration.md)
for setup.
