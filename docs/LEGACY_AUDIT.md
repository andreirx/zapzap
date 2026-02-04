# LEGACY_AUDIT.md — ZapZap Core Game Loop & WASM Migration Analysis

> Generated: 2026-02-04 | Branch: `multiplayer` | Commit: `5482fa4`

---

## 1. Executive Summary

ZapZap is a custom-engine Metal game (~4,500 lines of Swift + 52 lines of MSL) implementing a connection puzzle on a 12x10 tile grid. The architecture follows a monolithic pattern where a single `Renderer.draw(in:)` call drives the entire application: projection setup, input processing, game logic, animation, and GPU command encoding — all on the main thread, all in one frame callback.

**Critical finding:** The game has **zero separation** between simulation and presentation. `GameManager` mutates renderer layers directly; `Renderer.update()` runs game state transitions. This is the primary obstacle for a WASM port, where simulation must run in a Worker thread independent of the rendering surface.

---

## 2. The Core Game Loop

### Frame Pipeline (`Renderer.draw(in:)` — `Renderer.swift:1168`)

```
┌──────────────────────────────────────────────────────────────────┐
│ MTKViewDelegate.draw(in:)  —  Called by MetalKit at display rate │
├──────────────────────────────────────────────────────────────────┤
│ 1. inFlightSemaphore.wait()        ← Block if GPU is 3 frames behind  │
│ 2. updateConstants()                ← Compute orthographic projection  │
│ 3. update()                         ← ALL GAME LOGIC (see below)       │
│ 4. commandQueue.makeCommandBuffer() ← Begin GPU work                   │
│ 5. currentScreen.render(encoder:)   ← Encode all draw calls            │
│ 6. present(drawable)                ← Schedule display                  │
│ 7. commandBuffer.commit()           ← Submit to GPU                    │
│ 8. frameIndex += 1                  ← Advance frame counter            │
└──────────────────────────────────────────────────────────────────┘
```

### The `update()` Method (`Renderer.swift:813`) — WHERE EVERYTHING HAPPENS

This single method handles ALL non-rendering game logic per screen:

| Screen | What `update()` does |
|--------|---------------------|
| **Logo** | Fade in/out logo quad, trigger `initializeGameScreens()` at frame 65, auto-transition to menu |
| **Game** | Process button taps (pause, 6 power-up buttons), update power-up alpha states, call `gameMgr.update()`, update all GameObjects |
| **Main Menu** | Random tile rotation, check menu button taps (Zen/Bot/Tutorial/Multiplayer) |
| **Purchase** | Check back button |
| **Tutorial** | Check prev/next/close buttons, swap tutorial images |
| **Pause** | Check back/quit/toggle-music/toggle-effects buttons |

### `GameManager.update()` (`GameManager.swift`) — THE SIMULATION TICK

Called from `Renderer.update()` when on the game screen:

```
GameManager.update()
├── Process lastInput → tapTile()
│   ├── Check if armed power-up → bombTable() / crossTile() / arrowColumn()
│   └── Otherwise → rotate tile → start RotateAnimation
├── animationManager.updateAnimations()
│   ├── FreezeFrameAnimation (blocks all others)
│   ├── RotateAnimation → on complete: checkConnections() → addElectricArcs()
│   ├── FallAnimation → on complete: checkConnections() → addElectricArcs()
│   ├── ParticleAnimation → on complete: cleanup
│   ├── ObjectFallAnimation → on complete: set waitingForInput
│   └── TextAnimation → on complete: cleanup
├── Check for ZAP (complete connection)
│   ├── Yes → FreezeFrameAnimation → removeAndShiftConnectingTiles() → FallAnimations
│   └── No → remain in waitingForInput
├── Bot move (if bot active, via DispatchQueue.global)
│   └── determineNextMove() → tapTile() with delay
└── Drop bonus objects periodically
```

---

## 3. State Machines

### Primary: `ZapGameState` (`GameManager.swift`)

