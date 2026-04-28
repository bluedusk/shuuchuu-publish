# Panel Scene Backgrounds (Shaders) — Design Spec

**Date:** 2026-04-28
**Status:** Draft, approved in brainstorming session
**Audience:** AI designer (visual/interaction design), then engineering plan
**Target:** macOS 26+ (Liquid Glass), Swift 6 / SwiftUI menubar popover (340×540pt)

---

## 1. Overview

The popover currently shows a static `Wallpaper` view (gradient/material) behind the Focus UI. Users want a richer ambient backdrop that plays behind the timer and mix list while they work.

This spec ships **Scenes** as a real-time Metal **shader** background — a curated, bundled set of fragment shaders rendered behind the popover UI. The user picks a shader from a small chip in the Focus header; it animates continuously while the popover is visible. Compared to a video-backed approach, shaders give us:

- Asset is a few KB of Metal source per scene instead of ~10 MB of MP4.
- Infinite, never-repeating animation (no loop seam).
- Crisp at any panel size — survives the planned 9:16 panel resize.
- Trivial GPU cost on Apple Silicon (<1 ms per frame at 680×1080 for typical shaders).
- Shader uniforms can read app state if we want the background to react (deferred to v2).

Image and video scenes are **explicit follow-ups**, not v1 scope. The architecture is built to absorb them with a new `SceneKind` case and a parallel render branch — no breaking changes to the model or the UI layer.

### Core model: scene is independent of audio

The active scene is **orthogonal** to whatever audio is playing. Specifically:

- The selected scene animates continuously regardless of mix/soundtrack/idle state — it does **not** pause when audio pauses (screensaver behavior).
- Shaders never touch `AVAudioSession`; `MixingController` and the YouTube `WKWebView` audio paths are untouched.
- "No scene" is a valid state (the default on first launch) and renders the existing `Wallpaper` unchanged.

### Goals

- Let users pick a procedural Metal-shader background.
- Stay fully isolated from the audio subsystem.
- Persist the active scene across launches and survive popover dismissals without burning GPU when the popover is closed.
- Ship a curated, bundled set of ~5 shaders sourced/ported by hand. Treat shader sources the same way the app treats `sounds/` — local content under `Sources/Shuuchuu/Resources/shaders/`, generated catalog at `scenes.json`. Both gitignored.
- Keep the door open for image and video scenes as additive follow-ups.

### Non-goals (defer)

- Image scenes (JPG/HEIC).
- Video scenes (MP4/MOV via AVPlayer).
- User-supplied shader folder ("drop `.metal` files in `~/Library/Application Support/shuuchuu/shaders/`").
- Audio-reactive uniforms (mix volume / pomodoro phase → shader).
- Per-shader uniform UI ("tweak the colors / speed").
- Hot-reload of `.metal` sources during development.
- Scene auto-pairing with soundtracks.
- Per-mix scene persistence (the active scene is global, not part of `x-noise.savedMix`).
- Tunable scrim opacity in `DesignSettings`.
- Configurable crossfade duration.
- Diagnostic HUD (FPS, GPU time, shader-compile times).

---

## 2. Architecture

### 2.1 New types

```swift
// Sources/Shuuchuu/Models/Scene.swift
public enum SceneKind: String, Codable, Sendable {
    case shader   // v1 — image/video added in follow-up specs
}

public struct Scene: Identifiable, Codable, Sendable, Equatable {
    public let id: String        // filename stem, e.g. "aurora"
    public let title: String     // display name, e.g. "Aurora"
    public let thumbnail: String // pre-rendered "aurora.jpg" alongside the source
    public let kind: SceneKind
}
```

```swift
// Sources/Shuuchuu/Models/ScenesLibrary.swift
@MainActor
public final class ScenesLibrary: ObservableObject {
    @Published public private(set) var scenes: [Scene] = []
    public init() { loadFromBundle() }
    public func entry(id: String) -> Scene? { scenes.first { $0.id == id } }
    private func loadFromBundle() { /* decode scenes.json from Bundle.module */ }
}
```

