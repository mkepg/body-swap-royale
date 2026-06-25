# Smoke Test — Broadcast World Shell ("Soul Festival Sky"), Slice 1

**Date:** 2026-06-25
**Scope:** Client-cosmetic world shell (`WorldShell` + `ArenaDressing`). No gameplay logic changed.
**Spec:** docs/superpowers/specs/2026-06-25-broadcast-world-shell-design.md
**Plan:** docs/superpowers/plans/2026-06-25-broadcast-world-shell.md

## Assets used (hybrid path)
- Dusk skybox: free Creator Store **"Sunset Dawn Skybox"** (assetId `325545295`), six faces wired into `Config.WORLD_SKYBOX`. Lives in the project owner's accessible assets. Fallback: set faces to `""` for the gradient-only look.

## Setup
- Open the place in Studio. Start a play session (Play Solo covers the visuals; **2 clients** are needed for the swap-flare and round-regression checks).

## Checks

### Verified during implementation via Studio MCP (single-client, edit/play):
1. **[PASS] Builds clean** — `[BSR] Client ready` prints; no console errors. `workspace.WorldShell` = 71 parts (22 wisps + 48 crowd + 1 aurora); `workspace.ArenaDressing` present (4 spotlight poles + 4 heads, 18 near orbs, 1 marquee).
2. **[PASS] Skybox** — `WorldShell` builds a `Sky` in Lighting from `Config.WORLD_SKYBOX` (verified `SkyboxUp` = the wired asset). Warm dusk sky renders.
3. **[PASS] Atmosphere grade** — `Atmosphere` + `BloomEffect` + `ColorCorrectionEffect` present; `ClockTime` 17.2. Tuned to a light atmosphere (density 0.05, haze 0.4) so the skybox reads through (heavy haze muddied it).
4. **[PASS] Wisps** — glowing soul-palette orbs high above the arena.
5. **[PASS] Spotlights** — 4 lit rigs at the footprint corners, accent-tinted (amber) heads.
6. **[PASS] Marquee** — "BODY SWAP ROYALE" in FredokaOne, legible, mounted on the balcony's arena-facing edge facing the waiting players (at (0, 61, -40)).
7. **[PASS] Near orbs** — ring of soul-colored orbs hugging the arena rim.
8. **[PASS] Fallback** — confirmed earlier that with `WORLD_SKYBOX` faces blank the dusk look holds via atmosphere/lighting alone (no Sky).

### Still to run manually (need 2 clients / a live round):
9. **[ ] Aurora flare on swap** — wait for a swap (or `RoundManager.forceSwap()` from the server command bar). The overhead aurora briefly brightens (transparency 0.85 → 0.45) then fades back over ~1.1s, for every client.
10. **[ ] Crowd cheer** — on an elimination and on the winner banner, the distant + near orbs bob ("cheer").
11. **[ ] No gameplay regression** — a normal round still runs end-to-end: swaps, grace, hex erosion, void death, winner declared. The shell never blocks movement (all parts `CanCollide=false`) and never appears under server ownership (it's client-built).
12. **[ ] Perf sanity** — no obvious FPS drop vs. before on a mid-tier setting.

## Per-floor dressing + banner redesign (2026-06-25 polish)
Verified single-client via MCP (counts + colors + screen captures):
13. **[PASS] Per-floor torches** — all 7 floors have 4 corner torches (28 posts + 28 heads); each head's Neon color matches its floor (amber→green→teal→blue→indigo→magenta→slate). Real `PointLight` + flame only on the top 3 floors (12 lights + 12 flames confirmed).
14. **[PASS] No clipping** — torch posts (~12 studs) sit well under the floor above (floors 50 apart).
15. **[PASS] Per-floor orb rings** — 84 orbs (7 × 12) soul-palette rings; reads as depth, not clutter.
16. **[PASS] Framed banner** — "BODY SWAP ROYALE" renders in the framed header (glow frame, gradient, ON AIR pill) on two posts at the balcony edge, legible to waiting players.
17. **[ ] Perf glance (2-client / live round)** — with ~12 dynamic lights + flame particles, watch FPS during tile erosion (Voxel re-lights). Dial `WORLD_TORCH_LIT_FLOORS` down if needed.

## Result
- Single-client visual + build verification: **PASS** (checks 1–8 and 13–16, via MCP).
- 2-client / live-round checks (9–12, 17): _pending a live 2-client session._
