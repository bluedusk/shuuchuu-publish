# Architecture hardening — 2026-04-28

A cross-cutting audit (five reviewers covering code quality, security, performance, architecture, and state/concurrency) flagged ~70 findings clustered around three seams: the `WKWebView`/JS bridge, the audio engine attach/detach lifecycle, and `AppModel` stretching to host two parallel playback pipelines. This document captures the architectural decisions made in response — design state and rationale, not a changelog.

The cleanup closed every Critical and most Major findings. Two architectural lifts (`AppModel` decomposition, `AudioSource` protocol unification) were deferred — see [§9](#9-deferred). Hygiene items (perf nits, code-organization cleanup) are tracked but not addressed here.

## Table of contents

1. [Audio engine attach/detach lifecycle](#1-audio-engine-attachdetach-lifecycle)
2. [Mix state persistence](#2-mix-state-persistence)
3. [JS bridge call protocol](#3-js-bridge-call-protocol)
4. [Web view ownership](#4-web-view-ownership)
5. [Navigation policy & content security](#5-navigation-policy--content-security)
6. [Audio cache (actor)](#6-audio-cache-actor)
7. [Catalog refresh tokens](#7-catalog-refresh-tokens)
8. [Bridge message ordering & generation token](#8-bridge-message-ordering--generation-token)
9. [Core flows](#9-core-flows)
10. [Deferred](#10-deferred)

---

## 1. Audio engine attach/detach lifecycle

`MixingController` (`Sources/Shuuchuu/Audio/MixingController.swift`) is the only owner of the `AVAudioEngine`. It reconciles `MixState` (the published list of active tracks) into engine topology: each track gets its own `AVAudioMixerNode`, wired `source.node → trackMixer → masterMixer → engine.mainMixerNode`.

### Invariants

- Mutating `MixState` is the only way to change what the engine plays. `AppModel` calls `mixer.reconcileNow()` after every state mutation. Direct calls into the controller (`pauseAll`, `setMasterVolume`, `setTrackVolume`) configure engine-level state but never mix membership.
- Per-track volume and per-track pause are **uniform**: `trackMixer.outputVolume` is set to the per-track volume, or to 0 when paused. This works for any source kind (`AVAudioPlayerNode`-backed and `AVAudioSourceNode`-backed alike).
- The engine is running iff the mix is non-empty AND at least one track is unpaused.

### In-flight attach as cancellable Task

Attaching a source is async (the source's `prepare()` may load a buffer or download a file). The controller tracks in-flight attaches in `attaching: [String: Task<Void, Never>]` keyed by track id. Two consequences:

1. **Detach cancels.** `detach(id:)` cancels any in-flight attach for that id. A slow `prepare()` can no longer race the user removing the track and re-attach after teardown.
2. **`stopAll()` cancels.** System sleep, or any code path that tears the engine down, also cancels every in-flight attach. Without this, an attach that was mid-`prepare()` would complete after sleep and re-start the engine — `state.contains(trackId)` would still be true.

`attachSource(for:)` checks `Task.isCancelled` after `prepare()` returns and bails before touching engine state.

### Detach order

`detach(id:)` calls `engine.disconnectNodeOutput(...)` **before** `engine.detach(...)`. Detaching while the engine is still wired to (and pulling buffers from) the node produced intermittent `-10878` faults on the audio render thread.

### Volume drag fast path

`setTrackVolume(_:_:)` writes `trackMixer.outputVolume` directly without running a full reconcile pass. Volume drags hit this 60Hz; a full reconcile would walk the mix twice per tick, rebuild the id-set, and (via `MixState`'s `@Published` `tracks`) trigger Combine subscribers including the persist pipeline. The fast path is conditional on the track being attached and not paused — if paused, the new volume is in `MixState` and `applyVolume` picks it up on resume.

`AppModel.setTrackVolume(_:_:)` mutates `MixState` first (so the new volume is persisted) then calls the fast path.

---

## 2. Mix state persistence

`MixState` (`Sources/Shuuchuu/Models/MixState.swift`) is the published source of truth for the active mix. Persistence is the only side effect of mutating `tracks`.

### Debounced writes

`tracks`'s `didSet` calls `schedulePersist()`, which cancels any pending persist Task and starts a fresh 200ms-delayed write. The effect: a 60Hz volume drag produces one UserDefaults write at the end of the gesture instead of 60-per-second. `flushPersist()` lands any pending write synchronously and is called from `AppModel.handleSleep()` so a mid-drag value isn't lost on system sleep.

### `setAllPaused` shape

The "set every track's paused flag in one mutation" path (`pauseAll` / `playAll`) was previously implemented by mutating `tracks[i].paused` in a loop and then doing `tracks = tracks` to "force didSet" — N didSets plus one redundant self-assignment. The current shape mutates a local copy and assigns once: one didSet, one persist.

### What persists

Only `id` + `volume`. Per-track play/pause state is per-session — every launch starts with all tracks paused. The legacy on-disk shape (which also persisted `paused` and a `masterPaused` flag) is one-time-migrated on load.

---

## 3. JS bridge call protocol

`WebSoundtrackController` (`Sources/Shuuchuu/Audio/WebSoundtrackController.swift`) drives the embed/watch-page bridges via `evaluateJavaScript`. The previous shape interpolated user-derived URLs into JS source strings via a hand-rolled `jsString(_:)` escape helper; that helper missed `U+2028` / `U+2029` / `\r` / `\u{0000}`, any of which broke out of the string literal and ran in the YouTube/Spotify origin.

### `bridgeCall(_:args:)` is the only JS sink

```swift
private func bridgeCall(_ methodPath: String, args: [Any] = []) {
    // methodPath is always a code constant from our own source.
    // args go through JSONSerialization — the security boundary.
    ...
    webView.evaluateJavaScript("\(methodPath)\(payload)", completionHandler: nil)
}
```

Args are JSON-encoded via `JSONSerialization.data(withJSONObject:)`, then post-escaped to handle `U+2028` / `U+2029` (valid JSON, illegal inside JS string literals). The result is wrapped in `(...)` and concatenated to `methodPath` so a method that takes no args becomes `methodPath()`. Every prior call site (8 in total) was migrated; `evaluate(_:)` and `jsString(_:)` are deleted.

The guarantee: any string a user can put into the soundtrack library can only land as a JS string-literal argument, never as code.

---

## 4. Web view ownership

`WKWebView` lives in a hidden 1×1 off-screen `NSWindow` retained for the app lifetime. This survives popover dismissal so audio continues across menubar close/reopen. Reusing the same web view across activations also keeps cookies (Spotify login) alive between switches.

### The protocol vends a player view

```swift
@MainActor
protocol WebSoundtrackControlling: AnyObject {
    func load(_ soundtrack: WebSoundtrack, autoplay: Bool)
    func setPaused(_ paused: Bool)
    func setVolume(_ volume: Double)
    func unload()
    func playerView() -> AnyView          // <— sole sanctioned embed surface
    var onTitleChange: ((WebSoundtrack.ID, String) -> Void)? { get set }
    var onSignInRequired: ((WebSoundtrack.ID) -> Void)? { get set }
    var onPlaybackError: ((WebSoundtrack.ID, Int) -> Void)? { get set }
}
```

The previous shape required UI consumers to know about `WKWebView`: `SoundtrackChipRow` imported `WebKit`, took the concrete `WebSoundtrackController` (the protocol couldn't vend a player view), and `SoundtracksTab` had a `concreteController` computed property that did a force-cast with `fatalError` if it failed.

`playerView() -> AnyView` returns a fileprivate `SoundtrackPlayerEmbed` that:
- Wraps an `NSViewRepresentable` lifting the `WKWebView` out of the hidden window into the inline container
- Reparents the web view back to the hidden window via its own `onDisappear`

The UI layer is now WebKit-free. Tests use `MockSoundtrackController.playerView() = AnyView(EmptyView())`. A future swap-in (e.g. an `AVPlayer`-backed controller for an Apple Music path) would compile the existing `SoundtrackChipRow` and `SoundtracksTab` unchanged.

---

## 5. Navigation policy & content security

The web view is the largest attack surface in the app — it loads YouTube and Spotify content, and our injected `youtube-control.js` runs against the live YouTube watch page. The hardening is layered.

### Dedicated `WKWebsiteDataStore`

```swift
config.websiteDataStore = WKWebsiteDataStore(forIdentifier: Self.dataStoreIdentifier)
```

Cookies live in our own per-app data store keyed on a fixed UUID, isolated from any other WebKit-using app on the system. A hypothetical RCE in a YouTube/Spotify page can't reach the default-store cookies of other apps. (Migration cost: any existing Spotify login pre-cleanup needs re-auth once.)

### `WKNavigationDelegate` with main-frame allow-list

```swift
private static let mainFrameAllowedHosts: [String] = [
    "youtube.com", "youtube-nocookie.com", "youtu.be", "spotify.com",
]
```

Main-frame navigations are restricted to those hosts plus `about:` and `data:` schemes. Sub-frame navs (ads, analytics, video CDNs hosted off-domain) pass through — locking those down breaks the embeds and they don't host our scripts. New-window / popup navs (`targetFrame == nil`) are cancelled outright.

The threat model: `evaluateJavaScript` runs against the document's current origin. If a compromised YouTube page could redirect us to attacker.example, our subsequent `bridgeCall("window.bridge.play")` would call into their `window.bridge.play` and exfiltrate. Pinning the main frame closes that path.

### CSP on bundled bridge HTMLs

Both `youtube-bridge.html` and `spotify-bridge.html` carry strict `<meta http-equiv="Content-Security-Policy">` tags:

- `default-src 'none'`
- `script-src` limited to `'self'` + `'unsafe-inline'` (+ `https://open.spotify.com` for the iframe API on the Spotify bridge)
- `frame-src` limited to the embed origin
- Everything else (`img-src`, `connect-src`, `font-src`, …) blocked by the default

### Explicit postMessage origin + `event.source` check

`youtube-bridge.html` previously sent commands with target origin `'*'` and accepted incoming messages on origin alone. The current shape:
- Outgoing: `iframe.contentWindow.postMessage(payload, 'https://www.youtube-nocookie.com')`
- Incoming: requires `e.source === iframe.contentWindow` AND origin is youtube-nocookie/youtube — a nested ad iframe sharing the parent origin can no longer spoof bridge events.

### Anchored host check in `youtube-control.js`

The `if (location.hostname.indexOf('youtube.com') === -1) return;` substring check would also pass `youtube.com.attacker.example`, where this script would run with our injected privileges. It's now `/^([a-z0-9-]+\.)*youtube\.com$/i`.

### Other small wins

- `webView.isInspectable = true` is now `#if DEBUG`-only.

---

## 6. Audio cache (actor)

`AudioCache` (`Sources/Shuuchuu/Catalog/AudioCache.swift`) is now an actor. Three shape changes:

### Per-key in-flight dedup

```swift
private var inFlight: [String: Task<URL, Error>] = [:]

func localURL(for info: StreamedInfo) async throws -> URL {
    try Self.validateHash(info.sha256)
    if let existing = inFlight[info.sha256] { return try await existing.value }
    let task = Task<URL, Error> { [info] in
        try await self.fetchAndCache(info: info)
    }
    inFlight[info.sha256] = task
    defer { inFlight[info.sha256] = nil }
    return try await task.value
}
```

N parallel fetches for the same track now share a single download Task. The previous shape had each caller fileExists-check, both find false, both download, both rename — wasted bandwidth and an occasional corrupt file on the rename collision.

### Hash validation

`validateHash(_:)` rejects any sha256 that isn't 64 hex chars before using it as a path component. Without this, a malicious catalog could embed `..` segments and write outside `baseDir`.

### `safeExtension(for:)` allow-list

Cache file extension is pinned to a small audio-format allow-list (`caf`/`mp3`/`m4a`/`aac`/`wav`/`flac`/`ogg`); anything else falls back to `caf`. Without this, the catalog URL's path-extension flowed straight into the on-disk filename.

### `StreamedInfo` signature

`localURL` now takes `StreamedInfo` directly. The previous shape took `Track` and `fatalError`'d on a non-streamed kind — a wiring bug we'd discover at runtime instead of compile time. `StreamedNoiseSource.prepare()` extracts info via pattern match before the call.

---

## 7. Catalog refresh tokens

`Catalog.refresh()` (`Sources/Shuuchuu/Catalog/Catalog.swift`) bumps a `currentRefreshID: UUID` on entry; each refresh remembers its own value across the network await and only writes back to `state` if the token is still current. A slow stale fetch can no longer overwrite fresh state if a newer refresh started while it was in flight.

This is a token-based discard rather than a true `Task.cancel` — bandwidth is still spent on the stale fetch, but its result is dropped.

---

## 8. Bridge message ordering & generation token

`BridgeMessageProxy` (`WebSoundtrackController.swift`) is the `WKScriptMessageHandler` shim for the JS bridge. Two changes:

### `MainActor.assumeIsolated` instead of `Task { @MainActor }`

WebKit invokes script-message handlers on the main thread. The previous shape hopped through `Task { @MainActor }`, which adds a scheduling step where two messages can be reordered — one `titleChanged` for soundtrack A could land *after* a parallel `load(B)` even though WebKit dispatched it first. `assumeIsolated` runs the handler synchronously in WebKit's dispatch order.

### Generation token on identity-bound messages

`bridgeReadyForId: WebSoundtrack.ID?` snapshots `loadedSoundtrack?.id` at every "ready" event and is cleared on every `load(...)`. Identity-bound messages (`titleChanged`, `signInRequired`, `error`) are gated on:

```swift
private var isCurrentLoadMessage: Bool {
    bridgeReady && bridgeReadyForId == loadedSoundtrack?.id
}
```

This catches the residual race where a queued message from soundtrack A's destroyed page is delivered after `load(B)` ran and `B`'s "ready" already arrived. Without the token, `titleChanged` for A would write A's title under B's library entry. With the token, A's stale message sees `bridgeReadyForId == A` but `loadedSoundtrack?.id == B` → discarded.

`stateChange` is currently observability-only and not gated. `ready` is the token-setter and not gated.

---

## 9. Core flows

End-to-end walks through the orchestrator (`AppModel`) for each user-facing action. Every flow goes through `AppModel` — UI views never poke `MixState` or `MixingController` directly.

### App launch

```
ShuuchuuApp.init
  ├─ build dependency graph (Catalog, MixState, MixingController, AudioCache,
  │   FocusSettings, FocusSession, DesignSettings, Favorites, Preferences,
  │   SavedMixes, SoundtracksLibrary, WebSoundtrackController)
  └─ AppModel(...)
       ├─ MixState.load() — restore tracks (paused=true) from UserDefaults
       ├─ Restore AudioMode from UserDefaults (idle / mix / soundtrack(id))
       │   └─ if .soundtrack(id) and entry exists:
       │       soundtrackController.load(entry, autoplay: false)
       ├─ Wire callback closures: onTitleChange, onSignInRequired, onPlaybackError
       ├─ Wire FocusSession.onPhaseChange → pauseActiveSource
       └─ Combine pipeline: state.$tracks ⊞ savedMixes.$mixes
                            → matchLoadedMix → currentlyLoadedMixId

PopoverView appears
  └─ AppModel.handleLaunch (idempotent)
       └─ catalog.refresh()
            ├─ stale-while-revalidate: emit cached state immediately if any
            ├─ fetcher.fetch() (network or bundle, depending on injection)
            ├─ if currentRefreshID still ours: state = .ready(fresh)
            └─ on success: trackIndex built; mixer.reconcileNow()
                 └─ saved tracks that couldn't resolve at MixState load time
                    now find their Track and attach
```

`MixingController` reconciles against the restored `MixState` synchronously at construction — but procedural tracks attach immediately, while bundled/streamed tracks need `prepare()`. Until `loadCatalog()` provides the trackIndex, `resolveTrack(id)` returns nil and reconcile no-ops for those ids. The post-catalog `reconcileNow()` is what actually wires them up.

### Mix mutation: toggle a track

```
SoundChip tap → AppModel.toggleTrack(track)
  ├─ if state.contains(track.id): state.remove(id:)
  ├─ else: state.append(id:, volume: 0.5)
  ├─ if !state.isEmpty: enterMixMode()
  │       └─ if mode == .soundtrack: soundtrackController.setPaused(true)
  │          mode = .mix
  └─ mixer.reconcileNow()
       ├─ For removed ids: detach(id:)
       │       ├─ cancel any in-flight attach Task
       │       ├─ entry.source.stop()
       │       ├─ engine.disconnectNodeOutput + engine.detach for each node
       └─ For new ids: attaching[id] = Task { attachSource(for: id) }
            attachSource (off-main, async)
              ├─ resolveTrack → makeSource (Procedural | Bundled | Streamed)
              ├─ try await source.prepare() — may load buffer or download
              ├─ if Task.isCancelled: bail
              ├─ if state no longer wants this id: bail
              ├─ engine.attach(source.node + trackMixer); connect chain
              ├─ applyVolume(...)
              └─ reconcileEngineState (start engine if shouldRun)
```

Mode flips happen synchronously in `AppModel`. The actual audio attach is asynchronous, but mode/state are already coherent before the attach completes — UI never races against in-progress attaches.

### Mix mutation: volume drag (60Hz fast path)

```
Slider drag → AppModel.setTrackVolume(trackId, v)
  ├─ state.setVolume(id:, volume:)
  │       └─ tracks[i].volume = v → didSet → schedulePersist (200ms debounce)
  └─ mixer.setTrackVolume(trackId, v)        ← fast path
       ├─ entry = attached[trackId]
       ├─ if track is paused: no-op (volume in MixState; applyVolume on resume)
       └─ else: entry.trackMixer.outputVolume = v
```

Crucially `mixer.reconcileNow()` is **not** called — a full reconcile would walk the mix twice and re-publish through Combine. The fast path is one dictionary lookup + one float write.

### Apply preset or saved mix

```
applyPreset(p) | applySavedMix(m)
  ├─ filter tracks with volume >= 0.02 (drop near-silent contributions)
  ├─ state.replace(with: newTracks) — single tracks= assignment, one didSet
  ├─ if !newTracks.isEmpty: enterMixMode()
  └─ mixer.reconcileNow()
       └─ detaches old tracks, attaches new ones (async per track)
```

`replace(with:)` short-circuits if the new array equals current — no didSet, no churn.

### Pause/resume the active source

```
ringTap | togglePlayAll → pauseActiveSource(paused)
  ├─ .idle: no-op
  ├─ .mix: state.setAllPaused(paused)              ← mutates copy, one didSet
  │        mixer.reconcileNow() (engine pauses if anyPlaying becomes false)
  └─ .soundtrack: soundtrackController.setPaused(paused)
                  soundtrackPaused = paused
```

`activeSourcePaused` is a computed property that reflects the source-of-truth for the active mode (`!state.anyPlaying` for mix, `soundtrackPaused` for soundtrack).

### Activate a soundtrack

```
SoundtrackChipRow tap (when not active) → AppModel.activateSoundtrack(id:)
  ├─ idempotent guard — same id is no-op
  ├─ if mode == .mix: state.setAllPaused(true); mixer.reconcileNow()
  │       — mix is paused but tracks remain in state; user can flip back
  ├─ mode = .soundtrack(id)
  ├─ soundtrackError = nil
  ├─ soundtrackController.load(entry, autoplay: true)
  │       └─ YouTube: loadYouTubeBridge or loadYouTubeWatch (if previously fell back)
  │          Spotify: loadSpotifyBridge (or fast-path if same .spotify already loaded)
  │          all: bridgeReady=false, bridgeReadyForId=nil
  └─ soundtrackPaused = false

Bridge fires "ready" message
  ├─ MainActor.assumeIsolated → handleBridgeMessage
  ├─ bridgeReady = true; bridgeReadyForId = loadedSoundtrack?.id
  ├─ deferred work: bridgeCall("…load", args:[url]); bridgeCall("…setVolume", args:[v])
  └─ if pendingAutoplay: bridgeCall("…play"); pendingAutoplay = false

Bridge fires "titleChanged"
  └─ if isCurrentLoadMessage: onTitleChange?(id, title)
       └─ AppModel: soundtracksLibrary.setTitle(id:, title:)
```

### Switch from soundtrack back to mix

```
"Switch to mix" link on FocusPage → AppModel.switchToMix()
  ├─ guard mode == .soundtrack
  ├─ soundtrackController.setPaused(true)         — bridge pauses, web view retained
  ├─ soundtrackPaused = true
  ├─ mode = .mix
  ├─ state.setAllPaused(false)                    — resume all tracks
  └─ mixer.reconcileNow()
```

The web view is **not** unloaded — flipping back into the soundtrack is one bridgeCall, not a fresh page load. `unload()` happens only on `removeSoundtrack(id:)` for the active id.

### Save a mix (with conflict resolution)

```
SaveMixHeader CTA → beginSaveMix → saveMode = .naming(text:"")
  ↓
User types → updateSaveName(text)
  ↓
Commit → commitSaveMix
  ├─ trim whitespace; bail if empty
  ├─ savedMixes.save(name:, tracks:)
  ├─ .saved → saveMode = .inactive
  └─ .duplicate(existing) → saveMode = .confirmingOverwrite(text:, existing:)

From confirmingOverwrite:
  ├─ overwriteExisting → savedMixes.overwrite(id:, tracks:)
  └─ saveAsNewWithSuffix → savedMixes.saveWithUniqueSuffix(baseName:, tracks:)
                            (picks "Name 2", "Name 3"… smallest free)
```

`saveMode` is the entire state machine — `SaveMixHeader` renders one of three sub-views off this enum. Cancel flips back to `.inactive` from any state.

### Pomodoro phase transition

```
FocusSession countdown elapses → onPhaseChange(newPhase)
  └─ AppModel:
       case .focus:                pauseActiveSource(false)   — resume
       case .shortBreak, .longBreak: pauseActiveSource(true)  — pause
```

Manual ring tap on `FocusPage` takes a separate path — that toggles `togglePlayAll()` and doesn't touch session state. The auto-mirror handles only phase boundaries.

### System sleep / wake

```
NSWorkspace.willSleep → AppModel.handleSleep
  ├─ mixer.stopAll()
  │       ├─ for each attached: detach(id:) — cancels in-flight attach + tears down nodes
  │       ├─ for any remaining inFlight attach Tasks: cancel
  │       └─ engine.pause()
  ├─ state.flushPersist()                — land any debounced volume mutation
  └─ session.pause()

NSWorkspace.didWake → AppModel.handleWake
  └─ no-op for v2 (no auto-resume)
```

After wake, the next mix mutation re-triggers `reconcileNow()` which re-attaches everything. The web view's media stays paused via the bridge state.

### Streamed track first play

```
attachSource → makeSource(track) → StreamedNoiseSource.prepare
  └─ guard case .streamed(let info)
     try await cache.localURL(for: info)
       ├─ AudioCache (actor): validateHash(info.sha256)  — 64 hex chars
       ├─ if inFlight[hash]: return try await existing.value
       ├─ task = Task { try await self.fetchAndCache(info: info) }
       │       fetchAndCache:
       │         ├─ ext = safeExtension(for: info.url)   — pinned allow-list
       │         ├─ if file exists on disk: touch mtime; return URL
       │         ├─ data = await downloader.download(...)
       │         ├─ verify SHA256(data) == info.sha256 (else throw integrityFailed)
       │         ├─ atomic write to .tmp; replaceItemAt(fileURL)
       │         └─ evictIfOverLimit(keeping: fileURL)   — LRU eviction
       └─ inFlight[hash] = task; defer { = nil }; return try await task.value

  → AVAudioFile(forReading: localURL); read into AVAudioPCMBuffer; isReady=true
  → AVAudioPlayerNode connected; .scheduleBuffer(.loops); .play()
```

The `inFlight` dedup means a slider that adds the same streamed track twice in 100ms shares one network round-trip.

### Catalog refresh (stale-while-revalidate)

```
catalog.refresh
  ├─ myID = UUID(); currentRefreshID = myID
  ├─ cached = loadCache()
  ├─ if cached and currentRefreshID == myID: state = .ready(cached.categories)
  │       — UI sees stale-but-usable data instantly
  ├─ data = try await fetcher.fetch()              — may take seconds
  ├─ guard currentRefreshID == myID else { return } — newer refresh started
  ├─ fresh = decode CatalogDocument
  ├─ persist data → cacheFile (atomic)
  └─ state = .ready(fresh.categories)
```

If a slow fetch is in flight and a new `refresh()` starts, the slow one's `data` arrives, the token check fails, and the result is silently discarded — fresh state isn't overwritten by stale.

---

## 10. Deferred

### Architectural lifts

These are bigger refactors that benefit from a deliberate planning conversation before code, not a "yes, do it" cycle. Both touch many files and the right shape is a design decision.

**`AppModel` decomposition.** `AppModel.swift` is 446 lines, exposes 25+ public methods, owns navigation + save-mix flow + soundtrack title fetch + mode persistence + lifecycle wiring + the catalog match pipeline. Carve out:
- `SaveMixCoordinator` — the inline save-mix state machine (`SaveMode` + `beginSaveMix` / `commitSaveMix` / `overwriteExisting` / etc.)
- `SoundtrackCoordinator` — `addSoundtrack` / `activateSoundtrack` / `removeSoundtrack` / `setSoundtrackVolume` / oEmbed title fetch / `signInRequired` & `soundtrackError` plumbing
- `Navigator` — `page`, `soundsTab`, `goTo(_:)` and any future routing surface

`AppModel` keeps the dependency graph and the cross-cutting "active source" concept.

**`AudioSource` protocol unification.** The current shape has two parallel playback pipelines (mix via `MixingController`, soundtrack via `WebSoundtrackController`) coordinated by `switch model.mode` scattered across `AppModel`, `FocusPage`, and `SoundsPage` — ~30 sites in total. Adding a third source (Apple Music, system-audio capture, etc.) requires editing every switch.

A protocol roughly:

```swift
protocol AudioSource {
    var id: AudioSourceID { get }
    var isPaused: Bool { get }
    func setPaused(_ paused: Bool)
    func setVolume(_ volume: Float)
    func teardown()
    func playerView() -> AnyView   // optional, source decides
}
```

…with a single owner enforcing "exactly one is active" routes intent through `activeSource.setPaused(...)`. Mode switches collapse from 30 case-ladders to one assignment.

The protocol shape isn't obvious — `MixingController` operates on N tracks with per-track volume, `WebSoundtrackController` on a single embed. Either the protocol is wide enough to accommodate both (loses some safety), or there's a higher-level `Composition` abstraction wrapping `MixingController` so the source-level interface stays narrow. That choice is the planning conversation.

### Hygiene

Tracked but not done — small individually, can be done in one cleanup pass:

- **Perf:** `MixState.contains` / `track` / `setVolume` / `setPaused` are linear `firstIndex` scans (add `[String: Int]`); `Wallpaper.blobs(for:)` recomputed twice per blob with OKLCH→sRGB chain on each call (hoist + cache); `EqBars` runs an infinite `repeatForever` animation while popover is closed (gate on `activeSourcePaused`); `AppModel.matchLoadedMix` runs on every `state.$tracks` tick (add `.removeDuplicates()` keyed on the id-set); `FluorescentHum` uses 3× `sin` per sample at 48kHz (LUT).
- **Code quality:** `AudioMode` hand-rolled `Codable` duplicates synthesizable behavior; `SettingsPage.swift` is 393 lines containing 3 unrelated component types; `TrackIconMap` is a flat 50-case switch (move into `catalog.json`); 40 lines of commented-out `glassSection` code in `SettingsPage.swift`; `MixDisplay` / `matchLoadedMix` use `AnyHashable` for ids (introduce `enum MixId { case preset(String); case saved(UUID) }`).
- **Defense-in-depth:** cap bridge message string lengths at the Swift boundary (e.g. titleChanged title at 200 chars); defer the YouTube oEmbed lookup to first activation rather than first add (privacy — it leaks every video id at add time).
- **Catalog state machine:** collapses "loading + had-cache" and "ready" — caller can't tell stale-while-revalidating from fresh. Add `revalidating: Bool` or `.ready(stale: Bool)`.

---

## File-level index

| Concern | File |
|---|---|
| Engine attach/detach + volume fast path | `Sources/Shuuchuu/Audio/MixingController.swift` |
| Debounced mix persist | `Sources/Shuuchuu/Models/MixState.swift` |
| Typed JS bridge call + generation token + nav delegate | `Sources/Shuuchuu/Audio/WebSoundtrackController.swift` |
| Player-view abstraction | `Sources/Shuuchuu/Audio/WebSoundtrackControlling.swift` |
| WebKit-free row | `Sources/Shuuchuu/UI/Components/SoundtrackChipRow.swift` |
| CSP + postMessage origin + event.source | `Sources/Shuuchuu/Resources/soundtracks/youtube-bridge.html` |
| CSP | `Sources/Shuuchuu/Resources/soundtracks/spotify-bridge.html` |
| Anchored host check | `Sources/Shuuchuu/Resources/soundtracks/youtube-control.js` |
| Cache actor + dedup + hash validation | `Sources/Shuuchuu/Catalog/AudioCache.swift` |
| Catalog cancellation token | `Sources/Shuuchuu/Catalog/Catalog.swift` |
| `Sendable` `StreamedInfo` | `Sources/Shuuchuu/Catalog/CatalogModels.swift` |
| New tests (invalid-hash, dedup) | `Tests/ShuuchuuTests/AudioCacheTests.swift` |
