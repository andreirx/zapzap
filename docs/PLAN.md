# ZapZap Native Porting Plan

## Phase 1: The Core Simulation (Rust)
**Goal:** A headless version of ZapZap running in WASM.
- [x] **Data Structures:** `Tile` (u8 bitmask), `Grid` (flat `Vec<Option<Tile>>`), `Direction`, `Marking` in `components.rs` + `grid.rs`.
- [x] **Game Logic:** `check_connections()` (iterative BFS flood-fill) and `remove_and_shift_connecting_tiles()` (gravity) in `systems/board.rs`.
- [x] **The Loop:** `GameState.tick()` in `state.rs` implements the full state machine (WaitingForInput -> RotatingTile -> FreezeDuringZap -> FallingTiles -> cascade). `bridge.rs` exports `tick_game()` + `tap_tile()` + score/phase getters via `wasm_bindgen`.
- [x] **AI:** `BotPlayer::determine_next_move()` in `systems/bot.rs` (sequential; `rayon` deferred).

## Phase 2: Asset Pipeline
**Goal:** Assets accessible to Vite.
- [x] **Extraction:** `scripts/extract_assets.py` walks `.xcassets`, flattens `.textureset` dirs, copies 9 images to `public/assets/`.
- [x] **Audio:** Script copies 19 audio files (3 MP3 + 16 WAV) to `public/audio/`.

## Phase 3: The Renderer (WebGPU)
**Goal:** Visual parity with Metal.
- [x] **Shaders:** `src/renderer/shaders.wgsl` — `vs_main` reads per-instance data from storage buffer, applies rotation/scale/translation, maps sprite_id to atlas UV. `fs_main` for alpha blend, `fs_additive` for HDR glow (color * 6.4 * alpha).
- [x] **Texture Loading:** `src/renderer/assets.ts` — async `loadAllTextures()` loads 8 game textures via `createImageBitmap` + `GPUDevice.queue.copyExternalImageToTexture`.
- [x] **Instance Rendering:** Storage buffer holds up to 256 `RenderInstance` structs (32 bytes each). Single `draw(6, instanceCount)` call renders all tiles as instanced quads.
- [x] **HDR Pipeline:** `src/renderer/index.ts` configures `rgba16float` + `display-p3` + `toneMapping: { mode: 'extended' }`.

## Phase 4: UI & Interaction (React)
**Goal:** Replace `UIMeshes.swift` with DOM.
- [x] **HUD:** Score counters (blue left, orange right) as positioned `<span>` overlays.
- [x] **Menus:** Start menu with gradient "ZapZap" title + "Start Game" button. Game over screen with winner display + "Play Again".
- [x] **Input:** `onPointerDown` on canvas, converts screen coords -> game space via orthographic projection math, posts `{ type: 'tap', x, y }` to worker.

## Phase 5: Verification
- [x] **Unit Tests:** 20 Rust tests covering tile rotation, grid ops, BFS flood-fill, gravity, bot AI, game state lifecycle. All pass via `cargo test -p zapzap-sim`.
- [x] **WASM Compilation:** `cargo check --target wasm32-unknown-unknown -p zapzap-sim` — 0 errors, 0 warnings.
- [x] **TypeScript Compilation:** `npx tsc --noEmit` — 0 errors.
- [ ] **E2E:** Manual verification pending (requires `wasm-pack build` + `npm run dev`).
