# MAP.md — MESHES (Geometry & Visualization)

## Component Role
The **geometry generation subsystem**. Responsible for creating all vertex/index buffers, managing per-instance uniforms, and providing drawable mesh primitives. This is the "graphics data" layer — it generates what the renderer draws.

## Files

### `Meshes.swift` (319 lines) — LOW RISK
**Role:** Base mesh infrastructure and common mesh types.

**Key Classes:**
- `PerInstanceUniforms` — Struct passed to GPU: `modelMatrix` (float4x4) + `alphaUniform` (Float)
- `Mesh` — Base class for all drawable geometry:
  - Owns `vertexBuffer`, `indexBuffer`, `uniformBuffer` (all MTLBuffer)
  - Properties: `position` (SIMD2), `rotation` (Float), `scale` (Float), `alpha` (Float) — all trigger `updateModelMatrix()` on change
  - `draw(encoder:)` — Sets vertex/uniform buffers, issues draw call
  - Model matrix = translation × rotation × scale (computed on CPU, uploaded per-draw)
- `QuadMesh(Mesh)` — Textured rectangle (4 vertices, 6 indices). Takes size + UV coordinates.
- `TextQuadMesh(Mesh)` — Runtime text-to-texture rendering:
  - Platform-specific (`UIKit` / `AppKit`) text rasterization to `CGImage`
  - Creates `.rgba8Unorm` MTLTexture from rasterized text
  - Overrides `draw()` to bind its own texture (overriding the layer texture)

**Platform Aliases:** `Font = UIFont/NSFont`, `Color = UIColor/NSColor`, `Image = UIImage/NSImage`

**Helper Functions:** `matrix4x4_translation()`, `matrix4x4_rotation_z()`, `matrix4x4_scale()`

### `SegmentStripeMesh.swift` (273 lines) — LOW RISK
**Role:** Procedural triangle strip generation along a polyline path.

**Key Classes:**
- `SegmentColor` — Enum with 13 colors, each mapping to 3 UV coordinate pairs (first/middle/last segment) from the arrows texture atlas
- `SegmentStripMesh(Mesh)` — Given a list of points, generates a triangle strip with:
  - Perpendicular expansion by `width` at each point
  - Corner smoothing via averaged perpendiculars at middle points
  - Extra cap vertices at start/end for rounded appearance
  - `remakeVertices()` for dynamic updates (used by particles and electric arcs)

### `ElectricArcMesh.swift` (113 lines) — LOW RISK
**Role:** Procedural lightning/electric arc effect.

**Key Classes:**
- `Segment` — Simple struct holding start/end SIMD2 points
- `ElectricArc` — Midpoint displacement algorithm:
  - Takes startPoint, endPoint, and `powerOfTwo` (controls subdivision level: 2^n segments)
  - Recursive binary subdivision with random perpendicular displacement
  - `twitchPoints(byFactor:)` — Per-frame randomized displacement perturbation for animation
- `ElectricArcMesh(SegmentStripMesh)` — Combines `ElectricArc` point generation with `SegmentStripMesh` rendering

**Global:** `maxArcDisplacement` — Controls maximum displacement factor (0.1 for menu, 0.2 for gameplay)

### `ParticleEffects.swift` (104 lines) — LOW RISK
**Role:** Particle system for explosion effects.

**Key Class:**
- `Particle(SegmentStripMesh, Poolable)` — A 2-point segment strip that acts as a physics particle:
  - Properties: `speed` (SIMD2), static `friction` (0.02), static `attractor` (gravity well), `attractStrength` (0.3)
  - `update()` — Per-frame: attract toward attractor, apply friction, update position
  - `draw()` — Calls `update()` then `remakeVertices()` then `super.draw()` (physics in render — coupling)
  - `generate(count:speedLimit:width:)` — Factory that pulls from `AnimationPools.particlePool`

### `UIMeshes.swift` (178 lines) — LOW RISK
**Role:** UI button mesh generation using 9-slice technique.

**Key Class:**
- `ButtonMesh(Mesh)` — 9-quad button with corners, edges, and center:
  - Takes inner dimensions, border width, and UV coordinates for the 9-slice
  - `tappedInside(point:)` — AABB hit testing in game coordinates
  - 12 factory methods for different button styles (lit, unlit, red, pause, back, check, cancel, etc.) mapping to different texture atlas regions

## Connections to Architecture
- All mesh classes inherit from `Mesh` which uses `Renderer.device` (static) for buffer creation
- `QuadMesh` is used everywhere: tiles, backgrounds, tutorials, bonus objects
- `SegmentStripMesh` → `ElectricArcMesh` and `Particle` (both use triangle strips)
- `TextQuadMesh` creates its own `MTLTexture` per instance (potential memory concern for dynamic text)
- `ButtonMesh.tappedInside()` is the entire UI interaction system (no UIKit buttons)

## Refactor Risk Summary
- **All files: LOW RISK** — These are pure geometry generators with minimal coupling. The vertex format (float3 pos + float2 uv, stride 20) maps directly to WebGPU vertex buffers.
- **Note:** `Particle.draw()` runs physics simulation inside the render call — this should be separated for the WASM port.
- **Note:** `TextQuadMesh` rasterizes text via CoreGraphics/AppKit — needs a different approach in WebGPU (Canvas 2D → texture, or SDF text rendering).
