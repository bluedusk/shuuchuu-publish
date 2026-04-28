# Panel Scene Backgrounds (Video & Image) — Design Spec

**Date:** 2026-04-28
**Status:** Draft, approved in brainstorming session
**Audience:** AI designer (visual/interaction design), then engineering plan
**Target:** macOS 26+ (Liquid Glass), Swift 6 / SwiftUI menubar popover (340×540pt)

---

## 1. Overview

The popover currently shows a static `Wallpaper` view (gradient/material) behind the Focus UI. Users want a richer ambient backdrop — a looping screensaver-style video or a high-quality still image — that plays behind the timer and mix list while they work. Reference: macOS Aerial screensavers (cinematic 10–30 s loops, slow camera moves) and high-quality desktop wallpapers.

This spec adds **Scenes**: a curated, bundled library of looping MP4 videos and JPG/HEIC images, picked via a small chip in the Focus header, rendered as the bottommost layer of the popover under the existing UI.

### Core model: scene is independent of audio

The active scene is **orthogonal** to whatever audio is playing. A user might run a fireplace video with rain audio, or no audio at all. Specifically:

- The selected scene loops continuously regardless of mix/soundtrack/idle state — it does **not** pause when audio pauses (screensaver behavior).
- The scene's own audio track is always muted; `MixingController` and the YouTube `WKWebView` audio paths are untouched.
- "No scene" is a valid state (the default on first launch) and renders the existing `Wallpaper` unchanged.

### Goals

- Let users pick a cinematic looping video or a still image as the popover backdrop.
- Stay fully isolated from the audio subsystem — no `AVAudioSession` involvement, no risk to the mix engine.
- Persist the active scene across launches and survive popover dismissals without burning CPU/GPU when the popover is closed.
- Ship a curated, bundled set of 5–8 scenes and treat the assets the same way the app treats `sounds/` — gitignored local content, generated catalog.

### Non-goals (defer)

- User-supplied folder ("bring your own MP4s" à la macOS screensavers).
- YouTube / streamed video sources.
- Scene auto-pairing with soundtracks (e.g., "Lofi Beats" auto-selects its matching scene).
- Per-mix scene persistence (the active scene is a global setting, not part of `x-noise.savedMix`).
- Tunable scrim opacity in `DesignSettings`.
- Configurable crossfade duration.
- Ken Burns slow-zoom on still images.
- Per-scene volume of muted audio (always muted).
- Diagnostic HUD (FPS, memory, decoder stats).

---

## 2. Architecture

### 2.1 New types

```swift
// Sources/Shuuchuu/Models/Scene.swift
public enum SceneKind: String, Codable, Sendable {
    case image
    case video
}

public struct Scene: Identifiable, Codable, Sendable, Equatable {
    public let id: String           // filename stem, e.g. "fireplace-loop"
    public let title: String        // display name, e.g. "Fireplace"
    public let filename: String     // "fireplace-loop.mp4" or "mountain.jpg"
    public let thumbnail: String    // "fireplace-loop.jpg" (always JPG, pre-rendered)
    public let kind: SceneKind
}

// Sources/Shuuchuu/Models/ScenesLibrary.swift
@MainActor
public final class ScenesLibrary: ObservableObject {
    @Published public private(set) var scenes: [Scene] = []
    public init() { loadFromBundle() }
    public func entry(id: String) -> Scene? { scenes.first { $0.id == id } }
    private func loadFromBundle() { /* decode scenes.json from Bundle.module */ }
}

// Sources/Shuuchuu/Scenes/SceneController.swift
@MainActor
public final class SceneController: ObservableObject {
    public enum Renderable {
        case none
        case image(NSImage)
        case video(AVQueuePlayer)   // looper retained internally on the controller
    }

    @Published public private(set) var activeSceneId: String?
    @Published public private(set) var renderable: Renderable = .none

    private let library: ScenesLibrary
    private let prefs: Preferences
    private var looper: AVPlayerLooper?

    public init(library: ScenesLibrary, prefs: Preferences) {
        // Restore last-used id from UserDefaults (key: "shuuchuu.activeScene").
        // If the id no longer exists in the library, start at nil silently.
    }

    public func setScene(_ id: String?) {
        // 1. nil / unknown id → renderable = .none, activeSceneId = nil, persist.
        // 2. Resolve id → Scene via library; check FileManager.fileExists at the
        //    bundle URL. If missing, fall back to .none and log.
        // 3. .image: NSImage(contentsOf:) → publish .image(img).
        // 4. .video: build AVQueuePlayer + AVPlayerLooper, isMuted = true,
        //    publish .video(player). Observe currentItem.status; if .failed
        //    within 2s, fall back to .none and log.
        // 5. Persist activeSceneId; publish.
    }

    /// Called by SceneBackground.onAppear / onDisappear so we don't decode
    /// video while the menubar popover is dismissed.
    public func popoverDidAppear() {
        if case .video(let p) = renderable { p.play() }
    }
    public func popoverDidDisappear() {
        if case .video(let p) = renderable { p.pause() }
    }
}
```

