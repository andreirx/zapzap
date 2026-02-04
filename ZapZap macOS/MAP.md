# MAP.md — ZapZap macOS (Platform Target)

## Component Role
The **macOS platform shell**. Provides the AppKit app lifecycle and mouse input handling. Mirrors the iOS target structure — all game logic lives in `ZapZap Shared/`.

## Files

### `AppDelegate.swift` (small)
- Standard `NSApplicationDelegate` boilerplate
- No custom logic

### `GameViewController.swift` (75 lines) — LOW RISK
**Role:** macOS entry point. Sets up Metal and bridges mouse input to the game.

**Key Responsibilities:**
1. Creates `MTKView` with Metal device
2. Configures **EDR/HDR rendering:**
   - `CAMetalLayer.pixelFormat = .rgba16Float`
   - `CAMetalLayer.colorspace = extendedLinearDisplayP3`
   - `CAMetalLayer.wantsExtendedDynamicRangeContent = true`
3. Creates `GameManager` and `Renderer`
4. Starts background music
5. Mouse input: `mouseUp(with:)` → converts from window coords → scales by `backingScaleFactor` → flips Y axis → `gameManager.notifyInput(at:)`

**Note:** macOS Y-axis is flipped vs. iOS (origin bottom-left vs. top-left), handled by: `y = drawableSize.height - location.y * scaleFactor`

### Storyboards
- `Main.storyboard` — Single window with MTKView

### Entitlements
- Game Center enabled
- App Sandbox enabled (network client/server, read-only user files)

## Connections to Architecture
- Same as iOS: `GameViewController` → `GameManager` → `Renderer`
- Mouse events flow: AppKit → `mouseUp(with:)` → coordinate conversion → `GameManager.notifyInput()`
- Also hosts `CustomAnimator` (in MultiplayerManager.swift) for presenting Game Center views via `NSViewControllerPresentationAnimator`

## Refactor Risk
- **LOW RISK** — Minimal platform code. For WASM port, this entire target is replaced by the HTML/Canvas host.
