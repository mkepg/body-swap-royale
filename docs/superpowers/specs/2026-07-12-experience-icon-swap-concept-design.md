# Experience Icon — "Swap Arrows" Concept (Design)

**Date:** 2026-07-12
**Status:** Approved concept, pre-production (prompt-kit refresh next)
**Supersedes the concept in:** [2026-07-10-experience-icon-design.md](2026-07-10-experience-icon-design.md) §3 (the single-character "Possession Close-Up"). That document's *process, palette, constraints, and acceptance checklist remain in force*; only the visual concept changes.
**Related:** [body-swap-royale-gdd.md](../../body-swap-royale-gdd.md) §1 (core loop), `docs/marketing/experience-icon/` (kit, candidates, reference, concept boards).

## 1. Why the concept changed

The shipped-quality candidate `gemini-master8-ref-1.png` (a single avatar with a cyan soul entering its head) tested as **not communicating the game** — it reads as spooky *possession*, not the actual hook. Per the GDD, the core loop is: **every 30 seconds control is randomly reassigned — you get swapped into a different player's body** in a combat-free survival royale. A single possessed character cannot convey an *exchange between players*.

The original design spec (§3) deliberately rejected a two-body depiction for 64px legibility and chose the single face. Real-world feedback overturns that trade: communicating the mechanic matters more than the cleanest possible face, provided the icon still reads at 64px. Concept exploration (see `docs/marketing/experience-icon/concepts/`) converged on the **literal two-player swap**, executed as **"Swap Arrows."**

## 2. The concept — "Swap Arrows"

Two blocky Roblox avatars, head-and-shoulders, angled slightly toward each other in the lower two-thirds of the frame. Between and just above their heads floats a bold, glowing **cyan soul-energy double-arrow (⇄)** — the swap glyph — as the single focal element. The ⇄ is a universal "exchange" symbol, so the swap reads instantly and survives 64px; the two color-blocked characters supply Roblox authenticity and the "two different players" read.

### 2.1 The two players (distinct on purpose)
- **Player 1 (male) — brand continuity with master8:** near-white cube head, **spiky orange hair**, **royal-blue hoodie** with orange accents, flat decal comic-surprise face.
- **Player 2 (female):** near-white cube head, **long pink/magenta hair** (ponytail or side-swept, chunky stylized), **teal hoodie/jacket**, flat decal comic-surprise face.
- Both are unmistakably Roblox avatars: flat printed decal faces, cube heads, slab shoulders, straight non-tapering blocky arms, **no hands/fingers**.
- Contrast logic: both hair masses are warm (orange / pink) so they pop against the violet sky; both outfits are cool (blue / teal) for a consistent party-casual family; the **cyan glyph stays the only bright-cyan element**, keeping it the focal point.

### 2.2 The swap glyph (hero element)
Two chunky, glossy **cyan arrows** curving between the heads — top arrow pointing right, bottom arrow pointing left (horizontal ⇄, glyph form "A"). Rendered as **soul energy**: soft cyan bloom, a couple of soul-wisps/sparks, glossy 3D — *not* a flat UI icon. Kept large and high-contrast; it is the primary 64px signal.

### 2.3 Palette & staging (unchanged Soul Festival dusk)
Violet #3B2A6E → amber #E8703A dusk sky; cyan #6FE3FF soul glyph/wisps; gold #FFB84D accents; near-white character skin. A few faint glowing soul-wisp dots, one subtle teal aurora ribbon, soft vignette. **Square 1:1, full-bleed.**

## 3. Acceptance (the original 7 checks from spec §8 / RESUME §1, **plus a new #3** for gameplay communication — 8 total)

1. **64px read** — the ⇄ glyph + two color-blocked heads legible (verify by downscale, as before).
2. **Authenticity** — two unmistakable Roblox avatars.
3. **Communicates gameplay** *(the reason for this pivot)* — a literal swap between two players.
4. **Safe zone** — glyph + both faces within the central ~80%; watch the top edge for the glyph and hair.
5. **One focal subject** — the glyph unifies the pair; no fused/merged figures.
6. **Tone** — comic surprise, mischievous, zero horror; kid-friendly.
7. **Compliance** — no text/letters/logos (arrows are not text); moderation-safe. The Gemini ✦ watermark is removed at finalize (bilinear-gradient inpaint), not per-roll.
8. **Contrast pop** — warm hair + cool outfits + cyan glyph separate cleanly from the dusk background in a grayscale squint.

## 4. Production approach (unchanged pipeline, new concept)

- **Engine:** Gemini only (Bing dropped as inferior).
- **Reference-guided:** keep uploading `docs/marketing/experience-icon/reference/ref-avatar.png` (grey R15) — it guides proportions/silhouette for *both* avatars.
- **Kit refresh:** rebuild `docs/marketing/experience-icon/prompts.md` around this concept — new Master (Swap Arrows), single-axis variants (e.g., glyph size/placement, camera distance, expression, background density), and updated failure-fixes. Remove the stale cream/no-hair, Bing-era prompts.
- **Loop:** roll in Gemini → save all to `candidates/` (`gemini-swap-1.png`, …) → score vs §3 + verify 64px → pick → ≤2 refine rounds → finalize (`scripts/finalize-icon.ps1` + watermark inpaint) → upload via Creator Dashboard (per-place Icon; replaceable at zero cost).
- **Provisional asset:** the current `final/icon-512.png` (master8) stays as a placeholder only until a Swap Arrows winner replaces it.

## 5. Risks / open questions

- **Two faces at 64px** — the known trade. Mitigation: keep the two heads large and angled inward, and let the bold ⇄ glyph carry the meaning at small sizes. If faces muddy at 64px, tighten to a two-head close-up and shrink shoulders.
- **Glyph reading as a UI/app icon** rather than in-world energy — mitigate with glossy 3D soul styling, bloom, and wisps so it belongs to the scene.
- **Gemini rendering two on-model avatars** (twice the chance of off-model drift) — the reference image plus explicit per-character wording should hold; re-roll off-model outputs.