### 2.2 Wiring into AppModel

`AppModel` gains two stored properties:

```swift
let scenes: ScenesLibrary
let scene: SceneController
```

Constructed in `AppModel.live(...)` next to `soundtracksLibrary` and `soundtrackController`. Injected into the SwiftUI environment from `PopoverView` like the other subsystems:

```swift
.environmentObject(model.scenes)
.environmentObject(model.scene)
```

`SceneController` is **fully self-contained**: it owns its `AVQueuePlayer`, persists its own state to `UserDefaults` (`shuuchuu.activeScene`), and exposes only `activeSceneId` + `setScene(_:)` + popover-visibility hooks. It does not call into `MixingController`, `FocusSession`, or any audio code. It does not know the mix state, the soundtrack mode, or the pomodoro phase.

### 2.3 PopoverView ZStack order

`PopoverView` adds `SceneBackground()` as the **bottom** layer:

```
ZStack {
    SceneBackground()                  // NEW: video/image when activeSceneId != nil
        .frame(width: size.width, height: size.height)
    Wallpaper(mode: design.wallpaper)  // existing — visible when no scene picked,
                                       //  also visible behind scrim under the scene
        .frame(width: size.width, height: size.height)
    SceneScrim()                       // NEW: top/bottom darken to keep UI legible
        .frame(width: size.width, height: size.height)
        .allowsHitTesting(false)
        .opacity(scene.activeSceneId == nil ? 0 : 1)
    FocusPage()
        // ...
}
```

When `activeSceneId == nil`, `SceneBackground` renders an empty view and `SceneScrim` is invisible — the popover looks identical to today. **No behavioral change in the empty-state path.**

### 2.4 SceneBackground

`NSViewRepresentable` wrapping a thin `NSView` whose layer hosts an `AVPlayerLayer` for video scenes or sets `layer.contents = nsImage` for image scenes. Branches on `library.entry(id: scene.activeSceneId)?.kind`.

```swift
struct SceneBackground: NSViewRepresentable {
    @EnvironmentObject var scene: SceneController

    func makeNSView(context: Context) -> SceneHostView { SceneHostView() }

    func updateNSView(_ view: SceneHostView, context: Context) {
        switch scene.renderable {
        case .none:               view.clear()
        case .image(let img):     view.show(image: img)
        case .video(let player):  view.show(videoPlayer: player)
        }
    }
}
```

`SceneHostView` keeps two stacked CALayers (front/back) and crossfades between them on each `show(...)` call (200 ms `CABasicAnimation` on `opacity`). This handles every transition: video → video, video → image, image → image, anything → empty.

Lifecycle hooks on `SceneBackground`:

```swift
.onAppear  { scene.popoverDidAppear() }
.onDisappear { scene.popoverDidDisappear() }
```

These map directly to the `MenuBarExtra` window appearing/disappearing, so we never decode video while the popover is hidden.

### 2.5 SceneScrim

A `LinearGradient`-on-`Rectangle` overlay (top 25% opacity black fading to clear at 30%, bottom 0 fading to 45% black). Fixed values for v1; not exposed in `DesignSettings`. `allowsHitTesting(false)` so it doesn't capture cursor or clicks.

### 2.6 Picker UI

