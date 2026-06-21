# Smoke Test — Round-Flow Bookends (Lobby + Results)

**Date:** 2026-06-20
**Spec:** docs/superpowers/specs/2026-06-20-round-flow-bookends-design.md
**Why manual:** the banner is runtime client render + server round-loop timing,
which lune can't cover. The pure decision is unit-tested in
`tests/round_screen_model.spec.luau`.

## Setup
- Studio → Test → Clients and Servers → **2 players**, Start.
- Set `Config.HAZARDS_ENABLED = false` (keep the floor solid so nobody falls and
  the round won't end on its own while you inspect the Lobby/Active banners).

## Checks

1. **Lobby banner.** Before the round starts, both clients show the top banner:
   "Waiting for players" with "2 / 2 players" underneath, then it switches to
   "Round starting in N" counting down. Accent stroke is neutral (grey-blue). The
   arena bodies remain visible behind the banner.

2. **Active hides the banner.** When the round begins (phase Active), the banner
   disappears; only the in-round swap HUD (timer/telegraph) is visible.

3. **Eliminated notice (Active-only).** Temporarily set `HAZARDS_ENABLED = true`
   (or in the command bar eliminate one body via the existing harness, e.g.
   `RoundManager.forceSwap()` then let a body fall). On the client that loses a
   body: a centered "You were eliminated" notice appears during Active, and its
   camera retargets to a living body (spectate).

4. **Results banner — winner's client.** When one player remains, the winner's
   client shows the banner with the small "WINNER" label, the winner's **name**,
   the big word **Victory** (teal/win accent), and a bottom line "Next round in N"
   ticking down from `Config.ROUND_END_SECONDS`.

5. **Results banner — loser's client.** The other client shows the same banner with
   the winner's name but the big word **Defeated** (red/lose accent) and the same
   ticking "Next round in N".

6. **Return to Lobby.** After the countdown, both clients revert to the Lobby
   banner ("Waiting for players" / "Round starting in N").

## Pass criteria
All six checks behave as described; text is readable (TextScaled) and the banner
clears the top inset. Note any pixel/spacing tweaks and adjust sizes in
`ClientRoundHud.build()`. Also confirm the big headline does not jump
distractingly in vertical position between the Lobby and Results banners; if it
does, tune the banner layout (e.g. label LayoutOrder / VerticalAlignment) in
`build()`.

## HUD consistency & kid-friendly skin (added 2026-06-21)

Run these on TWO window shapes: a wide desktop window AND a narrow phone-sized
window (Studio device emulator or just drag the client window narrow).

7. **Nothing balloons.** Banner, bottom "Next round in N" pill, and the swap timer
   number are all capped and centered on desktop (no full-width slab). The bottom
   pill is no wider than the banner.

8. **Kid-friendly skin.** Banner is a chunky rounded panel with a thick white
   outline and an offset drop shadow; the panel FILL color matches state -- blue in
   Lobby, green on Victory, red on Defeated. Title text (VICTORY/DEFEATED) is white
   with a dark outline in the rounded FredokaOne font. The WINNER pill is yellow.

9. **Pop-in.** The banner and bottom pill bounce in (scale up) when they appear,
   rather than snapping.

10. **No zone collisions.** The "You were eliminated" notice appears BELOW the big
    swap countdown (never overlapping it), as red text. The swap timer (top) and the
    bookend banner (top) never show at the same time.

11. **Mobile pass.** On the narrow window everything stays readable and on-screen:
    panels shrink via scale but text remains legible; nothing clips off the edges.

## Pass criteria (HUD)
All five checks hold on both window shapes. Note any spacing/size tweaks -- adjust the
values in `src/client/HudTheme.luau` (`Cap`, `Zone`, `Radius`, etc.), NOT in the
individual HUD modules (that is the whole point of the shared theme).
