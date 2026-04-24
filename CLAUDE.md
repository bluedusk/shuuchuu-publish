# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

x-noise is a macOS 26+ menubar app (Swift 6, SwiftUI, Liquid Glass) that plays categorized white-noise and ambient soundscapes. It mirrors Momentum's Sounds UX as a native menubar experience.

Design spec and implementation plan live under `docs/superpowers/` — read them when making non-trivial changes, they cover decisions not recoverable from the code.

## Build & run

It's an **SPM package**, not an Xcode project — there is no `.xcodeproj`.

```bash
swift run                   # build (if needed) + launch
swift build                 # debug build to .build/debug/XNoise
swift build -c release      # release build to .build/release/XNoise
swift test                  # run all XCTest suites (34 tests today)
swift test --filter DSPTests
swift test --filter AudioCacheTests/testLRUEviction
```

To open in Xcode: `open -a Xcode Package.swift`. Xcode recognizes SPM packages directly; pick the `XNoise` scheme and "My Mac" destination.

The app is `LSUIElement = true` — **no Dock icon, no main window**. After launch, look for a waveform icon in the top-right menubar. To kill a stale instance: `pkill -x XNoise`.

## Catalog regeneration

Tracks and categories are declared in `Sources/XNoise/Resources/catalog.json`, generated from the filenames in `Sources/XNoise/Resources/sounds/`:

```bash
python3 scripts/gen-catalog.py > Sources/XNoise/Resources/catalog.json
```

The generator hard-codes category assignments in its `CATEGORIES` list. When adding a new MP3, drop it into `Sources/XNoise/Resources/sounds/` and add its id (filename stem) to the right category in `scripts/gen-catalog.py`.

Both `sounds/` and `catalog.json` are gitignored — they're treated as local content, not repo-owned.

## Architecture

`AppModel` (`@MainActor, ObservableObject`) is the single orchestrator. It wires four subsystems and routes all user actions:

- **`Catalog`** — fetches and decodes `catalog.json`; publishes a `loading | ready | offline | error` state with stale-while-revalidate semantics. Production uses `BundleCatalogFetcher` (reads from `Bundle.module`); tests inject stubs. Cached copy is persisted to `~/Library/Application Support/x-noise/catalog.json` for optimistic loads.
- **`AudioController`** — owns one `AVAudioEngine` + one `AVAudioMixerNode`; exactly one `NoiseSource` is attached at a time. User-visible volume lives on `mixer.outputVolume` so it survives source swaps. `play()` / `stop()` ramp the mixer for fade-in (150ms) / fade-out (300ms). No crossfade yet — source swaps are hard stop-then-start (deferred follow-up).
- **`AudioCache`** (SHA-256 keyed, LRU eviction) — used only by `StreamedNoiseSource`. The cache filename *is* the track's SHA-256 in the catalog, so path derivation and integrity verification are the same operation.
- **`Preferences`** — a thin `UserDefaults` wrapper for `lastTrackId`, `volume`, `lastCategoryId`, `resumeOnWake`, `resumeOnLaunch`.

Track playback is polymorphic via the `NoiseSource` protocol (`AnyObject & Sendable`), with three implementations dispatched by `Track.Kind` in the catalog:

- **`ProceduralNoiseSource`** (`kind: "procedural"`) — wraps `AVAudioSourceNode` around a DSP kernel (`Sources/XNoise/Audio/DSP/*.swift` — white/pink/brown/green/fluorescent). No I/O, always `isReady = true`.
- **`BundledNoiseSource`** (`kind: "bundled"`) — loads an MP3 from `Bundle.module` and schedules it on an `AVAudioPlayerNode` with `.loops`. This is the only kind currently used end-to-end.
- **`StreamedNoiseSource`** (`kind: "streamed"`) — same as bundled but the file is fetched through `AudioCache` first. Infrastructure exists but nothing in the shipping catalog uses this kind yet; it's the designed R2 path for future distribution.

## Conventions to preserve

- **Single audio engine.** `AudioController` is the only thing that touches `AVAudioEngine`. If you need another audio pipeline, add a new `NoiseSource` implementation — don't spin up a second engine.
- **Swift 6 strict concurrency is on.** Source types are classes (for `AVAudioNode` identity) so they're marked `@unchecked Sendable`. Mutation happens inside `AVAudioSourceNode`'s render block (audio thread) or on `@MainActor`; those don't overlap. When adding a source type, follow the same pattern — `RendererBox` in `ProceduralNoiseSource.swift` is the template for audio-thread state.
- **Info.plist is embedded via linker**, not bundled. `Package.swift` uses `-sectcreate __TEXT __info_plist` *and* `exclude: ["Resources/Info.plist"]` on the executable target. Don't remove the `exclude:` — doing so reintroduces a double-handling warning.
- **UI uses Liquid Glass (macOS 26 only).** `GlassEffectContainer`, `.glassEffect()`, `.buttonStyle(.glass)` / `.glassProminent`. There is no fallback path for older macOS.
- **No modals for error states.** Catalog and track failures surface inline (offline pill, per-tile error state). The `PopoverView` is the only user surface.

## Testing

DSP, Catalog, AudioCache, Preferences, AppModel, and the noise source wrappers all have unit tests. UI is preview-only — there are no snapshot tests. When adding a new track kind or source type, add tests alongside the existing `*Tests.swift` files in `Tests/XNoiseTests/`.

For tests that need an audio fixture, reuse `Tests/XNoiseTests/Fixtures/loop-1s.caf` (a 1-second 440Hz tone) or regenerate it with the Python + `afconvert` snippet shown in the implementation plan (`docs/superpowers/plans/2026-04-23-x-noise.md`, Task 10).

## Explicitly out of scope (follow-ups, not bugs)

These are intentionally deferred — don't "fix" them in passing:

- Crossfade between sources (currently hard-swap)
- `.AVAudioEngineConfigurationChange` handling for headphone plug/unplug
- Real tile loading-progress wiring (`PopoverView.tileState(for:)` hardcodes `progress: 0`)
- Keyboard navigation + VoiceOver labels
- `NSApplication.willTerminateNotification` fade-on-quit
- App Sandbox entitlements + code signing + notarization
- R2 bucket upload + making `StreamedNoiseSource` actually used
