# Body Swap Royale — Game Design Document (GDD)

**Version:** 1.3
**Document Type:** Game Design Document (player-facing design intent)
**Platform:** Roblox
**Status:** Pre-production (core swap mechanic prototyped & validated)
**Companion document:** [Technical Design Document](body-swap-royale-tdd.md) — architecture, networking, algorithms, security, performance, roadmap, testing.
**Split note (2026-06-17):** This file was separated from the original combined GDD+TDD (`body-swap-royale-gdd-v1_3.md`). Design content lives here; engineering content lives in the TDD. Cross-references point between the two.

---

## Design Revision Notes (v1.0 → v1.1)

This revision integrates fixes for the three weaknesses identified in design review, calibrated so that reducing *feel-bad* never sands off the chaos that makes the game shareable.

| Change | Status | Section |
|--------|--------|---------|
| Post-Swap Grace Window | **Core (MVP)** | §4 |
| Swap Preview (telegraph upgrade) | **Core (MVP)** | §4, §5 |
| Control Signature ("Soul") identity system | **Core free tier (MVP) / premium (Alpha)** | §5, §8 |
| Legible Mastery Stats | **Core (Alpha)** | §9 |
| Economy rebalance (Soul monetization lane) | **Core (Alpha)** | §3, §8 |
| Risk Analysis additions | Documentation | §11 |
| **No-Doom Assignment Rule** | **PROPOSED — not committed** | §12 |
| Legacy Scoring (Ghost Points / Legacy Standings) | **EXPERIMENTAL — not committed** | §12 |

The two weaknesses that most threaten the game — *inherited death feeling unfair* and *the backwards incentive loop* — are addressed primarily by the grace window and swap preview, with deeper structural options held in §12 to be validated by playtest rather than shipped blind.

