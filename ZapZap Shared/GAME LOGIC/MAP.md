# MAP.md — GAME LOGIC (Simulation & State)

## Component Role
The **game simulation subsystem**. Contains the core game rules, board state management, connection-checking algorithms, scoring, power-up logic, bot AI, and multiplayer networking. This is the "brain" of the game.

## Files

### `GameManager.swift` (946 lines) — **HIGH RISK**
**Role:** Central orchestrator for all gameplay.

**Key Responsibilities:**
- Holds the `GameBoard` (simulation), `AnimationManager`, and weak `Renderer` reference
- Manages `ZapGameState` (11-state machine)
- Tile creation, rotation, and quad management (`tileQuads[][]`)
- Score tracking (left/right scores for multiplayer, combined for zen)
- Power-up state (6 power-ups × acquired/armed booleans = 12 bools)
- Bot integration (`BotPlayer` triggering via `DispatchQueue.global`)
- Core gameplay methods: `tapTile()`, `checkConnectionsAndStartZap()`, `bombTable()`, `dropCoins()`
- Frame-by-frame `update()` method: processes input, runs bot, updates animations, checks connections
- Electric arc management (create/clear/remake per board state change)

**State Machine (`ZapGameState`):**
```
waitingForInput → rotatingTile → fallingTiles → waitingForInput (normal cycle)
               → freezeDuringZap → fallingBonuses → waitingForInput (zap cycle)
               → freezeDuringBomb → fallingTiles → waitingForInput (bomb cycle)
               → gameOver (terminal)
waitingForOrange, waitingForIndigo, superheroBeforeDrop, superheroAfterDrop (unused/planned)
```

**Why HIGH RISK:** Directly references `renderer!.objectsLayer`, `renderer!.effectsLayer`, `renderer!.textLayer` throughout. The simulation layer cannot run without a renderer attached. For WASM, the simulation must be fully decoupled.

### `GameBoardLogic.swift` (395 lines) — MEDIUM RISK
**Role:** Pure board state and connection logic.

**Key Classes:**
- `Tile` — Single tile with 4-bit connection mask (UDLR). Supports `rotate()` and `hasConnection(direction:)`.
- `BoardConnections` — 2D array of `Tile?` (width × height). Codable for network serialization.
- `Direction` — `OptionSet` for bitwise direction checking (right=0x01, up=0x02, left=0x04, down=0x08)
- `GameBoard` — Full board state:
  - `connections: BoardConnections` — the tile grid
  - `connectMarkings: [[Connection]]` — flood-fill results (none/left/right/ok/animating)
  - `multiplierLeft/Right: [Int]` — per-row score multipliers
  - `rng: GKMersenneTwisterRandomSource` — seedable RNG for deterministic multiplayer

**Key Algorithms:**
- `checkConnections()` — **Recursive flood-fill** from both sides. Marks tiles as `.left`, `.right`, or `.ok` (both sides connected). Returns 1 if any complete connection exists.
- `expandConnectionsMarkings()` — Recursive DFS that propagates connection markers through matching tile edges.
- `getNewElement()` — RNG-based tile generation with "missing link" ratio enforcement (prevents too many dead-end tiles).
- `removeAndShiftConnectingTiles()` — Column-wise gravity: removes `.ok` tiles, shifts above down, generates new at top.
- `bombTable()` — Area-of-effect removal with column gravity.

**Why MEDIUM RISK:** Mostly pure logic, but `Connection` enum is used both as a board marking AND a sentinel for animation state (`.animating`), conflating two concerns. Also, the flood-fill is recursive (stack overflow risk on very large boards, though 12x10 is safe).

### `GameObjects.swift` (139 lines) — LOW RISK
**Role:** Game entity definitions (bonuses and power-ups).

**Classes:**
- `GameObject(QuadMesh)` — Base class with rotation, pulsating scale, sound, tile position, bonus points. Contains a static `objectFactory` dictionary for type-safe instantiation.
- `Bonus1`, `Bonus2`, `Bonus5` — Score pickups (1/2/5 points, different brightness)
- `Bomb` — Area-of-effect power-up
- `Cross` — Sets tile to all-connections (0x0F)
- `Arrow` — Column-clear power-up

**Why LOW RISK:** Clean entity hierarchy. Maps directly to ECS components.

### `MultiplayerManager.swift` (464 lines) — MEDIUM RISK
**Role:** Game Center multiplayer integration.

**Capabilities (partially implemented):**
- Player authentication and Game Center UI presentation
- Matchmaking (GKMatchmakerViewController)
- Score reporting to leaderboard ("MaxPoints")
- Data sending/receiving with message types: `SEED` (UInt64), `TAP@` (x,y coordinates), `GBRD` (JSON-encoded board state)
- Host determination (lowest player index)
- Custom macOS presentation animator

**Why MEDIUM RISK:** Lots of `TODO actual code` comments — the multiplayer data handling is stubbed. The architecture is sound but incomplete. Contains platform-specific UI code (`#if os(iOS)` / `#if os(macOS)`).

### `BotPlayer.swift` (100 lines) — LOW RISK
**Role:** AI opponent using brute-force evaluation.

**Algorithm:**
1. Deep-copy the `GameBoard`
2. For each tile (skip dead-ends and full-connections):
   - Try 1, 2, 3 rotations
   - Run `checkConnections()` on the copy
   - Score: complete connections (`ok`) = 2 points per tile; partial (`right`) = 1 point; right-pin connections = +3 bonus
3. Return the best (tile, rotationCount) pair
4. Runs on `DispatchQueue.global(qos: .background)` with 1.0–2.0s simulated "thinking" delay

**Why LOW RISK:** Pure logic, no rendering dependencies. Deep copies the board for evaluation. Direct port to WASM/Rust.

## Connections to Architecture
- `GameManager` ← owned by → `Renderer` (created in `GameViewController.viewDidLoad()`)
- `GameManager` ← holds → `GameBoard` (simulation state)
- `GameManager` ← holds → `AnimationManager` (from GFX LOGIC)
- `GameManager` ← weak ref → `Renderer` (for layer access — **coupling issue**)
- `BotPlayer` ← weak ref → `GameBoard` (read-only evaluation via deep copy)
- `MultiplayerManager` ← owned by → `Renderer` (not `GameManager` — architectural oddity)

## Refactor Risk Summary
- `GameManager.swift`: **HIGH** — Simulation + rendering mixed. Must extract pure simulation for WASM.
- `GameBoardLogic.swift`: **MEDIUM** — Good logic, but Connection enum overloaded. Recursive flood-fill.
- `MultiplayerManager.swift`: **MEDIUM** — Incomplete implementation, platform-specific UI.
- `GameObjects.swift`: **LOW** — Clean entity definitions.
- `BotPlayer.swift`: **LOW** — Pure algorithm, no dependencies on rendering.
