# Body Swap Royale — Technical Design Document (TDD)

**Version:** 1.3
**Document Type:** Technical Design Document (engineering: how it's built)
**Platform:** Roblox (Rojo project, Luau)
**Status:** Pre-production (core swap mechanic prototyped & validated)
**Companion document:** [Game Design Document](body-swap-royale-gdd.md) — gameplay intent, UX, UI, economy, progression, risks.
**Split note (2026-06-17):** Separated from the original combined GDD+TDD (`body-swap-royale-gdd-v1_3.md`). Engineering content lives here; design content lives in the GDD.

> **Prototype reality check (2026-06-17):** The current Rojo project (`src/`) implements the core swap mechanic, client control, client-side per-body animation, and the camera cut. Several MVP-core systems remain unbuilt (swap preview, grace window, hazards/elimination, RoundManager, movement validation, Souls). Status is annotated throughout and in §10. See also the **Known Open Issue** in §4.

---

## Architecture Revision History

The networking and animation architecture emerged from building and playtesting the prototype, not from up-front design. Each step below was rejected on evidence.

### v1.1 → v1.2 — Swap Architecture (networking)

The original v1.1 networking plan (server-authoritative input routing) did not survive contact with the prototype. The model that did:

1. **Server-authoritative input routing** (original plan). Bodies stay server-owned; clients send input intents; the server routes them to the mapped body without changing ownership. *Rejected:* with no client-side prediction, movement under realistic latency felt ~0.3–0.6s delayed — unacceptable for a game whose entire challenge is reacting to where a body is.
2. **Native `player.Character` reassignment.** Make the controlled body the player's `Character` to get prediction, camera, and animation for free. Felt perfect — but *rejected:* reassigning `Player.Character` **destroys the previous body synchronously** (confirmed; parking it in storage first does not save it), so a derangement would shred the very bodies it is trying to redistribute.
3. **Network-ownership transfer on persistent bodies** (**adopted**). Bodies are persistent models that are never anyone's `Character`. Control is granted by handing a player **network ownership** of a body; the owning client drives it locally (predicted → smooth) and a swap simply rotates ownership. No destruction, no per-frame input routing.

**Net effect:** The Soul pillar is *strengthened* — bodies carry their owner's cosmetics while control rotates to strangers. Server CPU drops (each client simulates only its own body). Anti-cheat shifts from "server simulates everything" to "server validates client-owned movement," making basic position/speed validation load-bearing from MVP rather than a Beta add-on.

### v1.2 → v1.3 — Animation

Prototyping the animations exposed a constraint specific to the ownership model. The first two approaches were rejected on evidence:

1. **Client animates the body it controls.** Natural, but *rejected:* because the bodies are not player `Character`s, animations a client plays on them **do not replicate** (confirmed: the server and every other client saw 0 tracks). Each player saw only their own body animate.
2. **Server animates every body** from replicated velocity. Server-played animations *do* replicate, so this fixed visibility — but *rejected:* it routes animation through the server, so the controlling player's own body animates a full round-trip late, which reads as laggy.
3. **Every client animates every body locally, from replicated movement** (**adopted**). Animation becomes a pure local function of each body's velocity + floor state. No animation data crosses the network.

**Why it is both responsive and synced:** for the body you control you own its physics, so velocity updates the instant you move — your local driver animates it the same frame. For other bodies you already receive their movement via physics replication, and the driver animates them from that. There is no separate animation state to desync: walk-vs-idle is a deterministic read of velocity, and velocity is already replicated consistently to everyone.

| Aspect | Detail |
|--------|--------|
| Advantage | Instant, responsive animation on your own body (local physics → local animation, zero network) |
| Advantage | Other bodies animate correctly from their replicated movement; inherently synchronized |
| Advantage | No dependency on animation replication (impossible for non-`Character` bodies) |
| Advantage | Swap-robust and orphan-free by construction; zero server CPU for animation |
| Disadvantage | Each client animates N (≤16) bodies — trivial cost, but O(N) per client |
| Disadvantage | Animation isn't server-authoritative; a future server-side replay must re-derive it from recorded movement (it's a pure function of movement, so this is straightforward) |
| Disadvantage | Possible imperceptible sub-frame disagreement between clients at transition moments |

The server-side animator built during prototyping was removed. **The core swap mechanic was not touched.**

---

## Table of Contents

