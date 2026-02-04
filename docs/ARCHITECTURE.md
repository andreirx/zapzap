# Architecture: The Hybrid Engine

## 1. The Host (TypeScript/React)
- **Role:** Thin Client.
- **Responsibility:**
    - Capture Input (Touch/Mouse).
    - Render UI Overlays (Score, Menus).
    - Initialize the `WasmWorker`.
- **Communication:** Sends `InputEvent` structs to Shared Memory.

## 2. The Guest (Rust/WASM)
- **Role:** The Universe.
- **Responsibility:**
    - **ECS World:** Stores all entity positions/states in linear memory.
    - **Systems:** Physics, Logic, AI run here.
- **Output:** writes directly to `RenderBuffer` (Float32Array).

## 3. The Renderer (WebGPU)
- **Role:** The Visualizer.
- **Responsibility:**
    - Reads `RenderBuffer`.
    - executes `ComputeShader` for particle effects.
    - executes `RenderPipeline` for drawing sprites.