```swift
// Sources/Shuuchuu/Scenes/SceneController.swift
@MainActor
public final class SceneController: ObservableObject {
    public enum Renderable {
        case none
        case shader(ShaderInstance)
    }

    @Published public private(set) var activeSceneId: String?
    @Published public private(set) var renderable: Renderable = .none

    private let library: ScenesLibrary
    private let renderer: ShaderRenderer

    public init(library: ScenesLibrary, renderer: ShaderRenderer) {
        // Restore last-used id from UserDefaults (key: "shuuchuu.activeScene").
        // If the id no longer exists in the library, start at nil silently.
    }

    public func setScene(_ id: String?) {
        // 1. nil / unknown id → renderable = .none, activeSceneId = nil, persist.
        // 2. Resolve id → Scene; ask renderer for a compiled ShaderInstance.
        //    On compile failure, fall back to .none and log.
        // 3. Persist activeSceneId; publish.
    }

    public func popoverDidAppear() { /* unpause MTKView via Renderable */ }
    public func popoverDidDisappear() { /* pause MTKView */ }
}
```

```swift
// Sources/Shuuchuu/Scenes/ShaderRenderer.swift
@MainActor
public final class ShaderRenderer {
    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private var pipelineCache: [String: MTLRenderPipelineState] = [:]
    private let vertexLibrary: MTLLibrary   // shared fullscreen-quad vertex stage

    public init?() {
        // Build device + queue. Compile the shared vertex source (one-time).
    }

    /// Compiles the .metal source for a scene id from Bundle.module and returns
    /// a ready-to-bind pipeline. Cached across calls.
    public func instance(for sceneId: String) throws -> ShaderInstance {
        // 1. If cached, return cached pipeline wrapped in a fresh ShaderInstance
        //    (each instance has its own startTime).
        // 2. Else: load "shaders/<id>.metal" as a String resource.
        // 3. device.makeLibrary(source: msl, options:) → MTLLibrary.
        //    Throws on syntax error.
        // 4. Build MTLRenderPipelineDescriptor with vertex from vertexLibrary
        //    and fragment from new library (function name: "sceneMain").
        // 5. device.makeRenderPipelineState(descriptor:) → cache + return.
    }
}

public struct ShaderInstance {
    public let id: String
    public let pipeline: MTLRenderPipelineState
    public let startTime: CFTimeInterval     // CACurrentMediaTime() at creation
}
```

### 2.2 Wiring into AppModel

`AppModel` gains three stored properties:

```swift
let scenes: ScenesLibrary
let shaderRenderer: ShaderRenderer        // shared device/queue
let scene: SceneController
```

Constructed in `AppModel.live(...)` next to `soundtracksLibrary` and `soundtrackController`. Injected into the SwiftUI environment from `PopoverView` like the other subsystems:

```swift
.environmentObject(model.scenes)
.environmentObject(model.scene)
```

`SceneController` is **fully self-contained**: it owns its `Renderable`, persists its own state to `UserDefaults` (`shuuchuu.activeScene`), and exposes only `activeSceneId` + `setScene(_:)` + popover-visibility hooks. It does not call into `MixingController`, `FocusSession`, or any audio code. It does not know the mix state, the soundtrack mode, or the pomodoro phase.

If `ShaderRenderer.init?` fails (no Metal device — extraordinarily unlikely on a macOS 26 supported Mac), `AppModel` keeps `scene` set to a no-op stub and the chip in the Focus header is hidden. Documented; not handled with a user-visible alert.

### 2.3 PopoverView ZStack order

`PopoverView` adds `SceneBackground()` as the **bottom** layer:

```
ZStack {
    SceneBackground()                  // NEW: shader render target
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

`NSViewRepresentable` over a thin `NSView` host that contains zero, one, or two stacked `MTKView`s. Two-view stack handles the crossfade: front view holds the active shader, back view holds the previous shader for the duration of the fade.

```swift
struct SceneBackground: NSViewRepresentable {
    @EnvironmentObject var scene: SceneController

    func makeNSView(context: Context) -> SceneHostView { SceneHostView() }

    func updateNSView(_ view: SceneHostView, context: Context) {
        switch scene.renderable {
        case .none:
            view.clear()
        case .shader(let inst):
            view.show(shader: inst)
        }
    }
}

