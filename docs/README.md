# Documentation Index

Every feature in this project goes through the same pipeline: a **design spec**
(what and why, agreed before code), an **implementation plan** (the ordered
steps), **Lune specs** for the pure logic, and a **smoke test** procedure for the
runtime behavior that only Roblox can exercise. This index maps the result.

## Start here

| Document | What it covers |
|---|---|
| [Game Design Document](body-swap-royale-gdd.md) | Gameplay intent, UX, economy, progression, risks |
| [Technical Design Document](body-swap-royale-tdd.md) | Architecture, networking, animation, anti-cheat, performance |
| [Critical review](reviews/2026-07-03-critical-review.md) | Self-assessment of the project's weak points |
| [World enrichment roadmap](world-enrichment-roadmap.md) | Cross-slice plan for the "Soul Festival Sky" world |

The TDD's *Architecture Revision History* is the best single read: it records the
two networking models that were built, playtested, and rejected on evidence
before the current one was adopted.

## Setting up

| Document | What it covers |
|---|---|
| [Getting started](dev-environment/getting-started.md) | Rokit, Rojo, Studio setup, troubleshooting |
| [MCP configuration](dev-environment/mcp-configuration.md) | Roblox Studio MCP setup |

## Feature slices

36 design specs in [`specs/`](specs/) and 36 matching
implementation plans in [`plans/`](plans/), grouped by
the system they build:

**Core loop & swap mechanic** — round state, round manager, grace window, round
flow bookends, dynamic swap cadence, swap legibility, swap/doom exclusion, core
loop correctness, disconnect strand-survivor handling, movement validation, swap
preview onboarding.

**Arenas & hazards** — disappearing-tile hazard, Hex-A-Gone arena, Soul Sweeper
arena and its v2 turbine rework, refined across four follow-up slices
(jump-club tuning, touch elimination, collision fix, hitbox/visual alignment).

**World & lobby** — broadcast world shell, per-floor dressing and banners, lobby
staging area, grandstand stage, beyblade lobby, orb vocabulary reassessment.

**Economy, progression & shop** — economy persistence, XP fill animation, Soul
Shop slice 1, arena dim / soul toggle, per-effect dim.

**Platform & input** — cross-platform controls, mobile jump button.

**Marketing assets** — experience icon, icon swap concept, experience thumbnails.

## Verification

| Location | What it holds |
|---|---|
| [`../tests/`](../tests/) | 33 Lune spec files covering pure logic — run with `bash scripts/test.sh` |
| [`smoke-tests/`](smoke-tests/) | 21 manual Studio procedures for runtime behavior Lune cannot reach |

Pure logic lives in Roblox-free modules under `src/shared/`, which is what makes
the Lune specs possible. Anything that needs a live DataModel — network
ownership transfer, physics, replication, DataStore persistence — is covered by
a written smoke-test procedure instead.

## Marketing

[`marketing/`](marketing/) holds the experience icon and thumbnail work:
generation prompts, candidate rounds, and the finalized assets under each
`final/` directory. Rejected candidate rounds are kept outside the repository so clones stay small.
