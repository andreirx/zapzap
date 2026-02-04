# MAP.md — ZapZap Project Root

## Component Role
ZapZap is a **match-three / connection puzzle game** built with Swift and Metal for iOS and macOS. Players rotate tiles on a 12x10 grid to form electrical connections between left and right pins, triggering "zap" chains that score points. The game features Zen mode (single-player), Vs Bot mode, and a planned (incomplete) multiplayer mode via Game Center.

## Architecture Overview

```
ZapZap/
├── ZapZap iOS/          → iOS platform target (AppDelegate, GameViewController, input handling)
├── ZapZap macOS/        → macOS platform target (AppDelegate, GameViewController, input handling)
├── ZapZap Shared/       → ALL game logic, rendering, meshes, audio (shared between both targets)
│   ├── GFX LOGIC/       → Metal renderer, graphics layers, animation system, screen management
│   ├── GAME LOGIC/      → Game state machine, board logic, multiplayer, bot AI
│   ├── MESHES/          → Geometry generation (quads, segments, particles, electric arcs, UI buttons)
│   ├── Sound LOGIC/     → Audio playback manager (AVFoundation)
│   ├── Assets.xcassets/ → Texture atlases, app icons, color assets
│   ├── AudioResources/  → 19 audio files (standard + Halloween variants)
│   ├── Math.swift       → SIMD matrix utilities (projection, rotation, translation, scale)
│   ├── ObjectPool.swift → Generic object pooling system for animations and particles
│   └── ShaderTypes.h    → C/ObjC bridging header (shared structs between Metal & Swift)
├── ZZWorkspace.xcworkspace → Xcode workspace (dual-target)
├── docs/                → Architecture documentation
└── CLAUDE.md            → Engineering guidelines for migration
```

## Key Classes — Where Things Live

| Concern | File | Class/Struct |
|---------|------|-------------|
| **Main Loop** | `GFX LOGIC/Renderer.swift` | `Renderer.draw(in:)` → `update()` → per-screen logic |
| **State Machine** | `GAME LOGIC/GameManager.swift` | `ZapGameState` enum (11 states) |
| **Board Simulation** | `GAME LOGIC/GameBoardLogic.swift` | `GameBoard` (connections, flood-fill, tile gen) |
| **Renderer** | `GFX LOGIC/Renderer.swift` | `Renderer` (MTKViewDelegate, Metal command encoding) |
| **Animation System** | `GFX LOGIC/GameBoardAnimations.swift` | `AnimationManager` (7 animation types) |
| **GPU Shaders** | `GFX LOGIC/Shaders.metal` | `vertex_main`, `sprite_fragment_main`, `additive_fragment_main` |
| **Input Handling** | `iOS/GameViewController.swift`, `macOS/GameViewController.swift` | `touchesEnded`, `mouseUp` |

## Rendering Pipeline
1. Pixel format: `.rgba16Float` with `extendedLinearDisplayP3` colorspace → **EDR/HDR capable**
2. Two blend modes: Standard alpha (`GraphicsLayer`) and Additive (`EffectsLayer` with 6.4x multiplier)
3. Orthographic 2D projection, per-instance model matrix + alpha uniform
4. Screen → Layer → Mesh hierarchy; each Screen renders its layers in order

## Refactor Risk Summary
- **HIGH RISK:** `Renderer.swift` (1230 lines) — Monolithic god class mixing UI logic, game state transitions, screen management, input handling, and rendering. This is the #1 refactor target.
- **HIGH RISK:** `GameManager.swift` (946 lines) — Couples simulation logic with rendering layer references (`renderer!.objectsLayer`, etc.)
- **MEDIUM RISK:** `GameBoardAnimations.swift` (961 lines) — Large file but well-structured animation system with object pooling
- **LOW RISK:** Pure data/geometry files (Math.swift, Meshes.swift, SegmentStripeMesh.swift, etc.)