final class SceneHostView: NSView {
    func show(shader: ShaderInstance) {
        // 1. Build a new MTKView with .delegate = ShaderDrawDelegate(instance: shader,
        //    renderer: <shared>).
        // 2. Add as front layer.
        // 3. Crossfade-out the previous front (now demoted to back) over 200 ms.
        // 4. Remove demoted view at fade end.
    }
    func clear() { /* fade out front, remove */ }
}
```

`ShaderDrawDelegate` (per-MTKView):

- Owns a single `ShaderInstance`.
- `mtkView(_:drawableSizeWillChange:)` → updates the cached `resolution` uniform.
- `draw(in:)` is called every frame by MTKView's `CVDisplayLink`. Builds a one-shot command buffer, sets the pipeline, binds three constant buffers (`time`, `resolution`, `accent`), draws three vertices (fullscreen quad), commits.

Lifecycle hooks on `SceneBackground`:

```swift
.onAppear  { scene.popoverDidAppear() }
.onDisappear { scene.popoverDidDisappear() }
```

`popoverDidAppear` sets `mtkView.isPaused = false`; `popoverDidDisappear` sets it to `true`. `isPaused = true` halts MTKView's render loop entirely — no GPU work, no `draw(in:)` calls.

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

Same `minimalIcon` styling as the gear (45% opacity → primary on hover, 28×28 frame). SF Symbol: `paintbrush.pointed`. Tooltip: "Scene".

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
│ │ thumb│ │ thumb│            │
│ │      │ │      │            │
│ └──────┘ └──────┘            │
│  Aurora    Plasma            │
│                              │
│ ┌──────┐ ┌──────┐            │
│ │ thumb│ │ thumb│            │
│ └──────┘ └──────┘            │
└──────────────────────────────┘
```

- "None" tile first; tap → `scene.setScene(nil)`.
- Then a 2-column grid of bundled scenes. Tile = 130×75 thumbnail (16:9), with title beneath. Selected tile gets a 2pt accent stroke.
- Tap a tile → `scene.setScene(id)` → popover dismisses.
- All v1 scenes are shaders, so no per-tile kind affordance is needed. (Reserve top-right corner for a glyph when image/video kinds land.)
- Empty state when `scenes.isEmpty`: centered text "No scenes installed." + one-line hint pointing at `Sources/Shuuchuu/Resources/shaders/`. Visible only on a fresh checkout (the directory is gitignored); production builds always ship the curated set.

### 2.7 Asset pipeline

New directory `Sources/Shuuchuu/Resources/shaders/`, gitignored alongside `sounds/`:

```
Sources/Shuuchuu/Resources/shaders/
├── aurora.metal
├── aurora.jpg                <- thumbnail
├── plasma.metal
├── plasma.jpg
├── starfield.metal
├── starfield.jpg
├── soft-waves.metal
├── soft-waves.jpg
├── rainfall.metal
└── rainfall.jpg
```

The shared vertex stage and any helper functions live as Swift string constants in `ShaderRenderer.swift`, compiled once into a separate `MTLLibrary` at renderer init. Scene authors never write or include shared MSL code.

`scripts/gen-scenes.py` (new) scans the directory for `<id>.metal` files (excluding the `_`-prefixed shared file), pairs them with `<id>.jpg` thumbnails, humanizes the stem to a title, and writes `Sources/Shuuchuu/Resources/scenes.json`:

```json
[
  {"id": "aurora",     "title": "Aurora",     "thumbnail": "aurora.jpg",     "kind": "shader"},
  {"id": "plasma",     "title": "Plasma",     "thumbnail": "plasma.jpg",     "kind": "shader"},
  {"id": "starfield",  "title": "Starfield",  "thumbnail": "starfield.jpg",  "kind": "shader"},
  {"id": "soft-waves", "title": "Soft Waves", "thumbnail": "soft-waves.jpg", "kind": "shader"},
  {"id": "rainfall",   "title": "Rainfall",   "thumbnail": "rainfall.jpg",   "kind": "shader"}
]
```

Both `shaders/` and `scenes.json` are gitignored. Running the script is a manual step (same as `gen-catalog.py`) — no build phase.

