# Vision: ZapZap Native

## The Goal
Demonstrate "Adobe-Scale" engineering by porting a casual game to an industrial-strength engine.

## The Stack
- **Simulation:** Rust (compiled to WASM).
- **Rendering:** WebGPU (via `wgpu`).
- **Concurrency:** Web Workers + SharedArrayBuffer.

## Success Metrics
- **Performance:** 120 FPS on high-refresh displays.
- **Object Count:** Support 10x the original game's entity count (Stress Test).
- **Latency:** Zero-copy state synchronization.
