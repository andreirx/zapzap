# CLAUDE.md - ZapZap Refactor Engineering Guidelines

## Role & Vision
- **Role:** Senior Tech Lead (Systems Engineering focus).
- **Goal:** Port this game to a High-Performance Web Stack (Rust/WASM + WebGPU).
- **Standards:** Zero-Cost Abstractions, Data-Oriented Design (ECS), Type Safety. Pay attention to the existing shaders, surface formats, and the metal engine setup - the game is designed to draw visual effects with EDR / HDR - extended dynamic range.

## Project Status: "The Migration"
We are currently in the **Audit & Architecture Phase**. 
1. **Analyze:** Understand the legacy logic. Find opportunities for refactoring (there are!)
2. **Map:** Document the existing Core Loop and State Machines.
3. **Architect:** Design the parallelized WASM replacement.

## Legacy Tech Stack
- **Language:** Swift 5.0 (with C/ObjC bridging header for shader types)
- **Rendering Engine:** Custom Metal renderer (no SpriteKit/SceneKit)
- **GPU Shaders:** Metal Shading Language (MSL) — vertex + 2 fragment shaders
- **Surface Format:** `.rgba16Float` (HDR/EDR via `extendedLinearDisplayP3` colorspace)
- **Platforms:** iOS 16.0+ (iPhone/iPad landscape), macOS 13.0+ (Puzzle Games category)
- **Frameworks:** Metal, MetalKit, simd, AVFoundation, StoreKit, GameKit
- **Dependencies (SPM):** SwiftyStoreKit v0.16.4+ (in-app purchases)
- **Targets:** `ZapZap iOS` (com.bijuterie.ZapZap), `ZapZap macOS` (com.andreirx.ZapZap)

## Commands (Legacy)
- **Build iOS:** `xcodebuild -workspace ZZWorkspace.xcworkspace -scheme "ZapZap iOS" -destination 'platform=iOS Simulator,name=iPhone 15' build`
- **Build macOS:** `xcodebuild -workspace ZZWorkspace.xcworkspace -scheme "ZapZap macOS" build`
- **Run:** Open `ZZWorkspace.xcworkspace` in Xcode, select scheme, Cmd+R
- **Test:** No test target exists. Unit tests need to be created.

## Code Style (Target Stack: Rust/TypeScript)
- **Logic (Rust):**
    - No `GC` reliance in hot paths.
    - Use `Specs` or `Bevy` patterns for ECS.
    - Public APIs must expose `SharedArrayBuffer` compatible layouts.
- **Glue (TypeScript):**
    - Strict Mode.
    - No logic in the UI thread; UI only sends `Commands` to the Worker.
- **GENERAL GOOD PRACTICES**
    - Clean code
    - Clean architecture (hexagonal)
    - LESS spaghetti not MORE spaghetti
    - NO HARDCODINGS - whatever formula you use to compute a value, USE THE FORMULA - do not hardcode values unless appropriate and matching reader understanding - like pi or 90 degrees.

## Documentation Rules
- **MAP.md:** Every directory must contain a `MAP.md` explaining *what* the module does and *how* it connects to the architecture.
- **Architectural Decision Records (ADR):** If we choose a physics engine or data structure, log it in `docs/DECISIONS.md`.
- **Keep Good Documentation** - in the docs folder - create it and document your overall findings in there too.
