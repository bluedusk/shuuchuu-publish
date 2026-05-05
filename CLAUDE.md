# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Shuuchuu (集中) is a macOS 26+ menubar app (Swift 6, SwiftUI) that plays categorized white-noise and ambient soundscapes layered as a multi-track mix, with a Liquid-Glass-styled popover and a pomodoro session timer. The repo working directory is still `~/playground/x-noise/` and the GitHub release repo is `bluedusk/shuuchuu-publish` — the SPM target / Swift module / on-disk app are all `Shuuchuu`.

Design spec and implementation plan live under `docs/superpowers/` — read them when making non-trivial changes, they cover decisions not recoverable from the code. (Older plans/specs reference the previous `XNoise`/`x-noise` names — those are frozen historical artifacts and intentionally weren't rewritten.)

## Build & run

It's an **SPM package**, not an Xcode project — there is no `.xcodeproj`.

```bash
swift run                   # build (if needed) + launch
swift build                 # debug build to .build/debug/Shuuchuu
swift build -c release      # release build to .build/release/Shuuchuu
swift test                  # 154 tests — DSP, Catalog, AudioCache, Preferences, AppModel (gating + save-mix + soundtrack), Soundtracks (URL, persistence, library, filter, tags), Scenes (controller, library), License, FocusSession, ProceduralNoiseSource, StreamedNoiseSource, SavedMixes, SoundtrackPersistence, Smoke
swift test --filter DSPTests
swift test --filter AudioCacheTests/testLRUEviction
```

To open in Xcode: `open -a Xcode Package.swift`. Xcode recognizes SPM packages directly; pick the `Shuuchuu` scheme and "My Mac" destination.

The app is `LSUIElement = true` — **no Dock icon, no main window**. After launch, look for the 集中 logo in the top-right menubar. To kill a stale instance: `pkill -x Shuuchuu`.

**Bash session CWD drifts.** When running multi-step shell sequences via the Bash tool, prefer absolute paths or `cd /path && cmd` one-liners — a `cd` in one call leaks into the next, which silently broke a build during this session.

**Propose a commit after every logical chunk of work.**

## Catalog regeneration

Tracks and categories are declared in `Sources/Shuuchuu/Resources/catalog.json`, generated from the filenames in `Sources/Shuuchuu/Resources/sounds/`:

```bash
python3 scripts/gen-catalog.py > Sources/Shuuchuu/Resources/catalog.json
```

The generator hard-codes category assignments in its `CATEGORIES` list. When adding a new MP3, drop it into `Sources/Shuuchuu/Resources/sounds/` and add its id (filename stem) to the right category in `scripts/gen-catalog.py`.

Both `sounds/` and `catalog.json` are gitignored — they're treated as local content, not repo-owned.

## Downloading YouTube audio / video

Use `yt-dlp` (already installed). Sandbox source clips into `my_sounds/` (gitignored) — never write into `Resources/sounds/` directly; that path is for curated catalog assets only.

**Audio only** (default for ambience sourcing — no transcode, raw stream off the CDN):
```bash
yt-dlp -f bestaudio --download-sections "*5:00-8:00" --force-keyframes-at-cuts \
       --restrict-filenames -o "my_sounds/%(id)s_%(title).60s_5-8.%(ext)s" "URL"
```
- `bestaudio` on YouTube is itag 251 (Opus ~128–160k VBR in `.webm`/Matroska).
- macOS CoreAudio reads `.opus` (Ogg) but **not** `.webm`. Remux without re-encoding: `ffmpeg -i in.webm -c:a copy out.opus`.
- For the catalog (cross-platform, incl. future Windows): transcode to MP3 128k, don't ship Opus.

**Video**: swap the format selector — `-f "bestvideo[height<=1080]+bestaudio"` (yt-dlp invokes `ffmpeg` to mux). `-F URL` lists every available stream.

**Bulk fetch**: `scripts/fetch-ambience.sh` is the reference pipeline — query list → `--match-filter "view_count > 200000 & duration > 600"` → dedup by id → top-N by views → parallel `xargs -P 3` downloads with `--download-archive` for idempotency. Copy and edit the QUERIES array for new themes.

**Failure modes**: members-only / age-gated / region-locked / DRM'd content fails (cookies via `--cookies-from-browser chrome` fixes the first three). Premium-only itags (141 AAC 256k) silently fall back to free-tier. If extraction errors appear, `brew upgrade yt-dlp` — YouTube changes its player JS every few weeks.

## Architecture

`AppModel` (`@MainActor, ObservableObject`) is a thin orchestrator. It owns the dependency graph and routes user intents to `MixState` (which `MixingController` reconciles into audio). **All mix mutations go through `MixState` — `AppModel` doesn't touch the audio engine directly.** Subsystems wired in:

- **`Catalog`** — fetches and decodes `catalog.json`; publishes a `loading | ready | offline | error` state with stale-while-revalidate semantics. Production uses `BundleCatalogFetcher` (reads from `Bundle.module`); tests inject stubs. Cached copy is persisted to `~/Library/Application Support/shuuchuu/catalog.json` for optimistic loads.
- **`MixState`** — the user-intent layer (track ids + per-track volumes + paused flags). Persisted to `UserDefaults` (`shuuchuu.savedMix`), debounced 200ms via `schedulePersist()`. `flushPersist()` lands pending writes synchronously (called from `AppModel.handleSleep`).
- **`MixingController`** — one `AVAudioEngine` + master `AVAudioMixerNode`. Each active track wires `source.node → trackMixer → masterMixer → engine.mainMixerNode`. Per-track volume **and** per-track pause are uniform: `trackMixer.outputVolume` (set to per-track volume, or 0 when paused) — works for both `AVAudioPlayerNode`-backed and `AVAudioSourceNode`-backed sources. Master volume is on `masterMixer.outputVolume`. In-flight `attachSource` Tasks are tracked and cancelled on `detach`/`stopAll`.
- **`AudioMode`** (`Models/AudioMode.swift`) — source of truth for which pipeline is active: `.idle`, `.mix`, `.soundtrack(id)`. `AppModel.activeSourcePaused` reads from the right side.
- **`FocusSession` + `FocusSettings`** — pomodoro state (focus / short-break / long-break cycles) and persisted timing settings.
- **`DesignSettings`** — accent hue (single source — derived expressions live in `SHTokens`), wallpaper mode, glass blur/opacity/stroke. Dark-mode only — there is no theme switch. Backed by UserDefaults.
- **`Favorites`** — persisted set of starred track ids.
- **`SavedMixes`** — persisted user-named mix presets. Distinct from built-in `Presets`; both feed `AppModel.matchLoadedMix`.
- **`SoundtracksLibrary` + `WebSoundtrackControlling`** — see [Soundtracks subsystem](#soundtracks-subsystem) below.
- **`ScenesLibrary` + `SceneController` + `ShaderRendering`** — see [Scenes subsystem](#scenes-subsystem) below.
- **`LicenseController`** — see [License subsystem](#license-subsystem) below.
- **`AudioCache`** (actor, SHA-256 keyed, LRU eviction) — used only by `StreamedNoiseSource`. The cache filename *is* the track's SHA-256 in the catalog, so path derivation and integrity verification are the same operation. In-flight fetches are deduplicated per sha256.
- **`Preferences`** — thin `UserDefaults` wrapper for `volume`, `lastCategoryId`, `resumeOnWake`, `resumeOnLaunch`.

Track playback is polymorphic via the `NoiseSource` protocol (`AnyObject & Sendable`), with three implementations dispatched by `Track.Kind` in the catalog:

- **`ProceduralNoiseSource`** (`kind: "procedural"`) — wraps `AVAudioSourceNode` around a DSP kernel (`Sources/Shuuchuu/Audio/DSP/*.swift` — white/pink/brown/green/fluorescent). No I/O, always `isReady = true`.
- **`BundledNoiseSource`** (`kind: "bundled"`) — loads an MP3 from `Bundle.module` and schedules it on an `AVAudioPlayerNode` with `.loops`. This is the only kind currently used end-to-end.
- **`StreamedNoiseSource`** (`kind: "streamed"`) — same as bundled but the file is fetched through `AudioCache` first. Infrastructure exists but nothing in the shipping catalog uses this kind yet; it's the designed R2 path for future distribution.

## Soundtracks subsystem

Parallel playback pipeline to the mix: the user can paste a YouTube or Spotify URL, and the active soundtrack plays in a hidden long-lived `WKWebView` driven by injected JS bridges (`Sources/Shuuchuu/Resources/soundtracks/{youtube,spotify}-bridge.html` + `youtube-control.js`). The web view is owned by `WebSoundtrackController` (concrete) which implements `WebSoundtrackControlling` (protocol) — `AppModel` only sees the protocol; tests use `MockSoundtrackController`. The protocol vends a SwiftUI player view via `playerView() -> AnyView`, so UI rows never import `WebKit`.

- `AudioMode` flips are synchronous; the underlying audio attach/load is async.
- `SoundtracksLibrary` persists user-added `WebSoundtrack` entries.
- JS bridge calls go through `bridgeCall(method:, args:)` — args are JSON-encoded via `JSONSerialization` (with U+2028/U+2029 post-escape), never string-interpolated. `methodPath` is always a code constant.
- Identity-bound bridge events (`titleChanged` / `signInRequired` / `error`) are gated on a per-load generation token (`bridgeReadyForId`) so a stale message from a previous load can't write under a new entry's id.

## Scenes subsystem

Animated shader-backed backgrounds layered above `Wallpaper` (the static OKLCH gradient). Picking a scene from the FocusPage chip swaps `SceneBackground`'s host content; clearing the scene falls back to the wallpaper.

- **`Scene`** (`Models/Scene.swift`) — declarative scene metadata.
- **`ScenesLibrary`** — registry of available scenes (aurora, starfield, soft-waves, rainfall, plasma starters).
- **`SceneController`** — picks/warms/compiles scenes; emits compile failures as warnings, never crashes.
- **`ShaderRendering`** (protocol) / **`ShaderRenderer`** (concrete) — Metal shader pipeline. Tests inject `StubShaderRenderer`.

## License subsystem

LemonSqueezy-backed paywall (5-day trial, 3-device limit, soft revalidate). Lives in `Sources/Shuuchuu/License/`:

- **`LicenseController`** — orchestrates trial start, activation, validation, gating; published `LicenseState` is read by `LockedView` and feature gates throughout the UI.
- **`LemonSqueezyClient`** — HTTP client for the LS API.
- **`LicenseStorage`** — keychain-backed persistence of license keys + activation state.

`license.startTrialIfNeeded()` is called synchronously in `AppModel.init` before any soundtrack-restore that depends on `license.isUnlocked`, and before any SwiftUI surface reads `model.license.state`.

## Releases

In-app updates use Sparkle 2.9 (SPM dep). The appcast lives at `appcast.xml` (repo root) and is served via `https://raw.githubusercontent.com/bluedusk/shuuchuu-publish/main/appcast.xml`. Binaries ship through GitHub Releases on `bluedusk/shuuchuu-publish`.

To cut a release:

```bash
./scripts/release.sh 0.2.0 "Brief changelog message"
./scripts/release.sh 0.2.0                # auto-generate from git log since prev tag
./scripts/release.sh --beta 0.3.0-beta.1  # beta channel + GitHub pre-release
```

Required `.env` (gitignored):
- `SPARKLE_EDDSA_KEY` — base64 EdDSA private key (one-time generated via Sparkle's `generate_keys`).
- `X_NOISE_SIGN_IDENTITY` — `Developer ID Application: <name> (<team>)`.
- `X_NOISE_NOTARY_PROFILE` — keychain profile from `xcrun notarytool store-credentials`.

The script bumps `CFBundleShortVersionString` + `CFBundleVersion` in `Sources/Shuuchuu/Resources/Info.plist`, builds, signs with hardened runtime + `config/packaging/Shuuchuu.entitlements`, notarises, staples, tags, pushes to GitHub Releases, EdDSA-signs the zip, and prepends a new `<item>` to `appcast.xml`.

**EdDSA keys** (one-time): after `swift build` resolves Sparkle, run `.build/artifacts/sparkle/Sparkle/bin/generate_keys`. Public key replaces the placeholder in `Info.plist`'s `SUPublicEDKey`. Private key is exported with `generate_keys -x` and stored offline + as `SPARKLE_EDDSA_KEY` in `.env`. The placeholder pubkey currently in `Info.plist` is `AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=` and **must be replaced** before the first signed release.

**Beta channel:** users tap the version row in Settings → Updates 5 times within 3 s to reveal a "Beta updates" toggle. The toggle is `UserDefaults["app.betaUpdates"]`; when on, `UpdateChecker.allowedChannels(for:)` returns `["beta"]` and Sparkle includes appcast items tagged `<sparkle:channel>beta</sparkle:channel>`.

## Conventions to preserve

- **Single audio engine.** `MixingController` is the only thing that touches `AVAudioEngine`. If you need another audio pipeline, add a new `NoiseSource` implementation — don't spin up a second engine.
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
- **System `Slider` has a thumb + an extended hit region** that flips the cursor to ↔. For thin volume bars, use the custom `ThumblessSlider` / `MiniVolumeSlider` patterns in `Sources/Shuuchuu/UI/Components/`.
- **`.scrollIndicators(.never)` is more aggressive than `.hidden`** — the latter still leaves a scroll-tracking area near content edges that flips the cursor to ↕ on macOS NSScrollView.
- **`Button { action } label: { ... }` with `.buttonStyle(.plain)` last.** Modifiers chained after the Button (instead of inside the label) interact badly with custom backgrounds.
- **Cursor weirdness over the popover is often the host app (Warp etc.) using `NSEvent.addGlobalMonitorForEvents`,** not our bug. Cursor management is independent of event delivery; events go to the topmost window but cursor shape is set by tracking areas across all windows.

## Audio engine format

`AVAudioEngine.connect(_:to:format:)` with `format: nil` crashes if any other node attached to the destination has a different sample rate or channel count. `MixingController.attachSource(for:)` reads each source's `audioFormat` (the loaded buffer's PCM format) and passes it explicitly so the mixer format-converts per-input. When adding a new `NoiseSource` implementation, expose `var audioFormat: AVAudioFormat?` and follow the same pattern.

## Mix persistence

Only `id` + `volume` are persisted to `UserDefaults` (`shuuchuu.savedMix`). Per-track paused state is per-session — every launch starts with all tracks paused (the user explicitly plays them). Writes are debounced 200ms via `MixState.schedulePersist`; `MixState.flushPersist()` lands pending writes synchronously and is called from `AppModel.handleSleep`. Mutations must go through `AppModel` (`toggleTrack`, `setTrackVolume`, `removeTrack`, `togglePause`, `togglePlayAll`, `applyPreset`, `applySavedMix`) — calling `MixingController` directly bypasses `MixState`.

## Testing

154 unit tests across DSP, Catalog, AudioCache, Preferences, AppModel (gating + save-mix + soundtrack flows), Soundtracks (URL parsing, persistence, library, filter state, tags), Scenes (controller + library), License (state + controller), FocusSession, ProceduralNoiseSource, StreamedNoiseSource, SavedMixes, and Smoke. UI is preview-only — there are no snapshot tests. When adding a new track kind or source type, add tests alongside the existing `*Tests.swift` files in `Tests/ShuuchuuTests/`.

For tests that need an audio fixture, reuse `Tests/ShuuchuuTests/Fixtures/loop-1s.caf` (a 1-second 440Hz tone) or regenerate it with the Python + `afconvert` snippet shown in the implementation plan (`docs/superpowers/plans/2026-04-23-x-noise.md`, Task 10).

## Explicitly out of scope (follow-ups, not bugs)

These are intentionally deferred — don't "fix" them in passing:

- Crossfade between sources (currently hard-swap)
- `.AVAudioEngineConfigurationChange` handling for headphone plug/unplug
- Real tile loading-progress wiring (`PopoverView.tileState(for:)` hardcodes `progress: 0`)
- Keyboard navigation + VoiceOver labels
- `NSApplication.willTerminateNotification` fade-on-quit
- App Sandbox entitlements + code signing + notarization
- R2 bucket upload + making `StreamedNoiseSource` actually used
