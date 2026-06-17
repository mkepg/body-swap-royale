# Body Swap Royale — Game Design & Technical Design Document

**Version:** 1.3
**Document Type:** Combined GDD + TDD
**Platform:** Roblox
**Status:** Pre-production (core swap mechanic prototyped & validated)

---

## Revision Notes (v1.0 → v1.1)

This revision integrates fixes for the three weaknesses identified in design review, calibrated so that reducing *feel-bad* never sands off the chaos that makes the game shareable.

| Change | Status | Section |
|--------|--------|---------|
| Post-Swap Grace Window | **Core (MVP)** | §4 |
| Swap Preview (telegraph upgrade) | **Core (MVP)** | §4, §6 |
| Control Signature ("Soul") identity system | **Core free tier (MVP) / premium (Alpha)** | §6, §9 |
| Legible Mastery Stats | **Core (Alpha)** | §10 |
| Economy rebalance (Soul monetization lane) | **Core (Alpha)** | §3, §9 |
| Risk Analysis additions | Documentation | §17 |
| **No-Doom Assignment Rule** | **PROPOSED — not committed** | §17.5 |
| Legacy Scoring (Ghost Points / Legacy Standings) | **EXPERIMENTAL — not committed** | §17.5 |

The two weaknesses that most threaten the game — *inherited death feeling unfair* and *the backwards incentive loop* — are addressed primarily by the grace window and swap preview (shipped), with deeper structural options held in §17.5 to be validated by playtest rather than shipped blind.

---

## Revision Notes (v1.1 → v1.2 — Swap Architecture)

This revision records the networking architecture that emerged from actually building and playtesting the core swap mechanic. The original v1.1 networking plan (§5) did not survive contact with the prototype; the model below is what produces a smooth, swappable game on Roblox. The design, economy, identity, and progression sections are unchanged — this is a netcode revision.

**The path (each step rejected on evidence):**

1. **Server-authoritative input routing** (the original §5 plan). Bodies stay server-owned; clients send input intents; the server routes them to the mapped body without changing ownership. *Rejected:* with no client-side prediction, movement under realistic latency felt ~0.3–0.6s delayed — unacceptable for a game whose entire challenge is reacting to where a body is.
2. **Native `player.Character` reassignment.** Make the controlled body the player's `Character` to get prediction, camera, and animation for free. Felt perfect — but *rejected:* reassigning `Player.Character` **destroys the previous body synchronously** (confirmed; parking it in storage first does not save it), so a derangement would shred the very bodies it is trying to redistribute.
3. **Network-ownership transfer on persistent bodies** (**adopted**). Bodies are persistent models that are never anyone's `Character`. Control is granted by handing a player **network ownership** of a body; the owning client drives it locally (predicted → smooth) and a swap simply rotates ownership. No destruction, no per-frame input routing.

| Change | Status | Section |
|--------|--------|---------|
| Networking model: ownership transfer on persistent bodies | **Core (MVP)** | §5, §11, §12 |
| Players have no `Character`; bodies are persistent & fixed-appearance | **Core (MVP)** | §5, §6 |
| Camera transition: hard cut + 0.3s FOV punch (not a positional ease) | **Core (MVP)** | §4, §6 |
| Client-side animation driver (bodies aren't `Character`s) | **Core (MVP)** | §5, §12 |
| Basic server-side movement validation pulled into MVP | **Core (MVP)** | §14, §18 |
| Derangement via Sattolo's algorithm (single-cycle = always valid) | Implementation detail | §4 |

**Net effect:** The Soul pillar is *strengthened* — bodies carry their owner's cosmetics while control rotates to strangers, which is exactly its rationale. Server CPU drops (each client simulates only its own body). Anti-cheat shifts from "server simulates everything" to "server validates client-owned movement," which makes basic position/speed validation load-bearing from MVP rather than a Beta add-on.

---

## Revision Notes (v1.2 → v1.3 — Animation)

Prototyping the body animations exposed a constraint specific to the ownership model and settled how animation is driven. As with the swap architecture, the first two approaches were rejected on evidence:

1. **Client animates the body it controls.** Natural, but *rejected:* because the bodies are not player `Character`s, animations a client plays on them **do not replicate** (confirmed: the server and every other client saw 0 tracks). Each player saw only their own body animate.
2. **Server animates every body** from replicated velocity. Server-played animations *do* replicate, so this fixed visibility — but *rejected:* it routes animation through the server, so the controlling player's own body animates a full round-trip late, which reads as laggy, unresponsive movement.
3. **Every client animates every body locally, from replicated movement** (**adopted**). Animation becomes a pure local function of each body's velocity + floor state. No animation data crosses the network.

**Why it is both responsive and synced:** for the body you control you own its physics, so its velocity updates the instant you move — your local driver animates it the same frame (no round trip). For other bodies you already receive their movement via physics replication, and the driver animates them from that, so it matches exactly what you see them doing. There is no separate animation state to desync: walk-vs-idle is a deterministic read of velocity, and velocity is already replicated consistently to everyone.

| Aspect | Detail |
|--------|--------|
| Advantage | Instant, responsive animation on your own body (local physics → local animation, zero network) |
| Advantage | Other bodies animate correctly from their replicated movement; inherently synchronized |
| Advantage | No dependency on animation replication (impossible for non-`Character` bodies) |
| Advantage | Swap-robust and orphan-free by construction; zero server CPU for animation |
| Disadvantage | Each client animates N (≤16) bodies — trivial cost, but O(N) per client |
| Disadvantage | Animation isn't server-authoritative; a future server-side replay must re-derive it from the recorded movement track (it's a pure function of movement, so this is straightforward) |
| Disadvantage | Possible imperceptible sub-frame disagreement between clients at transition moments |