1. [Systems Architecture](#1-systems-architecture)
2. [Swap & Grace Algorithms](#2-swap--grace-algorithms)
3. [Feature Technical Considerations](#3-feature-technical-considerations)
4. [Multiplayer Design](#4-multiplayer-design)
5. [Technical Design](#5-technical-design)
6. [Analytics and Metrics](#6-analytics-and-metrics)
7. [Security and Anti-Cheat](#7-security-and-anti-cheat)
8. [Performance Optimization](#8-performance-optimization)
9. [Technical Risks](#9-technical-risks)
10. [Development Roadmap](#10-development-roadmap)
11. [Testing Strategy](#11-testing-strategy)

---

## 1. Systems Architecture

### Client Systems

| System | Responsibility | Status |
|--------|----------------|--------|
| InputBindingManager | Reads input and drives the body the client currently owns via `Humanoid:Move` locally (client-owned → predicted) | 🟢 `ClientControl.luau` |
| CameraController | Points the camera at the owned body (`CameraSubject`); plays the swap cut + FOV punch | 🟢 in `ClientControl.luau` |
| ClientAnimator | Animates **every** visible body locally from its replicated velocity + floor state — not just the owned one. No animation is replicated; each client derives it. Bodies aren't `Character`s, so the default `Animate` can't drive them | 🟢 `ClientAnimator.luau` |
| SwapVFXController | Plays visual effects during swap previews and executions | 🟡 |
| SoulController (v1.1) | Manages the player's persistent control-signature ("Soul") VFX; re-parents it to the newly controlled body on each swap | 🟡 |
| HUDController | Renders timer, player count, current body indicator | 🟡 |
| MenuController | Lobby, settings, shop, profile UIs | 🟡 |
| AudioController | Triggers swap warnings, ambient round audio, death sounds | 🟡 |
| NotificationController | Toast notifications for kills, swaps, achievements | 🟡 |
| ReplayBufferRecorder | Captures local viewpoint data for share-clip feature | ⚪ |

### Server Systems

| System | Responsibility | Status |
|--------|----------------|--------|
| RoundManager | Authoritative round state machine | 🟡 not implemented; swap loop runs unconditionally |
| BodyManager | Creates one persistent body per player, baked once with that player's avatar (normalized dimensions); owns body lifecycle | 🟢 `BodyManager.luau` |
| ControlManager | Holds the Player↔Body control map; grants control by assigning network ownership of a body to a player | 🟢 `ControlManager.luau` |
| SwapController | Computes derangements and executes swaps by rotating ownership via ControlManager | 🟢 `SwapController.luau` |
| HazardSystem | Spawns and updates environmental dangers | 🟢 `HazardSystem.luau` (disappearing-tile floor; phase logic in pure `TileFieldModel`) |
| ScoreTracker | Tracks survivors, eliminations, attributions, and mastery stats | 🟡 |
| PlayerStateManager | Holds canonical alive/dead status per player | 🟡 |
| AnalyticsLogger | Pushes events to analytics endpoint | ⚪ |
| AntiCheatValidator | Validates client-owned movement (position/speed) and rejects invalid states | 🟡 load-bearing, not implemented |
| EconomyService | Awards XP and currency on server side only | 🟢 `EconomyService.luau` + `ProfileStore.luau`; pure `RewardModel`/`ProgressionModel`/`ProfileModel`/`RewardScreenModel` |
| AIRecapService | Calls Anthropic API for post-round narrative | ⚪ |
| ReplayBuilder | Constructs server-authoritative replay timeline | ⚪ |

### Networking Considerations

The swap mechanic creates non-trivial networking challenges. The standard Roblox model assumes one-to-one player-character ownership, with the local client running prediction on its own character. The swap breaks that one-to-one assumption (see the Architecture Revision History for the two approaches rejected first).

**Adopted approach — network-ownership transfer on persistent bodies.** Bodies are persistent models that are **never any player's `Character`**. A player is granted control of a body by being made its **network owner** (`BasePart:SetNetworkOwner(player)` on the body's `HumanoidRootPart`); the owning client then drives that body locally (`Humanoid:Move`) and points its camera at it. Because the controlling client owns the body's physics, movement is **client-side predicted and smooth**. A swap is a rotation of network ownership across the active bodies; nothing is created or destroyed. The grace window and Soul re-parent remain purely server-driven flags / cosmetic VFX. The cost is a thin client control + animation layer and a shift of anti-cheat toward server-side movement validation (§7).

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
        [Server: AntiCheatValidator validates position/speed deltas]   ← 🟡 not yet implemented
```

### State Management

The authoritative state lives on the server. Key state objects:

- **RoundState** — current phase, time remaining, active modifiers *(🟡 RoundManager pending)*
- **PlayerState** — per-player: alive/dead, currently controlled character, score, mastery counters
- **CharacterState** — per-character: alive/dead, current humanoid health, position, grace timers
- **SwapHistory** — full audit log of every swap event for replay generation

Clients receive replicated subsets of state and never trust their own local state for authoritative decisions.

> The current `ControlManager` holds the live `bodyOf` / `controllerOf` maps; the broader RoundState/PlayerState/SwapHistory objects are designed but not yet implemented.

### Animation Model

Bodies are not player `Character`s, so the engine's default `Animate` does not run on them, and animations a client plays on a body **do not replicate** to anyone else. Animation is therefore driven **locally on every client, for every body**, as a pure function of each body's replicated movement:

- Each client runs a `ClientAnimator` loop over all bodies and plays idle / walk / jump / fall on each body's `Animator` based on its `AssemblyLinearVelocity` and `FloorMaterial`, re-asserting the wanted track if it ever stops (self-healing).
- For the body **you** control, velocity comes from your own (owned) physics, so the animation updates the same frame you move — instant and responsive.
- For **other** bodies, velocity comes from their replicated movement, so their animation matches exactly what you see them doing.

Nothing about animation crosses the network, and there is no animation state to desync. This also makes the system swap-robust: the driver never cares who controls a body, so a swap needs no animation handoff and cannot leave an orphaned looping track. *(Implemented: `ClientAnimator.luau`; thresholds `WALK_THRESHOLD = 0.5`, `RISING_THRESHOLD = 1`; jump is one-shot, idle/walk/fall loop.)*

### Anti-Exploit Considerations (architecture)

- Because the controlling client owns its body's physics, the server **validates** movement rather than simulating it: position deltas checked against max velocity × dt, teleport/speed outliers rejected (load-bearing — see §7). 🟡 not yet implemented.
- Swap timing controlled exclusively by server clock; client cannot trigger or delay.
- Network ownership is assigned only by the server's ControlManager; a client cannot grant itself ownership of a body. 🟢
- Grace window timers are server-authoritative; client cannot extend them.
- Cosmetic ownership (including Souls) validated against server-side inventory before equipping.
- HttpService calls (for AI recap) made only from secured server scripts, never client.

---

## 2. Swap & Grace Algorithms

### Swap Algorithm

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

*Implemented* in `SwapController.luau` (`sattoloDerangement` draws `j` from `1..i-1`, never `i`). The actual ownership transfer is delegated to `ControlManager.assignOne`, which calls `root:SetNetworkOwner(player)` and fires `SetControlledBody`.

### Grace Window Logic *(🟢 implemented — `src/shared/GraceModel.luau`)*

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

This logic is implemented in the pure `GraceModel` (time-injected, lune-tested). `RoundManager` stamps a window on each swap (`Config.GRACE_SECONDS = 1.5`, `Config.GRACE_FLOOR_SECONDS = 0.5`) and routes the void death through `RoundManager.eliminateFromHazard`, which consults `GraceModel.canDieFromHazard` before eliminating. `HasMovedSinceSwap` is derived server-side from observed **horizontal** position change on the client-owned body (vertical fall does not count, per GDD §4), sampled in the void monitor against the body's swap-time position; the threshold is `Config.GRACE_MOVE_EPSILON`. The client-side grace visual (shield shimmer + Soul pulse) is deferred to the Soul/VFX work.

> **Update (2026-07-03 — Core Loop Correctness Bundle,
> [spec](specs/2026-07-03-core-loop-correctness-design.md)):** the deferred
> client-side grace visual above is now implemented and corrected. (a) Inherited momentum no
> longer trips `HasMovedSinceSwap`/cancels grace, because `ControlManager` zeroes
> `AssemblyLinearVelocity`/`AssemblyAngularVelocity` server-authoritatively during the
> ownership handoff (own → zero → re-own), so every swap hands off a body at rest. (c) The
> client shimmer no longer guesses the window from local input; the server mirrors its
> `graceBlocked` gate on-change to an authoritative `GraceProtected` body attribute, and
> `SoulController` starts/stops the shimmer from `GetAttributeChangedSignal("GraceProtected")`.

### Camera Transition (implementation)

The swap camera change is a **hard cut + ~0.3s FOV punch**, not a positional interpolation (a fast fly-across the arena is more disorienting and can clip geometry). On receiving `SetControlledBody(body, isSwap=true)` the client sets `CameraSubject` to the new humanoid and, if `isSwap`, snaps `FieldOfView` to 88 and tweens to 70 over 0.3s (`Quad`/`Out`). *Implemented in `ClientControl.luau`.*

### Proposed — No-Doom Assignment Resolution *(see GDD §12; proposed, not committed)*

```
function ResolveAssignment(player, targetBody):
    if IsDoomed(targetBody):
        targetBody.GraceUntil = now() + 2.5
        if not HasRecoverablePath(targetBody):
            SoftTeleportToNearestSafe(targetBody)
    ReassignControl(player, targetBody)
```

> **Update (2026-07-03 — Core Loop Correctness Bundle,
> [spec](specs/2026-07-03-core-loop-correctness-design.md)):** the rescue-based
> resolution above (extend grace / soft-teleport) is still proposed and not committed, but a
> narrower exclusion-based Layer 2 is now **implemented**: void-bound bodies are excluded from
> the derangement via a current-state floor-beneath probe (raycast from body root to `VOID_Y`,
> excluding player bodies, at swap commit). `RoundManager.commitSwap` computes the safe subset
> via the pure, lune-tested `ControlModel.filterSafe(orderedPlayers, isSafe)`, and the derangement
> plan is computed only over that subset; a doomed body is simply never assigned to a victim —
> its own controller keeps it and dies.

---

## 3. Feature Technical Considerations

These are the engineering notes for the features whose design lives in [GDD §5](body-swap-royale-gdd.md#5-detailed-feature-breakdown).

### Random Body Swap
- Use `BindableEvent` between server systems and `RemoteEvent` for client notification.
- Camera change is a hard cut + ~0.3s FOV punch, not a positional interpolation.
- Control **is** network ownership of a persistent body: rotate `SetNetworkOwner` on swap. Bodies are never player `Character`s, which keeps the swap non-destructive (reassigning `Character` destroys the old body).
- Compute the derangement with Sattolo's algorithm (single-cycle = guaranteed no fixed point).
- A thin client layer drives the owned body, retargets the camera, and animates it (default character scripts don't apply to non-`Character` bodies).

### Swap Preview & Warning System *(🟡)*
- Use `ScreenGui` with a `Frame` at high `ZIndex` for the flash.
- Use `SoundService` with priority audio to prevent muting by ambient sounds.
- Tween properties via `TweenService` for smooth flash curves.
- Preview outline computed server-side (which body each player will inherit) and replicated only to that player via a `SwapPreview` remote.

### Control Signature ("Soul") *(🟡)*
- Re-parent the Soul VFX to the newly controlled body on each swap — a cheap VFX move, no replication rework. Sits cleanly on the ownership model.
- Free halo is a lightweight billboard; premium particle Souls respect the per-tier particle budget (§8).

### AI Post-Round Recap *(⚪)*
- Server-side only (`HttpService` is server-only on Roblox).
- 1–3s response time acceptable since recap happens during a natural pause.
- Cache fallback templates for resilience; rate-limit to one call per round end maximum.

**Sample API prompt structure:**

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

### Dynamic Hazard System *(🟡)*
- Hazards driven by server-side timers, replicated to clients for visual cues.
- Use `Touched` events with debounce for elimination logic; check `CanDieFromHazard` (grace) first.
- Telegraphs use particle effects and color tweens, not network-heavy meshes.

### Replay System *(⚪)*
- Record swap events and death events server-side; build replay client-side from the event log.
- Use a 2D representation, not a 3D replay, to save memory and bandwidth.

### Round Modifiers *(⚪)*
- Modifiers stored as data objects with hooks into RoundManager.
- Modular design lets new modifiers be added without touching core swap logic.

---

## 4. Multiplayer Design

### Lobby Structure

- Lobbies hold 4 to 16 players
- Region-locked by default (US East, US West, EU, Asia, etc.)
- Skill-tiered matchmaking buckets (Novice / Standard / Elite)
- Private lobbies (friends only) bypass tier matching

### Player Synchronization

- Each player **network-owns the body they currently control**; that client simulates and predicts its movement, and the engine replicates it to everyone.
- The server is authoritative for swap state, hazards, grace timers, elimination, and economy — and **validates** (rather than simulates) the position/speed of client-owned bodies.
- Smooth interpolation client-side for bodies owned by *other* players.
- A swap rotates ownership atomically; the brief ownership handoff is masked by the swap's camera cut.

### Match Lifecycle

```
Lobby Created → Players Join (matched or invited) → Countdown (45s, skips at 12)
→ Map and Modifier Selected → Round Begins → Active Play (until 1 alive)
→ Round End / Recap / Rewards → Return to Lobby (rounds continue)
→ Lobby Dissolves (after extended inactivity)
```

### Reconnection Handling

If a player disconnects:
- Network ownership of their controlled body automatically reverts to the server, which AI-stabilizes it for 5 seconds
- If they reconnect in 5 seconds, ownership is handed back and they regain control
- Beyond 5 seconds, their body is removed and they are eliminated for the current round
- They can rejoin the lobby for the next round automatically

### ⚠️ Known Open Issue — disconnect cleanup vs. the ownership model

**Status: RESOLVED (2026-06-18).** Implemented via the pure `ControlModel` absorb rule and `ControlManager.removePlayer`; see `docs/plans/2026-06-18-disconnect-control-model-fix.md`. Regression covered by `tests/control_model.spec.luau` (case 2, plus N=3 absorb). The notes below are retained as the rationale.

In the ownership model, **the body wearing a player's avatar is not necessarily the body that player controls** — after the first swap, a player controls someone else's avatar-body, and their own avatar-body is driven by a stranger. The current prototype (`init.server.luau` → `BodyManager.removeBody`) destroys the *leaving player's avatar-body immediately* on `PlayerRemoving`. Two failure modes follow:

1. **Yanking an active player's body:** if player A disconnects, A's avatar-body may currently be controlled by player B. Destroying it pulls B's controlled body out from under them mid-round.
2. **Orphaned controlled body:** the body A *was* controlling (B's, or someone else's avatar-body) is now network-owned by a player who no longer exists, with no controller reassignment.

The §11/GDD reconnection text describes "their controlled body" without distinguishing the two. A correct design must:
- Decouple **body lifecycle** (tied to avatar identity, owned by `BodyManager`) from the **control map** (owned by `ControlManager`).
- On disconnect, release control first, then decide body removal by *whether the body is currently controlled by someone else*, not by who it belongs to.
- Maintain the invariant the derangement relies on: the pool of bodies handed to the next swap must equal the set of active controllers, so removing/adding a body must trigger a control-map reconciliation (and possibly a body retire/respawn at round boundaries rather than mid-cycle).

This is a structural correctness issue, not a polish item — the derangement and grace systems both assume a clean controllers↔bodies bijection.

### Scalability Concerns

- Roblox handles server creation automatically, so horizontal scaling is solved.
- Per-server load is bounded by the 16-player cap.
- API call costs (for AI recap) scale linearly with active servers — need monitoring.
- Asset streaming optimized to keep per-server memory under 1GB.

---

## 5. Technical Design

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

The design target (full system). The **current** Rojo layout (`src/`) is noted afterward.

```
ReplicatedStorage/
  Modules/
    Constants/
    Shared/        (EventTypes, DataSchemas)
    Networking/    (RemoteEvents, RemoteFunctions)
  Assets/          (Cosmetics, Souls, UI)

ServerScriptService/
  Core/
    RoundManager
    BodyManager          -- persistent avatar bodies (never player Characters)
    ControlManager       -- Player<->Body map; grants control via network ownership
    SwapController       -- derangement + ownership rotation
    HazardSystem
    PlayerStateManager
  Services/
    EconomyService
    AnalyticsService
    AIRecapService
    AntiCheatValidator   -- validates client-owned movement
  Init.server

StarterPlayerScripts/
  Controllers/
    InputBindingManager  -- drives the owned body locally (predicted)
    CameraController     -- points camera at owned body; swap cut + FOV punch
    ClientAnimator       -- animates ALL bodies locally from replicated velocity
    SwapVFXController
    SoulController
    HUDController
  UI/ (MenuController, LobbyUI, GameplayUI)
  Init.client
```

**Current prototype layout** (Rojo, mapped via `default.project.json`):

```
src/shared/   → ReplicatedStorage.Shared   (Config.luau, Remotes.luau)
src/server/   → ServerScriptService.Server (init.server, BodyManager, ControlManager, SwapController)
src/client/   → StarterPlayer.StarterPlayerScripts.Client (init.client, ClientControl, ClientAnimator)
```

Remotes are created at **runtime** (`Remotes.luau`) rather than as hand-placed instances, since this is a Rojo project with no instance model files: the server ensures the `Remotes` folder + events exist; the client `WaitForChild`s them. `Config.luau` is the single source of truth for tunables (cycle/grace timing, normalized scales, walk/jump, spawn layout, R15 animation IDs).

### Module Structure

The full design uses an OOP module pattern (`new()` + lifecycle hooks). The current prototype modules are simpler stateless/table modules (e.g. `SwapController.start()`, `ControlManager.assignOne()`); they can be promoted to the `new()` pattern when RoundManager introduces multiple round instances.

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

| Name | Direction | Purpose | Status |
|------|-----------|---------|--------|
| SetControlledBody | Server → Client | Tells a client which body it now controls (on spawn and each swap; carries an `isSwap` flag) | 🟢 |
| SwapEvent | Server → Client | Notify swap occurred (HUD/VFX) | 🟡 |
| SwapPreview | Server → Client | Notify player which body they will inherit | 🟡 |
| RoundStateChanged | Server → Client | Round phase changes | 🟡 |
| EliminationEvent | Server → Client | Player eliminated | 🟡 |
| EquipCosmetic | Client → Server | Cosmetic / Soul change request | ⚪ |
| PurchaseItem | Client → Server | Coin purchase | ⚪ |
| GetPlayerData | Server → Client | Initial data sync | ⚪ |

> There is no `SubmitInput` remote. Movement is not routed through the server — the controlling client owns its body and drives it locally, so per-frame input never crosses the wire. The server's role in movement is ownership assignment and validation.

### Data Persistence Strategy *(⚪ not implemented)*

Use `DataStoreService` with `UpdateAsync` for safe concurrent writes.

```lua
PlayerData {
    Version, Level, XP, Coins,
    Cosmetics: { [string]: boolean },
    Souls: { [string]: boolean },
    EquippedCosmetics: { Hat, Trail, Soul, SwapInSignature, ... },
    Achievements: { [string]: boolean },
    Stats: { wins, rounds, swaps, bodiesSaved, clutchInherits, longestStreak, ... },
    BattlePass: { season, tier, premium },
    LastLogin, LoginStreak,
}
```

Backup with `DataStoreService:GetDataStore("PlayerBackup_v2")` for redundancy.

### Error Handling

- All `pcall` around DataStore operations.
- All `pcall` around HttpService calls.
- Fallback templates for AI recap if API fails.
- Client-side error logging via custom remote.
- Server-side error logging to internal Roblox logs.
- Graceful degradation: if a system fails, game continues with reduced functionality.

> The prototype already `pcall`s around `SetNetworkOwner` (`ControlManager`) and around avatar construction (`BodyManager.buildAvatarBody`, with a blank-`HumanoidDescription` fallback for test players with no web avatar).

---

## 6. Analytics and Metrics

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

- Time to first action, first round, first death, first win, first purchase
- Average rounds per session

### Fairness & Feel Metrics (v1.1)

These exist specifically to measure whether the inherited-death fixes are working:

- **Post-swap death rate** — deaths occurring within 3s of a swap (should fall after grace window ships)
- **Early-leave rate after death** — proxy for "that felt unfair"
- **Pre-swap hazard-parking rate** — proxy for the sabotage meta (informs the GDD §12 decisions)

### Funnel Tracking

```
Visit game → Click Play → Enter lobby → Round starts → Survive 1 swap → Win first round → Return D1 → Make first purchase
```

Each step tracked individually to identify drop-off points.

---

## 7. Security and Anti-Cheat

### Exploit Prevention

- Server validates all client-owned body positions against legal movement (no teleporting / speed hacks); outliers corrected or rejected. 🟡 not yet implemented — load-bearing under client-owned physics.
- A client can only control the one body the server has granted it network ownership of; ownership is never client-assigned. 🟢
- Cosmetic and Soul equipping validated server-side against owned inventory.
- Currency changes ONLY occur server-side.
- Critical events (swaps, eliminations, grace timers) ONLY triggered by server.

### Validation Rules

| Action | Validation |
|--------|------------|
| Movement | Position delta within max velocity * dt |
| Jump | On ground or jump cooldown elapsed |
| Cosmetic / Soul equip | Item exists in player inventory |
| Currency spend | Balance >= cost; double-write to log |
| Round join | Player not banned, slot available |

### Server Authority Model

The server is the **source of truth** for: network ownership of every body, all hazard states, round state and timer, swap timing/preview/target assignment, grace window timers, player elimination, economy transactions.

Movement is **client-owned but server-validated**: the controlling client simulates its body's physics (for prediction/feel), and the server validates the resulting positions against legal movement, correcting or rejecting outliers. This is the standard Roblox shape, and it is load-bearing in this game because every body is client-driven.

Clients can only: drive the single body the server has granted them ownership of; display server-replicated state; render local visual effects (purely cosmetic, including Souls).

### Abuse Detection

- Win/loss ratio outliers flagged for review
- Rapid currency gain flagged
- Disconnect rate per player tracked
- Reports system for player-flagged behavior
- Automated bans for repeat exploit patterns

---

## 8. Performance Optimization

### Memory Considerations

- Asset streaming via `ContentProvider:PreloadAsync` only for critical assets
- Cosmetics and Souls loaded on-demand when equipped
- Map assets unloaded between rounds if changing maps
- Target: under 800MB memory footprint on mid-tier mobile devices

### Replication Optimization

- Reduce position update frequency from default 60Hz to 30Hz for inactive characters
- Use `Vector3int16` or quantized positions where precision allows
- Batch swap events into a single RemoteEvent fire
- Avoid replicating per-frame VFX state — let clients compute Soul/aura effects locally
- Server CPU benefits from the ownership model: each client simulates only the one body it owns, so the server validates rather than simulates N humanoids

### Asset Streaming

- **`StreamingEnabled` is OFF for the single-arena MVP.** Because players have no `Character`, the client has no default streaming focus, so with streaming on the engine withholds *all* spatial parts (bodies and map alike) — the prototype hit exactly this (clients saw only skybox). For one bounded arena, streaming buys nothing, so it is disabled. *(Set in `default.project.json`: `Workspace.StreamingEnabled = false`.)*
- If large maps are introduced later, re-enable streaming and set each player's `ReplicationFocus` to their currently-controlled body on every swap, so content streams around the body they're driving.
- Hazard zones always loaded.
- Cosmetic and Soul models lazy-loaded when player joins server.

### Mobile Optimization

| Setting | Mobile (low) | Mobile (high) | Desktop |
|---------|--------------|---------------|---------|
| Shadow quality | Off | Low | High |
| Particle limit | 50 | 150 | 500 |
| Render distance | 200 | 350 | 500 |
| Character detail | Low LOD | Medium LOD | Full LOD |
| Post-processing | Off | Basic | Full |

Mobile users represent ~60% of Roblox's audience. Mobile performance is a tier-one priority. Premium Soul particle effects must respect the per-tier particle budget; the free Soul halo is a lightweight billboard that runs on every device.

---

## 9. Technical Risks

> Design and monetization-design risks are in [GDD §11](body-swap-royale-gdd.md#11-risk-analysis-design).

### Technical Risks

| Risk | Severity | Mitigation |
|------|----------|------------|
| Swap mechanic feels buggy | Medium | Prototyped & validated on the ownership-transfer model (smooth under simulated latency); continue camera-cut polish and playtesting |
| Movement feels laggy | **Resolved** | Was high under the original server-routing plan (0.3–0.6s). Fixed by client-owned bodies (prediction). See revision history. |
| Client-owned physics widens cheat surface (speed/teleport) | Medium | Server-side movement validation, pulled into MVP as load-bearing (§7) |
| **Disconnect cleanup corrupts the controllers↔bodies bijection** | **Resolved** | Fixed via the ControlModel absorb rule + `ControlManager.removePlayer`; bijection asserted by lune tests. See §4. |
| API costs exceed budget | Medium | Caching, rate limiting, fallbacks |
| Mobile performance issues | High | Early mobile testing, performance budgets; ownership model lowers server CPU |
| Data loss from DataStore failure | High | Backup datastores, defensive code |
| Network desync on swap | Low | Swap is an atomic, non-destructive ownership rotation; brief handoff masked by the camera cut |

### Scalability Risks

| Risk | Severity | Mitigation |
|------|----------|------------|
| Server crashes at high concurrency | High | Stress test before launch, monitor live |
| Matchmaking quality degrades | Medium | Adjust matchmaking tiers as user base grows |
| Live ops team can't keep up | Medium | Plan content calendar 3 months ahead |
| Single popular streamer overwhelms | Low | Auto-scale server creation |

---

## 10. Development Roadmap

**Status legend:** 🟢 Done · 🟡 In progress / partially built · ⚪ Not started.

### MVP Scope (Weeks 1-6)

- [x] 🟢 Core swap mechanic working with 4+ players *(ownership-transfer model)* — *prototyped; not yet tested at 4+ concurrent*
- [ ] 🟡 Swap preview (target-body highlight + ping) — *`PREVIEW_SECONDS` defined; no behavior*
- [x] 🟢 Post-swap grace window (1.5s) — *`GraceModel.canDieFromHazard` + `RoundManager.eliminateFromHazard` gate; server-only (visual deferred)*
- [ ] 🟡 Control Signature — free Soul halo + floor ring
- [ ] 🟡 Basic server-side movement validation (speed/teleport sanity) *(load-bearing under client-owned physics)*
- [x] 🟢 Client control layer + client-side per-body animation *(every client animates every body locally from replicated velocity)*
- [x] 🟢 One arena map with basic hazards — *full disappearing-tile floor (`HazardSystem` + `TileFieldModel`); baseplate replaced*
- [x] 🟢 Standard 30-second swap cycle — *implemented as an unconditional loop; needs RoundManager gating*
- [ ] ⚪ Lobby matchmaking (basic, no skill tiers)
- [ ] 🟡 Round state machine — *RoundManager not implemented*
- [ ] 🟡 Win/lose conditions — *no death/elimination path*
- [ ] ⚪ Basic UI (menu, lobby, gameplay, results)
- [x] 🟢 DataStore for player level and coins — *`ProfileStore` (UpdateAsync, retry, no-clobber-on-failed-load) + `EconomyService` session cache; survival-depth Coins/XP/Level awarded at round end; reward panel + persistent HUD balance*
- [ ] ⚪ One cosmetic category (hats)

**Definition of done:** Two friends can join the game, play a round with random swaps, orient safely after each swap, see a winner declared, and earn currency.

> **DoD status (2026-06-30):** death/elimination, grace, win declaration, the RoundManager, and now **currency** (Coins/XP/Level + DataStore persistence) are all in place — the MVP Definition-of-Done sentence ("…and earn currency") is met. Remaining MVP-scope polish: swap preview, Control Signature visuals, movement validation, lobby matchmaking, and basic menu/results UI.

### Alpha Phase (Weeks 7-12)

- [ ] ⚪ 3 maps with varied hazard sets
- [ ] ⚪ 3 round modifiers (Double Speed, Blackout, Chain)
- [ ] ⚪ Full cosmetic system (4 categories)
- [ ] ⚪ Premium Soul tiers + updated economy mix
- [ ] ⚪ Legible mastery stats (Bodies Saved, Clutch Inherits, Swap-Survival %, Longest Streak)
- [ ] ⚪ Shop with Robux purchases
- [ ] ⚪ Tutorial flow (incl. preview + Soul + grace demo)
- [ ] ⚪ Basic analytics integration (incl. fairness & feel metrics)
- [ ] ⚪ Closed alpha test with 50-100 invited testers
- [ ] ⚪ AI recap integration (basic)
- [ ] ⚪ Fairness playtest: "does inherited death feel fair?" (gates GDD §12)

**Definition of done:** Game can be played for 30 minutes without bugs, monetization works, telemetry flowing, fairness question answered.

### Beta Phase (Weeks 13-20)

- [ ] ⚪ 5 maps total
- [ ] ⚪ 7 round modifiers
- [ ] ⚪ Achievements system (30+ achievements)
- [ ] ⚪ Daily reward system
- [ ] ⚪ Mobile optimization complete
- [ ] ⚪ Anti-cheat baseline implemented
- [ ] ⚪ Open beta with 5,000-10,000 active users
- [ ] ⚪ Replay system functional
- [ ] ⚪ Friend invite system
- [ ] ⚪ Experiment A (Ghost Points) behind a flag, measured against sabotage telemetry
- [ ] ⚪ No-Doom rule evaluated/built only if fairness metrics still demand it

**Definition of done:** Game is stable, monetization tested, mobile playable, retention measurable.

### Launch Phase (Weeks 21-24)

- [ ] ⚪ Public launch with marketing push
- [ ] ⚪ First Battle Pass season
- [ ] ⚪ Influencer outreach campaign
- [ ] ⚪ 24/7 monitoring and hotfix capability
- [ ] ⚪ First seasonal event prepared

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

### Prioritized Implementation Order

**Priority 1 (Cannot ship without):** core swap mechanic 🟢 · swap preview 🟡 · post-swap grace window 🟢 · free Soul halo 🟡 · client-side per-body animation 🟢 · basic server-side movement validation 🟡 · one map with hazards 🟡 · win/lose conditions 🟡 · lobby and matchmaking ⚪ · basic UI ⚪ · DataStore persistence ⚪

**Priority 2 (Should ship with):** 3+ maps · 3+ modifiers · cosmetic system + shop · premium Souls + updated economy mix · legible mastery stats · tutorial · daily rewards · achievements · mobile optimization

**Priority 3 (Ship if time):** AI recap · replay system · Battle Pass

**Priority 4 (Post-launch / gated):** tournament mode · UGC · custom lobbies · spectator mode · No-Doom Assignment Rule *(only if fairness metrics demand it)* · Legacy Scoring experiments *(gated by fairness playtest)*

---

## 11. Testing Strategy

### Unit Testing

Test pure-logic modules in isolation:
- Derangement algorithm always produces valid swap permutations *(Sattolo: assert no fixed point for n≥2)*
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
- **Dedicated fairness playtest:** measure whether inherited death feels fair after grace + preview (gates GDD §12)

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

*End of Technical Design Document — v1.3 (split from combined GDD+TDD on 2026-06-17). Design content: see [body-swap-royale-gdd.md](body-swap-royale-gdd.md).*
