# x-noise — Design Spec

**Date:** 2026-04-23
**Status:** Draft, approved in brainstorming session
**Target:** macOS 26+ (Liquid Glass), Swift 6 / SwiftUI

---

## 1. Overview

x-noise is a macOS menubar app for playing categorized white-noise and ambient soundscapes. It mirrors the Sounds UX of the Momentum Chrome extension (categories: Noise, Soundscapes, Ambient, Binaural, Speech Blocker), reimagined as a native menubar experience using the Liquid Glass design language.

### Goals

- Stream a CDN-hosted catalog of ambient tracks, cache-on-demand for offline use.
- Provide procedurally generated noise colors (White, Pink, Brown, Green, Fluorescent Hum) that play with zero network dependency.
- Liquid-Glass-styled popover with a category browser, track grid, and persistent now-playing bar.
- Live-updating menubar icon reflecting playing state.
- Smooth crossfades when switching tracks; fades in/out on start/stop.
- Resilient offline behavior: cached catalog and cached tracks keep working without network.

### Non-goals (v1)

- No focus sessions, no session timer, no pomodoro, no daily/lifetime stats.
- No site blocker.
- No Spotify, YouTube, or custom-upload integrations.
- No preferences window (settings live in the popover's ellipsis menu).
- No iCloud sync.
- No dock icon; `LSUIElement = true` — menubar only.
- No telemetry.
- No in-app onboarding.

---

## 2. Architecture

```
┌──────────────────────────────────────────────────────────┐
│  XNoiseApp  (@main, App)                                 │
│    MenuBarExtra(style: .window)                          │
│      ├─ MenubarLabel                                     │
│      └─ PopoverView                                      │
└─────────────────────┬────────────────────────────────────┘
                      │ .environmentObject
                      ▼
┌──────────────────────────────────────────────────────────┐
│  AppModel  (@MainActor, ObservableObject)                │
│    ├─ catalog:  Catalog                                  │
│    ├─ audio:    AudioController                          │
│    ├─ cache:    AudioCache                               │
│    └─ prefs:    Preferences                              │
└───────┬────────────────┬─────────────────┬───────────────┘
        ▼                ▼                 ▼
┌──────────────┐   ┌─────────────────┐   ┌──────────────────┐
│ Catalog      │   │ AudioController │   │ AudioCache       │
│ JSON fetch,  │   │ AVAudioEngine   │   │ download-to-disk │
│ decode,      │   │ + mixer node    │   │ SHA-256 verify,  │
│ state        │   │ + active        │   │ LRU eviction     │
│ machine      │   │   NoiseSource   │   │                  │
└──────────────┘   └─────────────────┘   └──────────────────┘
```

### Subsystem responsibilities

**`AppModel`** — single orchestrator and UI entry point. Holds references to the four subsystems, exposes published state (`isPlaying`, `currentTrack`, `volume`, `catalogState`), and routes user actions (`play(track:)`, `stop()`, `setVolume(_:)`, `selectCategory(_:)`). It owns the crossfade orchestration when a new track is picked while another is playing.

**`Catalog`** — fetches and decodes `catalog.json` from the R2-hosted CDN. Publishes a state enum: `.loading | .ready([Category]) | .offline(stale: [Category]?) | .error`. Uses stale-while-revalidate: shows cached catalog immediately, refreshes in the background. Default `URLSession` + `URLCache` handles ETag/Last-Modified revalidation.

**`AudioController`** — owns exactly one `AVAudioEngine` with a single `AVAudioMixerNode`. Exactly one `NoiseSource` is attached at a time (plus a transient second source during crossfades). Volume is controlled on the mixer so it survives source swaps.

**`AudioCache`** — given a track's remote URL and expected SHA-256, returns a local file URL. Downloads on miss, verifies integrity, stores in `~/Library/Caches/x-noise/<sha256>.<ext>`. LRU eviction when total cached size exceeds 500 MB. The currently-playing file is exempt from eviction.

**`Preferences`** — a thin wrapper over `UserDefaults`. Persists `lastTrackId`, `volume`, `lastCategoryId`, `resumeOnWake`, `resumeOnLaunch`.

### Data flow (playback)

1. User taps a track tile → `AppModel.play(track:)`.
2. `AppModel` constructs the appropriate `NoiseSource`:
   - `procedural` kind → `ProceduralNoiseSource(variant:)` — no I/O.
   - `streamed` kind → `StreamedNoiseSource(track:, cache:)` — may block on download.
3. `AppModel` asks `audio` to swap sources. `AudioController` calls `source.prepare()` (awaitable), then crossfades from the previous source (if any) to the new one.
4. UI observes `audio.state` and updates tile + now-playing-bar accordingly.

---

## 3. Audio pipeline

### `NoiseSource` protocol

```swift
protocol NoiseSource: Sendable {
    var id: String { get }
    var displayName: String { get }
    var node: AVAudioNode { get }
    var isReady: Bool { get }
    func prepare() async throws
}
```

Three implementations:

**`ProceduralNoiseSource`** — wraps `AVAudioSourceNode`. One per variant (`.white`, `.pink`, `.brown`, `.green`, `.fluorescent`). Always `isReady = true`. `prepare()` is a no-op.

DSP kernels (executed inside the `AVAudioSourceNode` render block, one-per-sample):

- **White** — `Float.random(in: -1...1)` per sample (or a faster xorshift RNG for lower jitter; decide in implementation).
- **Pink** — Paul Kellet's 5-pole filter, public-domain algorithm. Five running accumulators, ~10 multiply-adds per sample.
- **Brown** — integrated white with leaky feedback: `b = 0.98 * b + 0.02 * white`, then scaled.
- **Green** — white filtered through a band-pass centered at 500 Hz, Q ≈ 0.7.
- **Fluorescent Hum** — 60 Hz sine + 120/180 Hz harmonics with tiny phase jitter to simulate ballast buzz.

Render blocks are `@Sendable`. CPU cost is negligible (<1% of one core at 48 kHz stereo).

**`StreamedNoiseSource`** — wraps `AVAudioPlayerNode`. `prepare()`:

1. `let localURL = try await cache.localURL(for: track)`
2. `let file = try AVAudioFile(forReading: localURL)`
3. Allocate an `AVAudioPCMBuffer` matching the file's length; `try file.read(into: buffer)`.
4. `playerNode.scheduleBuffer(buffer, at: nil, options: .loops, completionHandler: nil)` — seamless gapless loop.
5. Flip `isReady = true`.

When `AudioController.play()` is called after `prepare()`, it invokes `playerNode.play()`.

**`BundledNoiseSource`** — reserved code path for any very small tracks we might ship inside the app bundle. Probably unused in v1 since everything's on R2, but the protocol shape supports it without rework.

### `AudioController`

```swift
@MainActor
final class AudioController: ObservableObject {
    enum State: Equatable {
        case idle
        case loading(TrackID)
        case playing(TrackID)
        case error(String)
    }

    @Published private(set) var state: State = .idle
    @Published var volume: Float = 0.7

    private let engine = AVAudioEngine()
    private let mixer = AVAudioMixerNode()
    private var current: NoiseSource?

    init() {
        engine.attach(mixer)
        engine.connect(mixer, to: engine.mainMixerNode, format: nil)
    }

    func play(_ source: NoiseSource) async { /* swap + prepare + fade in */ }
    func stop() async { /* fade out + pause engine */ }
}
```

### Crossfade when switching sources

When a new track is played while another is already playing, we crossfade by briefly attaching both sources to a `CrossfadeMixer` sub-mixer:

1. Attach new source's node to a second input on the sub-mixer (or the main mixer with a per-node volume ramp).
2. In parallel: ramp old source volume from target → 0 over 300 ms; ramp new source volume from 0 → target over 300 ms.
3. When old ramp completes: detach old source, free its buffer memory.

Ramps use a `CADisplayLink` (via `NSScreen`'s display-link API on macOS) for frame-accurate smoothing.

### Fades (single source)

- **Start** — 150 ms fade-in on `mixer.outputVolume` from 0 → target.
- **Stop** — 300 ms fade-out from current → 0, then `engine.pause()`.

### Memory budget

Raw PCM at 44.1 kHz stereo is 353 KB/sec. A 60 s loop = ~21 MB in memory. To stay on the single-buffer code path, **track files in the catalog should be ≤ 60 s** (this is enforced by the CDN-side authoring, not by the app).

If we ever need longer tracks, the fallback is `AVAudioFile` + `scheduleSegments` streaming in chunks. Out of scope for v1.

### Lifecycle / interruption

- `NSWorkspace.willSleepNotification` → `AudioController.stop()`. Remember `wasPlayingTrackId` in memory only.
- `NSWorkspace.didWakeNotification` → if `prefs.resumeOnWake == true` and `wasPlayingTrackId` set, replay it.
- `.AVAudioEngineConfigurationChange` → rebuild engine connections (handles headphone plug/unplug).

---

## 4. Catalog + cache

### Hosting

Cloudflare R2 public bucket, HTTPS-only. App knows only the catalog URL (hardcoded build-time constant); all track URLs come from the catalog document. Zero egress cost on R2 is the reason for choosing it.

### Catalog schema

`https://<r2-domain>/catalog.json`:

```json
{
  "schemaVersion": 1,
  "categories": [
    {
      "id": "noise",
      "name": "Noise",
      "tracks": [
        {
          "id": "white",
          "name": "White Noise",
          "kind": "procedural",
          "variant": "white"
        }
      ]
    },
    {
      "id": "soundscapes",
      "name": "Soundscapes",
      "tracks": [
        {
          "id": "rain",
          "name": "Rain",
          "kind": "streamed",
          "url": "https://cdn.x-noise.app/tracks/rain.caf",
          "sha256": "a1b2...",
          "bytes": 3456789,
          "durationSec": 60,
          "artworkUrl": "https://cdn.x-noise.app/art/rain.jpg"
        }
      ]
    }
  ]
}
```

**Track `kind`:**
- `"procedural"` — `ProceduralNoiseSource` constructed locally; `variant` required.
- `"streamed"` — `StreamedNoiseSource`; `url` and `sha256` required.

**Other track fields:**
- `bytes` — used for progress UI ("downloading 2 MB / 3 MB").
- `durationSec` — informational display.
- `artworkUrl` — optional; SF Symbol placeholder if absent.

### `Catalog` service

```swift
@MainActor
final class Catalog: ObservableObject {
    enum State {
        case loading
        case ready([Category])
        case offline(stale: [Category]?)
        case error(String)
    }
    @Published private(set) var state: State = .loading
    func refresh() async { ... }
}
```

Stale-while-revalidate fetch strategy:

1. At launch, read `~/Library/Application Support/x-noise/catalog.json` if present → publish `.ready(cached)` immediately.
2. In background, hit the CDN. `URLSession.shared` handles ETag/Last-Modified via the default `URLCache`.
3. On success → decode, atomic-replace the local file, publish `.ready(fresh)`.
4. On network failure with cached data → stay on `.ready(cached)` silently.
5. On network failure with no cache → `.offline(stale: nil)` with an inline retry UI.

Manual refresh: an entry in the popover's ellipsis menu, for debugging.

### `AudioCache` service

```swift
actor AudioCache {
    func localURL(
        for track: StreamedTrack,
        progress: AsyncStream<Double>.Continuation? = nil
    ) async throws -> URL

    func evictIfOver(limit: Int64 = 500 * 1024 * 1024) async
    func clear() async
}
```

**Location:** `~/Library/Caches/x-noise/` (system `.cachesDirectory`; macOS may purge under disk pressure, which is correct for streamed content).

**Filename:** `<sha256>.<ext>` derived from the catalog's `sha256` field. Using the hash as the filename means integrity verification and path derivation are the same operation — if the file exists on disk at that path, it has already been verified.

**Download:**
1. `URLSession.shared.download(from: track.url)`.
2. Compute SHA-256 on the downloaded file.
3. If it matches `track.sha256` → atomic rename into `<cacheDir>/<sha256>.<ext>`.
4. If not → delete, throw `.integrityFailed`.

**Reuse:** if `<cacheDir>/<sha256>.<ext>` exists, return it without hitting the network.

**Progress:** `URLSession`'s download delegate publishes bytes-received; we forward to the optional `AsyncStream<Double>` (0.0–1.0) for tile-level progress UI.

**Eviction:** LRU via file `contentAccessDate`. Runs after every successful download. If total size > 500 MB, delete oldest-accessed until under the limit. Currently-playing track is exempt.

### Preferences (`UserDefaults`)

| Key | Type | Default | Purpose |
|---|---|---|---|
| `x-noise.lastTrackId` | `String?` | `nil` | For resume-on-launch |
| `x-noise.volume` | `Float` | `0.7` | Mixer output volume |
| `x-noise.lastCategoryId` | `String?` | `nil` | Restores selected category tab |
| `x-noise.resumeOnWake` | `Bool` | `false` | Auto-replay on wake |
| `x-noise.resumeOnLaunch` | `Bool` | `false` | Auto-play on app launch |

---

## 5. UI (Liquid Glass)

### Menubar label

Two states only:

- **Idle** — `Image(systemName: "waveform")`.
- **Playing** — same symbol with `.symbolEffect(.variableColor.iterative)`; optionally a 4 pt accent dot beside it.

No time display. No width change between states, so the system UI doesn't reflow.

### Popover — overall structure

Fixed size ~360 × 480 pt. `MenuBarExtra(style: .window)`. Three vertical zones:

```
┌────────────────────────────────────────┐
│  [Noise] [Soundscapes] [Ambient] [⋯]  │  ← category tabs   (zone 1)
├────────────────────────────────────────┤
│                                        │
│   ▣  ▣  ▣                              │
│  White Pink Brown                      │  ← track grid      (zone 2)
│                                        │
│   ▣  ▣                                 │
│  Green Fluorescent                     │
│                                        │
├────────────────────────────────────────┤
│  ● Rain  ──────●──  🔊   ▷/‖  ⋯       │  ← now-playing bar (zone 3)
└────────────────────────────────────────┘
```

**Zone 1 — Category tabs.** Horizontal scrolling row of capsule buttons. Selected uses `.glassEffect(.regular.tint(.accentColor))`; unselected `.glassEffect(.clear)`. Tap → zone 2 crossfades to that category's tracks.

**Zone 2 — Track grid.** 3-column `LazyVGrid` of `TrackTile` views.

**Zone 3 — Now-playing bar.** Persistent after the first play of a session. Shows current track artwork + name, volume slider, play/pause button, ellipsis menu. Hidden only before the first play has occurred in the current app session.

### `TrackTile`

```
┌─────────┐
│         │   96×96 artwork (RoundedRectangle radius 12)
│   ☁️    │      or SF Symbol placeholder
│         │
└─────────┘
   Rain        ← 13pt medium
   60s · 3 MB  ← 11pt .secondary (only while downloading/uncached)
```

States:

- **Idle, cached** → plain thumbnail.
- **Idle, uncached** → thumbnail with cloud-download indicator bottom-right.
- **Loading** → thumbnail dimmed 40%, circular progress ring overlay bound to cache download progress.
- **Playing** → animated equalizer SF Symbol overlay; tile has accent-tinted glass ring.
- **Error** → `xmark.circle.fill` bottom-right; tap retries.

Tap:
- Not playing → `AppModel.play(track)`.
- Currently playing → `AppModel.stop()`.
- Long-press → context menu (Remove from cache, Copy track name).

### Liquid Glass specifics

**Container.** Wrap popover content in `GlassEffectContainer(spacing: 8)` so adjacent glass elements morph coherently when tabs/tiles animate.

**Materials:**
- Popover body: `.ultraThinMaterial` (automatic in `MenuBarExtra(style: .window)` on macOS 26).
- Category tabs: `.glassEffect(.regular)` unselected, `.glassEffect(.regular.tint(.accentColor))` selected, with `.glassEffectID(category.id, in: categoriesNamespace)` for morph animation.
- Now-playing bar: its own `.glassEffect(.regular)` panel, anchored to bottom.
- Track tiles: no glass on idle — too visually noisy at 3×N repetition. Glass appears on the *playing* tile (highlight ring) and on hover.

**Buttons:**
- Primary play/pause: `.buttonStyle(.glassProminent)` with accent tint.
- Small actions (ellipsis, retry): `.buttonStyle(.glass)`.
- Volume slider: native `Slider`, no custom styling.

**Motion:**
- Category switch: `.transition(.blurReplace)` on the track grid.
- State changes: `withAnimation(.smooth(duration: 0.25))`.
- Playing-tile equalizer icon: `.symbolEffect(.pulse)`.

**Typography + color:**
- System fonts only (`.body`, `.caption`, `.caption2`).
- `.accentColor` + semantic colors (`.primary`, `.secondary`). Dark/light mode automatic.

### Empty / loading / offline states

| Condition | UI |
|---|---|
| Catalog loading, no cache | Centered `ProgressView("Loading sounds…")` with glass backdrop |
| Catalog offline, stale cache | Normal UI + orange offline pill at top: `wifi.slash Offline` |
| Catalog offline, no cache | "Can't reach sound library" message + Retry button |
| Track download fails | Per-tile error state; inline error pill in now-playing bar if mid-playback |

### Keyboard + accessibility

- `Space` — toggles play/pause when popover has focus.
- `←/→/↑/↓` — moves focus across the track grid.
- `Return` — plays focused track.
- VoiceOver labels: `"\(track.name), \(category.name), \(stateDescription)"`.
- All glass elements maintain sufficient contrast in their tinted state per Apple's Liquid Glass HIG guidance.

---

## 6. Lifecycle + errors

### Launch

1. Instantiate `AppModel` (holds `Catalog`, `AudioController`, `AudioCache`, `Preferences`).
2. Load `Preferences` from `UserDefaults` (synchronous).
3. `Catalog.refresh()` — publishes cached `.ready` optimistically, hits network in background.
4. Attach `AVAudioEngine` mixer (engine not started yet — no audio thread until first play).
5. If `prefs.resumeOnLaunch == true` and `prefs.lastTrackId` exists: await `.ready`, then `AppModel.play(lastTrack)`.

### Quit (`NSApplication.willTerminateNotification`)

- `AudioController.stop()` (fade-out fits within the ~5 s `willTerminate` budget).
- No stats to flush.
- `UserDefaults` writes are already synchronous.

### Sleep / wake

- Sleep → `stop()`, remember `wasPlayingTrackId` in memory.
- Wake → if `prefs.resumeOnWake == true` and `wasPlayingTrackId` set, replay.

### Audio engine config change

Headphone plug/unplug triggers `.AVAudioEngineConfigurationChange`. Handler: rebuild connections (re-attach current source, reconnect mixer to `mainMixerNode`), restart engine if it was running.

### Popover open/close

Playback is independent of popover visibility. Audio continues when the popover dismisses — this is the whole point of a menubar player.

### Error handling principles

- No modals for non-fatal errors.
- Catalog failures → offline pill + cached data; or retry UI if no cache.
- Download failures → per-tile error + retry affordance.
- SHA-256 mismatch → delete cached file, surface as download error.
- Audio engine start failure → `AudioController.state = .error(msg)`; inline banner in now-playing area. No auto-retry.
- Decode failure → mark cached file bad, delete it, surface as download error.
- No internet + no cache → zone 2 message: "Sound library unavailable." Procedural noise tracks remain fully playable.

Principle: failures reduce to inline states that self-recover when conditions return.

---

## 7. Project layout + testing

### Directory structure

```
x-noise/
├─ XNoise.xcodeproj
├─ XNoise/
│  ├─ XNoiseApp.swift             # @main, scene, env injection
│  ├─ AppModel.swift              # orchestrator
│  ├─ Preferences.swift           # UserDefaults wrapper
│  │
│  ├─ Audio/
│  │  ├─ AudioController.swift    # engine + mixer + crossfade
│  │  ├─ NoiseSource.swift        # protocol
│  │  ├─ ProceduralNoiseSource.swift
│  │  ├─ StreamedNoiseSource.swift
│  │  └─ DSP/
│  │     ├─ WhiteNoiseRender.swift
│  │     ├─ PinkNoiseRender.swift
│  │     ├─ BrownNoiseRender.swift
│  │     ├─ GreenNoiseRender.swift
│  │     └─ FluorescentHumRender.swift
│  │
│  ├─ Catalog/
│  │  ├─ Catalog.swift
│  │  ├─ CatalogModels.swift      # Codable Category, Track
│  │  └─ AudioCache.swift
│  │
│  ├─ UI/
│  │  ├─ MenubarLabel.swift
│  │  ├─ PopoverView.swift
│  │  ├─ CategoryTabs.swift
│  │  ├─ TrackGrid.swift
│  │  ├─ TrackTile.swift
│  │  └─ NowPlayingBar.swift
│  │
│  └─ Resources/
│     └─ Assets.xcassets
│
└─ XNoiseTests/
   ├─ DSPTests.swift
   ├─ CatalogTests.swift
   ├─ AudioCacheTests.swift
   └─ AppModelTests.swift
```

One file = one type where practical. DSP kernels are split per noise color so each stays small and independently testable.

### Testing strategy

- **DSP** — property tests on rendered buffers. White → RMS ≈ 1/√3 for uniform on [-1, 1]; zero-mean within tolerance. Pink → spectral slope ≈ –3 dB/oct (via FFT on a 65 k-sample buffer). Brown → –6 dB/oct. Rendering is offline into pre-allocated buffers; no audio plays during tests.
- **Catalog** — fixture JSON files; test decoder + stale-while-revalidate state machine with injected fake URLSession.
- **AudioCache** — temp-directory-backed; verifies SHA-256 matching, atomic rename, LRU eviction, "cached file reused without network" happy path, and integrity-failure recovery.
- **AppModel** — mocks `AudioController` and `AudioCache`; tests orchestration (play → loading → ready → playing; swap-while-playing triggers crossfade with both sources briefly active).
- **UI** — SwiftUI previews per view (`#Preview("playing")`, `#Preview("error")`, etc.). No snapshot tests in v1.
- **End-to-end** — one XCUITest that launches the app, opens the popover, taps the first track, verifies now-playing bar populates. Requires a reachable dev CDN.

---

## 8. Open items to resolve during planning

- **R2 bucket setup** — decide on bucket name, custom domain (or use public `r2.dev`), catalog.json publishing workflow. Probably a small shell script + a `sounds/` source folder in the repo.
- **Initial track roster** — finalize the list of streamed tracks for v1 (names, lengths, source audio files). Start with ~12 to validate the pipeline end-to-end.
- **Track authoring conventions** — loop point handling, peak normalization target (–14 LUFS?), format (`.caf` vs `.m4a`), stereo vs mono. Keep tracks ≤ 60 s.
- **App icon** — placeholder SF Symbol during development; proper icon pre-ship.
- **Code signing + notarization** — required for distribution outside Mac App Store; decide distribution channel (direct download vs MAS) before ship.
- **Entitlements + sandbox** — App Sandbox on, hardened runtime on. Entitlements needed: `com.apple.security.network.client` (catalog + track downloads), `com.apple.security.files.user-selected.read-only` (only if Custom Upload ever lands — not v1). No microphone, no camera, no AppleEvents. Cache lives inside the sandbox container at `~/Library/Containers/app.x-noise/Data/Library/Caches/x-noise/` automatically.
- **Toolchain** — Xcode 26+, Swift 6, macOS 26 deployment target. Liquid Glass APIs (`glassEffect`, `GlassEffectContainer`, `.buttonStyle(.glass)`, `.buttonStyle(.glassProminent)`) require the 26 SDK.