The server-side animator built during prototyping was removed. **The core swap mechanic was not touched.**

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Problem Statement](#2-problem-statement)
3. [Game Overview](#3-game-overview)
4. [Core Gameplay Mechanics](#4-core-gameplay-mechanics)
5. [Game Systems Architecture](#5-game-systems-architecture)
6. [Detailed Feature Breakdown](#6-detailed-feature-breakdown)
7. [User Experience (UX)](#7-user-experience-ux)
8. [User Interface (UI)](#8-user-interface-ui)
9. [Game Economy](#9-game-economy)
10. [Progression System](#10-progression-system)
11. [Multiplayer Design](#11-multiplayer-design)
12. [Technical Design](#12-technical-design)
13. [Analytics and Metrics](#13-analytics-and-metrics)
14. [Security and Anti-Cheat](#14-security-and-anti-cheat)
15. [Performance Optimization](#15-performance-optimization)
16. [Live Operations](#16-live-operations)
17. [Risk Analysis](#17-risk-analysis)
17.5. [Proposed & Experimental Features](#175-proposed--experimental-features-not-in-core-launch)
18. [Development Roadmap](#18-development-roadmap)
19. [Testing Strategy](#19-testing-strategy)
20. [Complete Feature Inventory](#20-complete-feature-inventory)

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

> *v1.1 note: The old "Swap effects" line is absorbed and expanded into the new Soul signatures lane (see §6 and §9). Soul signatures become the flagship category because they are the only cosmetic the player always sees on themselves across every swap.*

### Replayability Factors

- **Procedural starting states:** No two rounds begin from identical positions because previous round dynamics influence body distribution
- **Map rotation:** 5+ maps at launch, each with distinct hazard sets
- **Modifier rotation:** Round modifiers (Chain Swap, Blackout, Double Speed) shuffle to keep meta fresh
- **AI-generated recaps:** Each round produces unique narrative content
- **Cosmetic chase:** Limited-time and seasonal cosmetics (including evolving Souls) drive return visits
- **Social anchoring:** Friend group dynamics make the game more fun the more it's played together

---

## 4. Core Gameplay Mechanics

### The Swap Mechanic

The defining feature of the game. Every 30 seconds, an authoritative server event rotates which player controls which body. Control is **network ownership** of a persistent body (see §5), so a swap is just a reassignment of ownership — no body is ever a player's `Character`, and nothing is created or destroyed.

**Process (v1.1 — telegraph upgraded to a preview):**

1. At **27 seconds** into a cycle, a screen-wide flash and audio cue activates.
2. From **27s–30s**, a **Swap Preview** displays so the swap is a readable challenge rather than a blind dice roll:
   - A highlighted outline / picture-in-picture of the body the player is about to inherit
   - A directional ping toward that body's current location on the map
   - A one-glance danger read (the target body's outline tints amber if it is currently near a hazard)
3. At **30 seconds**, the server executes the swap atomically by rotating network ownership of the controlled bodies across the active players (a derangement).
4. Each client's camera hard-cuts to its new body and plays a 0.3s FOV "punch." (A positional ease across the arena was considered and dropped: a fast fly-across is *more* disorienting than a clean cut, and risks clipping through geometry. The cut reads as intentional with the FOV juice.)
5. The player's client now owns and drives the new body locally (predicted movement), and the **Post-Swap Grace Window** begins.

**Swap Algorithm:**

```
function ExecuteSwap(activePlayers):
    if length(activePlayers) < 2:
        return  // no swap possible

    bodies = [ controlledBodyOf(p) for p in activePlayers ]
    sattoloDerangement(bodies)   // single-cycle permutation: no body stays put

    for i, player in activePlayers:
        SetNetworkOwner(bodies[i], player)   // hand control to the new owner
        NotifyClient(player, bodies[i], isSwap=true)   // retarget camera + juice
```

A **derangement** (permutation where no element stays in place) guarantees every player gets a *different* body. The prototype uses **Sattolo's algorithm**, which produces a single-cycle permutation in one O(n) pass and is *always* a derangement — no rejection-sampling retry loop is needed, and it is correct down to n=2. Because the swap only rewrites network ownership (never `Character`), it is atomic, cheap, and non-destructive.

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

```
function OnSwapComplete(player, character):
    character.GraceUntil = now() + 1.5
    character.GraceMinFloor = now() + 0.5

function CanDieFromHazard(character):
    if now() < character.GraceMinFloor:
        return false                      // hard floor — always protected briefly
    if now() < character.GraceUntil and not character.HasMovedSinceSwap:
        return false                      // still in grace, hasn't oriented yet
    return true
```

**Calibration note:** The grace window is the most likely value to need tuning. Start at 1.5s and A/B test against 1.0s and 2.0s during alpha, watching **early-leave rate** (frustration) against **average round length** (tension). If rounds start to feel "safe," shorten it.

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

> *v1.1 note: A further mitigation for genuinely unrecoverable inherited bodies — the **No-Doom Assignment Rule** — is documented as a proposed feature in §17.5. It is intentionally **not** committed to core, to avoid over-sanding the chaos before the grace window's effect is measured.*

### Progression Systems

**In-Round Progression (none directly):** No in-round upgrades or pickups exist. The round itself is the experience.

**Meta Progression:**

- Player level (XP-based, 1-100)
- Cosmetic unlocks via XP and currency (including Souls)
- Legible mastery stats (see §10)
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

## 5. Game Systems Architecture

### Client Systems

| System | Responsibility |
|--------|----------------|
| InputBindingManager | Reads input and drives the body the client currently owns via `Humanoid:Move` locally (client-owned → predicted) |
| CameraController | Points the camera at the owned body (`CameraSubject`); plays the swap cut + FOV punch |
| ClientAnimator | Animates **every** visible body locally from its replicated velocity + floor state — not just the owned one. No animation is replicated; each client derives it, which keeps the owned body instant and other bodies in sync. Bodies aren't `Character`s, so the default `Animate` can't drive them |
| SwapVFXController | Plays visual effects during swap previews and executions |
| SoulController (v1.1) | Manages the player's persistent control-signature ("Soul") VFX; re-parents it to the newly controlled body on each swap |
| HUDController | Renders timer, player count, current body indicator |
| MenuController | Lobby, settings, shop, profile UIs |
| AudioController | Triggers swap warnings, ambient round audio, death sounds |
| NotificationController | Toast notifications for kills, swaps, achievements |
| ReplayBufferRecorder | Captures local viewpoint data for share-clip feature |

### Server Systems

| System | Responsibility |
|--------|----------------|
| RoundManager | Authoritative round state machine |
| BodyManager | Creates one persistent body per player, baked once with that player's avatar (normalized dimensions); owns body lifecycle |
| ControlManager | Holds the Player↔Body control map; grants control by assigning network ownership of a body to a player |
| SwapController | Computes derangements and executes swaps by rotating ownership via ControlManager |
| HazardSystem | Spawns and updates environmental dangers |
| ScoreTracker | Tracks survivors, eliminations, attributions, and mastery stats |
| PlayerStateManager | Holds canonical alive/dead status per player |
| AnalyticsLogger | Pushes events to analytics endpoint |
| AntiCheatValidator | Validates client-owned movement (position/speed) and rejects invalid states |
| EconomyService | Awards XP and currency on server side only |
| AIRecapService | Calls Anthropic API for post-round narrative |
| ReplayBuilder | Constructs server-authoritative replay timeline |

### Networking Considerations

The swap mechanic creates non-trivial networking challenges. The standard Roblox model assumes one-to-one player-character ownership, with the local client running prediction on its own character. The swap breaks that one-to-one assumption, and the model below is what survived prototyping (see the v1.1→v1.2 revision notes for the two approaches that were rejected first).

**Approach — network-ownership transfer on persistent bodies.** Bodies are persistent models that are **never any player's `Character`**. A player is granted control of a body by being made its **network owner**; the owning client then drives that body locally (`Humanoid:Move`) and points its camera at it. Because the controlling client owns the body's physics, movement is **client-side predicted and smooth** — the same thing that makes a normal Roblox character feel responsive. A swap is simply a rotation of network ownership across the active bodies; nothing is created or destroyed.

This deliberately *does* use ownership transfer, which v1.1 sought to avoid. Prototyping showed the avoidance was the wrong call: pure server-side input routing left movement feeling 0.3–0.6s laggy under realistic latency, while the obvious native alternative (`player.Character` reassignment) destroys the previous body on every swap. Ownership transfer on persistent bodies is the synthesis: it keeps client prediction (feel) without destroying bodies (swappability). The grace window and Soul re-parent remain purely server-driven flags / cosmetic VFX. The cost is a thin client control + animation layer (bodies aren't `Character`s, so default controls/camera/`Animate` don't apply to them automatically) and a shift of anti-cheat toward server-side movement validation (§14), since the client now owns its body's physics.

### Data Flow

```
SPAWN / SWAP (server):
  [Server: ControlManager] → SetNetworkOwner(body, player)
                           → RemoteEvent: SetControlledBody(player, body, isSwap)
                                  │
                                  ▼
  [Client] retargets camera + animation to the now-owned body

PER-FRAME MOVEMENT (client-owned, predicted):
  [Client Input] → [Humanoid:Move on the owned body, locally]
                          │  (client owns physics → predicted, smooth)
                          ▼
              [Engine replicates body state to server + others]
                          │
                          ▼
        [Server: AntiCheatValidator validates position/speed deltas]
```

### State Management

The authoritative state lives on the server. Key state objects:

- **RoundState** — current phase, time remaining, active modifiers
- **PlayerState** — per-player: alive/dead, currently controlled character, score, mastery counters
- **CharacterState** — per-character: alive/dead, current humanoid health, position, grace timers
- **SwapHistory** — full audit log of every swap event for replay generation

Clients receive replicated subsets of state and never trust their own local state for authoritative decisions.

### Animation Model

Bodies are not player `Character`s, so the engine's default `Animate` does not run on them, and animations a client plays on a body **do not replicate** to anyone else. Animation is therefore driven **locally on every client, for every body**, as a pure function of each body's replicated movement:

- Each client runs a `ClientAnimator` loop over all bodies and plays idle / walk / jump / fall on each body's `Animator` based on its `AssemblyLinearVelocity` and `FloorMaterial`, re-asserting the wanted track if it ever stops (self-healing).
- For the body **you** control, velocity comes from your own (owned) physics, so the animation updates the same frame you move — instant and responsive.
- For **other** bodies, velocity comes from their replicated movement, so their animation matches exactly what you see them doing.

Nothing about animation crosses the network, and there is no animation state to desync — walk-vs-idle is a deterministic read of velocity, which is already replicated. This also makes the system swap-robust: the driver never cares who controls a body, so a swap needs no animation handoff and cannot leave an orphaned looping track. (See the v1.2→v1.3 revision notes for the two approaches this replaced and the full trade-offs.)

### Anti-Exploit Considerations

- Because the controlling client owns its body's physics, the server **validates** movement rather than simulating it: position deltas are checked against max velocity × dt, and teleport/speed outliers are rejected (this is load-bearing here, not a backstop — see §14)
- Swap timing controlled exclusively by server clock; client cannot trigger or delay
- Network ownership is assigned only by the server's ControlManager; a client cannot grant itself ownership of a body
- Grace window timers are server-authoritative; client cannot extend them
- Cosmetic ownership (including Souls) validated against server-side inventory before equipping
- HttpService calls (for AI recap) made only from secured server scripts, never client

---

## 6. Detailed Feature Breakdown

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

**Technical Considerations:**
- Use `BindableEvent` between server systems and `RemoteEvent` for client notification
- Camera change is a **hard cut + ~0.3s FOV punch**, not a positional interpolation (a fast fly-across the arena is more disorienting and can clip geometry)
- Control **is** network ownership of a persistent body: rotate `SetNetworkOwner` on swap. Bodies are never player `Character`s, which is what keeps the swap non-destructive (reassigning `Character` destroys the old body)
- Compute the derangement with Sattolo's algorithm (single-cycle = guaranteed no fixed point)
- A thin client layer drives the owned body, retargets the camera, and animates it (default character scripts don't apply to non-`Character` bodies)

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

**Technical Considerations:**
- Use ScreenGui with a Frame at high ZIndex for the flash
- Use SoundService with priority audio to prevent muting by ambient sounds
- Tween properties via TweenService for smooth flash curves
- Preview outline computed server-side (which body each player will inherit) and replicated only to that player

**Dependencies:** AudioController, HUDController, SwapController

---

### Feature: Control Signature ("Soul") (v1.1)

**Purpose:** Solve three problems with one system — *readability* (which body is me after a swap?), *identity* (a persistent self in a game where you're always in someone else's body), and a *monetization gap* (in v1.0 your purchased cosmetics live on your body, which a stranger is usually driving, so you rarely see what you bought).

**Design:** A **Soul** is a persistent visual signature attached to whichever body the player currently controls. It re-parents to the new body on every swap — a cheap VFX move, with no replication rework. This sits cleanly on the ownership model: each persistent body wears its *owner's* fixed avatar and cosmetics, and since control rotates to other players, your purchased cosmetics are usually being driven by a stranger — which is precisely why a self-following Soul has value.

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
- Performance on mobile low-spec → free halo is lightweight; premium particle Souls respect the particle-limit budget (§15)
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

**Technical Considerations:**
- Server-side only (HttpService is server-only on Roblox)
- 1-3 second response time acceptable since recap happens during natural pause
- Cache fallback templates for resilience
- Rate limit per round to control costs (one call per round end maximum)

**Sample API Prompt Structure:**

```
You are a sports commentator narrating a chaotic body-swap arena round.
Summarize the following round in 2-3 sentences, dramatic but funny.

Round data:
- Players: {playerList}
- Winner: {winnerName}
- Total swaps: {swapCount}
- Notable deaths: {deathLog}
- Final body owner: {winnerName}

Output only the recap text, no preamble.
```

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

**Technical Considerations:**
- Hazards driven by server-side timers, replicated to clients for visual cues
- Use `Touched` events with debounce for elimination logic; check `CanDieFromHazard` (grace) first
- Telegraphs use particle effects and color tweens, not network-heavy meshes

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

**Technical Considerations:**
- Record swap events and death events server-side
- Build replay client-side from event log
- Use 2D representation, not 3D replay, to save memory and bandwidth

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

**Technical Considerations:**
- Modifiers stored as data objects with hooks into RoundManager
- Modular design lets new modifiers be added without touching core swap logic

**Dependencies:** RoundManager, SwapController, HUDController

---

## 7. User Experience (UX)

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

## 8. User Interface (UI)

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

Minimal, as described in HUD section. Mobile users get touch joystick on bottom-left and jump button on bottom-right. The Soul aura is the primary self-locator.

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

## 9. Game Economy

### Currency Systems

| Currency | Source | Use |
|----------|--------|-----|
| Coins | Round rewards, daily login, achievements | Most cosmetic purchases |
| Robux | Real money purchase | Premium cosmetics, Souls, gamepasses, currency conversion |
| Tokens | Limited-time events only | Event-exclusive items |

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

## 10. Progression System

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

## 11. Multiplayer Design

### Lobby Structure

- Lobbies hold 4 to 16 players
- Region-locked by default (US East, US West, EU, Asia, etc.)
- Skill-tiered matchmaking buckets (Novice / Standard / Elite)
- Private lobbies (friends only) bypass tier matching

### Player Synchronization

- Each player **network-owns the body they currently control**; that client simulates and predicts its movement, and the engine replicates it to everyone
- The server is authoritative for swap state, hazards, grace timers, elimination, and economy — and **validates** (rather than simulates) the position/speed of client-owned bodies
- Smooth interpolation client-side for bodies owned by *other* players
- A swap rotates ownership atomically; the brief ownership handoff is masked by the swap's camera cut

### Match Lifecycle

```
Lobby Created
  ↓
Players Join (matched or invited)
  ↓
Countdown (45s, skips at 12 players)
  ↓
Map and Modifier Selected
  ↓
Round Begins
  ↓
Active Play (until 1 alive)
  ↓
Round End / Recap / Rewards
  ↓
Return to Lobby (rounds continue)
  ↓
Lobby Dissolves (after extended inactivity)
```

### Reconnection Handling

If a player disconnects:
- Network ownership of their controlled body automatically reverts to the server, which AI-stabilizes it for 5 seconds
- If they reconnect in 5 seconds, ownership is handed back and they regain control
- Beyond 5 seconds, their body is removed and they are eliminated for the current round
- They can rejoin the lobby for the next round automatically

### Scalability Concerns

- Roblox handles server creation automatically, so horizontal scaling is solved
- Per-server load is bounded by 16-player cap
- API call costs (for AI recap) scale linearly with active servers — need monitoring
- Asset streaming optimized to keep per-server memory under 1GB

---

## 12. Technical Design

### Roblox Services Used

| Service | Use |
|---------|-----|
| Players | Player management, joining, leaving |
| ReplicatedStorage | Shared modules and remote events |
| ServerStorage | Server-only assets and configs |
| ServerScriptService | Server logic |
| StarterPlayerScripts | Client-side initialization |
| RunService | Frame stepping, heartbeat |
| TweenService | UI and camera animations |
| TeleportService | Cross-server lobby joining (future) |
| HttpService | Anthropic API calls (server only) |
| DataStoreService | Persistent player data |
| MarketplaceService | Robux purchases, gamepass checks |
| Lighting | Map ambient and dynamic lighting |
| SoundService | Centralized audio playback |
| TextChatService | In-game chat |
| AnalyticsService | First-party analytics |

### Recommended Architecture

**Top-level structure:**

```
ReplicatedStorage/
  Modules/
    Constants/
    Shared/
      EventTypes
      DataSchemas
    Networking/
      RemoteEvents
      RemoteFunctions
  Assets/
    Cosmetics/
    Souls/
    UI/

ServerScriptService/
  Core/
    RoundManager
    BodyManager          -- persistent avatar bodies (never player Characters)
    ControlManager       -- Player<->Body map; grants control via network ownership
    SwapController        -- derangement + ownership rotation
    HazardSystem
    PlayerStateManager
  Services/
    EconomyService
    AnalyticsService
    AIRecapService
    AntiCheatValidator    -- validates client-owned movement
  Init.server

StarterPlayerScripts/
  Controllers/
    InputBindingManager   -- drives the owned body locally (predicted)
    CameraController       -- points camera at owned body; swap cut + FOV punch
    ClientAnimator         -- animates ALL bodies locally from replicated velocity
    SwapVFXController
    SoulController
    HUDController
  UI/
    MenuController
    LobbyUI
    GameplayUI
  Init.client
```

### Module Structure

Each module exports a single table with `new()` and lifecycle hooks:

```lua
local RoundManager = {}
RoundManager.__index = RoundManager

function RoundManager.new()
    local self = setmetatable({}, RoundManager)
    self.currentState = "Lobby"
    self.players = {}
    return self
end

function RoundManager:Start() end
function RoundManager:Stop() end
function RoundManager:GetState() end

return RoundManager
```

### Remote Events / Functions

| Name | Direction | Purpose |
|------|-----------|---------|
| SetControlledBody | Server → Client | Tells a client which body it now controls (on spawn and each swap; carries an isSwap flag) |
| SwapEvent | Server → Client | Notify swap occurred (HUD/VFX) |
| SwapPreview | Server → Client | Notify player which body they will inherit |
| RoundStateChanged | Server → Client | Round phase changes |
| EliminationEvent | Server → Client | Player eliminated |
| EquipCosmetic | Client → Server | Cosmetic / Soul change request |
| PurchaseItem | Client → Server | Coin purchase |
| GetPlayerData | Server → Client | Initial data sync |

> Note: there is no `SubmitInput` remote. Movement is not routed through the server — the controlling client owns its body and drives it locally, so per-frame input never crosses the wire. The server's role in movement is ownership assignment and validation.

### Data Persistence Strategy

Use `DataStoreService` with `UpdateAsync` for safe concurrent writes.

```lua
PlayerData {
    Version: number,
    Level: number,
    XP: number,
    Coins: number,
    Cosmetics: { [string]: boolean },
    Souls: { [string]: boolean },
    EquippedCosmetics: { Hat, Trail, Soul, SwapInSignature, ... },
    Achievements: { [string]: boolean },
    Stats: { wins, rounds, swaps, bodiesSaved, clutchInherits, longestStreak, etc. },
    BattlePass: { season, tier, premium },
    LastLogin: number (timestamp),
    LoginStreak: number,
}
```

Backup with `DataStoreService:GetDataStore("PlayerBackup_v2")` for redundancy.

### Error Handling

- All `pcall` around DataStore operations
- All `pcall` around HttpService calls
- Fallback templates for AI recap if API fails
- Client-side error logging via custom remote
- Server-side error logging to internal Roblox logs
- Graceful degradation: if a system fails, game continues with reduced functionality

---

## 13. Analytics and Metrics

### KPIs

| KPI | Target (Month 1) | Target (Month 6) |
|-----|------------------|------------------|
| DAU | 50,000 | 500,000 |
| Session length | 18 min | 25 min |
| D1 retention | 25% | 35% |
| D7 retention | 10% | 18% |
| D30 retention | 4% | 8% |
| ARPDAU | $0.05 | $0.15 |
| Concurrent peak | 5,000 | 50,000 |

### Retention Metrics

- D1, D7, D30 retention by acquisition cohort
- Session count per user per day
- Rounds per session
- Drop-off points (where users leave mid-session)

### Monetization Metrics

- Conversion rate (free → paying)
- ARPPU (average revenue per paying user)
- Robux spent per category (cosmetics, Souls, gamepasses, currency)
- Soul attach rate (% of players who equip a premium Soul)
- Battle Pass attach rate
- Repeat purchase rate

### Session Analytics

- Time to first action
- Time to first round
- Time to first death
- Time to first win
- Time to first purchase
- Average rounds per session

### Fairness & Feel Metrics (v1.1)

These exist specifically to measure whether the inherited-death fixes are working:

- **Post-swap death rate** — deaths occurring within 3s of a swap (should fall after grace window ships)
- **Early-leave rate after death** — proxy for "that felt unfair"
- **Pre-swap hazard-parking rate** — proxy for the sabotage meta (informs §17.5 decisions)

### Funnel Tracking

```
Visit game → Click Play → Enter lobby → Round starts → Survive 1 swap → Win first round → Return D1 → Make first purchase
```

Each step tracked individually to identify drop-off points.

---

## 14. Security and Anti-Cheat

### Exploit Prevention

- Server validates all client-owned body positions against legal movement (no teleporting / speed hacks); outliers corrected or rejected
- A client can only control the one body the server has granted it network ownership of; ownership is never client-assigned
- Cosmetic and Soul equipping validated server-side against owned inventory
- Currency changes ONLY occur server-side
- Critical events (swaps, eliminations, grace timers) ONLY triggered by server

### Validation Rules

| Action | Validation |
|--------|------------|
| Movement | Position delta within max velocity * dt |
| Jump | On ground or jump cooldown elapsed |
| Cosmetic / Soul equip | Item exists in player inventory |
| Currency spend | Balance >= cost; double-write to log |
| Round join | Player not banned, slot available |

### Server Authority Model

The server is the **source of truth** for:
- Network ownership of every body (who is allowed to control what)
- All hazard states
- Round state and timer
- Swap timing, preview assignment, and target assignment
- Grace window timers
- Player elimination
- Economy transactions

Movement is **client-owned but server-validated**: the controlling client simulates its body's physics (for prediction/feel), and the server validates the resulting positions against legal movement, correcting or rejecting outliers. This is the standard Roblox shape — client owns movement for feel, server validates for fairness — and it is load-bearing in this game because every body is client-driven.

Clients can only:
- Drive the single body the server has granted them ownership of
- Display server-replicated state
- Render local visual effects (purely cosmetic, including Souls)

### Abuse Detection

- Win/loss ratio outliers flagged for review
- Rapid currency gain flagged
- Disconnect rate per player tracked
- Reports system for player-flagged behavior
- Automated bans for repeat exploit patterns

---

## 15. Performance Optimization

### Memory Considerations

- Asset streaming via `ContentProvider:PreloadAsync` only for critical assets
- Cosmetics and Souls loaded on-demand when equipped
- Map assets unloaded between rounds if changing maps
- Target: under 800MB memory footprint on mid-tier mobile devices

### Replication Optimization

- Reduce position update frequency from default 60Hz to 30Hz for inactive characters
- Use `Vector3int16` or quantized positions where precision allows
- Batch swap events into single RemoteEvent fire
- Avoid replicating per-frame VFX state — let clients compute Soul/aura effects locally
- Server CPU benefits from the ownership model: each client simulates only the one body it owns, so the server validates rather than simulates N humanoids

### Asset Streaming

- **`StreamingEnabled` is OFF for the single-arena MVP.** Because players have no `Character`, the client has no default streaming focus, so with streaming on the engine withholds *all* spatial parts (bodies and map alike) — the prototype hit exactly this (clients saw only skybox). For one bounded arena, streaming buys nothing, so it is disabled.
- If large maps are introduced later, re-enable streaming and set each player's `ReplicationFocus` to their currently-controlled body on every swap, so content streams around the body they're driving.
- Hazard zones always loaded
- Cosmetic and Soul models lazy-loaded when player joins server

### Mobile Optimization

| Setting | Mobile (low) | Mobile (high) | Desktop |
|---------|--------------|---------------|---------|
| Shadow quality | Off | Low | High |
| Particle limit | 50 | 150 | 500 |
| Render distance | 200 | 350 | 500 |
| Character detail | Low LOD | Medium LOD | Full LOD |
| Post-processing | Off | Basic | Full |

Mobile users represent ~60% of Roblox's audience. Mobile performance is a tier-one priority, not an afterthought. Premium Soul particle effects must respect the per-tier particle budget; the free Soul halo is a lightweight billboard that runs on every device.

---

## 16. Live Operations

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

## 17. Risk Analysis

### Technical Risks

| Risk | Severity | Mitigation |
|------|----------|------------|
| Swap mechanic feels buggy | Medium | Prototyped & validated on the ownership-transfer model (smooth under simulated latency); continue camera-cut polish and playtesting |
| Movement feels laggy | **Resolved** | Was high under the original server-routing plan (0.3–0.6s). Fixed by client-owned bodies (prediction). See v1.1→v1.2 notes. |
| Client-owned physics widens cheat surface (speed/teleport) | Medium | Server-side movement validation, pulled into MVP as load-bearing (§14) |
| API costs exceed budget | Medium | Caching, rate limiting, fallbacks |
| Mobile performance issues | High | Early mobile testing, performance budgets; ownership model lowers server CPU |
| Data loss from DataStore failure | High | Backup datastores, defensive code |
| Network desync on swap | Low | Swap is an atomic, non-destructive ownership rotation; brief handoff masked by the camera cut |

### Design Risks

| Risk | Severity | Mitigation |
|------|----------|------------|
| Players don't understand mechanic | Medium | Strong tutorial, visual telegraphs, swap preview |
| Game feels random not strategic | Medium | Legible mastery stats, modifiers, positioning meta |
| Friend groups dominate matches | Low | Skill matchmaking; private/public split |
| Cosmetic monetization underperforms | Medium | A/B test pricing, monitor purchase patterns, Soul as flagship |
| Toxic blame dynamics | Medium | Optional emote system; report tools |
| **Inherited death feels unfair** (eliminated before you can react) | **High** | Grace window + swap preview (core). No-Doom rule proposed (§17.5). Monitor post-swap death rate & early-leave rate. |
| **Sabotage-before-swap meta** (parking your body next to a hazard for whoever inherits it) | **High** | Partially offset by mastery rewards; **root cause is the win condition — not fully solved.** Legacy-scoring experiment in §17.5. Monitor pre-swap hazard-parking rate. |
| **Over-fixing removes the chaos** (fairness patches sand off the shareable feel-bad) | **Medium** | Calibrated grace (1.5s); keep any No-Doom rule narrow; A/B test fairness vs. fun via session length & clip-share rate. |
| **Cognitive overload** (too many systems for young/mobile players) | **Medium** | Keep core to one identity anchor (Soul); gate legacy scoring behind opt-in (§17.5). |

### Monetization Risks

| Risk | Severity | Mitigation |
|------|----------|------------|
| Low conversion rate | High | Continuous A/B testing of shop UX |
| Cosmetics seen as overpriced | Medium | Frequent sales, free cosmetic drops, free Soul halo |
| Battle Pass not perceived as value | Medium | Tune reward density, premium-only items |
| Whales drive most revenue (unbalanced) | Low | Maintain F2P viability so whales don't leave |

### Scalability Risks

| Risk | Severity | Mitigation |
|------|----------|------------|
| Server crashes at high concurrency | High | Stress test before launch, monitor live |
| Matchmaking quality degrades | Medium | Adjust matchmaking tiers as user base grows |
| Live ops team can't keep up | Medium | Plan content calendar 3 months ahead |
| Single popular streamer overwhelms | Low | Auto-scale server creation |

---

## 17.5 Proposed & Experimental Features (Not in Core Launch)

These systems address real weaknesses but carry enough risk — of removing chaos, adding cognitive load, or changing the game's identity — that they are **documented for evaluation, not committed to the build.** Each must clear a playtest gate before promotion.

### Proposed — No-Doom Assignment Rule

**Status:** Proposed. Not committed. Evaluate *after* the grace window's effect on fairness is measured. If grace + preview already make inherited death feel fair, this rule may be unnecessary — and adding it risks sanding off chaos that the game wants to keep.

**What it would do:** Prevent the derangement from handing a fresh player a body that is *already unrecoverable* at the instant of the swap. A narrow safety net, not a fairness blanket.

A body is flagged **doomed** only if, at swap time, it is:
- airborne over a kill volume (void/lava) with no recoverable surface within jump range, **or**
- already inside a death sequence that cannot be cancelled.

When a swap would assign a player to a doomed body, apply **one** rescue (in priority order):
1. Extend that body's grace window to **2.5s** (a real chance to recover), or
2. If still unrecoverable, soft-teleport the body to the nearest safe surface at swap completion.

```
function ResolveAssignment(player, targetBody):
    if IsDoomed(targetBody):
        targetBody.GraceUntil = now() + 2.5
        if not HasRecoverablePath(targetBody):
            SoftTeleportToNearestSafe(targetBody)
    ReassignControl(player, targetBody)
```

**Why it's only proposed:**
- **Pro:** removes the most egregious "died before I could move" cases.
- **Con:** "doomed" is fuzzy to define and easy to over-scope; if it expands to "any risky position," the game loses the chaos that makes it shareable. It also adds server complexity to an already novel mechanic.
- **Decision gate:** only build this if, *after* grace + preview ship, the post-swap death rate and early-leave rate remain high. Keep the definition of "doomed" deliberately narrow — falling-but-recoverable and near-a-hazard are *not* doomed; they are the game.

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

Everything in §17.5 depends on that answer. Get it before writing another line of scoring or assignment code.

---

## 18. Development Roadmap

### MVP Scope (Weeks 1-6)

- [ ] Core swap mechanic working with 4+ players *(ownership-transfer model)*
- [ ] **Swap preview (target-body highlight + ping)**
- [ ] **Post-swap grace window (1.5s)**
- [ ] **Control Signature — free Soul halo + floor ring**
- [ ] **Basic server-side movement validation (speed/teleport sanity)** *(load-bearing under client-owned physics)*
- [ ] Client control layer + **client-side per-body animation** (every client animates every body locally from replicated velocity)
- [ ] One arena map with basic hazards
- [ ] Standard 30-second swap cycle
- [ ] Lobby matchmaking (basic, no skill tiers)
- [ ] Round state machine
- [ ] Win/lose conditions
- [ ] Basic UI (menu, lobby, gameplay, results)
- [ ] DataStore for player level and coins
- [ ] One cosmetic category (hats)

**Definition of done:** Two friends can join the game, play a round with random swaps, orient safely after each swap, see a winner declared, and earn currency.

### Alpha Phase (Weeks 7-12)

- [ ] 3 maps with varied hazard sets
- [ ] 3 round modifiers (Double Speed, Blackout, Chain)
- [ ] Full cosmetic system (4 categories)
- [ ] **Premium Soul tiers + updated economy mix**
- [ ] **Legible mastery stats (Bodies Saved, Clutch Inherits, Swap-Survival %, Longest Streak)**
- [ ] Shop with Robux purchases
- [ ] Tutorial flow (incl. preview + Soul + grace demo)
- [ ] Basic analytics integration (incl. fairness & feel metrics)
- [ ] Closed alpha test with 50-100 invited testers
- [ ] AI recap integration (basic)
- [ ] **Fairness playtest: "does inherited death feel fair?" (gates §17.5)**

**Definition of done:** Game can be played for 30 minutes without bugs, monetization works, telemetry flowing, fairness question answered.

### Beta Phase (Weeks 13-20)

- [ ] 5 maps total
- [ ] 7 round modifiers
- [ ] Achievements system (30+ achievements)
- [ ] Daily reward system
- [ ] Mobile optimization complete
- [ ] Anti-cheat baseline implemented
- [ ] Open beta with 5,000-10,000 active users
- [ ] Replay system functional
- [ ] Friend invite system
- [ ] **Experiment A (Ghost Points) behind a flag, measured against sabotage telemetry**
- [ ] **No-Doom rule evaluated/built only if fairness metrics still demand it**

**Definition of done:** Game is stable, monetization tested, mobile playable, retention measurable.

### Launch Phase (Weeks 21-24)

- [ ] Public launch with marketing push
- [ ] First Battle Pass season
- [ ] Influencer outreach campaign
- [ ] 24/7 monitoring and hotfix capability
- [ ] First seasonal event prepared

**Definition of done:** Game listed publicly, social channels active, daily content cadence established.

### Post-Launch Roadmap (Months 7+)

| Month | Focus |
|-------|-------|
| Month 7-9 | Stabilization, balance, community building |
| Month 10-12 | Season 2 with new mechanic (evaluate Experiment B / Volunteer Swap) |
| Year 2 Q1 | Major map expansion, custom lobbies |
| Year 2 Q2 | Tournament mode, competitive seasons |
| Year 2 Q3 | Player-created maps (UGC) |
| Year 2 Q4 | Year 2 anniversary mega event |

---

## 19. Testing Strategy

### Unit Testing

Test pure-logic modules in isolation:
- Derangement algorithm always produces valid swap permutations
- Round state machine transitions correctly
- Grace window timers grant and expire correctly
- XP and currency calculations are accurate
- Mastery-stat counters (Bodies Saved, etc.) increment correctly
- Cosmetic / Soul equip logic validates ownership

Use [TestEZ](https://github.com/Roblox/testez) framework.

### Gameplay Testing

- Internal playtests twice per week
- Closed alpha with 50-100 testers
- Open beta with thousands
- Focus tests with target demographic (kids 9-14)
- **Dedicated fairness playtest:** measure whether inherited death feels fair after grace + preview (gates §17.5)

### Load Testing

- Stress test with bots simulating 16-player rounds
- Multiple concurrent server stress test
- API endpoint stress test for AI recap
- DataStore concurrency tests

### Exploit Testing

- Hire external pentesters or invite known Roblox exploit community for paid bug bounty
- Common exploits to test: teleport hacks, speed hacks, currency duplication, infinite jump, grace-timer extension
- Confirm server authority blocks every attempted exploit

### QA Checklist (Pre-Launch)

- [ ] No crashes in 50 consecutive rounds
- [ ] Memory stable under 800MB on mid-tier mobile after 1 hour
- [ ] All cosmetics and Souls display correctly on all character body types
- [ ] DataStore writes successful 99.9%+ of the time
- [ ] AI recap API responds 95%+ of the time
- [ ] Tutorial completion rate 80%+ in user testing
- [ ] First-round win rate around 1/N where N = player count (proves fairness)
- [ ] Post-swap death rate within target after grace window ships
- [ ] All purchases work cross-platform
- [ ] All achievements trigger correctly
- [ ] Mobile UI fully usable on iPhone SE-size screens
- [ ] All text readable at minimum supported screen size
- [ ] No major accessibility blockers

---

## 20. Complete Feature Inventory

### Master List

#### Core Gameplay (MVP)
1. Random body swap every 30s
2. Swap preview (target-body highlight + ping) *(v1.1)*
3. Post-swap grace window (1.5s) *(v1.1)*
4. Camera transition on swap
5. Last-body-standing win condition
6. Control Signature — free Soul halo *(v1.1)*
7. One arena map
8. Disappearing tile hazard
9. Round state machine
10. Lobby matchmaking
11. Round start/end flow

#### Game Modes (Alpha)
12. Standard mode
13. Double Speed modifier
14. Blackout modifier
15. Chain Swap modifier

#### Cosmetics & Identity (Alpha)
16. Hats
17. Body trails
18. Outfits
19. Premium Souls (auras, trails) *(v1.1)*
20. Swap-in signatures
21. Custom swap audio

#### Economy (Alpha)
22. Coin currency
23. Robux currency (via marketplace)
24. Shop UI (incl. Souls tab)
25. Cosmetic drops post-round
26. Daily login rewards
27. XP and leveling
28. Legible mastery stats *(v1.1)*

#### Social (Beta)
29. Friend invites
30. Private lobbies
31. In-game chat
32. Player profiles
33. Friend leaderboards

#### Progression (Beta)
34. Achievements system
35. Daily challenges
36. Weekly challenges
37. Battle Pass (seasonal, incl. evolving Souls)

#### Polish (Beta)
38. Tutorial flow
39. Replay system
40. AI-generated post-round recap
41. Sharable recap images
42. Settings menu with accessibility options

#### Anti-Cheat (Beta)
43. Server-authoritative state (swaps, grace, elimination, economy)
44. Network-ownership integrity (clients can't self-grant body control)
45. Position/speed validation *(basic version pulled into MVP — load-bearing under client-owned physics)*
46. Grace-timer authority
47. Currency transaction logging
48. Reports system

#### Live Ops (Launch)
49. Limited-time events
50. Seasonal content rotation
51. Event-exclusive cosmetics & Souls
52. Tournament mode (post-launch)

#### Proposed / Experimental (NOT core — see §17.5)
- No-Doom Assignment Rule *(proposed)*
- Legacy Scoring — Ghost Points / Legacy Standings *(experimental)*

#### Expansion (Post-Launch)
53. Additional maps (5+ at launch, 1 new per season)
54. Additional modifiers (1-2 new per season)
55. Custom user-made lobbies
56. Spectator mode
57. Replay sharing across players
58. Community events platform
59. UGC cosmetics submissions (long-term)

### Prioritized Implementation Order

**Priority 1 (Cannot ship without):**
- Core swap mechanic *(ownership-transfer model)*
- Swap preview *(v1.1)*
- Post-swap grace window *(v1.1)*
- Free Soul halo *(v1.1)*
- Client-side per-body animation *(local, from replicated velocity)*
- Basic server-side movement validation *(load-bearing under client-owned physics)*
- One map with hazards
- Win/lose conditions
- Lobby and matchmaking
- Basic UI
- DataStore persistence

**Priority 2 (Should ship with):**
- 3+ maps
- 3+ modifiers
- Cosmetic system + shop
- Premium Souls + updated economy mix *(v1.1)*
- Legible mastery stats *(v1.1)*
- Tutorial
- Daily rewards
- Achievements
- Mobile optimization

**Priority 3 (Ship if time):**
- AI recap
- Replay system
- Battle Pass

**Priority 4 (Post-launch / gated):**
- Tournament mode
- UGC
- Custom lobbies
- Spectator mode
- No-Doom Assignment Rule *(proposed — only if fairness metrics demand it)*
- Legacy Scoring experiments *(gated by fairness playtest)*

### Future Expansion Opportunities

- **Cross-game integration** with a future companion game in same universe
- **AI-driven dynamic hazards** that adapt to player behavior in real time
- **Voice chat with positional audio** for proximity-based blame
- **Limited-time crossover maps** with other popular Roblox games
- **Esports tournament series** with cash or Robux prize pools
- **Mobile-exclusive variant** with simplified controls for ultra-casual audience
- **Educational mode** for schools and clubs (cooperative, no elimination)

---

*End of Document — v1.1*