The picker is a SwiftUI `.popover` anchored to a new chip in the Focus header.

**Chip placement** — `FocusPage.header` gains one new button to the **left** of the existing gear:

```swift
HStack(alignment: .top, spacing: 10) {
    if settings.pomodoroEnabled { /* FOCUS title + dots */ }
    Spacer()
    sceneChip      // NEW
    Button(gear) { model.goTo(.settings) }
}
```

Same `minimalIcon` styling as the gear (45% opacity → primary on hover, 28×28 frame). SF Symbol: `photo.on.rectangle.angled`. Tooltip: "Scene".

**Picker popover content** (~280×360):

```
┌──────────────────────────────┐
│ Scenes                       │  <- 13pt semibold
│                              │
│ ┌──────┐                     │
│ │ none │   ← selected: ring  │
│ │  ⊘   │                     │
│ └──────┘                     │
│                              │
│ ┌──────┐ ┌──────┐            │
│ │ thumb│ │ thumb│ ▶          │  <- ▶ glyph in corner if .video
│ │      │ │      │            │
│ └──────┘ └──────┘            │
│  Aurora    Forest            │
│                              │
│ ┌──────┐ ┌──────┐            │
│ │ thumb│ │ thumb│ ▶          │
│ └──────┘ └──────┘            │
└──────────────────────────────┘
```

- "None" tile first; tap → `scene.setScene(nil)`.
- Then a 2-column grid of bundled scenes. Tile = 130×75 thumbnail (16:9), with title beneath. Selected tile gets a 2pt accent stroke.
- Video scenes get a small `play.fill` glyph in the upper-right corner (10pt, 70% opacity). Skip if you want them visually identical — call out for review.
- Tap a tile → `scene.setScene(id)` → popover dismisses.
- Empty state when `scenes.isEmpty`: centered text "No scenes installed." + one-line hint pointing at `Sources/Shuuchuu/Resources/scenes/`. Visible only in dev / on a fresh checkout — production builds always ship the curated set.

### 2.7 Build / asset pipeline

New directory `Sources/Shuuchuu/Resources/scenes/`, gitignored alongside `sounds/`:

```
Sources/Shuuchuu/Resources/scenes/
├── fireplace-loop.mp4
├── fireplace-loop.jpg     <- thumbnail
├── aurora.mp4
├── aurora.jpg
├── mountain.heic          <- still scene
├── mountain.jpg           <- thumbnail (still HEIC needs a JPG thumb too)
└── ...
```

`scripts/gen-scenes.py` (new) scans the directory, infers `kind` from extension (`.mp4`/`.mov` → video, `.jpg`/`.heic`/`.png` → image), titles via simple humanization of the filename stem, and writes `Sources/Shuuchuu/Resources/scenes.json`:

```json
[
  {
    "id": "fireplace-loop",
    "title": "Fireplace",
    "filename": "fireplace-loop.mp4",
    "thumbnail": "fireplace-loop.jpg",
    "kind": "video"
  },
  {
    "id": "mountain",
    "title": "Mountain",
    "filename": "mountain.heic",
    "thumbnail": "mountain.jpg",
    "kind": "image"
  }
]
```

Both the `scenes/` directory and `scenes.json` are gitignored. Running the script is a manual step (same as `gen-catalog.py`) — no build phase.

### 2.8 Persistence

`SceneController` writes `activeSceneId` to `UserDefaults` under key `shuuchuu.activeScene` (string or absent). Read at init, restored on launch. If the persisted id no longer exists in the library (renamed/removed), fall back to `nil` silently.

This is **not** part of `x-noise.savedMix` — scenes are a global preference, independent of which mix or soundtrack is active.

---

## 3. Behaviour

### 3.1 Default state (first launch)

`activeSceneId == nil`, `SceneBackground` renders nothing, `SceneScrim` is invisible. The popover looks exactly like today. The new chip in the header is the only visible change; tapping it opens the picker with "None" selected.

### 3.2 Picking a scene

