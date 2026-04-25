# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

ShuuChuu (集中) is a macOS 26+ menubar app (Swift 6, SwiftUI) that plays categorized white-noise and ambient soundscapes layered as a multi-track mix, with a Liquid-Glass-styled popover and a pomodoro session timer. The repo and SPM target are still named `XNoise` for brevity.

Design spec and implementation plan live under `docs/superpowers/` — read them when making non-trivial changes, they cover decisions not recoverable from the code.

## Build & run

It's an **SPM package**, not an Xcode project — there is no `.xcodeproj`.

```bash
swift run                   # build (if needed) + launch
swift build                 # debug build to .build/debug/XNoise
swift build -c release      # release build to .build/release/XNoise
swift test                  # run XCTest suites (DSP, Catalog, AudioCache, Preferences are current; AppModel/MixingController tests removed during the v2 rewrite — TODO restore)
swift test --filter DSPTests
swift test --filter AudioCacheTests/testLRUEviction
```

To open in Xcode: `open -a Xcode Package.swift`. Xcode recognizes SPM packages directly; pick the `XNoise` scheme and "My Mac" destination.

The app is `LSUIElement = true` — **no Dock icon, no main window**. After launch, look for the 集中 logo in the top-right menubar. To kill a stale instance: `pkill -x XNoise`.

**Bash session CWD drifts.** When running multi-step shell sequences via the Bash tool, prefer absolute paths or `cd /path && cmd` one-liners — a `cd` in one call leaks into the next, which silently broke a build during this session.

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
- **`MixingController`** — one `AVAudioEngine` + master `AVAudioMixerNode`. Each active track is a separate `AVAudioPlayerNode` (or `AVAudioSourceNode` for procedural) attached to the mixer with its own per-node volume. Master volume is on `mixer.outputVolume`. Per-track pause via `pause(trackId:)` (player.pause, doesn't detach) so volume + buffer state survive. `pauseAll()`/`resumeAll()` is master-pause; independent of per-track state.
- **`FocusSession` + `FocusSettings`** — pomodoro state (focus / short-break / long-break cycles) and persisted timing settings.
- **`DesignSettings`** — accent hue (single source — derived expressions live in `XNTokens`), wallpaper mode, theme (system/dark/light), glass blur/opacity/stroke. Backed by UserDefaults.
- **`Favorites`** — persisted set of starred track ids.
- **`AudioCache`** (SHA-256 keyed, LRU eviction) — used only by `StreamedNoiseSource`. The cache filename *is* the track's SHA-256 in the catalog, so path derivation and integrity verification are the same operation.
- **`Preferences`** — thin `UserDefaults` wrapper for `volume`, `lastCategoryId`, `resumeOnWake`, `resumeOnLaunch`.

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

## macOS 26 SwiftUI gotchas

- **`@EnvironmentObject` for observed objects, not init params.** Passing `@ObservedObject` through view initializers triggers `_ButtonGesture.internalBody` MainActor crashes inside `MenuBarExtra` popovers.
- **Don't `@MainActor`-annotate UserDefaults wrappers.** It inserts spurious runtime isolation checks during view body computation that null-deref `swift_task_isMainExecutorImpl` on macOS 26.3.x. Reserve `@MainActor` for things that genuinely need it (audio engine, UI orchestration).
- **`.background(.material, in: Shape)` is reliable; `Rectangle().fill(.material)` in a ZStack background is not** — same crash class as above.
- **`.contentShape(Rectangle())` must come AFTER `.clipShape(...)`.** A rounded clip strips hit-test from the corners; contentShape after re-claims a full rect.
- **SwiftUI gradients (`RadialGradient`/`LinearGradient`) don't claim hit-testing.** Add a `Color` floor first in a ZStack if you need cursor capture in a gradient-only region.
- **System `Slider` has a thumb + an extended hit region** that flips the cursor to ↔. For thin volume bars, use the custom `ThumblessSlider` / `MiniVolumeSlider` patterns in `Sources/XNoise/UI/Components/`.
- **`.scrollIndicators(.never)` is more aggressive than `.hidden`** — the latter still leaves a scroll-tracking area near content edges that flips the cursor to ↕ on macOS NSScrollView.
- **`Button { action } label: { ... }` with `.buttonStyle(.plain)` last.** Modifiers chained after the Button (instead of inside the label) interact badly with custom backgrounds.
- **Cursor weirdness over the popover is often the host app (Warp etc.) using `NSEvent.addGlobalMonitorForEvents`,** not our bug. Cursor management is independent of event delivery; events go to the topmost window but cursor shape is set by tracking areas across all windows.

## Audio engine format

`AVAudioEngine.connect(_:to:format:)` with `format: nil` crashes if any other node attached to the destination has a different sample rate or channel count. `MixingController.addOrUpdate` reads each source's `audioFormat` (the loaded buffer's PCM format) and passes it explicitly so the mixer format-converts per-input. When adding a new `NoiseSource` implementation, expose `var audioFormat: AVAudioFormat?` and follow the same pattern.

## Mix persistence

The active mix (track ids, per-track volumes, paused state, master pause) is snapshotted to `UserDefaults` (`x-noise.savedMix`) on every mutation and restored on launch. Mutations must go through `AppModel` (`toggleTrack`, `setTrackVolume`, `removeTrack`, `togglePause`, `togglePlayAll`, `applyPreset`) — calling `MixingController` directly bypasses `persistMix()`.

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
