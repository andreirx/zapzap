# MAP.md — GFX LOGIC (Rendering & Animation)

## Component Role
The **graphics and animation subsystem**. Contains the Metal renderer, the layered rendering architecture, the screen management system, and the entire animation pipeline. This is the visual heart of the game.

## Files

### `Renderer.swift` (1230 lines) — **HIGH RISK**
**Role:** Monolithic rendering + UI orchestrator. Implements `MTKViewDelegate`.

**Key Responsibilities:**
- Metal device/command queue setup
- Texture resource management (`ResourceTextures` class with ambience/theme system)
- Screen creation and transition management (logo → menu → game → pause → tutorial)
- All button creation and positioning (20+ ButtonMesh instances)
- Input dispatching (tap → which button → what action)
- Game state transitions (via `update()` called every frame)
- Power-up arm/disarm UI logic
- The main `draw(in:)` render loop: semaphore wait → update constants → update game → encode → present
- Orthographic projection calculation with aspect-ratio fitting
- Coordinate conversion (screen pixels → game units)

**Why HIGH RISK:** This file mixes rendering, UI logic, input handling, screen management, and game state transitions. In a WASM port, these need to be 4-5 separate systems.

**Key Method — The Render Loop:**
```
draw(in:) → inFlightSemaphore.wait()
         → updateConstants()     // projection matrix
         → update()              // ALL game logic per screen
         → makeCommandBuffer()
         → currentScreen.render(encoder:)
         → present(drawable)
         → commandBuffer.commit()
```

### `GraphicsLayer.swift` (217 lines) — LOW RISK
**Role:** Abstraction layer between the renderer and mesh drawing.

**Classes:**
- `VertexDescriptor` — Shared Metal vertex layout (float3 position + float2 texcoord, stride 20 bytes)
- `GraphicsLayer` — Standard layer with texture + meshes array, alpha blending pipeline (srcAlpha/oneMinusSrcAlpha)
- `GameBoardLayer(GraphicsLayer)` — Specialized layer that draws the tile grid from `GameManager.tileQuads[][]`
- `EffectsLayer(GraphicsLayer)` — Additive blending pipeline (src=one, dst=one) for EDR/HDR glow effects. Also manages particles and electric arc twitching per frame.

**Pixel Format:** All pipelines use `.rgba16Float` → 16-bit float per channel → HDR/EDR support

### `GameBoardAnimations.swift` (961 lines) — MEDIUM RISK
**Role:** The animation system. Manages 7 types of animations via `AnimationManager`.

**Animation Types:**
| Type | Class | Pooled? | Purpose |
|------|-------|---------|---------|
| Tile Rotation | `RotateAnimation` | Yes | 90° tile rotation with arrow overlay |
| Menu Tile Rotation | `SimpleRotateAnimation` | No | Decorative background tile spin |
| Tile Falling | `FallAnimation` | Yes | Gravity-based tile drop (9.8 g, friction 0.005) |
| Particle Burst | `ParticleAnimation` | Yes | Explosion effects on tile removal |
| Freeze Frame | `FreezeFrameAnimation` | Yes | Pause all other animations during zap display |
| Object Falling | `ObjectFallAnimation` | No | Bonus items falling from sky |
| Floating Text | `TextAnimation` | No | Score pop-ups (+1, +5, etc.) |

**Why MEDIUM RISK:** Well-structured with `Animation` protocol and object pooling, but coupled to `GameManager` via weak reference for state transitions (e.g., setting `zapGameState = .waitingForInput` when falls complete).

### `Screen.swift` (39 lines) — LOW RISK
**Role:** Simple container that holds an ordered list of `GraphicsLayer` instances and renders them in sequence.

### `Shaders.metal` (52 lines) — LOW RISK
**Role:** All GPU shader code.

**Shaders:**
- `vertex_main` — Standard 2D transform: `projectionMatrix * modelMatrix * position`
- `sprite_fragment_main` — Texture sample × alpha uniform (standard blending)
- `additive_fragment_main` — Texture sample × 6.4 × alpha uniform (EDR glow, additive blending)

**Note for WASM Port:** The 6.4x multiplier in `additive_fragment_main` exceeds the 0.0–1.0 SDR range intentionally — it produces visible HDR glow on EDR-capable displays. WebGPU equivalent needs `rgba16float` surface + extended color space support.

## Connections to Architecture
- `Renderer` ← creates → `Screen` objects, each containing → `GraphicsLayer` / `EffectsLayer` instances
- `Renderer` ← owns → `GameManager` (calls `gameMgr.update()` every frame)
- `Renderer` ← owns → `MultiplayerManager`
- `GraphicsLayer` ← contains → `Mesh` subclass instances (drawn per frame)
- `AnimationManager` ← owned by → `GameManager` (not `Renderer`)
- `EffectsLayer.render()` calls `ElectricArcMesh.twitch()` → procedural animation in the render pass

## Refactor Risk Summary
- `Renderer.swift`: **HIGH** — God class. Must decompose into: RenderBackend, ScreenManager, InputRouter, UIBuilder
- `GameBoardAnimations.swift`: **MEDIUM** — Good pooling pattern, but animation completion callbacks mutate game state
- `GraphicsLayer.swift`: **LOW** — Clean abstraction, maps well to WebGPU render pipeline
- `Screen.swift`: **LOW** — Trivial container
- `Shaders.metal`: **LOW** — Simple shaders, direct WGSL translation possible
