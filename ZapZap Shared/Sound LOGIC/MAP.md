# MAP.md — Sound LOGIC (Audio System)

## Component Role
The **audio subsystem**. A singleton manager that handles background music playback and sound effects using AVFoundation. Supports theme-based audio variants (e.g., Halloween).

## Files

### `SoundManager.swift` (139 lines) — LOW RISK
**Role:** Singleton audio manager.

**Key Class — `SoundManager`:**
- Singleton via `SoundManager.shared`
- `AVAudioPlayer`-based playback for both music and effects
- **Ambience system:** `setAmbience(named:)` appends a suffix to filenames (e.g., `"explode"` → `"explode_haloween"`) with fallback to base file
- Background music: looping (`numberOfLoops = -1`), respects other audio on iOS
- Sound effects: creates a new `AVAudioPlayer` per effect, auto-removes via delegate on completion
- Toggle controls: `isBackgroundMusicEnabled`, `isSoundEffectsEnabled`
- iOS-only: `AVAudioSession` configured as `.ambient`

**Audio Files (19 total):**
| File | Type | Purpose |
|------|------|---------|
| `bop.wav` | Effect | Tile tap feedback |
| `buzz.wav` | Effect | Processing |
| `rotate.wav` | Effect | Tile rotation |
| `powerup.wav` | Effect | Power-up activation |
| `explode.wav` | Effect | Tile explosion |
| `bomb.wav` | Effect | Bomb detonation |
| `coindrop.wav` | Effect | Bonus collection |
| `nope.wav` | Effect | Invalid action |
| `superhero.wav` | Effect | Special power |
| `alarm.wav` | Effect | Power-up armed |
| `IttyBitty.mp3` | Music | Main background track |
| `DungeonLevel.mp3` | Music | Alternative track (unused in code) |
| `*_haloween.*` | Both | 7 Halloween-themed variants |

## Connections to Architecture
- Called from `GameManager` (gameplay sounds), `Renderer` (UI sounds), `GameViewController` (music start)
- No rendering dependencies — clean separation
- Ambience system mirrors `ResourceTextures.setAmbience()` for visual theme consistency

## Refactor Risk
- **LOW RISK** — Well-isolated singleton. For WASM port, replace with Web Audio API. The ambience/fallback pattern is reusable.
- **Note:** `activeSoundEffectPlayers` array grows/shrinks per effect — could cause issues with rapid-fire sounds (no pool, new AVAudioPlayer each time).