```
                    ┌─────────────┐
                    │ waitingFor  │◄────────────────────────────────┐
                    │   Input     │                                 │
                    └──────┬──────┘                                 │
                           │ tapTile()                              │
                    ┌──────▼──────┐                                 │
                    │ rotatingTile│                                 │
                    └──────┬──────┘                                 │
                           │ animation complete                     │
                    ┌──────▼──────┐     ┌──────────────┐           │
                    │ checkConnect├────►│ freezeDuring │           │
                    │   ions      │ zap │     Zap      │           │
                    └──────┬──────┘     └──────┬───────┘           │
                           │ no zap            │ freeze done       │
                    ┌──────▼──────┐     ┌──────▼───────┐           │
                    │ fallingTiles│◄────┤ remove tiles  │           │
                    └──────┬──────┘     │ + new tiles   │           │
                           │ done      └───────────────┘           │
                           └───────────────────────────────────────┘

                    Special states:
                    - freezeDuringBomb → fallingTiles → waitingForInput
                    - fallingBonuses → waitingForInput
                    - gameOver (terminal, requires menu transition)
```

### Secondary: `GameScreen` (implicit in `Renderer.currentScreen`)

```
logoScreen → mainMenuScreen ←→ tutorialScreen
                  │    ↑          purchaseScreen
                  ▼    │          pauseScreen
             gameScreen ──→ pauseScreen ──→ mainMenuScreen
                  │                              ↑
                  └──── gameOver ─────────────────┘
```

---

## 4. CPU-Intensive Functions

### 4.1 `BotPlayer.determineNextMove()` — `BotPlayer.swift:17`
**Category:** CPU-Intensive (Brute-Force Search)

**What it does:** Deep-copies the entire `GameBoard`, then iterates over all 120 tiles × 3 rotations = 360 evaluations. Each evaluation runs `checkConnections()` (a recursive flood-fill).

**Cost:** O(W × H × 3 × flood_fill) = O(12 × 10 × 3 × 120) = ~43,200 operations per bot move.

**Current mitigation:** Runs on `DispatchQueue.global(qos: .background)` — but the deep copy and flood-fill are still O(n) allocations.

**WASM proposal:**
- Move to Rust with a flat `[u8; 120]` board representation (no heap allocation per tile).
- Replace recursive flood-fill with iterative BFS using a pre-allocated stack.
- Use `rayon` for parallel evaluation of rotation candidates.
- Expose via `SharedArrayBuffer` for zero-copy transfer of best-move result.

---

### 4.2 `GameBoard.checkConnections()` — `GameBoardLogic.swift`
**Category:** CPU-Intensive (Recursive Flood-Fill)

**What it does:** Dual-origin flood-fill from left pins (column 0) and right pins (column W-1). Uses recursive `expandConnectionsMarkings()` that follows matching tile edges.

**Cost:** O(W × H) per call, called:
- After every tile rotation (1× per tap)
- After every fall animation completes (potentially cascading)
- During bot evaluation (360× per bot move)

**Risk:** Recursive DFS with max depth = W × H = 120. Not dangerous for current board size, but would stack-overflow on larger boards.

**WASM proposal:**
- Rewrite as iterative BFS with `VecDeque<(u8, u8)>` work queue.
- Pre-allocate marking arrays as flat `[Connection; 120]`.
- Return connection state as a bitmask for zero-copy sharing.

---

### 4.3 `ElectricArc.generatePoints()` — `ElectricArcMesh.swift:57`
**Category:** CPU-Intensive (Per-Frame Procedural Generation)

**What it does:** Recursive midpoint displacement algorithm. Called via `twitchPoints()` every frame for every visible electric arc.

**Cost per arc:** O(2^n) where n = `powerOfTwo` (typically 3-4, so 8-16 points). But there can be 10-20 arcs visible simultaneously, and `remakeVertices()` regenerates the full triangle strip each frame.

**WASM proposal:**
- Compute arc points in a Rust compute shader equivalent (WebGPU compute pass).
- Use a persistent vertex buffer with partial updates instead of full regeneration.
- Amortize twitching: update arcs at 30fps, render at 60+fps with interpolation.

---

### 4.4 `SegmentStripMesh.remakeVertices()` — `SegmentStripeMesh.swift:185`
**Category:** CPU-Intensive (Vertex Buffer Regeneration)

**What it does:** Rebuilds the entire vertex and index arrays for a segment strip, then calls `updateBuffers()` to memcpy to GPU. Called every frame for every particle and electric arc.

**Cost:** With 1000 pre-allocated particles and ~20 arcs, this is potentially 1020 vertex buffer rebuilds per frame.

**WASM proposal:**
- Use GPU-side particle simulation (compute shader writing to a storage buffer).
- Instance rendering instead of per-particle draw calls.
- Electric arcs: write points to a storage buffer, generate strips in vertex shader.

---

## 5. Memory-Heavy Functions

