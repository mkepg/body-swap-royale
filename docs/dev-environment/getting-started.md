# Getting Started — Cloning & Running Body Swap Royale

This guide takes a fresh clone to a running Studio session and a green test run.

## Prerequisites

| Tool | Purpose | Install |
|------|---------|---------|
| **Git** | Clone the repo | <https://git-scm.com/downloads> |
| **Roblox Studio** | Run the place | <https://create.roblox.com/> |
| **Rokit** | Toolchain manager (pins `rojo` + `lune` from `rokit.toml`) | <https://github.com/rojo-rbx/rokit#installation> |
| **Rojo Studio plugin** | Lets Studio sync from `rojo serve` | Install once via `rojo plugin install` (see below) |

Optional, for the Roblox Studio MCP workflow:

| Tool | Purpose |
|------|---------|
| An MCP-capable editor | Drives Studio over MCP — see [`mcp-configuration.md`](mcp-configuration.md) for the Roblox Studio MCP setup |

This project does **not** use Wally; all Luau lives in `src/` and has no
third-party dependencies, so there's no package install step.

## 1. Clone and install the toolchain

```bash
git clone https://github.com/<your-account>/body-swap-royale.git
cd body-swap-royale
rokit install                 # installs rojo 7.6.1 + lune 0.10.4 from rokit.toml
```

`rokit install` drops shims under `~/.rokit/bin`. Make sure that's on your
`PATH`:

```bash
export PATH="$HOME/.rokit/bin:$PATH"
```

(Add the line to your shell rc — `~/.bashrc`, `~/.zshrc`, etc. — so it persists.
On Windows the path is the same under Git Bash; Rokit also adds the equivalent
PowerShell env entry on install.)

Sanity check:

```bash
rojo --version    # Rojo 7.6.1
lune --version    # lune 0.10.4
```

## 2. Install the Rojo Studio plugin (once per machine)

```bash
rojo plugin install
```

This drops the Rojo plugin into Studio's plugins folder. You only do this once
per machine, regardless of how many Rojo projects you work on.

## 3. Build the place file

The `.rbxlx` is intentionally gitignored — every clone builds its own:

```bash
rojo build -o body-swap-royale.rbxlx
```

Open `body-swap-royale.rbxlx` in Roblox Studio.

## 4. Start syncing

In a terminal at the repo root:

```bash
rojo serve
```

In Studio, click the Rojo plugin toolbar button → **Connect**. Code changes
under `src/` will now stream into the open place. Save the place once after
the initial connect so Studio persists the synced tree.

## 5. Run the test suite (Lune)

All pure-Luau logic (hex math, round state, models) is tested under `tests/`
with [Lune](https://lune-org.github.io/docs). Anything that depends on Roblox
APIs is **not** lune-testable and lives in a smoke test under `docs/smoke-tests/`.

Run the whole suite:

```bash
bash scripts/test.sh
```

Run a subset by substring match:

```bash
bash scripts/test.sh hex          # hex_grid + hex_erosion + hex_prism
bash scripts/test.sh round        # round_state + round_screen_model
```

Or invoke lune directly on a single file:

```bash
lune run tests/hex_grid.spec.luau
```

A successful run prints per-spec output and ends with `N passed, 0 failed`.

## 6. Smoke-test runtime behavior in Studio

Some behavior (Studio-side hazards, server glue, replication) can't be lune-tested.
Each runtime-affecting feature ships with a manual procedure under
`docs/smoke-tests/`. Two recurring ones:

- `docs/smoke-tests/2026-06-18-round-loop-smoke-test.md` — the full round loop.
- `docs/smoke-tests/2026-06-22-disconnect-strand-smoke-test.md` — disconnect flow.

You'll need a 2-player local server (Studio → **Test** → **Clients and Servers**
→ 2 players → Start).

To force a swap on demand from the server console:

```lua
require(game.ServerScriptService.Server.RoundManager).forceSwap()
```

## Project layout

```
src/
  client/    StarterPlayerScripts → StarterPlayer (HUD, soul controller, animator)
  server/    ServerScriptService    (managers: round, body, control, hazard, lobby, swap)
  shared/    ReplicatedStorage.Shared (pure modules — config, models, hex math, remotes)
tests/       Lune spec files for the shared/pure modules
docs/
  body-swap-royale-gdd.md           Game design (design intent)
  body-swap-royale-tdd.md           Technical design (architecture, networking, perf)
  dev-environment/                   Dev setup (this file, MCP config)
  smoke-tests/                       Manual Studio procedures
  specs/ , plans/                    Per-feature design + implementation plans
scripts/test.sh                     Lune spec runner
default.project.json                Rojo project mapping
rokit.toml                          Pinned tool versions
```

## Common issues

**`rojo: command not found`** — `rokit install` succeeded but `~/.rokit/bin`
isn't on `PATH`. Either export it (`export PATH="$HOME/.rokit/bin:$PATH"`) or
re-source your shell rc.

**Studio shows no live updates** — the Rojo plugin is installed but not
connected. Click the Rojo button in Studio's toolbar and press **Connect**.

**Tests fail with `module 'shared/X' not found`** — you're invoking `lune run`
from somewhere other than the repo root. Specs use repo-relative requires
(`require("../src/shared/X")`).

**Lune complains about a `game` or `script` global** — the offending spec is
trying to touch a Roblox API. That logic belongs in a `src/server` or
`src/client` module and gets covered by a smoke test, not lune.
