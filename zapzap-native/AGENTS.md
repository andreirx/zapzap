# AGENTS.md - Engineering Constraints

## 1. The Rendering Protocol (Critical)
We are moving from "Immediate Mode" (Swift) to "Data-Driven" (Rust).
- **Rust Side:** Does NOT draw. It populates a `Vec<RenderInstance>`.
- **Instance Layout:** `[x, y, rotation, scale, sprite_index, alpha, padding, padding]` (32 bytes).
- **Sprite Index:** You must maintain a mapping: `0 = arrow_red`, `1 = arrow_blue`, etc.

## 2. HDR / EDR Implementation
- The WebGPU context MUST be `rgba16float` with `toneMapping: { mode: 'extended' }`.
- The Shader MUST multiply alpha by 6.4 for "Additive" sprites (Electric Arcs) to achieve the glow effect found in the original Metal shader.

## 3. Worker Architecture
- **Do not** run game logic on the Main Thread.
- **Do not** serialize JSON. Use `Float32Array` views on the `SharedArrayBuffer`.

## 4. Asset Handling
- The Swift project uses `.xcassets` (folders). The Python script must flatten this to simple filenames: `arrow.png`, `bomb.png`.
- If an asset is missing, use a fallback colored square. Do not crash.