### 5.1 `ResourceTextures.loadTextures()` — `Renderer.swift:37`
**Category:** Memory-Heavy (Bulk Texture Loading)

**What it does:** Loads 7 texture atlases synchronously at frame 65 via `MTKTextureLoader`. Uses `MTLStorageMode.private` (GPU-only), which is correct, but the loading blocks the main thread.

**Textures loaded:** arrows, base_tiles, stars, superhero, tutorials, base_tiles_haloween, arrows_haloween

**WASM proposal:**
- Use `createImageBitmap()` + `GPUDevice.createTexture()` with async loading.
- Implement a loading screen with progress indicator.
- Consider texture compression (BCn/ASTC → WebGPU compressed texture formats).

---

### 5.2 `TextQuadMesh.createTextureFromImage()` — `Meshes.swift:224`
**Category:** Memory-Heavy (Runtime Texture Allocation)

**What it does:** Allocates a CGContext + raw pixel buffer (`calloc`), rasterizes text, creates an MTLTexture, uploads pixels. Called for every text mesh: score displays, button labels, floating score popups.

**Risk:** Each `TextAnimation` creates a new `TextQuadMesh` (new texture allocation). During high-scoring chains, multiple text animations can spawn per second.

**WASM proposal:**
- Use Canvas 2D `measureText()` + `drawText()` → `GPUTexture` for static text.
- For dynamic text (scores, popups): use a **glyph atlas** with pre-rasterized digits 0-9, +, -, and compose at the vertex level.
- Alternative: SDF (Signed Distance Field) text rendering for resolution-independent text.

---

### 5.3 `AnimationPools` Pre-allocation — `ObjectPool.swift:57`
**Category:** Memory-Heavy (Upfront Allocation)

**What it does:** Pre-allocates at startup:
- 10 RotateAnimations
- 50 ParticleAnimations
- 50 FallAnimations
- 10 FreezeFrameAnimations
- 1000 Particles (each with its own MTLBuffer)

**Risk:** 1000 particles × (vertexBuffer + indexBuffer + uniformBuffer) = 3000 MTLBuffer allocations at startup. Each `Particle` also inherits from `SegmentStripMesh` → full vertex array generation.

**WASM proposal:**
- Replace per-particle buffers with a single instance buffer.
- Use `GPUBuffer` with `MAP_WRITE` for streaming particle data.
- Target: 1 draw call for all particles via instanced rendering.

---

### 5.4 `GameBoard.copy()` — `GameBoardLogic.swift`
**Category:** Memory-Heavy (Deep Copy for Bot)

**What it does:** Creates a complete deep copy of the board (120 Tile objects + connection arrays + marking arrays). Called once per bot evaluation (per move).

**WASM proposal:**
- Use a flat `[u8; 120]` representation that can be `memcpy`'d in O(1) pointer arithmetic.
- In Rust: `#[derive(Clone, Copy)]` on the board struct for stack-allocated copies.

---

## 6. Main-Thread-Bound Logic

### 6.1 `Renderer.update()` — `Renderer.swift:813` — **CRITICAL**
**Category:** Main-Thread-Bound (Blocks Frame)

**Everything** in `update()` runs synchronously on the main thread inside `draw(in:)`:
- Input processing
- Game state machine transitions
- Animation updates (including 1000+ particle physics)
- Electric arc regeneration
- Button alpha state updates (12 power-up buttons × alpha calculation)
- Bot move result processing
- Object spawning

**WASM proposal:**
- **Simulation Worker:** Move `GameManager.update()`, `AnimationManager.updateAnimations()`, and `BotPlayer` to a Web Worker running WASM.
- **Render Thread:** Main thread only handles: input capture → post to worker, read `SharedArrayBuffer` → encode WebGPU commands.
- **State Sync:** Simulation writes to a `SharedArrayBuffer`-backed flat state. Renderer reads it each frame. Lock-free via double-buffering.

---

### 6.2 `Renderer.initializeGameScreens()` — `Renderer.swift:303` — **CRITICAL**
**Category:** Main-Thread-Bound (Blocks Frame, causes visible hitch)

**What it does at frame 65:**
- Loads 7 texture atlases (synchronous disk I/O + GPU upload)
- Creates 20+ layers
- Generates ~100 menu background tile quads
- Creates 20+ button meshes with vertex buffers
- Creates 10+ text meshes (text rasterization + texture upload)
- Sets up game board tiles (120 quads)

