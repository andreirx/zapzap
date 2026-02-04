# Vision: ZapZap Native

## The Goal
Porting a casual iOS / MacOS swift game to an industrial-strength engine.
 The objective is not just to "port a game," but to architect a **Host-Guest System** that decouples simulation from presentation, enabling native performance in a browser environment.

## 2. The Tech Stack
- **Simulation:** Rust (compiled to `wasm32-unknown-unknown`).
- **Rendering:** WebGPU (via `wgpu`) with Canvas 2D Fallback.
- **Concurrency:** Web Workers + `SharedArrayBuffer` (Zero-Copy).
- **Toolchain:** `wasm-pack` + Vite.

---

## 3. Architecture: The Host-Guest Model

We treat the Browser Main Thread as the "Host" (OS) and the Web Worker as the "Guest" (Engine).

### A. The Guest (Simulation Layer)
- **Runtime:** WebAssembly (Rust).
- **Role:** Pure deterministic logic. It calculates physics, AI, and board state.
- **Constraint:** It **never** touches the DOM. It has no concept of "Pixels" or "Screen," only "Units" and "Memory."
- **Execution:** Runs in a `setTimeout` loop inside a Web Worker to ensure UI non-blocking behavior.

### B. The Host (Presentation Layer)
- **Runtime:** JavaScript/TypeScript (Main Thread).
- **Role:** Input capture, Audio dispatch, and GPU Command Encoding.
- **Constraint:** It never calculates game logic. It strictly visualizes the memory state provided by the Guest.

### C. The Bridge (Shared Memory)
Communication relies on **SharedArrayBuffer (SAB)**, bypassing the expensive structured cloning (serialization) of standard `postMessage`.

**Memory Layout (Float32 View):**
| Offset | Field | Type | Description |
|:---|:---|:---|:---|
| `0` | `lock` | `Atomic i32` | Spinlock for frame synchronization. |
| `1` | `frame_seq` | `f32` | Monotonic frame counter. |
| `2` | `phase` | `u8` | Game State Enum (Waiting, Falling, Zap, etc). |
| `3..9` | `meta` | `f32` | Scores, Board Dims, Entity Counts. |
| `10..N` | `Instances` | `struct` | `[x, y, rot, scale, sprite_id, alpha, flags, padding]` (32 bytes). |
| `N..M` | `Effects` | `struct` | `[x, y, z, u, v]` (20 bytes per vertex). |

---

## 4. The Rendering Stratagem (Graceful Degradation)

The engine employs a **Strategy Pattern** for rendering to support the entire device spectrum.

### Primary: WebGPU (The "Metal" Path)
- **Target:** Chrome 113+, Edge, Desktop/High-End Mobile.
- **Pipeline:**
    1.  **DMA Transfer:** `device.queue.writeBuffer()` moves SAB data directly to GPU VRAM.
    2.  **Vertex Shader:** Decodes instance data.
    3.  **Fragment Shader:**
        -   **Pass 1 (Alpha):** Standard blending for tiles.
        -   **Pass 2 (Additive):** Electric arcs use `color * 6.4` to drive values >1.0.
- **HDR/EDR:** Configured as `rgba16float` with `toneMapping: extended`. On XDR displays (MacBook Pro), this produces physical light emission > 200 nits.

### Secondary: Canvas 2D (The "Compatibility" Path)
- **Target:** Firefox, Safari (current), Older Hardware.
- **Pipeline:**
    1.  **CPU Iteration:** Loops over the `Float32Array` view in JavaScript.
    2.  **State Machine:** Manages `ctx.save()/restore()` for transforms.
    3.  **Simulation:** Emulates HDR glow using `ctx.globalCompositeOperation = 'lighter'`.
- **Result:** 100% functional parity, reduced visual fidelity (SDR), 60 FPS cap.

---

## 5. The Byte Lifecycle: From Rust to Pixel

Tracing a single tile's position (`x=225.0`) through the stack:

1.  **Rust (Heap):** The ECS updates `position.x`. Rust writes IEEE 754 float `0x43610000` to WASM Linear Memory (offset `0x1000`).
2.  **Bridge (Copy):** The Worker copies this range from WASM Heap → SharedArrayBuffer.
3.  **Sync:** Worker executes `Atomics.store(lock, 1)`.
4.  **Host (Read):** Main thread wakes on `requestAnimationFrame`, checks lock.
5.  **WebGPU (Upload):** Browser Driver (Dawn/Skia) initiates a DMA transfer over PCIe bus.
6.  **VRAM:** Bytes land in the GPU Storage Buffer.
7.  **Shader:** Vertex shader reads `instances[i].position.x` and generates clip-space coordinates.

---

## 6. Build & Deployment Pipeline

This is a **Serverless Static Deployment**. There is no backend game server.

1.  **Compilation (`wasm-pack`):**
    -   Compiles Rust -> `.wasm` binary (Instruction Set Architecture).
    -   Generates JS Glue (`wasm-bindgen`) to map JS functions to WASM imports/exports.
2.  **Bundling (`vite`):**
    -   Treats `.wasm` as a static asset (MIME `application/wasm`).
    -   Bundles React UI + Worker + Glue Code.
3.  **Security Headers (Critical):**
    -   To enable `SharedArrayBuffer`, the CDN must serve:
        -   `Cross-Origin-Opener-Policy: same-origin`
        -   `Cross-Origin-Embedder-Policy: require-corp`
    -   *Why:* Mitigates Spectre/Meltdown timing attacks, allowing the browser to allocate high-precision shared memory.

---

## 7. Why Rust? (Engineering Defense)

While C++ is the legacy standard for engines, Rust was chosen for **Safety in Concurrency**.
-   **Borrow Checker:** Guarantees thread safety at compile time. Prevents data races when writing to the shared render buffer.
-   **WASM Bindgen:** Superior developer experience (DX) for interacting with the browser DOM/Console compared to C++ `emscripten/bind`.
-   **Data-Oriented:** The language design encourages ECS (Entity Component System) patterns over OOP, aligning perfectly with the linear memory requirements of WebGPU storage buffers.
