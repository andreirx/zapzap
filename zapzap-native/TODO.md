# TODO.md - The Master Plan

## Batch 1: The Engine Foundation (`crates/engine`)
- [x] **Asset Loading:** Create `AssetManager` in Rust that reads from `public/assets/`.
- [x] **Renderer:** Create a generic `SpriteRenderer` struct that accepts a buffer of `[x, y, u, v, w, h]`.
- [x] **Input:** Create an `InputQueue` resource that JS writes to and Rust reads.

## Batch 2: The Game Data (`crates/zapzap`)
- [x] **Assets:** `scripts/extract_assets.py` flattens `.xcassets` into `public/assets/` and copies audio to `public/audio/`. 28 files extracted.
- [x] **Grid:** Define the `Grid` struct (flat `Vec<Option<Tile>>`) in `crates/zapzap/src/grid.rs`.
- [x] **Components:** Define `Direction`, `Marking`, constants in `crates/zapzap/src/components.rs`.

## Batch 3: The Game Logic (The Hard Stuff)
- [x] **Port Logic:** Port `GameBoardLogic.swift` -> `crates/zapzap/src/systems/board.rs`.
    - *Constraint:* Uses iterative BFS (`VecDeque` queue), NOT recursion.
    - *Reference:* `../../ZapZap Shared/GAME LOGIC/GameBoardLogic.swift`.
- [x] **Port AI:** Port `BotPlayer.swift` -> `crates/zapzap/src/systems/bot.rs`.
    - *Note:* Sequential for now; `rayon` can be added later for parallel evaluation.
    - *Reference:* `../../ZapZap Shared/GAME LOGIC/BotPlayer.swift`.
- [x] **Tests:** 20 unit tests covering tile rotation, grid ops, flood-fill BFS, gravity, bot AI, and game state.

## Batch 4: The Glue (WASM Interface)
- [x] **WASM Bridge:** `bridge.rs` exposes `init_game`, `tick_game`, `tap_tile`, `enable_bot`, `get_render_buffer_ptr/len`, score getters, `reset_game` via `wasm_bindgen`. Uses `thread_local! RefCell` for safe global state.
- [x] **State Representation:** `state.rs` defines `GameState` struct holding `GameBoard`, phase state machine, scores, and `RenderInstance` buffer.
- [x] **Memory Layout:** `#[repr(C)]` `RenderInstance` { x, y, rotation, scale, sprite_id, alpha, flags, pad } = 32 bytes.
- [x] **Export:** `get_render_buffer_ptr()` returns pointer to `Vec<RenderInstance>` data for SharedArrayBuffer reads.
- [x] **Loop:** `tick_game(dt)` runs state machine (input -> rotate -> check_connections -> freeze -> zap -> gravity -> cascade) and rebuilds render buffer.

## Batch 5: The Renderer (WebGPU)
- [x] **Shader Port:** `src/renderer/shaders.wgsl` with `vs_main` (storage buffer instances, rotation, scale, atlas UV), `fs_main` (alpha blend), `fs_additive` (color * 6.4 * alpha HDR glow).
- [x] **Texture Loading:** `src/renderer/assets.ts` async loads all 8 game textures via `createImageBitmap` + `copyExternalImageToTexture`.
- [x] **Pipeline:** `src/renderer/index.ts` configures `rgba16float` + `display-p3` + `extended` tone mapping, camera uniform, texture bind group, instance storage buffer, alpha-blend pipeline.

## Batch 6: The Host (Worker & Loop)
- [x] **Worker Setup:** `src/worker/sim.worker.ts` loads WASM module (`zapzap-sim`), initializes game with random seed.
- [x] **Shared Memory:** Allocates `SharedArrayBuffer` with header (8 floats: lock, frame, phase, scores, instance count, board dims) + instance data.
- [x] **Game Loop:** `setTimeout(gameLoop, 16)` ~60fps loop calling `tick_game` and copying render buffer from WASM memory.
- [x] **Main Thread Sync:** `Atomics.store` + `Atomics.notify` signals new frame data to main thread.

## Batch 7: The UI (React Overlay)
- [x] **Canvas:** Full-screen `<canvas>` with `touch-action: none` in `App.tsx`.
- [x] **HUD:** Score overlays (left blue, right orange) positioned at top corners.
- [x] **Menus:** "Start Game" overlay with gradient title, "Game Over" overlay with winner display and "Play Again".
- [x] **Input:** `onPointerDown` converts screen coords to game space via orthographic projection math, sends `{ type: 'tap', x, y }` to worker.

## Batch 8: Verification
- [x] **Rust Tests:** 20 tests pass via `cargo test -p zapzap-sim`.
- [x] **WASM Check:** `cargo check --target wasm32-unknown-unknown -p zapzap-sim` compiles clean (0 warnings).
- [x] **TypeScript Check:** `npx tsc --noEmit` compiles clean.
- [ ] **E2E:** Manual verification pending (requires `wasm-pack build` + `npm run dev`).