**This all happens in a single frame**, causing a visible pause hidden behind the logo screen.

**WASM proposal:**
- Async resource loading with `fetch()` + streaming decode.
- Progressive initialization across multiple frames.
- Show a loading bar during setup.

---

### 6.3 `Mesh.updateModelMatrix()` — `Meshes.swift:69`
**Category:** Main-Thread-Bound (Per-Draw CPU Cost)

**What it does:** Computes `translation × rotation × scale` matrix and `memcpy`s to the uniform buffer. Called in `draw(encoder:)` for EVERY mesh EVERY frame.

**Cost estimate:** ~200 meshes × (3 matrix multiplies + memcpy) per frame = 600 matrix operations + 200 memcpys.

**WASM proposal:**
- Dirty-flag pattern: only recompute when position/rotation/scale actually changes.
- In WebGPU: use a single dynamic uniform buffer with offsets, or a storage buffer with instanced drawing.
- For static meshes (buttons, backgrounds): compute matrix once, never update.

---

### 6.4 `Particle.draw()` — `ParticleEffects.swift:51`
**Category:** Main-Thread-Bound (Physics in Render)

**What it does:** Runs `update()` (physics: attract + friction + position) inside `draw()`, then rebuilds vertices, then issues a draw call. This means particle physics is coupled to frame rate and runs on the render thread.

**WASM proposal:**
- Decouple particle simulation from rendering.
- Run particle physics in the simulation worker.
- Write particle positions to a `SharedArrayBuffer`.
- Renderer reads positions and draws instanced quads.

---

## 7. Coupling Analysis — The Separation Problem

### Renderer → GameManager (should not exist in WASM)
| Location | Coupling |
|----------|----------|
| `Renderer.update()` | Reads/writes `gameMgr.lastInput`, `gameMgr.zapGameState`, calls `gameMgr.update()` |
| `Renderer.update()` | Reads/writes 12 power-up booleans on `gameMgr` |
| `Renderer.update()` | Calls `gameMgr.startNewGame()`, `gameMgr.addBot()` |
| `Renderer.setCurrentScreen()` | Calls `gameMgr.clearElectricArcs()`, `gameMgr.addElectricArcs()` |
| `Renderer.initializeGameScreens()` | Calls `gameMgr.createTiles()` |

### GameManager → Renderer (should not exist in WASM)
| Location | Coupling |
|----------|----------|
| `GameManager.updateScoreLeft/Right()` | Calls `renderer!.updateText()` and creates `TextAnimation` on `renderer!.textLayer` |
| `GameManager.addElectricArcs()` | Appends to `renderer!.effectsLayer.meshes` |
| `GameManager.clearElectricArcs()` | Removes from `renderer!.effectsLayer.meshes` |
| `GameManager.remakeElectricArcs()` | Directly mutates `renderer!.effectsLayer` |
| `GameManager.dropCoins()` | Creates `ObjectFallAnimation` targeting `renderer!.objectsLayer` |
| `AnimationManager` callbacks | Sets `zapGameState`, calls `checkConnections()`, mutates renderer layers |

### How to Break the Coupling for WASM

```
Current:
  Renderer ←──mutual refs──→ GameManager
       ↕                          ↕
  GraphicsLayer              GameBoard

Target:
  [Main Thread]              [Worker Thread]
  ┌───────────┐              ┌─────────────────┐
  │ WebGPU    │◄─SharedBuf──►│ WASM Simulation  │
  │ Renderer  │              │ (GameManager)    │
  │           │  ←Commands── │ (AnimationMgr)   │
  │           │              │ (BotPlayer)      │
  └───────────┘              └─────────────────┘
       ↑                          ↑
   Input Events              Command Queue
   (postMessage)             (from Main Thread)
```

**Required refactors before port:**
1. Extract a `SimulationState` struct that contains ALL mutable game state (board, scores, power-ups, animation states, particle positions).
2. Make `GameManager.update()` return a `FrameDelta` (what changed) instead of mutating renderer layers.
3. The renderer reads `SimulationState` and applies visual changes — no back-references.

---

## 8. File-by-File Risk Matrix

