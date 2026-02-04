# MAP.md — ZapZap Shared

## Component Role
This is the **shared code module** — all game logic, rendering, assets, and audio live here. Both the iOS and macOS targets compile these same files. This directory IS the game; the platform targets are thin wrappers.

## Directory Structure

| Path | Role |
|------|------|
| `GFX LOGIC/` | Rendering pipeline: Metal renderer, graphics layers, animation system, screen management |
| `GAME LOGIC/` | Simulation: Game state machine, board logic, tile connections, multiplayer, bot AI |
| `MESHES/` | Geometry: Quad meshes, segment strips, electric arcs, particles, UI buttons, text rendering |
| `Sound LOGIC/` | Audio: Background music and sound effects via AVFoundation |
| `Assets.xcassets/` | Texture atlases (tiles, arrows, stars, superhero, tutorials, company logo), app icons |
| `AudioResources/` | 19 audio files: 12 standard + 7 Halloween variants (.wav effects, .mp3 music) |

## Root-Level Files

### `Math.swift`
- `simd_float4x4` extensions: orthographic projection, perspective projection, 2D/3D transforms
- `align()` utility for constant buffer alignment
- **Connects to:** Used by `Mesh.updateModelMatrix()` and `Renderer.updateConstants()`

### `ObjectPool.swift`
- Generic `ObjectPool<T: Poolable>` with pre-allocation, get, and release
- `AnimationPools` static class: pre-allocated pools for RotateAnimation (10), ParticleAnimation (50), FallAnimation (50), FreezeFrameAnimation (10), Particle (1000)
- **Connects to:** Used by `AnimationManager` to avoid GC pressure during gameplay

### `ShaderTypes.h`
- Bridging header defining `BufferIndex`, `VertexAttribute`, `TextureIndex` enums
- `UniformScene` (projection matrix) and `UniformModel` (model matrix + alpha) structs
- **Connects to:** Shared between Metal shaders and Swift code via Xcode bridging

## Refactor Risk
- **HIGH RISK (Coupling):** The `GAME LOGIC` and `GFX LOGIC` directories have circular dependencies. `GameManager` directly references `Renderer` layers, and `Renderer` directly mutates `GameManager` state. Separating simulation from rendering is the primary refactor goal.