> The networking and animation architecture revisions (v1.1 → v1.2 → v1.3) are technical in nature and now live in the [TDD revision history](body-swap-royale-tdd.md#architecture-revision-history). The design, economy, identity, and progression sections below are unaffected by those revisions.

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Problem Statement](#2-problem-statement)
3. [Game Overview](#3-game-overview)
4. [Core Gameplay Mechanics](#4-core-gameplay-mechanics)
5. [Detailed Feature Breakdown](#5-detailed-feature-breakdown)
6. [User Experience (UX)](#6-user-experience-ux)
7. [User Interface (UI)](#7-user-interface-ui)
8. [Game Economy](#8-game-economy)
9. [Progression System](#9-progression-system)
10. [Live Operations](#10-live-operations)
11. [Risk Analysis (Design)](#11-risk-analysis-design)
12. [Proposed & Experimental Features](#12-proposed--experimental-features-not-in-core-launch)
13. [Complete Feature Inventory](#13-complete-feature-inventory)

---

## 1. Executive Summary

### Game Overview

Body Swap Royale is a chaotic last-player-standing multiplayer arena game where every 30 seconds, every player's controls are randomly reassigned to a different player's character. Players must survive environmental hazards in a body they did not choose, in a position they did not create, with no preparation time. The game eliminates traditional combat entirely — the arena itself is the threat. Players are forced to navigate constantly shifting circumstances where the previous controller's actions directly determine their starting situation after each swap.

### Core Concept

Identity and control are decoupled. Players experience the consequences of other players' decisions while leaving their own consequences behind for someone else to inherit. Every 30 seconds the entire social and competitive landscape resets, producing a continuous stream of unpredictable, narratively coherent moments where blame is attributable, deaths are personal, and victories feel earned despite the chaos.

### Target Audience

- **Primary:** Roblox players aged 9 to 16 who play in friend groups of 4 to 12 people
- **Secondary:** Content creators (TikTok, YouTube Shorts) seeking inherently clip-worthy gameplay
- **Tertiary:** Casual party-game audiences crossing over from titles like Fall Guys, Gang Beasts, and Stumble Guys

### Platform Compatibility

| Platform | Support Level | Notes |
|----------|--------------|-------|
| PC (Windows/Mac) | Full | Primary development target |
| Mobile (iOS/Android) | Full | Critical — represents ~60% of Roblox users |
| Xbox | Full | Controller support required |
| Tablet | Full | UI scaling required |
| VR | Not supported | Camera and input model incompatible with swap mechanic |

### Unique Selling Points (USPs)

1. **The Swap Mechanic** — No other Roblox game implements random control reassignment as its core loop
2. **Attributable Chaos** — Every death has a name attached to it, generating social drama
3. **Zero Skill Floor, High Skill Ceiling** — Anyone can play immediately, but strategic body positioning rewards experienced players
4. **30-Second Content Cycle** — A new shareable moment is generated every half-minute by design
5. **Combat-Free Competitive Multiplayer** — Appeals to players who want competition without aggression
6. **AI-Driven Round Recap** — Personalized post-round narrative summaries generated via Anthropic API
7. **Persistent Soul Identity (v1.1)** — Your signature aura follows you across every body you control — the one cosmetic you always see on yourself, and only possible because of the swap mechanic

---

## 2. Problem Statement

### Player Need / Entertainment Gap

The Roblox party-game category is dominated by either pure obstacle courses (obbys) or arena PvP shooters. Players who want chaotic social gameplay with friends have limited options that:

- Generate genuinely novel moments rather than repeating predictable scenarios
- Allow casual and skilled players to coexist competitively
- Produce shareable content without requiring players to be skilled at the game
- Work equally well with 4 friends or 12 strangers
- Resolve quickly enough for short play sessions but reward extended engagement

Existing solutions like Fall Guys clones rely on level memorization and physics-based comedy. Murder Mystery games rely on social deduction with rigid role assignment. Body Swap Royale fills the gap between these by making the core experience inherently unpredictable while remaining mechanically simple.

### Why the Concept is Engaging

**Cognitive Engagement:** The swap mechanic creates a continuous low-level problem-solving challenge. Players must rapidly assess unfamiliar situations and react before context disappears.

**Social Engagement:** Because each death can be traced to a specific other player's actions, the game generates blame, gratitude, and shared stories — the raw materials of friend-group humor.

**Emotional Engagement:** The 3-second swap warning creates a universal dread moment. Players know change is coming but cannot control where they'll end up. This shared anticipation is visceral and bonding.

**Aesthetic Engagement:** The visual spectacle of seeing your character continue moving without your input, and watching another character snap into your control, is intrinsically novel.

### Competitive Advantages

| Competitor Type | Their Approach | Our Advantage |
|----------------|----------------|---------------|
| Fall Guys clones | Skill-based obstacle courses | Skill matters less than adaptability; less frustrating for casual players |
| Murder Mystery 2 | Static role assignment | Continuously shifting roles; no "I got a bad role" complaints |
| Battle royale clones | Combat-driven elimination | Combat-free; broader age and audience reach |
| Obby games | Solo skill challenges | Inherently social; friend groups stay together |
| Party game compilations | Fixed minigame rotations | Single coherent mechanic that deepens rather than repeats |

---

## 3. Game Overview

### Genre

**Primary:** Multiplayer Party Arena
**Secondary:** Last-Player-Standing / Battle Royale (combat-free variant)
**Tertiary:** Social Chaos / Party Game

### Gameplay Loop

```
┌─────────────────────────────────────────────────────────┐
│                                                         │
│   LOBBY (45s countdown, 8-16 players queued)            │
│              │                                          │
│              ▼                                          │
│   ROUND START (3s map intro, spawn animation)           │
│              │                                          │
│              ▼                                          │
│   ┌──── 30-SECOND CYCLE ────┐                           │
│   │                         │                           │
│   │  Players navigate map   │                           │
│   │  Hazards activate       │                           │
│   │  Deaths occur            │                           │
│   │                         │                           │
│   │  3-SECOND PREVIEW       │                           │
│   │  (flash + sound +       │                           │
│   │   target-body preview)  │                           │
│   │                         │                           │
│   │  SWAP EVENT             │                           │
│   │  (controls reassigned)  │                           │
│   │                         │                           │
│   │  1.5s GRACE WINDOW      │                           │
│   │  (orient safely)        │                           │
│   │                         │                           │
│   └──────────┬──────────────┘                           │
│              │ (repeats until 1 alive)                  │
│              ▼                                          │
│   ROUND END                                             │
│   (winner crowned, AI recap, replay)                    │
│              │                                          │
│              ▼                                          │
│   REWARDS (XP, currency, cosmetics drop)                │
│              │                                          │
│              ▼                                          │
│   RETURN TO LOBBY                                       │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

### Session Length

- **Single round:** 2 to 5 minutes depending on player count and skill
- **Typical lobby session:** 3 to 5 consecutive rounds (~15 to 25 minutes)
- **Target retention session:** 30 to 45 minutes per visit

### Multiplayer Requirements

- **Minimum players to start round:** 4
- **Optimal player count:** 8 to 12
- **Maximum per server:** 16
- **Fill behavior:** Lobby auto-starts at 6 players after 30-second countdown; auto-starts immediately at 12

### Monetization Opportunities (v1.1)

| Category | Examples | Estimated % of Revenue |
|----------|----------|------------------------|
| **Soul signatures** | Persistent auras, soul trails, swap-in bursts, seasonal evolving Souls | 35% |
| Cosmetic skins | Character outfits, hats, body trails (worn by your body) | 30% |
| Game passes | VIP lobby, double XP, queue priority | 20% |
| Battle Pass | Seasonal progression with exclusive Souls + skins | 10% |
| Modifier passes | Personal swap event triggers | 5% |

> *v1.1 note: The old "Swap effects" line is absorbed and expanded into the new Soul signatures lane (see §5 and §8). Soul signatures become the flagship category because they are the only cosmetic the player always sees on themselves across every swap.*

### Replayability Factors

- **Procedural starting states:** No two rounds begin from identical positions because previous round dynamics influence body distribution
- **Map rotation:** 5+ maps at launch, each with distinct hazard sets
- **Modifier rotation:** Round modifiers (Chain Swap, Blackout, Double Speed) shuffle to keep meta fresh
- **AI-generated recaps:** Each round produces unique narrative content
- **Cosmetic chase:** Limited-time and seasonal cosmetics (including evolving Souls) drive return visits
- **Social anchoring:** Friend group dynamics make the game more fun the more it's played together

---

## 4. Core Gameplay Mechanics

> The networking model that realizes the swap (network-ownership transfer on persistent bodies), the derangement algorithm, the grace-timer logic, and the camera-cut implementation are documented in the [TDD §1 Systems Architecture](body-swap-royale-tdd.md#1-systems-architecture) and [TDD §2 Swap & Grace Algorithms](body-swap-royale-tdd.md#2-swap--grace-algorithms). This section covers the *design intent and player experience*.

### The Swap Mechanic

The defining feature of the game. Every 30 seconds, an authoritative server event rotates which player controls which body. A swap reassigns *control* — nothing about a player's body is created or destroyed, and no body is ever a player's avatar in the engine sense (see TDD for why this matters).

**Player-facing process (v1.1 — telegraph upgraded to a preview):**

1. At **27 seconds** into a cycle, a screen-wide flash and audio cue activates.
2. From **27s–30s**, a **Swap Preview** displays so the swap is a readable challenge rather than a blind dice roll:
   - A highlighted outline / picture-in-picture of the body the player is about to inherit
   - A directional ping toward that body's current location on the map
   - A one-glance danger read (the target body's outline tints amber if it is currently near a hazard)
3. At **30 seconds**, the server executes the swap atomically across the active players (a derangement: everyone gets a *different* body).
4. Each client's camera hard-cuts to its new body and plays a 0.3s FOV "punch." (A positional ease across the arena was considered and dropped: a fast fly-across is *more* disorienting than a clean cut, and risks clipping through geometry. The cut reads as intentional with the FOV juice.)
5. The player now drives the new body, and the **Post-Swap Grace Window** begins.

A **derangement** (permutation where no element stays in place) guarantees every player gets a *different* body — no player ever keeps the body they were just in.

### Post-Swap Grace Window (v1.1)

**Purpose:** Restores a sliver of agency at the exact moment players currently have none — the instant after a swap, when you inherit an unfamiliar body in an unfamiliar position. Without this, a player can be eliminated before their first input, which is the single biggest source of "I lost and it wasn't my fault."

For a short window immediately after each swap, the controlled body cannot die from environmental hazards.

| Property | Value | Rationale |
|----------|-------|-----------|
| Grace duration | **1.5 seconds** | Long enough to orient, short enough to preserve round tension. Deliberately *not* a mini-truce. |
| Early exit | Ends after first movement input (min 0.5s floor) | Active players leave grace fast; idle/confused players keep the full window. |
| Blocks | Hazard deaths (void, crush, etc.) | — |
| Does NOT block | Movement, falling, being pushed | Player still feels the chaos; they just can't *die* yet. |
| Visual | Brief shield shimmer + Soul-aura pulse on the controlled body | Readable to the player and to others. |

**Calibration note:** The grace window is the most likely value to need tuning. Start at 1.5s and A/B test against 1.0s and 2.0s during alpha, watching **early-leave rate** (frustration) against **average round length** (tension). If rounds start to feel "safe," shorten it.

> The grace eligibility logic (`CanDieFromHazard`, hard floor, first-move exit) is specified in [TDD §2](body-swap-royale-tdd.md#2-swap--grace-algorithms).

### Player Actions and Controls

The control scheme is intentionally minimal so that swapping into a new body never requires learning new inputs.

| Action | PC | Mobile | Xbox |
|--------|-----|--------|------|
| Move | WASD | Joystick | Left stick |
| Jump | Space | Jump button | A |
| Sprint | Shift | Sprint button | B (hold) |
| Look | Mouse | Touch drag | Right stick |
| Emote | E | Emote button | Y |
| Menu | Esc | Menu icon | Start |

No combat inputs exist. No combat exists.

### Win and Lose Conditions (v1.1)

**Win condition:** Be the player currently controlling the last living body when the round ends.

**Lose conditions:**

- The body you currently control dies (falls into void, crushed, etc.) **after its grace window has ended**
- You disconnect during a round (your body becomes AI-controlled briefly then is removed)

**Edge case — simultaneous death:** If two bodies die in the same physics tick, the player who entered their body most recently is declared eliminated first (this rewards earlier swap survivors).

> *v1.1 note: A further mitigation for genuinely unrecoverable inherited bodies — the **No-Doom Assignment Rule** — is documented as a proposed feature in §12. It is intentionally **not** committed to core, to avoid over-sanding the chaos before the grace window's effect is measured.*

### Progression Systems

**In-Round Progression (none directly):** No in-round upgrades or pickups exist. The round itself is the experience.

**Meta Progression:**

- Player level (XP-based, 1-100)
- Cosmetic unlocks via XP and currency (including Souls)
- Legible mastery stats (see §9)
- Achievement medals
- Seasonal Battle Pass tracks
- Leaderboards (daily, weekly, all-time)

### Round Structure (v1.1)

| Phase | Duration | Player State |
|-------|----------|--------------|
| Pre-round | 3s | Spawn animation, camera intro |
| Active phase 1 | 27s | Free play, no swap pending |
| Swap preview | 3s | Visual/audio cue + target-body preview active |
| Swap execution | <0.5s | Control reassignment |
| Grace window | 1.5s | Inherited body protected from hazard death while orienting |
| Active phase 2 | ~25.5s | Free play in new body |
| ... | (repeats) | ... |
| Final swap | varies | Last swap before final body |
| Round end | 5s | Winner declaration |
| Recap & replay | 15s | AI-generated narrative + visual replay |
| Reward screen | 10s | XP, currency, cosmetic drops, mastery stats |

### Matchmaking Flow

```
Player taps Play
    │
    ▼
Region check (auto-select nearest server)
    │
    ▼
Skill-based bucket (Novice / Standard / Elite)
    │
    ▼
Join existing lobby (if space + waiting)
    OR
Create new lobby (if none available)
    │
    ▼
Lobby fills to 6 → countdown begins
    │
    ▼
Lobby reaches 12 → countdown skips, round starts
    │
    ▼
Round begins
```

Players can also join lobbies via friend invites, bypassing matchmaking entirely.

---

## 5. Detailed Feature Breakdown

> Each feature's engineering notes (the former "Technical Considerations" blocks) now live in [TDD §3 Feature Technical Considerations](body-swap-royale-tdd.md#3-feature-technical-considerations). This section keeps purpose, user flow, and design edge cases.

### Feature: Random Body Swap

**Purpose:** Core differentiator. Drives all other gameplay.

**User Flow:**
1. Player joins round, controls Character A
2. 30 seconds pass, preview + warning flashes
3. Server executes swap; player now controls Character B
4. Grace window lets player orient; then they adapt to Character B's situation
5. Cycle repeats

**Edge Cases:**
- Player count drops to 1 during 27-second window → no swap occurs; remaining player wins
- Player disconnects mid-swap → their body becomes AI-stabilized for 5 seconds then removed
- Two players die simultaneously → most recently swapped-into body declared eliminated first
- Server lag at swap moment → swap delayed up to 0.5s; if longer, round paused

**Dependencies:** RoundManager, PlayerStateManager, CameraController

---

### Feature: Swap Preview & Warning System (v1.1)

**Purpose:** Create the universal dread moment that becomes the game's signature beat — and make the incoming swap *readable* so inherited death feels fair rather than arbitrary.

**User Flow:**
1. At T-3s before swap, screen flashes a warm orange-to-red color
2. Sound effect plays: a low "incoming" rumble
3. Numbers 3, 2, 1 appear large and centered
4. A **Swap Preview** highlights the body the player is about to inherit: an outline / picture-in-picture, a directional ping to its location, and an amber tint if that body is currently near a hazard

**Edge Cases:**
- Player muted audio → ensure visual cue is fully communicative
- Player has motion sensitivity → setting to reduce flash intensity
- Multiple warnings stacking (e.g., Double Speed modifier) → don't overlap, queue
- Blackout modifier → preview is suppressed by design (that's the point of Blackout)

**Dependencies:** AudioController, HUDController, SwapController

---

### Feature: Control Signature ("Soul") (v1.1)

**Purpose:** Solve three problems with one system — *readability* (which body is me after a swap?), *identity* (a persistent self in a game where you're always in someone else's body), and a *monetization gap* (in v1.0 your purchased cosmetics live on your body, which a stranger is usually driving, so you rarely see what you bought).

**Design:** A **Soul** is a persistent visual signature attached to whichever body the player currently controls. It re-parents to the new body on every swap. Each persistent body wears its *owner's* fixed avatar and cosmetics, and since control rotates to other players, your purchased cosmetics are usually being driven by a stranger — which is precisely why a self-following Soul has value.

| Tier | Example | Visible to | Notes |
|------|---------|-----------|-------|
| Free (default) | Colored nameplate halo + faint floor ring | You + others | Replaces v1.0's "current body username" HUD text with something glanceable. Solves readability for everyone, free. |
| Premium auras | Glow color, particle aura, soul-flame | You + others | Core cosmetic lane. |
| Soul trails | Trail that follows your controlled body | You + others | — |
| Swap-in signatures | Custom burst when you swap into a body | Others (showcase) | Folds in v1.0's "swap effects." |
| Seasonal / evolving Souls | Souls that level up across a season | You + others | Battle-pass tie-in; long retention hook. |

**Why it's a pillar, not a skin:** The Soul is the one cosmetic the player always sees on themselves, across every swap, every round — the most valuable cosmetic real estate in the game, and only purchasable *because* of the swap mechanic.

**User Flow:**
1. Player equips a Soul from the shop or Battle Pass
2. On spawn and after every swap, the Soul VFX attaches to the body they currently control
3. The player can always locate "themselves" by their Soul; others can recognize them across swaps

**Edge Cases:**
- Performance on mobile low-spec → free halo is lightweight; premium particle Souls respect the particle-limit budget (TDD §8)
- Two similar Souls in one lobby → free halo color is auto-assigned distinct per player

**Dependencies:** SoulController, EconomyService, SwapController

---

### Feature: AI Post-Round Recap

**Purpose:** Generate a unique, shareable narrative summary of each round.

**User Flow:**
1. Round ends, winner declared
2. Server collects round event log (swaps, deaths, attributions)
3. Server makes API call to Anthropic with structured prompt
4. AI returns 2-3 sentence narrative recap
5. Recap displayed on results screen with a "Share" button

**Edge Cases:**
- API call times out → fallback to template-based recap from local pool
- API returns inappropriate content → content filter rejects, fallback used
- Network unavailable → use cached template variations

**Dependencies:** RoundManager, AnalyticsLogger, HttpService

---

### Feature: Dynamic Hazard System

**Purpose:** Keep players engaged in active danger so passive parking isn't viable.

**User Flow:**
1. Hazards spawn or activate at scripted moments during round
2. Hazards have visible windups (telegraphs) before damage
3. Player must navigate to avoid them
4. Hazard touch = elimination (unless within an active grace window)

**Hazard Types (MVP):**

| Hazard | Behavior | Telegraph |
|--------|----------|-----------|
| Disappearing tile | Floor segments vanish on timer | Color shifts red 2s before |
| Sweeping beam | Laser sweeps across area | Red warning line traces path |
| Wind gust | Pushes players in one direction | Particle stream visible |
| Crusher | Vertical or horizontal slam | Shadow grows before impact |
| Void zone | Map area becomes deadly | Border markers + sound |
| Shrinking floor | Outer edge becomes void | Visible perimeter recede |

**Edge Cases:**
- Player in mid-air during disappearing tile activation → falls through correctly
- Swap occurs during hazard windup → new player sees full telegraph and gets grace window
- Multiple hazards overlap → priority system, most lethal wins

**Dependencies:** HazardSystem, RoundManager

---

### Feature: Replay System

**Purpose:** Let players review what happened in the round and share key moments.

**User Flow:**
1. Round ends
2. Replay screen shows top-down view of arena
3. Animated arrows show every swap that occurred (Player A → Body B)
4. Critical deaths are highlighted with timestamps
5. Player can scrub or watch full playback

**Edge Cases:**
- Round longer than 5 minutes → compress to highlight reel
- Player disconnected mid-round → reconnects show partial replay
- Storage limits → keep replays only for current session

**Dependencies:** ReplayBuilder, RoundManager

---

### Feature: Round Modifiers

**Purpose:** Vary round-to-round dynamics to extend long-term replayability.

**Modifier Types:**

| Modifier | Effect | Frequency |
|----------|--------|-----------|
| Standard | Random swaps every 30s | 60% of rounds |
| Chain Swap | Players shift one position by score | 8% |
| Blackout | No 3-second warning or preview | 8% |
| Double Speed | Swaps every 15s | 8% |
| Targeted Swap | Highest and lowest get swapped | 6% |
| Volunteer Swap | Each player gets one manual swap trigger | 5% |
| Mirror Match | All bodies are identical character models | 5% |

**User Flow:**
1. Lobby UI announces modifier 5 seconds before round start
2. Brief explanation of modifier shown
3. Round runs with modifier active
4. Standard rounds rotate naturally with modifier rounds

**Edge Cases:**
- Combining modifiers (future) → balance carefully
- Modifier breaks core flow → kill switch for hot-fixing
- Mirror Match + Soul → the Soul becomes the *only* way to tell players apart, increasing its value

**Dependencies:** RoundManager, SwapController, HUDController

---

## 6. User Experience (UX)

### New Player Onboarding

First-time players need to understand the swap mechanic immediately. The risk is that without context, a swap feels like a bug.

**Onboarding sequence:**

1. **First Launch Tutorial Round** — Player loads into a guided practice arena with 3 bots
2. **Visual demo** — A pre-swap moment shows the preview: arrow pointing from Player → Body A → Body B
3. **First swap experienced** — Tutorial pauses briefly, text overlay: "Your controls just swapped! The glowing aura is always *you*."
4. **30-second free play** — Player tries movement in second body, with grace window demonstrated
5. **Tutorial complete** — Player drops into normal matchmaking

**Tutorial principles:**
- Skippable for returning players
- No more than 90 seconds total
- Shows, doesn't tell
- Bots in tutorial use cosmetic styles to feel like real players

### Tutorials

Beyond the initial tutorial, contextual hints appear in early matches:

- After first survival: "Nice! Your goal: be controlling the last body alive"
- After first swap preview: "See the highlighted body? That's who you're about to become — get ready"
- After surviving a dangerous inherit: "Clutch! You had a moment of safety right after the swap — use it to get your bearings"
- After first survived chaotic swap: "You're getting it"

> *v1.1 note: v1.0's hint "that body was already falling when you got it — bad luck happens" is removed. With the grace window and swap preview, inherited death should feel like a challenge the player had a beat to react to, not unavoidable bad luck.*

### Menus

| Menu | Purpose | Access |
|------|---------|--------|
| Main Menu | Entry point, Play / Shop / Profile / Settings | Lobby spawn |
| Profile | Stats, achievements, mastery stats, cosmetic & Soul collection | Menu button |
| Shop | Robux purchases, gamepasses, Souls, limited items | Currency icon tap |
| Settings | Audio, video, accessibility, controls | Gear icon |
| Battle Pass | Seasonal progression view | BP icon in lobby |
| Friends | See online friends, invite to lobby | Friends icon |

### HUD (v1.1)

The in-round HUD is minimal to avoid distraction:

- Top center: Swap countdown timer (always visible, counts down from 30)
- Top left: Player count remaining
- Top right: Your current body's username (secondary identifier)
- **Primary identifier: your Soul aura on the controlled body** — the glanceable "this is me" anchor after every swap, replacing reliance on reading a username
- Bottom center: Swap preview + warning area (active during last 3 seconds)

### Notifications

Toast notifications for:
- Achievement unlocks
- Daily reward available
- Friend joined lobby
- Battle pass tier earned
- Limited-time event starting

### Accessibility Considerations

| Need | Solution |
|------|----------|
| Colorblind | All hazard colors have shape/pattern alternatives; Soul halos use shape variants too |
| Motion sensitivity | Reduce flash intensity toggle; reduce camera transition speed |
| Hearing impaired | All audio cues have visual equivalents |
| Motor impairment | Reduced control complexity by design (only 5 inputs); grace window aids reaction time |
| Cognitive load | One mechanic to learn; no resource management; single identity anchor (your Soul) |
| Screen size | UI scales fluidly across phone, tablet, and desktop |

---

## 7. User Interface (UI)

### Main Menu

```
┌────────────────────────────────────────────────────┐
│                                                    │
│           BODY SWAP ROYALE                         │
│                                                    │
│              [  PLAY  ]                            │
│                                                    │
│   [Shop]    [Profile]    [Battle Pass]   [⚙]      │
│                                                    │
│                                                    │
│   Daily Reward: Available  ❗                      │
│                                                    │
└────────────────────────────────────────────────────┘
```

- Background: rotating arena previews
- "Play" button is dominant
- Daily reward callout is highly visible to drive re-engagement

### Lobby UI

```
┌────────────────────────────────────────────────────┐
│   ROUND STARTING IN: 23                            │
│                                                    │
│   Modifier:  ⚡ Double Speed                        │
│                                                    │
│   Players (8/12):                                  │
│   - ChaoticGoose                                   │
│   - MikhaelDev                                     │
│   - Vesper99                                       │
│   - ...                                            │
│                                                    │
│   Map:  Sky Ruins                                  │
│                                                    │
│   [Invite Friends]    [Leave]                      │
└────────────────────────────────────────────────────┘
```

### Gameplay UI

Minimal, as described in the HUD section. Mobile users get touch joystick on bottom-left and jump button on bottom-right. The Soul aura is the primary self-locator.

### End-of-Round UI

```
┌────────────────────────────────────────────────────┐
│                                                    │
│              🏆 WINNER 🏆                          │
│            MikhaelDev                              │
│                                                    │
│   AI Recap:                                        │
│   "In a stunning final swap, Mikhael inherited    │
│   a flailing body mid-air and somehow rode the    │
│   wind to victory while Vesper plummeted to       │
│   their doom in their own former body."           │
│                                                    │
│   Your round:  Bodies Saved 3 · Clutch Inherits 1  │
│                                                    │
│   [Watch Replay]   [Share Recap]   [Continue]     │
│                                                    │
└────────────────────────────────────────────────────┘
```

### Reward Screens

After end-of-round, a screen shows XP gained, currency earned, mastery stats, and any cosmetic drops:

```
ROUND REWARDS
─────────────
+150 XP (Level 24 → 24.3)
+45 Coins
+1 Battle Pass Tier
Bodies Saved: 3   Swap-Survival: 71%
🎁 Cosmetic Drop: Stardust Soul Trail (Rare)
```

### Shop Screens

- Featured tab (rotating limited items)
- Souls tab (auras, trails, swap-in signatures)
- Cosmetics tab (filterable by type)
- Game passes tab
- Currency packs tab
- Battle Pass tab

### Mobile, Tablet, Desktop Adaptations

| Element | Mobile | Tablet | Desktop |
|---------|--------|--------|---------|
| Touch controls | Visible | Visible | Hidden |
| HUD scale | 1.5x | 1.2x | 1.0x |
| Menu layout | Stacked vertical | Two-column | Two-column |
| Text size | 18pt min | 16pt min | 14pt min |
| Chat | Collapsed by default | Side panel | Side panel |

---

## 8. Game Economy

### Currency Systems

| Currency | Source | Use |
|----------|--------|-----|
| Coins | Round rewards, daily login, achievements | Most cosmetic purchases |
| Robux | Real money purchase | Premium cosmetics, Souls, gamepasses, currency conversion |
| Tokens | Limited-time events only | Event-exclusive items |

> **Update (2026-07-17):** the first coin sink is SHIPPED — Soul Shop slice 1 (25-item
> catalog: halo colors/styles/trails, direct coin purchases, persistent equips). See the
> [slice-1 spec](superpowers/specs/2026-07-16-soul-shop-slice1-design.md); boxes,
> featured rotation, and Robux products remain parked as slices 2–4. Note: shipping the
> shop retired the "zero client→server remotes" property (validated-remote decision
> recorded in the spec §3).

### Reward Systems

**Per-Round Rewards:**
- 50 XP base + bonuses for survival duration
- 20-100 Coins based on placement
- Random cosmetic drop (1% chance per round)

**Daily Rewards:**
- Day 1: 50 Coins
- Day 2: 100 Coins
- Day 3: 1 Cosmetic Box
- Day 4: 200 Coins
- Day 5: 1 Rare Cosmetic Box
- Day 6: 300 Coins
- Day 7: 1 Epic Cosmetic Box + 500 Coins

**Achievement Rewards:**
- "First Win" — 200 Coins
- "Win 10" — Exclusive cosmetic
- "Survive Blackout Mode" — Title
- ... (50+ achievements)

### Premium Purchases

| Item | Robux Price | Type |
|------|-------------|------|
| Coin pack (small) | 99 | 1,000 Coins |
| Coin pack (medium) | 399 | 5,000 Coins |
| Coin pack (large) | 999 | 15,000 Coins |
| VIP Pass | 499 | Permanent: 2x XP, exclusive lobby |
| Battle Pass | 799 | Seasonal premium track (Souls + skins) |
| Lucky Drop x10 | 299 | 10 random cosmetic boxes |
| Soul (premium aura) | 199–499 | Persistent control-signature cosmetic |

### Cosmetics

| Rarity | Drop Rate | Examples |
|--------|-----------|----------|
| Common | 60% | Basic hats, simple trails, basic Soul halos |
| Uncommon | 25% | Themed outfits, sound effects, colored Souls |
| Rare | 10% | Animated cosmetics, Soul trails |
| Epic | 4% | Premium swap-in signatures |
| Legendary | 1% | Unique evolving Souls |

### Monetization Strategy (v1.1)

The strategy is **expressive monetization, never pay-to-win**. Every purchase is cosmetic or convenience (XP boost, faster matchmaking). Players who don't pay can still win every round.

The flagship hook is now the **Soul** category — a persistent signature the player sees on themselves across every swap, plus swap-in signatures others see when your body is inherited. This is a uniquely personal cosmetic with no equivalent in other games, and it exists only because of the swap mechanic.

**Anti-pay-to-win guardrail (explicit):** Nothing in the store may grant a survival advantage during a round. Specifically, no purchase may lengthen the grace window, control swap targets, grant hazard immunity, or reveal more swap information than free players get. The monetization ceiling for non-cosmetics is queue priority and double-XP.

### Balancing Considerations

- Cosmetic drop rates calibrated so a free-to-play player can build a meaningful collection in ~3 months
- Robux purchases should feel optional, not necessary
- Battle Pass progression should reward 30 minutes of daily play
- Event currencies tightly controlled to prevent inflation
- Free Soul halo guarantees every player has a working identity anchor without paying

---

## 9. Progression System

### Levels

- 100 player levels at launch
- Each level requires progressively more XP (formula: `100 * level^1.4`)
- Level 1 to 10: tutorial tier, rapid progression
- Level 11 to 50: standard progression
- Level 51 to 100: prestige tier with exclusive cosmetic rewards
- Level 100+: prestige system that resets level for a permanent badge

### Experience

XP sources:
- Round participation: 25 XP
- Round survival per swap survived: 5 XP
- Round win: 100 XP bonus
- Daily login: 50 XP
- Achievement completion: variable
- Daily challenges: 100-500 XP

### Legible Mastery Stats (v1.1)

The game's skill expression is otherwise invisible, which makes it *feel* like pure luck even where it isn't. Surfacing a few clear stats gives players a sense of mastery and a reason to improve. These are descriptive only — they change no game rules.

| Stat | Definition | Where shown |
|------|------------|-------------|
| **Bodies Saved** | Bodies you kept alive through at least one full cycle | Profile + end-of-round |
| **Clutch Inherits** | Times you survived a body that was in danger (amber) at the moment you inherited it | End-of-round highlight |
| **Swap-Survival %** | Cycles survived ÷ cycles played | Profile |
| **Longest Streak** | Most consecutive cycles survived in one round | Profile + leaderboard |

### Achievements

50+ achievements at launch, organized by category:

- **Survival** — Survive X swaps in a row, win without dying once
- **Chaos** — Inherit a falling body and survive
- **Social** — Play with friends, complete a 12-player round
- **Cosmetic** — Collect all common items, equip a full Soul set
- **Mastery** — Win on every map, win with every modifier, reach a Swap-Survival milestone
- **Special** — Hidden / Easter egg achievements

### Daily Rewards

7-day login cycle as detailed in Game Economy. Cycle resets to Day 1 after Day 7 or after a missed day (encourage continuous play).

### Retention Mechanics

| Mechanic | Effect |
|----------|--------|
| Daily login streak | Increases value of daily reward |
| Weekly challenges | 3 challenges per week, refresh Monday |
| Seasonal Battle Pass | 10-week seasons with progression tiers (incl. evolving Souls) |
| Limited-time events | 1-2 per month tied to holidays/themes |
| Friend bonuses | Bonus XP for playing with friends |
| Comeback rewards | Special bonus when returning after 7+ days inactive |

---

## 10. Live Operations

### Events

| Event Type | Frequency | Example |
|-----------|-----------|---------|
| Weekend events | Weekly | 2x XP weekend |
| Themed events | Monthly | Halloween, Winter, Spring |
| Collaboration events | Quarterly | Brand partnerships, creators |
| Mega events | Yearly | Anniversary celebration |

### Seasonal Content

10-week seasons with:
- New Battle Pass track
- New themed map
- New cosmetic line (including a seasonal Soul)
- New round modifier
- Seasonal challenges

### Content Updates

| Cadence | Content |
|---------|---------|
| Weekly | Bug fixes, balance tweaks, new cosmetic drops |
| Bi-weekly | New cosmetic / Soul sets in shop |
| Monthly | New map or major feature |
| Seasonal (10 weeks) | Major content drop, Battle Pass refresh |

### Community Engagement

- Official Discord server for community
- Weekly developer post on Roblox group
- Featured player clips highlighted in-game
- Player-suggested cosmetic contests
- Tournament events with exclusive rewards

---

## 11. Risk Analysis (Design)

> Technical, scalability, and monetization-infrastructure risks are tracked in [TDD §9 Technical Risks](body-swap-royale-tdd.md#9-technical-risks). This section covers design and monetization-design risk.

### Design Risks

| Risk | Severity | Mitigation |
|------|----------|------------|
| Players don't understand mechanic | Medium | Strong tutorial, visual telegraphs, swap preview |
| Game feels random not strategic | Medium | Legible mastery stats, modifiers, positioning meta |
| Friend groups dominate matches | Low | Skill matchmaking; private/public split |
| Cosmetic monetization underperforms | Medium | A/B test pricing, monitor purchase patterns, Soul as flagship |
| Toxic blame dynamics | Medium | Optional emote system; report tools |
| **Inherited death feels unfair** (eliminated before you can react) | **High** | Grace window + swap preview (core). No-Doom rule proposed (§12). Monitor post-swap death rate & early-leave rate. |
| **Sabotage-before-swap meta** (parking your body next to a hazard for whoever inherits it) | **High** | Partially offset by mastery rewards; **root cause is the win condition — not fully solved.** Legacy-scoring experiment in §12. Monitor pre-swap hazard-parking rate. |
| **Over-fixing removes the chaos** (fairness patches sand off the shareable feel-bad) | **Medium** | Calibrated grace (1.5s); keep any No-Doom rule narrow; A/B test fairness vs. fun via session length & clip-share rate. |
| **Cognitive overload** (too many systems for young/mobile players) | **Medium** | Keep core to one identity anchor (Soul); gate legacy scoring behind opt-in (§12). |

### Monetization Risks

| Risk | Severity | Mitigation |
|------|----------|------------|
| Low conversion rate | High | Continuous A/B testing of shop UX |
| Cosmetics seen as overpriced | Medium | Frequent sales, free cosmetic drops, free Soul halo |
| Battle Pass not perceived as value | Medium | Tune reward density, premium-only items |
| Whales drive most revenue (unbalanced) | Low | Maintain F2P viability so whales don't leave |

---

## 12. Proposed & Experimental Features (Not in Core Launch)

These systems address real weaknesses but carry enough risk — of removing chaos, adding cognitive load, or changing the game's identity — that they are **documented for evaluation, not committed to the build.** Each must clear a playtest gate before promotion.

### Proposed — No-Doom Assignment Rule

**Status:** Proposed. Not committed. Evaluate *after* the grace window's effect on fairness is measured. If grace + preview already make inherited death feel fair, this rule may be unnecessary — and adding it risks sanding off chaos that the game wants to keep.

> **Update (2026-07-03):** Bug #2's two correctness layers are now **IMPLEMENTED**, ahead of and
> independent from the full rescue-based rule below — see the
> [Core Loop Correctness Bundle](superpowers/specs/2026-07-03-core-loop-correctness-design.md).
> Layer 1: swap handoff zeroes body velocity server-authoritatively, so inherited momentum no
> longer cancels grace. Layer 2: a current-state floor-beneath probe excludes void-bound bodies
> from the derangement at commit — a doomed body is never handed to a victim; the griefer keeps
> their own falling body and dies. This is *exclusion*, not the rescue (extend grace / soft-
> teleport) the rule below still proposes; that rescue behavior remains proposed and not
> committed.

**What it would do:** Prevent the derangement from handing a fresh player a body that is *already unrecoverable* at the instant of the swap. A narrow safety net, not a fairness blanket.

A body is flagged **doomed** only if, at swap time, it is:
- airborne over a kill volume (void/lava) with no recoverable surface within jump range, **or**
- already inside a death sequence that cannot be cancelled.

When a swap would assign a player to a doomed body, apply **one** rescue (in priority order):
1. Extend that body's grace window to **2.5s** (a real chance to recover), or
2. If still unrecoverable, soft-teleport the body to the nearest safe surface at swap completion.

**Why it's only proposed:**
- **Pro:** removes the most egregious "died before I could move" cases.
- **Con:** "doomed" is fuzzy to define and easy to over-scope; if it expands to "any risky position," the game loses the chaos that makes it shareable. It also adds server complexity to an already novel mechanic.
- **Decision gate:** only build this if, *after* grace + preview ship, the post-swap death rate and early-leave rate remain high. Keep the definition of "doomed" deliberately narrow — falling-but-recoverable and near-a-hazard are *not* doomed; they are the game.

> The proposed assignment-resolution pseudocode is in [TDD §2](body-swap-royale-tdd.md#2-swap--grace-algorithms).

### Experimental — Legacy Scoring

Addresses the backwards incentive loop (your good positioning currently benefits a random opponent, and the optimal pre-swap move is to sabotage your own body). Every version is risky, so it is quarantined here.

**Experiment A — Ghost Points (low risk, test first)**
- You earn **XP/currency only** if the body you just left behind survives the *next* cycle.
- Does **not** affect placement or who wins.
- Pro: rewards good positioning; easy to add; reversible.
- Con: because it doesn't touch the win condition, the sabotage-to-win incentive technically survives — it just becomes less *rewarding* to grief.
- Validate: does pre-swap hazard-parking telemetry drop when Ghost Points are live?

**Experiment B — Legacy Standings (high risk, only if A succeeds)**
- Final placement blends *bodies you kept alive* with *being the last controller standing*.
- Pro: fully removes the perverse incentive — leaving your body in a good spot now helps *you* win.
- Con: changes the game's identity, adds two-body tracking, hard to tutorialize for ages 9–16, and may fragment the clean "last one standing" clarity that makes the hook legible.
- Validate: in playtests, can a brand-new player explain how they won? If not, B has failed regardless of how elegant it is.

### The One Validation That Unblocks Everything

Before building anything in this section, run a single focused playtest of **grace window + swap preview + Soul aura** and answer one question:

> *When a player is eliminated right after a swap, do they feel it was fair?*

- If **yes** — the core loop is fixed, and both the No-Doom rule and Legacy Scoring may be unnecessary complexity. Ship the clean version.
- If **no** — tune the grace window first; then consider the No-Doom rule; only then weigh Legacy Scoring.

Everything in §12 depends on that answer. Get it before writing another line of scoring or assignment code.

---

## 13. Complete Feature Inventory

**Implementation status legend** (reconciled against the prototype as of 2026-06-17):
🟢 **Done** — implemented in the current Rojo project · 🟡 **Pending** — designed, not yet implemented · ⚪ **Future** — later phase, not started.

See the [TDD §10 Development Roadmap](body-swap-royale-tdd.md#10-development-roadmap) for the engineering schedule and the same status applied to milestones.

### Master List

#### Core Gameplay (MVP)
1. 🟢 Random body swap every 30s *(ownership-transfer model, Sattolo derangement)*
2. 🟡 Swap preview (target-body highlight + ping) *(v1.1 — `PREVIEW_SECONDS` defined, behavior not built)*
3. 🟢 Post-swap grace window (1.5s) *(v1.1 — `GraceModel` + `RoundManager.eliminateFromHazard` gate; client visual deferred)*
4. 🟢 Camera transition on swap *(hard cut + 0.3s FOV punch)*
5. 🟡 Last-body-standing win condition *(no elimination/death logic yet)*
6. 🟡 Control Signature — free Soul halo *(v1.1)*
7. 🟡 One arena map *(only a baseplate exists)*
8. 🟢 Disappearing tile hazard *(v1.1 — pure `TileFieldModel` + `HazardSystem`; full tile-field arena, death via the existing grace-gated void monitor; visuals are flat colors, polish deferred)*
9. 🟡 Round state machine *(RoundManager not implemented; swap loop runs unconditionally)*
10. 🟡 Lobby matchmaking
11. 🟡 Round start/end flow

#### Game Modes (Alpha)
12. ⚪ Standard mode
13. ⚪ Double Speed modifier
14. ⚪ Blackout modifier
15. ⚪ Chain Swap modifier

#### Cosmetics & Identity (Alpha)
16. ⚪ Hats
17. ⚪ Body trails
18. ⚪ Outfits
19. ⚪ Premium Souls (auras, trails) *(v1.1)*
20. ⚪ Swap-in signatures
21. ⚪ Custom swap audio

#### Economy (Alpha)
22. ⚪ Coin currency
23. ⚪ Robux currency (via marketplace)
24. ⚪ Shop UI (incl. Souls tab)
25. ⚪ Cosmetic drops post-round
26. ⚪ Daily login rewards
27. ⚪ XP and leveling
28. ⚪ Legible mastery stats *(v1.1)*

#### Social (Beta)
29. ⚪ Friend invites
30. ⚪ Private lobbies
31. ⚪ In-game chat
32. ⚪ Player profiles
33. ⚪ Friend leaderboards

#### Progression (Beta)
34. ⚪ Achievements system
35. ⚪ Daily challenges
36. ⚪ Weekly challenges
37. ⚪ Battle Pass (seasonal, incl. evolving Souls)

#### Polish (Beta)
38. ⚪ Tutorial flow
39. ⚪ Replay system
40. ⚪ AI-generated post-round recap
41. ⚪ Sharable recap images
42. ⚪ Settings menu with accessibility options

#### Anti-Cheat (Beta)
43. 🟡 Server-authoritative state (swaps, grace, elimination, economy) *(swap/ownership authority done; grace/elimination/economy pending)*
44. 🟢 Network-ownership integrity (clients can't self-grant body control)
45. 🟡 Position/speed validation *(basic version planned for MVP — load-bearing under client-owned physics; not implemented)*
46. 🟡 Grace-timer authority
47. ⚪ Currency transaction logging
48. ⚪ Reports system

#### Live Ops (Launch)
49. ⚪ Limited-time events
50. ⚪ Seasonal content rotation
51. ⚪ Event-exclusive cosmetics & Souls
52. ⚪ Tournament mode (post-launch)

#### Proposed / Experimental (NOT core — see §12)
- No-Doom Assignment Rule *(proposed)*
- Legacy Scoring — Ghost Points / Legacy Standings *(experimental)*

#### Expansion (Post-Launch)
53. ⚪ Additional maps (5+ at launch, 1 new per season)
54. ⚪ Additional modifiers (1-2 new per season)
55. ⚪ Custom user-made lobbies
56. ⚪ Spectator mode
57. ⚪ Replay sharing across players
58. ⚪ Community events platform
59. ⚪ UGC cosmetics submissions (long-term)

### Future Expansion Opportunities

- **Cross-game integration** with a future companion game in same universe
- **AI-driven dynamic hazards** that adapt to player behavior in real time
- **Voice chat with positional audio** for proximity-based blame
- **Limited-time crossover maps** with other popular Roblox games
- **Esports tournament series** with cash or Robux prize pools
- **Mobile-exclusive variant** with simplified controls for ultra-casual audience
- **Educational mode** for schools and clubs (cooperative, no elimination)

---

*End of Game Design Document — v1.3 (split from combined GDD+TDD on 2026-06-17). Engineering content: see [body-swap-royale-tdd.md](body-swap-royale-tdd.md).*