1. User taps the chip → picker popover opens.
2. User taps a tile → `scene.setScene(id)`.
3. `SceneController` validates the file path; for video, it builds an `AVQueuePlayer` + `AVPlayerLooper` over the asset URL with `isMuted = true`.
4. `SceneBackground` observes `activeSceneId` change and triggers a 200 ms crossfade from the previous content to the new content.
5. Popover dismisses. The scene is now visible behind the UI.

### 3.3 Switching scenes

Same path as 3.2. The crossfade is the only visual transition; the previous player is released after the fade completes. There is never more than one active video player + at most one fading-out player at once.

### 3.4 Clearing the scene

User taps "None" → `setScene(nil)` → `SceneBackground` crossfades to empty → `Wallpaper` shows through unchanged.

### 3.5 Popover open / close

`SceneBackground.onAppear` calls `scene.popoverDidAppear()` → resumes video playback. `onDisappear` calls `popoverDidDisappear()` → pauses the player. Image scenes have no playback to manage; the image just stays in the layer's `contents`.

### 3.6 Sleep / wake

No special handling. `AVPlayer` survives sleep cycles. The existing `handleSleep()` / `handleWake()` in `AppModel` are not touched. (If a regression appears here in QA, add a `pause()` on sleep notification — but assume not needed.)

### 3.7 Audio interaction

None. The scene player is muted, never connects to `AVAudioSession`, and never touches `MixingController`. The mix engine, soundtrack `WKWebView`, and pomodoro session continue to operate independently.

### 3.8 Failure modes

- **File missing on disk** (e.g., user manually deleted from `scenes/` after the catalog was generated): `setScene` checks `FileManager.fileExists`. If false, set `activeSceneId = nil`, log a warning, render empty.
- **AVPlayer fails to load** (corrupt MP4, codec unsupported): observe `player.currentItem.status`; if `.failed` within 2 seconds of starting playback, treat as missing — fall back to nil, log.
- **Empty catalog** (`scenes.json` is `[]`): library publishes `[]`, picker shows the empty state, no crashes anywhere in the chain.
- **Persisted id no longer in catalog**: fall back to nil silently on init.

No modal alerts. Per project convention, all errors surface either inline or as silent fallbacks.

---

## 4. Asset guidelines

These are documented in the spec; they are **not** enforced in code. The encoding step happens once per scene by hand (or via a future helper script).

### 4.1 Video

- Container: MP4 (H.264 High profile) or MOV (HEVC). H.264 has wider compatibility; HEVC produces ~30 % smaller files at equivalent quality.
- Resolution: 720p (1280×720). The popover is 340×540; even at 2× Retina it never needs more than ~1080×680. Higher resolution wastes bandwidth and decode cycles.
- Frame rate: 24–30 fps. Slow ambient content does not benefit from 60 fps.
- Bitrate: 3–5 Mbps. Above ~6 Mbps the visual gain is invisible at the popover's effective size.
- Length: 10–30 seconds. Longer is fine but bloats the bundle.
- Loop quality: encode so the **first frame ≈ last frame**. Standard editing practice — overlap last 0.5 s with first 0.5 s in the source. `AVPlayerLooper` will produce a near-imperceptible seam on properly prepared loops.
- Audio: strip the audio track entirely (`ffmpeg -an`). It will never play; carrying it just bloats the file.
- Target file size: < 15 MB per clip. Bundled set of 5–8 clips: < 120 MB total.

### 4.2 Image

- Format: JPG (sRGB, quality 80–85) or HEIC.
- Resolution: 1920×1080 minimum. The popover renders at 340×540 logical, but Retina + future panel sizes make 1080p a safe floor.
- Color space: sRGB.
- Target file size: < 1 MB per image.

### 4.3 Thumbnails

Every scene needs a `<id>.jpg` thumbnail next to its asset. For video scenes, generate from a representative frame (`ffmpeg -ss 2 -i clip.mp4 -vframes 1 -q:v 4 clip.jpg`). For image scenes that are already JPG, the thumbnail can be the asset itself (or a downscaled copy).

Thumbnail target: 260×148 (2× the displayed 130×74 size), JPG quality 75, < 30 KB.

---

## 5. Performance considerations

