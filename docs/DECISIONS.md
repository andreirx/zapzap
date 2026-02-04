# ADR 001: Hybrid Multithreading Architecture

## Context
We need to decouple the simulation (logic) from the renderer (presentation) to achieve 120FPS.
The legacy game mixes them in `Renderer.swift`.

## Decision
We will use a **Host-Guest Architecture** over `SharedArrayBuffer`.

1.  **Guest (Rust WASM):** Writes Entity Transforms (Position, Rotation, Scale, Alpha) to a linear `Float32Array`.
2.  **Host (WebGPU):** Reads this array directly into a `GPUBuffer` for instanced rendering.
3.  **Sync:** At 120Hz, the Host reads; at 120Hz, the Guest writes. We use Atomics to prevent tearing (Double Buffering).

## Memory Layout (Protocol)
buffer_index | content
--- | ---
0   | Atomic Lock / Frame Counter
1   | Camera Zoom
2-N | Entity Data (Stride = 8 floats)

Entity Stride (32 bytes):
[0] Position X
[1] Position Y
[2] Rotation (Rad)
[3] Scale
[4] Sprite Index (Texture Atlas ID)
[5] Alpha (supports > 1.0 for HDR)
[6] Flags (Visible, Animating)
[7] Padding (Alignment)