| File | Lines | CPU | Memory | Main-Thread | Coupling | WASM Priority |
|------|-------|-----|--------|-------------|----------|--------------|
| `Renderer.swift` | 1230 | Low | Med | **HIGH** | **HIGH** | **P0** — Must decompose |
| `GameManager.swift` | 946 | Med | Low | **HIGH** | **HIGH** | **P0** — Must decouple |
| `GameBoardAnimations.swift` | 961 | Med | Low | **HIGH** | Med | **P1** — Extract state transitions |
| `GameBoardLogic.swift` | 395 | **HIGH** | Low | Med | Low | **P1** — Port to Rust (perf-critical) |
| `BotPlayer.swift` | 100 | **HIGH** | Med | Low* | Low | **P1** — Port to Rust (pure logic) |
| `Meshes.swift` | 319 | Med | Med | Med | Low | **P2** — Replace with WebGPU buffers |
| `SegmentStripeMesh.swift` | 273 | Med | Low | Med | Low | **P2** — Move to compute shader |
| `ParticleEffects.swift` | 104 | Med | Med | Med | Low | **P2** — GPU particle system |
| `ElectricArcMesh.swift` | 113 | Med | Low | Med | Low | **P2** — Compute shader |
| `UIMeshes.swift` | 178 | Low | Low | Low | Low | **P3** — Replace with HTML/Canvas UI |
| `GraphicsLayer.swift` | 217 | Low | Low | Low | Low | **P3** — Maps to WebGPU pipeline |
| `Screen.swift` | 39 | Low | Low | Low | Low | **P3** — Trivial container |
| `MultiplayerManager.swift` | 464 | Low | Low | Low | Med | **P3** — Replace with WebSocket/WebRTC |
| `SoundManager.swift` | 139 | Low | Low | Low | Low | **P3** — Replace with Web Audio API |
| `GameObjects.swift` | 139 | Low | Low | Low | Low | **P3** — ECS components |
| `ObjectPool.swift` | 64 | Low | Med | Low | Low | **P3** — Rust allocator / arena |
| `Math.swift` | 99 | Low | Low | Low | Low | **P3** — `glam` crate |
| `Shaders.metal` | 52 | Low | Low | Low | Low | **P3** — WGSL translation |
| `ShaderTypes.h` | 53 | Low | Low | Low | Low | **P3** — Rust struct definitions |

*BotPlayer runs on background queue but deep-copies game state on main thread

---

## 9. Proposed WASM Migration Order

### Phase 1: Decouple (Swift refactor, no WASM yet)
1. Extract `SimulationState` from `GameManager` — pure data, no renderer references.
2. Make `AnimationManager` output state deltas instead of mutating layers directly.
3. Create a `RenderCommands` struct that `Renderer` reads each frame.
4. Remove all `renderer!.` references from `GameManager`.

### Phase 2: Port Core Logic to Rust/WASM
1. `GameBoard` → Rust struct with flat array representation.
2. `checkConnections()` → Iterative BFS in Rust.
3. `BotPlayer.determineNextMove()` → Rust with `rayon` parallelism.
4. `AnimationManager` state machine → Rust ECS (Bevy).

### Phase 3: WebGPU Renderer
1. Port shaders: MSL → WGSL (vertex_main, sprite_fragment_main, additive_fragment_main).
2. Surface format: `rgba16float` + `"display-p3"` extended colorspace for EDR.
3. Instanced rendering for particles and electric arcs.
4. Compute shader for particle physics and arc point generation.

### Phase 4: Platform Integration
1. Replace UIKit/AppKit input with Canvas pointer events.
2. Replace AVFoundation with Web Audio API.
3. Replace Game Center with a custom WebSocket leaderboard.
4. Replace StoreKit with Stripe/web payment flow.

---

## 10. EDR/HDR Rendering — Critical Notes for WebGPU Port

The game intentionally renders beyond the standard 0.0–1.0 color range:

- **Surface format:** `.rgba16Float` (16-bit float per channel)
- **Colorspace:** `extendedLinearDisplayP3` (extended dynamic range)
- **`wantsExtendedDynamicRangeContent = true`** on `CAMetalLayer`
- **Additive fragment shader** multiplies color by `6.4`, producing luminance values >1.0 that appear as bright HDR glow on supported displays
- **Power-up armed state** sets button alpha to `3.0` — superbright via the alpha uniform multiplication

**WebGPU equivalent:**
```javascript
const context = canvas.getContext('webgpu');
context.configure({
  device,
  format: 'rgba16float',
  colorSpace: 'display-p3',
  toneMapping: { mode: 'extended' },  // Critical: enables EDR
});
```

This is non-negotiable for visual fidelity — the electric arcs and particle effects rely on HDR glow to look correct.
