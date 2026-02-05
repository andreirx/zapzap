# ZapZap

A tile-connection puzzle game ported from Swift/Metal to a high-performance web stack:
**Rust/WASM + WebGPU + React**.

**Play now:** [https://d1cx3pkxc7x828.cloudfront.net](https://d1cx3pkxc7x828.cloudfront.net)

---

## Architecture

```
 React UI (HUD, menus, overlays)
     |
     |  postMessage / SharedArrayBuffer
     v
 Web Worker ── sim.worker.ts
     |
     |  wasm-bindgen bridge
     v
 Rust/WASM ── crates/zapzap (game logic) + crates/engine (2D engine)
     |
     |  SharedArrayBuffer (10-float header + instances + effects)
     v
 WebGPU Renderer ── two-pass pipeline (alpha blend + additive HDR glow)
```

**Three layers, zero game logic on the main thread:**

| Layer | Technology | Responsibility |
|-------|-----------|----------------|
| **Host** | TypeScript + React | UI overlays, input routing, audio playback |
| **Guest** | Rust compiled to WASM | All game logic: grid, BFS flood-fill, gravity, animations, scoring, bot AI |
| **Renderer** | WebGPU (WGSL shaders) | Two-pass rendering: alpha-blend sprites + additive HDR glow effects |

The game simulation runs on a **Web Worker** at a fixed 60fps timestep. Frame data flows to
the main thread via a **SharedArrayBuffer** (preferred) or **postMessage** copies (fallback).
The renderer reads instance data (8 floats per tile: x, y, rotation, scale, sprite_id, alpha,
flags, atlas_row) and effects vertices (5 floats: x, y, z, u, v) to draw everything in a
single render pass with two sub-passes.

## Progressive Fallback

The game uses a layered fallback strategy so it works on any modern browser, from full HDR
down to basic Canvas 2D:

### Renderer Fallback

```
WebGPU + HDR/EDR (rgba16float, display-p3, extended tone mapping)
  |  fails? (toneMapping unsupported)
  v
WebGPU + sRGB (rgba16float, no HDR features)
  |  fails? (rgba16float unsupported)
  v
WebGPU + preferred format (bgra8unorm, basic sRGB)
  |  fails? (WebGPU unavailable entirely)
  v
Canvas 2D (software rendering, SDR only)
```

Before touching the real canvas, a **probe test** runs WebGPU configuration on a disposable
off-screen canvas. This prevents the real canvas from getting locked to a WebGPU context if
WebGPU setup fails — a subtle browser behavior where `canvas.getContext('webgpu')` permanently
prevents `canvas.getContext('2d')` on the same element.

### Data Transport Fallback

```
SharedArrayBuffer (zero-copy shared memory, Atomics sync)
  |  unavailable? (missing COOP/COEP headers)
  v
postMessage (structured clone copies per frame, ~8-50 KB/frame)
```

`SharedArrayBuffer` requires the server to send two HTTP headers:
```
Cross-Origin-Opener-Policy: same-origin
Cross-Origin-Embedder-Policy: require-corp
```
When these are absent, the worker automatically falls back to sending frame data via
`postMessage` with `buffer.slice()` copies. The buffer layout is identical, so the
render loop code doesn't change — only the transport mechanism differs.

## Enabling WebGPU and HDR in Your Browser

### Chrome (recommended)

WebGPU is **enabled by default** since Chrome 113 (April 2023) on macOS, Windows, and
ChromeOS. HDR extended tone mapping shipped in Chrome 128.

If you're on an older version or want to verify:
1. Navigate to `chrome://flags`
2. Search for **"WebGPU"** and set to **Enabled**
3. Search for **"WebGPU extended color"** and set to **Enabled** (for HDR)
4. Relaunch Chrome

HDR requires a display that supports extended dynamic range (most modern Mac displays,
HDR-capable monitors on Windows).

### Safari

WebGPU is **enabled by default** since Safari 18.0 (macOS Sonoma 14 / iOS 18, September
2024). Safari has native support for Display P3 color space.

No flags needed. Just make sure you're on macOS 14+ or iOS 18+.

### Firefox

WebGPU support is more recent and platform-dependent:
- **Windows:** Enabled by default since Firefox 141
- **macOS (Apple Silicon):** Enabled by default since Firefox 145
- **Linux / Intel Mac:** Still in progress

To enable manually:
1. Navigate to `about:config`
2. Search for `dom.webgpu.enabled` and set to **true**
3. Restart Firefox

Note: Firefox does not yet support HDR extended tone mapping for WebGPU canvases. The game
will run in sRGB mode on Firefox.

### Other Browsers

Any Chromium-based browser (Edge, Brave, Arc, Opera) inherits Chrome's WebGPU support.
Enable via the same `chrome://flags` mechanism if needed.

## Building Locally

### Prerequisites

- **Rust** 1.75+ with `wasm32-unknown-unknown` target
- **wasm-pack** (`cargo install wasm-pack`)
- **Node.js** 18+ and npm
- **Make** (standard on macOS/Linux)

### Quick Start

```bash
cd zapzap-native
make              # builds WASM, installs npm deps, starts dev server
```

### Build Commands

| Command | Description |
|---------|-------------|
| `make` | Full pipeline: wasm + install + dev server |
| `make wasm` | Compile Rust to WASM via wasm-pack |
| `make install` | npm install (links WASM package) |
| `make dev` | Start Vite dev server |
| `make build` | Production build to `dist/` |
| `make test` | Run all tests (Rust + WASM + TypeScript) |
| `make clean` | Remove build artifacts |

**Important:** After any Rust code change, you must run `make wasm` then `make install`
before the browser will pick up the changes. Vite does not auto-rebuild WASM.

### Production Build

```bash
cd zapzap-native
make build        # outputs to dist/
```

The `dist/` folder contains everything needed for static hosting: HTML, JS bundles,
WASM binary, textures, and audio files.

## Deployment

The game is deployed to AWS using CDK (S3 + CloudFront) with the critical COOP/COEP
headers that enable SharedArrayBuffer:

```bash
cd zapzap-native/infra
npm install
npx cdk bootstrap    # first time only, per AWS account/region
npx cdk deploy       # deploys dist/ to S3 + CloudFront
```

The CDK stack creates:
- **S3 Bucket** — private, serves as CloudFront origin via Origin Access Control
- **CloudFront Distribution** — HTTPS, gzip/brotli compression, global CDN
- **Response Headers Policy** — injects COOP/COEP headers on every response
- **Automatic deployment** — uploads `dist/` and invalidates CDN cache

First deployment takes ~10-15 minutes (CloudFront needs to propagate to global edge
locations). Subsequent deployments are 2-3 minutes.

To tear down:
```bash
npx cdk destroy
```

## Tests

36 Rust unit tests covering grid operations, game state transitions, animations,
board generation, bonus mechanics, bot AI, and visual effects:

```bash
cd zapzap-native
make test-rust     # Rust unit tests
make test-wasm     # WASM integration tests
make test-ts       # TypeScript checks
make test          # all of the above
```

## Credits

**Music:** "Itty Bitty 8 Bit" by Kevin MacLeod ([incompetech.com](https://incompetech.com))
Licensed under [Creative Commons: By Attribution 4.0](http://creativecommons.org/licenses/by/4.0/)
