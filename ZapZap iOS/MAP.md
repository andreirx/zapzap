# MAP.md — ZapZap iOS (Platform Target)

## Component Role
The **iOS platform shell**. Provides the UIKit app lifecycle and touch input handling. This is a thin wrapper — all game logic lives in `ZapZap Shared/`.

## Files

### `AppDelegate.swift` (small)
- Standard `UIApplicationDelegate` boilerplate
- No custom logic

### `GameViewController.swift` (73 lines) — LOW RISK
**Role:** iOS entry point. Sets up Metal and bridges touch input to the game.

**Key Responsibilities:**
1. Creates `MTKView` with Metal device
2. Configures **EDR/HDR rendering:**
   - `CAMetalLayer.pixelFormat = .rgba16Float`
   - `CAMetalLayer.colorspace = extendedLinearDisplayP3`
   - `CAMetalLayer.wantsExtendedDynamicRangeContent = true`
3. Creates `GameManager` and `Renderer`
4. Starts background music
5. Touch input: `touchesEnded()` → scales by `contentScaleFactor` → `gameManager.notifyInput(at:)`

### Storyboards
- `Main.storyboard` — Single scene with MTKView
- `LaunchScreen.storyboard` — Launch screen

### Entitlements
- Game Center enabled

## Connections to Architecture
- `GameViewController` → creates → `GameManager` → creates → `Renderer`
- Touch events flow: UIKit → `GameViewController.touchesEnded()` → `GameManager.notifyInput()` → `GameManager.lastInput` → processed in next `Renderer.draw()` frame
- The `viewController` reference is passed to `Renderer` for presenting Game Center UI

## Refactor Risk
- **LOW RISK** — Minimal platform code. For WASM port, this entire target is replaced by the HTML/Canvas host.