`Package.swift` already declares `Sources/Shuuchuu/Resources` as a resource path; the directory's `.metal` and `.jpg` files are picked up as `Bundle.module` resources automatically. **No `.metallib` precompilation.** The .metal sources are loaded as plain text resources at runtime and compiled by `MTLDevice.makeLibrary(source:)` on first use.

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
3. `SceneController` calls `renderer.instance(for: id)`. First-use compile of that scene's `.metal` source happens here (~50–200 ms on first call, ~µs on subsequent calls because the pipeline is cached).
4. `SceneController` publishes `.shader(instance)`.
5. `SceneBackground` observes the change, builds a new `MTKView` with a `ShaderDrawDelegate` over the instance, crossfades it in over 200 ms.
6. Picker dismisses. The shader is now visible behind the UI.

### 3.3 Switching scenes

Same path as 3.2. The crossfade is the only visual transition; the previous `MTKView` is removed after the fade completes. There are at most two `MTKView`s active at once (during the fade).

### 3.4 Clearing the scene

User taps "None" → `setScene(nil)` → `SceneBackground` crossfades to empty → `Wallpaper` shows through unchanged.

### 3.5 Popover open / close

`SceneBackground.onAppear` calls `scene.popoverDidAppear()` → sets `mtkView.isPaused = false`, render loop resumes. `onDisappear` calls `popoverDidDisappear()` → `isPaused = true`, GPU is idle. The `ShaderInstance.startTime` is preserved, so the time uniform continues to advance from where it left off — ie, the user perceives the shader as "still running" even though the GPU was idle while the popover was hidden. (For shaders where motion-from-zero matters, the author can mod or wrap the time uniform; the spec doesn't enforce a model.)

### 3.6 Sleep / wake

No special handling. MTKView's `isPaused` is already true while the popover is hidden, which is the typical state at sleep. On wake, if the popover is opened, render resumes.

### 3.7 Audio interaction

None. Shaders never touch `AVAudioSession` and never read app audio state in v1. The mix engine, soundtrack `WKWebView`, and pomodoro session continue to operate independently.

### 3.8 Failure modes

- **`.metal` source missing**: `ShaderRenderer.instance(for:)` throws; `SceneController.setScene` catches, sets `activeSceneId = nil`, logs a warning, renders empty.
- **`.metal` source has a compile error**: same path. The error is logged with the MSL diagnostic so the author can see what went wrong.
- **Empty catalog** (`scenes.json` is `[]`): library publishes `[]`, picker shows the empty state, no crashes anywhere in the chain.
- **Persisted id no longer in catalog**: fall back to nil silently on init.
- **No Metal device** (`MTLCreateSystemDefaultDevice()` returns nil): impossible on supported hardware, but `ShaderRenderer.init?` returns nil, the chip is hidden, the feature is silently disabled.

No modal alerts. Per project convention, all errors surface either inline or as silent fallbacks.

---

## 4. Shader authoring guidelines

These are documented in the spec; they are **not** enforced in code. Each scene is one self-contained `.metal` file plus one thumbnail JPG.

### 4.1 File template

```metal
// Sources/Shuuchuu/Resources/shaders/aurora.metal

#include <metal_stdlib>
using namespace metal;

fragment float4 sceneMain(float4 pos             [[position]],
                          constant float  &time       [[buffer(0)]],
                          constant float2 &resolution [[buffer(1)]],
                          constant float4 &accent     [[buffer(2)]]) {
    float2 uv = pos.xy / resolution;            // 0..1 across the panel
    // ... shader math ...
    float3 color = mix(accent.rgb, float3(0.05), 0.7);
    return float4(color, 1.0);
}
```

Required:

- One fragment function named **`sceneMain`** with exactly the signature above.
- Returns a premultiplied `float4` color (the framebuffer is configured with `bgra8Unorm` and standard alpha).
- No `#include` of project files; the only header is `<metal_stdlib>`. Each `.metal` file is compiled as a standalone `MTLLibrary`.

### 4.2 The shared vertex stage

A single fullscreen-quad vertex function is built into `ShaderRenderer` once at renderer init, from a Swift string constant compiled into its own `MTLLibrary`. Each scene's compiled fragment is paired with this shared vertex function at pipeline-build time. Authors never write a vertex stage.

The shared vertex stage emits a 3-vertex triangle that covers the entire viewport with `[[position]]` in framebuffer coordinates. That's why `pos.xy / resolution` gives 0..1 UVs.

### 4.3 Bound uniforms

| Buffer | Type     | Meaning                                              |
|--------|----------|------------------------------------------------------|
| 0      | `float`  | seconds since `ShaderInstance.startTime` (wall clock) |
| 1      | `float2` | drawable size in pixels (e.g. {680, 1080} on 2× displays) |
| 2      | `float4` | accent color from `DesignSettings.accent`, RGBA in linear sRGB |

No texture inputs in v1. No buffer 3+. No mutable state between frames.

### 4.4 Performance budget

Target: **< 1 ms per frame** at 2× retina (680×1080). Apple Silicon has plenty of headroom for typical shaders; this budget is generous, not tight. If a shader exceeds it, the panel still renders fine — the popover does not stutter — but the menu bar gets warmer and a battery-conscious user notices.

Authoring checklist:

- Avoid `for` loops with > 64 iterations (raymarchers, fractal iteration). Cap at ~32.
- Avoid `pow` and `exp` in tight inner loops. Approximate with polynomials when possible.
- Don't sample a texture you don't need (we don't bind any in v1, so this is moot, but worth keeping in mind for follow-ups).
- Test on the slowest target (M1 base) before shipping a shader.

### 4.5 Sourcing shaders

- **Original**: write directly in MSL.
- **Shadertoy port**: GLSL→MSL is mostly mechanical. `iTime → time`, `iResolution.xy → resolution`, `mainImage → sceneMain`, `gl_FragCoord → pos`, `vec2/vec3/vec4 → float2/float3/float4`, `mix/clamp/smoothstep` keep their names. Plan ~30 min per Shadertoy port for first-time authors. Only port shaders whose license permits redistribution (most Shadertoy shaders are CC-BY-NC-SA; check before bundling).

### 4.6 Thumbnails

Every `.metal` file needs a `<id>.jpg` thumbnail next to it. For v1, generate by hand: run the app, pick the scene, take a screenshot, crop to 16:9, downscale, save as `<id>.jpg`. Target: 260×148, JPG quality 75, < 30 KB.

A future helper could render shaders headlessly via a CLI (`xcrun metal` + offscreen `MTLTexture` → JPG); out of scope.

### 4.7 v1 starter set

Five shaders to validate the system end-to-end:

- **aurora** — vertical flowing color bands, accent-tinted.
- **plasma** — classic sin-of-sin gradient.
- **starfield** — slowly drifting parallax stars.
- **soft-waves** — horizontal sine waves with a subtle glow.
- **rainfall** — thin diagonal streaks against a dark sky.

These give a mix of "calm" (waves, rainfall) and "alive" (plasma, starfield) so the picker visibly demonstrates the range from day one.

---

## 5. Performance considerations

- **One active fragment shader at the panel size.** Even a moderately heavy shader (raymarcher with 32 steps) runs in well under 1 ms per frame at 680×1080 on Apple Silicon. The cost is dwarfed by the existing audio engine and SwiftUI render path.
- **Render loop pauses with the popover.** `mtkView.isPaused = true` on `onDisappear` halts the render callback entirely — zero GPU work while the popover is dismissed.
- **First-use compile cost.** ~50–200 ms to compile one `.metal` source the first time the user picks it. Pipelines are cached for the lifetime of the process, so subsequent picks are µs.
- **No SwiftUI redraws from shader frames.** The shader renders into an `MTKView`'s drawable, outside SwiftUI's render path. Pomodoro-driven 1 Hz timer label redraws don't affect shader playback or vice versa.
- **Memory**: trivial. One pipeline state per ever-used shader (~10s of KB), one drawable per active MTKView (~3 MB at 680×1080 RGBA).
- **Crossfade window**: ≤ 200 ms with two MTKViews rendering simultaneously — peak is two shaders' worth of work, still well under 2 ms total per frame.

---

## 6. Files added / modified

**Added:**
- `Sources/Shuuchuu/Models/Scene.swift` — `Scene` + `SceneKind` types.
- `Sources/Shuuchuu/Models/ScenesLibrary.swift` — `ObservableObject` library loader.
- `Sources/Shuuchuu/Scenes/SceneController.swift` — controller with `Renderable` lifecycle and `UserDefaults` persistence.
- `Sources/Shuuchuu/Scenes/ShaderRenderer.swift` — Metal device/queue holder, shared vertex library, MSL→pipeline cache.
- `Sources/Shuuchuu/Scenes/ShaderDrawDelegate.swift` — per-`MTKView` draw delegate that owns one `ShaderInstance` and binds the three uniform buffers each frame.
- `Sources/Shuuchuu/UI/Components/SceneBackground.swift` — `NSViewRepresentable` host + `SceneHostView` with crossfade.
- `Sources/Shuuchuu/UI/Components/SceneScrim.swift` — gradient overlay.
- `Sources/Shuuchuu/UI/Components/ScenePicker.swift` — popover content (grid + None tile).
- `Sources/Shuuchuu/Resources/shaders/` — gitignored bundle directory containing the 5 starter `.metal` files + thumbnails.
- `Sources/Shuuchuu/Resources/scenes.json` — gitignored generated catalog.
- `scripts/gen-scenes.py` — scanner that emits `scenes.json`.
- `Tests/ShuuchuuTests/SceneControllerTests.swift` — see §7.

**Modified:**
- `Sources/Shuuchuu/AppModel.swift` — add `scenes: ScenesLibrary`, `shaderRenderer: ShaderRenderer`, and `scene: SceneController` properties; construct in `live(...)`.
- `Sources/Shuuchuu/UI/PopoverView.swift` — add `SceneBackground` and `SceneScrim` to the bottom of the ZStack; inject env objects.
- `Sources/Shuuchuu/UI/Pages/FocusPage.swift` — add the scene chip + picker popover state to `header`.
- `.gitignore` — add `Sources/Shuuchuu/Resources/shaders/` and `Sources/Shuuchuu/Resources/scenes.json`.

---

## 7. Testing

The Metal/UI separation means the controller can be unit-tested without instantiating a real `ShaderRenderer`, and renders can be validated by SwiftUI Preview during development. There are no snapshot tests anywhere in the project — don't add one for this.

**`SceneControllerTests`** — XCTest, in `Tests/ShuuchuuTests/`:

- `setScene(_:)` with a known-good id → publishes the new id, persists to `UserDefaults`, publishes a non-`.none` `Renderable`.
- `setScene(nil)` → publishes nil, clears the persisted key, publishes `.none`.
- `setScene` with an id not in the library → falls back to nil, no crash.
- `setScene` with a library id whose renderer compile fails → falls back to nil, no crash, error logged.
- `init` with a previously persisted id that is still in the library and compiles → restores it.
- `init` with a previously persisted id no longer in the library → starts at nil.

Use a fixture `ScenesLibrary` injected via init and a stub `ShaderRendererProtocol` (extract a tiny protocol over `instance(for:)` so tests can inject a stub that returns/throws as needed). Use an in-memory `UserDefaults(suiteName:)`. **No real `MTLDevice` involvement in tests** — the Metal compile path is exercised manually during development by running the app and picking each shipped shader.

Skipped:
- Real `MTLRenderPipelineState` / `MTKView` integration tests — fragile, slow, and the surface is small enough to validate by hand.
- Snapshot/visual tests — none exist in the project; out of scope.
- Per-shader visual correctness — the author validates each shader at authoring time.

---

## 8. Out of scope (do not add in passing)

These are intentionally deferred:

- Image scenes (JPG/HEIC).
- Video scenes (MP4/MOV via AVPlayer).
- User-supplied shader/video/image folder.
- Audio-reactive uniforms (mix volume / pomodoro phase → shader).
- Per-shader uniform UI ("tweak the colors / speed").
- Hot-reload of `.metal` sources during development.
- Per-soundtrack auto-pairing.
- Per-mix scene persistence.
- Tunable scrim opacity in `DesignSettings`.
- Configurable crossfade duration.
- Per-scene metadata (author, license, longer description).
- A "Random" or "Shuffle" scene mode.
- Pause-on-audio-pause behavior (scene always loops; this was an explicit decision).
- Diagnostic HUD.
- A headless thumbnail-rendering CLI.

If any of these come up post-launch, they get their own spec.