- **One active video decoder.** `SceneController` holds at most one `AVQueuePlayer` at a time. During a crossfade, a second player exists for ~200 ms before the old one is released.
- **Decoding pauses with the popover.** `popoverDidDisappear()` calls `player.pause()` — no GPU/CPU spent decoding while the menubar window is dismissed. Image scenes consume no decode resources at all.
- **Working set per video clip**: ~30–80 MB (decoded frame buffer + lookahead). Acceptable; the app's existing audio buffers dominate.
- **No SwiftUI redraws from video frames.** The video is in an `AVPlayerLayer` outside SwiftUI's render path. Pomodoro-driven 1 Hz timer label redraws don't affect video playback or vice versa.
- **Image scenes are essentially free**: a single `NSImage` set on a `CALayer.contents` once.

---

## 6. Files added / modified

**Added:**
- `Sources/Shuuchuu/Models/Scene.swift` — `Scene` + `SceneKind` types.
- `Sources/Shuuchuu/Models/ScenesLibrary.swift` — `ObservableObject` library loader.
- `Sources/Shuuchuu/Scenes/SceneController.swift` — controller with `AVQueuePlayer`/`AVPlayerLooper` lifecycle and `UserDefaults` persistence.
- `Sources/Shuuchuu/UI/Components/SceneBackground.swift` — `NSViewRepresentable` host + `SceneHostView` with crossfade.
- `Sources/Shuuchuu/UI/Components/SceneScrim.swift` — gradient overlay.
- `Sources/Shuuchuu/UI/Components/ScenePicker.swift` — popover content (grid + None tile).
- `Sources/Shuuchuu/Resources/scenes/` — gitignored bundle directory.
- `Sources/Shuuchuu/Resources/scenes.json` — gitignored generated catalog.
- `scripts/gen-scenes.py` — scanner that emits `scenes.json`.
- `Tests/ShuuchuuTests/SceneControllerTests.swift` — see §7.

**Modified:**
- `Sources/Shuuchuu/AppModel.swift` — add `scenes: ScenesLibrary` and `scene: SceneController` properties; construct in `live(...)`.
- `Sources/Shuuchuu/UI/PopoverView.swift` — add `SceneBackground` and `SceneScrim` to the bottom of the ZStack; inject env objects.
- `Sources/Shuuchuu/UI/Pages/FocusPage.swift` — add the scene chip + picker popover state to `header`.
- `.gitignore` — add `Sources/Shuuchuu/Resources/scenes/` and `Sources/Shuuchuu/Resources/scenes.json`.

---

## 7. Testing

The audio/UI separation means scene logic can be unit-tested without an audio engine, and renders can be checked by SwiftUI Preview during development. There are no snapshot tests anywhere in the project — don't add one for this.

**`SceneControllerTests`** — XCTest, in `Tests/ShuuchuuTests/`:

- `setScene(_:)` with a known-good id → publishes the new id, persists to `UserDefaults`.
- `setScene(nil)` → publishes nil, clears the persisted key.
- `setScene` with an id that is not in the library → falls back to nil, no crash.
- `init` with a previously persisted id that is still in the library → restores it.
- `init` with a previously persisted id that is no longer in the library → starts at nil.

Use a fixture `ScenesLibrary` injected via init (not the bundle loader) and an in-memory `UserDefaults(suiteName:)`. No `AVPlayer` involvement in tests — exercise the controller's published state and persistence only. The video-loading path is exercised manually during development (run the app, pick a scene, watch it play).

Skipped:
- Real `AVPlayer` integration tests — fragile, slow, and the surface is small enough to validate by hand.
- Snapshot/visual tests — none exist in the project; out of scope.

---

## 8. Out of scope (do not add in passing)

These are intentionally deferred:

- User-supplied folder ("import from `~/Pictures/Wallpapers/`").
- YouTube / streamed video sources.
- Per-soundtrack auto-pairing.
- Per-mix scene persistence.
- Tunable scrim opacity in `DesignSettings`.
- Configurable crossfade duration.
- Ken Burns slow-zoom on still images.
- Per-scene metadata (author, license, longer description).
- A "Random" or "Shuffle" scene mode.
- Pause-on-audio-pause behavior (scene always loops; this was an explicit decision).
- Diagnostic HUD.

If any of these come up post-launch, they get their own spec.
