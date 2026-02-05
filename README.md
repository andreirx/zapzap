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

While WebGPU is shipping in modern browsers, it often requires manual activation depending on your OS version or specific hardware blocklists.

### Safari (macOS / iOS)

WebGPU is technically enabled by default in **Safari 18 (macOS Sequoia)**, but often requires manual intervention on **Safari 17 (macOS Sonoma)** or to unlock full HDR capabilities.

1. Open **Settings** > **Advanced**.
2. Check the box **"Show features for web developers"** (or "Show Develop menu in menu bar").
3. In the menu bar, click **Develop** > **Feature Flags**.
4. Search for **"WebGPU"**.
5. Check **"WebGPU"** (and "WebGPU standard" if present).
6. Restart Safari.

### Chrome (Recommended)

WebGPU is enabled by default on most modern systems (Chrome 113+). To force it on or enable HDR:

1. Navigate to `chrome://flags`.
2. Search for **"WebGPU"** and set it to **Enabled**.
3. Search for **"WebGPU extended color"** and set it to **Enabled** (required for the electric glow HDR effect).
4. Relaunch Chrome.

### Firefox

Firefox has WebGPU support but it is often disabled by default or blocklisted on specific drivers.

1. Navigate to `about:config` and accept the risk warning.
2. Search for `dom.webgpu.enabled` and set it to **true**.
3. (If still not working) Search for `gfx.webgpu.force-enabled` and set it to **true**.
4. Restart Firefox.

*Note: Firefox does not yet support the `tone-mapping` capability required for the HDR glow effect, so the game will run in standard sRGB mode even with WebGPU enabled.*

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
