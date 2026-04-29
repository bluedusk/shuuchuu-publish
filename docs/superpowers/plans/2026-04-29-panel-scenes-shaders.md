# Panel Scenes (Shaders) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a shader-backed scene background behind the popover, picked via a chip in the Focus header.

**Architecture:** A new `Scenes/` module owns a `ScenesLibrary` (decodes `scenes.json`), a `ShaderRenderer` (Metal device + per-shader pipeline cache, lazily compiles `.metal` sources from `Bundle.module`), and a `SceneController` (publishes the active scene id, persists to `UserDefaults`, warms pipelines on selection). A new SwiftUI layer in `PopoverView` hosts an `MTKView` per active shader with a 200 ms crossfade on switch. UI is preview-driven; controller logic is unit-tested with a stub renderer that needs no Metal device.

**Tech Stack:** Swift 6, SwiftUI on macOS 26, Metal 3 (`MTKView`, `MTLRenderPipelineState`, `device.makeLibrary(source:)` runtime compile), XCTest for unit tests.

**Spec:** `docs/superpowers/specs/2026-04-28-panel-scene-backgrounds-design.md`

**Notable deviation from the spec:** §2.1's `Renderable` enum is collapsed into a published `Active` struct on `SceneController` (carries only `id` + `startTime`, no `MTLRenderPipelineState`). The spec's design coupled controller tests to Metal; this restructure keeps the controller fully testable without an `MTLDevice` and matches the spec's own self-imposed test rule. `ShaderRenderer.pipeline(for:)` is the single Metal-touching call, made by `SceneBackground` at draw setup time.

---

## File map

**Created**

| Path | Responsibility |
|------|----------------|
| `Sources/Shuuchuu/Models/Scene.swift` | `Scene` struct + `SceneKind` enum |
| `Sources/Shuuchuu/Models/ScenesLibrary.swift` | `@MainActor ObservableObject` that decodes `scenes.json` from `Bundle.module` (or injected `Data` for tests) |
| `Sources/Shuuchuu/Scenes/ShaderRendering.swift` | `ShaderRendering` protocol + `ShaderRendererError` |
| `Sources/Shuuchuu/Scenes/ShaderRenderer.swift` | Real impl: Metal device, command queue, shared vertex library, MSL→pipeline cache |
| `Sources/Shuuchuu/Scenes/SceneController.swift` | Publishes `Active?`, persists last-used id, warms pipeline on `setScene` |
| `Sources/Shuuchuu/Scenes/ShaderDrawDelegate.swift` | `MTKViewDelegate` that binds the three uniform buffers each frame |
| `Sources/Shuuchuu/UI/Components/SceneBackground.swift` | `NSViewRepresentable` + `SceneHostView` (host with up to two stacked `MTKView`s + crossfade) |
| `Sources/Shuuchuu/UI/Components/SceneScrim.swift` | Top/bottom gradient overlay |
| `Sources/Shuuchuu/UI/Components/ScenePicker.swift` | Popover content: 2-column grid of thumbnails + None tile |
| `Sources/Shuuchuu/Resources/shaders/plasma.metal` | First (bootstrap) shader |
| `Sources/Shuuchuu/Resources/shaders/aurora.metal` | v1 starter shader |
| `Sources/Shuuchuu/Resources/shaders/starfield.metal` | v1 starter shader |
| `Sources/Shuuchuu/Resources/shaders/soft-waves.metal` | v1 starter shader |
| `Sources/Shuuchuu/Resources/shaders/rainfall.metal` | v1 starter shader |
| `Sources/Shuuchuu/Resources/shaders/<id>.jpg` (×5) | Hand-screenshotted thumbnails |
| `Sources/Shuuchuu/Resources/scenes.json` | Generated catalog (gitignored) |
| `scripts/gen-scenes.py` | Catalog generator |
| `Tests/ShuuchuuTests/SceneTests.swift` | Decode tests for `Scene` |
| `Tests/ShuuchuuTests/ScenesLibraryTests.swift` | Library decode + `entry(id:)` tests |
| `Tests/ShuuchuuTests/SceneControllerTests.swift` | Controller persistence + warm/fail behavior |
| `Tests/ShuuchuuTests/StubShaderRenderer.swift` | Test double for `ShaderRendering` |
| `Tests/ShuuchuuTests/Fixtures/scenes-fixture.json` | Static catalog used by ScenesLibrary tests |

**Modified**

| Path | What changes |
|------|--------------|
| `.gitignore` | Add `Sources/Shuuchuu/Resources/shaders/` and `Sources/Shuuchuu/Resources/scenes.json` |
| `Sources/Shuuchuu/AppModel.swift` | Add `scenes`, `shaderRenderer`, `scene` properties; constructor wires them |
| `Sources/Shuuchuu/ShuuchuuApp.swift` | `AppModel.live(...)` constructs and passes the three new types |
| `Sources/Shuuchuu/UI/PopoverView.swift` | Add `SceneBackground` and `SceneScrim` to the bottom of the ZStack; inject `model.scenes` and `model.scene` into env |
| `Sources/Shuuchuu/UI/Pages/FocusPage.swift` | Add scene chip + popover presentation in `header` |

---

## Conventions

- Every Swift task ends with `swift build` (must succeed) and a commit.
- Test tasks run `swift test --filter <SuiteName>` and require PASS before commit.
- After a UI/code change that the user could see, relaunch the app: `pkill -x Shuuchuu; swift run` (per CLAUDE.md).
- Use absolute paths in shell commands; the working dir is `/Users/dan/playground/x-noise/` but session CWD drifts (per CLAUDE.md).
- Imports go at the top of each file; `@MainActor` only where required (audio engine, UI orchestration). Per CLAUDE.md, do **not** annotate UserDefaults wrappers with `@MainActor`.

---

## Task 1: Update `.gitignore`

**Files:**
- Modify: `.gitignore`

- [ ] **Step 1: Read the current `.gitignore`**

```bash
cat /Users/dan/playground/x-noise/.gitignore
```

- [ ] **Step 2: Append shader resource ignore lines**

Add the following block immediately under the existing `# local dev content — sound files are not part of the repo …` block:

```gitignore
# local dev content — shaders/scenes are not part of the repo
Sources/Shuuchuu/Resources/shaders/
Sources/Shuuchuu/Resources/scenes.json
```

- [ ] **Step 3: Verify the patterns work**

```bash
mkdir -p /Users/dan/playground/x-noise/Sources/Shuuchuu/Resources/shaders
touch  /Users/dan/playground/x-noise/Sources/Shuuchuu/Resources/shaders/.gitkeep
cd /Users/dan/playground/x-noise && git status --short Sources/Shuuchuu/Resources/
```
Expected: no entry for `shaders/` or `scenes.json`. Then remove the placeholder:
```bash
rm /Users/dan/playground/x-noise/Sources/Shuuchuu/Resources/shaders/.gitkeep
```

- [ ] **Step 4: Commit**

```bash
cd /Users/dan/playground/x-noise && git add .gitignore && git commit -m "Scenes: gitignore Resources/shaders/ and scenes.json"
```

---

## Task 2: `Scene` model + tests

**Files:**
- Create: `Sources/Shuuchuu/Models/Scene.swift`
- Create: `Tests/ShuuchuuTests/SceneTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/ShuuchuuTests/SceneTests.swift`:

```swift
import XCTest
@testable import Shuuchuu

final class SceneTests: XCTestCase {
    func testDecodeShaderEntry() throws {
        let json = #"""
        [{"id":"plasma","title":"Plasma","thumbnail":"plasma.jpg","kind":"shader"}]
        """#
        let scenes = try JSONDecoder().decode([Scene].self, from: Data(json.utf8))
        XCTAssertEqual(scenes.count, 1)
        XCTAssertEqual(scenes[0].id, "plasma")
        XCTAssertEqual(scenes[0].title, "Plasma")
        XCTAssertEqual(scenes[0].thumbnail, "plasma.jpg")
        XCTAssertEqual(scenes[0].kind, .shader)
    }

    func testRoundTripEncoding() throws {
        let original = Scene(id: "aurora", title: "Aurora",
                             thumbnail: "aurora.jpg", kind: .shader)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Scene.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testRejectsUnknownKind() {
        let json = #"""
        [{"id":"x","title":"X","thumbnail":"x.jpg","kind":"video"}]
        """#
        XCTAssertThrowsError(try JSONDecoder().decode([Scene].self,
                                                      from: Data(json.utf8)))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd /Users/dan/playground/x-noise && swift test --filter SceneTests 2>&1 | tail -20
```
Expected: build error — `Scene` and `SceneKind` not found.

- [ ] **Step 3: Write the model**

Create `Sources/Shuuchuu/Models/Scene.swift`:

```swift
import Foundation

public enum SceneKind: String, Codable, Sendable, Equatable {
    case shader
}

public struct Scene: Identifiable, Codable, Sendable, Equatable {
    public let id: String
    public let title: String
    public let thumbnail: String
    public let kind: SceneKind

    public init(id: String, title: String, thumbnail: String, kind: SceneKind) {
        self.id = id
        self.title = title
        self.thumbnail = thumbnail
        self.kind = kind
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
cd /Users/dan/playground/x-noise && swift test --filter SceneTests 2>&1 | tail -20
```
Expected: 3 tests passed.

- [ ] **Step 5: Commit**

```bash
cd /Users/dan/playground/x-noise && \
  git add Sources/Shuuchuu/Models/Scene.swift Tests/ShuuchuuTests/SceneTests.swift && \
  git commit -m "Scenes: add Scene + SceneKind model with codable tests"
```

---

## Task 3: `ScenesLibrary` + tests

**Files:**
- Create: `Sources/Shuuchuu/Models/ScenesLibrary.swift`
- Create: `Tests/ShuuchuuTests/ScenesLibraryTests.swift`
- Create: `Tests/ShuuchuuTests/Fixtures/scenes-fixture.json`

- [ ] **Step 1: Create the fixture**

Create `Tests/ShuuchuuTests/Fixtures/scenes-fixture.json`:

```json
[
  {"id":"plasma","title":"Plasma","thumbnail":"plasma.jpg","kind":"shader"},
  {"id":"aurora","title":"Aurora","thumbnail":"aurora.jpg","kind":"shader"}
]
```

- [ ] **Step 2: Write the failing tests**

Create `Tests/ShuuchuuTests/ScenesLibraryTests.swift`:

```swift
import XCTest
@testable import Shuuchuu

@MainActor
final class ScenesLibraryTests: XCTestCase {
    func testDecodesInjectedData() {
        let url = Bundle.module.url(forResource: "scenes-fixture",
                                    withExtension: "json")!
        let data = try! Data(contentsOf: url)
        let lib = ScenesLibrary(jsonData: data)
        XCTAssertEqual(lib.scenes.count, 2)
        XCTAssertEqual(lib.scenes.map(\.id), ["plasma", "aurora"])
    }

    func testEntryByIdHit() {
        let url = Bundle.module.url(forResource: "scenes-fixture",
                                    withExtension: "json")!
        let lib = ScenesLibrary(jsonData: try! Data(contentsOf: url))
        XCTAssertEqual(lib.entry(id: "aurora")?.title, "Aurora")
    }

    func testEntryByIdMiss() {
        let url = Bundle.module.url(forResource: "scenes-fixture",
                                    withExtension: "json")!
        let lib = ScenesLibrary(jsonData: try! Data(contentsOf: url))
        XCTAssertNil(lib.entry(id: "nope"))
    }

    func testEmptyOnInvalidJSON() {
        let lib = ScenesLibrary(jsonData: Data("not json".utf8))
        XCTAssertTrue(lib.scenes.isEmpty)
    }

    func testEmptyOnNilDataInTestEnvironment() {
        // Bundle.module in tests is the test bundle and contains no scenes.json.
        let lib = ScenesLibrary()
        XCTAssertTrue(lib.scenes.isEmpty)
    }
}
```

- [ ] **Step 3: Run tests to verify they fail**

```bash
cd /Users/dan/playground/x-noise && swift test --filter ScenesLibraryTests 2>&1 | tail -20
```
Expected: build error — `ScenesLibrary` not found.

- [ ] **Step 4: Implement `ScenesLibrary`**

Create `Sources/Shuuchuu/Models/ScenesLibrary.swift`:

```swift
import Foundation
import Combine

@MainActor
public final class ScenesLibrary: ObservableObject {
    @Published public private(set) var scenes: [Scene] = []

    public init(jsonData: Data? = nil) {
        if let data = jsonData {
            decodeAndPublish(data)
        } else {
            loadFromBundle()
        }
    }

    public func entry(id: String) -> Scene? {
        scenes.first { $0.id == id }
    }

    private func loadFromBundle() {
        guard let url = Bundle.module.url(forResource: "scenes",
                                          withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            scenes = []
            return
        }
        decodeAndPublish(data)
    }

    private func decodeAndPublish(_ data: Data) {
        if let decoded = try? JSONDecoder().decode([Scene].self, from: data) {
            scenes = decoded
        } else {
            scenes = []
        }
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

```bash
cd /Users/dan/playground/x-noise && swift test --filter ScenesLibraryTests 2>&1 | tail -20
```
Expected: 5 tests passed.

- [ ] **Step 6: Commit**

```bash
cd /Users/dan/playground/x-noise && \
  git add Sources/Shuuchuu/Models/ScenesLibrary.swift \
          Tests/ShuuchuuTests/ScenesLibraryTests.swift \
          Tests/ShuuchuuTests/Fixtures/scenes-fixture.json && \
  git commit -m "Scenes: add ScenesLibrary with bundle + injected-data loaders"
```

---

## Task 4: `ShaderRendering` protocol + error type

**Files:**
- Create: `Sources/Shuuchuu/Scenes/ShaderRendering.swift`

No tests — protocol declaration only. Real conformance comes in Task 7; stub for tests comes in Task 5.

- [ ] **Step 1: Create the directory and file**

```bash
mkdir -p /Users/dan/playground/x-noise/Sources/Shuuchuu/Scenes
```

Create `Sources/Shuuchuu/Scenes/ShaderRendering.swift`:

```swift
import Foundation
import Metal

/// Errors thrown by `ShaderRendering` implementations.
public enum ShaderRendererError: Error, Equatable {
    case noMetalDevice
    case sourceNotFound(sceneId: String)
    case compileFailed(sceneId: String, message: String)
    case missingFunction(sceneId: String, function: String)
}

/// Compiles and caches Metal pipelines for shader scenes.
///
/// `warm(_:)` is called by `SceneController.setScene` when the user picks a scene —
/// it surfaces compile errors *before* the controller publishes the new id, so a
/// broken `.metal` file falls back to no scene instead of producing a black square.
///
/// `pipeline(for:)` is called by `SceneBackground`/`SceneHostView` at MTKView build
/// time. It is expected to return a cached pipeline (warm has already been called).
@MainActor
public protocol ShaderRendering: AnyObject {
    func warm(_ sceneId: String) throws
    func pipeline(for sceneId: String) throws -> MTLRenderPipelineState
}
```

- [ ] **Step 2: Verify the build still compiles**

```bash
cd /Users/dan/playground/x-noise && swift build 2>&1 | tail -10
```
Expected: build succeeds with no errors.

- [ ] **Step 3: Commit**

```bash
cd /Users/dan/playground/x-noise && \
  git add Sources/Shuuchuu/Scenes/ShaderRendering.swift && \
  git commit -m "Scenes: add ShaderRendering protocol and error type"
```

---

## Task 5: `SceneController` + tests with stub renderer

**Files:**
- Create: `Sources/Shuuchuu/Scenes/SceneController.swift`
- Create: `Tests/ShuuchuuTests/StubShaderRenderer.swift`
- Create: `Tests/ShuuchuuTests/SceneControllerTests.swift`

- [ ] **Step 1: Write the stub renderer (test-only)**

Create `Tests/ShuuchuuTests/StubShaderRenderer.swift`:

```swift
import Foundation
import Metal
@testable import Shuuchuu

@MainActor
final class StubShaderRenderer: ShaderRendering {
    var failOn: Set<String> = []
    private(set) var warmedIds: [String] = []

    func warm(_ sceneId: String) throws {
        warmedIds.append(sceneId)
        if failOn.contains(sceneId) {
            throw ShaderRendererError.compileFailed(
                sceneId: sceneId, message: "stub forced failure"
            )
        }
    }

    func pipeline(for sceneId: String) throws -> MTLRenderPipelineState {
        // Tests never exercise the draw path; trap so a regression surfaces loudly.
        fatalError("StubShaderRenderer.pipeline(for:) must not be called in tests")
    }
}
```

- [ ] **Step 2: Write the failing tests**

Create `Tests/ShuuchuuTests/SceneControllerTests.swift`:

```swift
import XCTest
@testable import Shuuchuu

@MainActor
final class SceneControllerTests: XCTestCase {
    private static let defaultsKey = "shuuchuu.activeScene"

    private func makeDefaults() -> UserDefaults {
        let suite = "tests.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        return d
    }

    private func library() -> ScenesLibrary {
        let url = Bundle.module.url(forResource: "scenes-fixture",
                                    withExtension: "json")!
        return ScenesLibrary(jsonData: try! Data(contentsOf: url))
    }

    func testSetSceneValidIdPublishesAndPersists() {
        let defaults = makeDefaults()
        let renderer = StubShaderRenderer()
        let ctl = SceneController(library: library(), renderer: renderer,
                                  defaults: defaults)
        ctl.setScene("aurora")
        XCTAssertEqual(ctl.activeSceneId, "aurora")
        XCTAssertNotNil(ctl.active)
        XCTAssertEqual(defaults.string(forKey: Self.defaultsKey), "aurora")
        XCTAssertEqual(renderer.warmedIds, ["aurora"])
    }

    func testSetSceneNilClearsAndUnpersists() {
        let defaults = makeDefaults()
        let ctl = SceneController(library: library(),
                                  renderer: StubShaderRenderer(),
                                  defaults: defaults)
        ctl.setScene("aurora")
        ctl.setScene(nil)
        XCTAssertNil(ctl.activeSceneId)
        XCTAssertNil(ctl.active)
        XCTAssertNil(defaults.string(forKey: Self.defaultsKey))
    }

    func testSetSceneUnknownIdFallsBackToNil() {
        let defaults = makeDefaults()
        let ctl = SceneController(library: library(),
                                  renderer: StubShaderRenderer(),
                                  defaults: defaults)
        ctl.setScene("not-in-library")
        XCTAssertNil(ctl.activeSceneId)
        XCTAssertNil(defaults.string(forKey: Self.defaultsKey))
    }

    func testSetSceneCompileFailureFallsBackToNil() {
        let defaults = makeDefaults()
        let renderer = StubShaderRenderer()
        renderer.failOn = ["aurora"]
        let ctl = SceneController(library: library(), renderer: renderer,
                                  defaults: defaults)
        ctl.setScene("aurora")
        XCTAssertNil(ctl.activeSceneId)
        XCTAssertNil(defaults.string(forKey: Self.defaultsKey))
    }

    func testInitRestoresFromDefaultsWhenIdValid() {
        let defaults = makeDefaults()
        defaults.set("plasma", forKey: Self.defaultsKey)
        let ctl = SceneController(library: library(),
                                  renderer: StubShaderRenderer(),
                                  defaults: defaults)
        XCTAssertEqual(ctl.activeSceneId, "plasma")
    }

    func testInitFallsBackWhenPersistedIdMissingFromLibrary() {
        let defaults = makeDefaults()
        defaults.set("ghost", forKey: Self.defaultsKey)
        let ctl = SceneController(library: library(),
                                  renderer: StubShaderRenderer(),
                                  defaults: defaults)
        XCTAssertNil(ctl.activeSceneId)
    }

    func testInitFallsBackWhenWarmFailsForPersistedId() {
        let defaults = makeDefaults()
        defaults.set("plasma", forKey: Self.defaultsKey)
        let renderer = StubShaderRenderer()
        renderer.failOn = ["plasma"]
        let ctl = SceneController(library: library(), renderer: renderer,
                                  defaults: defaults)
        XCTAssertNil(ctl.activeSceneId)
        // Should also remove the bad id from defaults so we don't retry next launch.
        XCTAssertNil(defaults.string(forKey: Self.defaultsKey))
    }
}
```

- [ ] **Step 3: Run tests to verify they fail**

```bash
cd /Users/dan/playground/x-noise && swift test --filter SceneControllerTests 2>&1 | tail -20
```
Expected: build error — `SceneController` not found.

- [ ] **Step 4: Implement `SceneController`**

Create `Sources/Shuuchuu/Scenes/SceneController.swift`:

```swift
import Foundation
import Combine
import QuartzCore

@MainActor
public final class SceneController: ObservableObject {
    public struct Active: Equatable, Sendable {
        public let id: String
        public let startTime: CFTimeInterval
    }

    @Published public private(set) var active: Active?

    public var activeSceneId: String? { active?.id }

    private let library: ScenesLibrary
    private let renderer: ShaderRendering
    private let defaults: UserDefaults

    private static let defaultsKey = "shuuchuu.activeScene"

    public init(library: ScenesLibrary,
                renderer: ShaderRendering,
                defaults: UserDefaults = .standard) {
        self.library = library
        self.renderer = renderer
        self.defaults = defaults
        if let id = defaults.string(forKey: Self.defaultsKey) {
            setScene(id)
        }
    }

    public func setScene(_ id: String?) {
        guard let id, library.entry(id: id) != nil else {
            clearActive()
            return
        }
        do {
            try renderer.warm(id)
            active = Active(id: id, startTime: CACurrentMediaTime())
            defaults.set(id, forKey: Self.defaultsKey)
        } catch {
            print("[SceneController] warm failed for \(id): \(error)")
            clearActive()
        }
    }

    private func clearActive() {
        active = nil
        defaults.removeObject(forKey: Self.defaultsKey)
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

```bash
cd /Users/dan/playground/x-noise && swift test --filter SceneControllerTests 2>&1 | tail -20
```
Expected: 7 tests passed.

- [ ] **Step 6: Commit**

```bash
cd /Users/dan/playground/x-noise && \
  git add Sources/Shuuchuu/Scenes/SceneController.swift \
          Tests/ShuuchuuTests/SceneControllerTests.swift \
          Tests/ShuuchuuTests/StubShaderRenderer.swift && \
  git commit -m "Scenes: add SceneController with persistence + warm-on-set"
```

---

## Task 6: Bootstrap `gen-scenes.py`, the first `.metal` file, and `scenes.json`

**Files:**
- Create: `scripts/gen-scenes.py`
- Create: `Sources/Shuuchuu/Resources/shaders/plasma.metal`
- Create: `Sources/Shuuchuu/Resources/shaders/plasma.jpg` (placeholder — real screenshot in Task 16)
- Create: `Sources/Shuuchuu/Resources/scenes.json` (generated)

This task only verifies the asset pipeline end-to-end with one shader. The other four are added in Task 15.

- [ ] **Step 1: Write `gen-scenes.py`**

Create `scripts/gen-scenes.py`:

```python
#!/usr/bin/env python3
"""Generate the bundled scenes.json that ships inside the app.

Scans Sources/Shuuchuu/Resources/shaders/ for `<id>.metal` files (excluding
`_`-prefixed shared files) and pairs each one with `<id>.jpg`. Files without a
matching thumbnail are skipped with a warning.

Run from project root:
    python3 scripts/gen-scenes.py > Sources/Shuuchuu/Resources/scenes.json
"""
import json
import os
import sys

SCENES_DIR = "Sources/Shuuchuu/Resources/shaders"


def humanize(stem: str) -> str:
    return stem.replace("-", " ").replace("_", " ").title()


def main() -> int:
    if not os.path.isdir(SCENES_DIR):
        print("[]")
        return 0
    entries = []
    for name in sorted(os.listdir(SCENES_DIR)):
        if not name.endswith(".metal") or name.startswith("_"):
            continue
        stem = name[: -len(".metal")]
        thumb = f"{stem}.jpg"
        if not os.path.exists(os.path.join(SCENES_DIR, thumb)):
            print(f"warning: missing thumbnail {thumb} for {name}",
                  file=sys.stderr)
            continue
        entries.append({
            "id": stem,
            "title": humanize(stem),
            "thumbnail": thumb,
            "kind": "shader",
        })
    json.dump(entries, sys.stdout, indent=2)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
```

```bash
chmod +x /Users/dan/playground/x-noise/scripts/gen-scenes.py
```

- [ ] **Step 2: Write the bootstrap shader (plasma)**

Create `Sources/Shuuchuu/Resources/shaders/plasma.metal`:

```metal
#include <metal_stdlib>
using namespace metal;

fragment float4 sceneMain(float4 pos             [[position]],
                          constant float  &time       [[buffer(0)]],
                          constant float2 &resolution [[buffer(1)]],
                          constant float4 &accent     [[buffer(2)]]) {
    float2 uv = pos.xy / resolution;
    float v = sin(uv.x * 10.0 + time)
            + sin(uv.y * 10.0 + time * 1.3)
            + sin((uv.x + uv.y) * 8.0 + time * 0.7);
    v = (v + 3.0) / 6.0;                    // 0..1
    float3 base = mix(float3(0.05, 0.04, 0.10), accent.rgb, v);
    return float4(base, 1.0);
}
```

- [ ] **Step 3: Drop in a placeholder thumbnail**

Use any 130×75 JPG. Easiest: a solid-color render via `sips`:

```bash
cd /Users/dan/playground/x-noise && \
  python3 -c "from PIL import Image; Image.new('RGB',(260,148),(40,30,80)).save('Sources/Shuuchuu/Resources/shaders/plasma.jpg', 'JPEG', quality=75)" \
  || sips -s format jpeg -z 148 260 /System/Library/Desktop\ Pictures/Solid\ Colors/Black.png --out Sources/Shuuchuu/Resources/shaders/plasma.jpg
```

If neither runs cleanly, hand-create any small JPG at that path. The real thumbnail comes in Task 16.

- [ ] **Step 4: Generate `scenes.json` and verify**

```bash
cd /Users/dan/playground/x-noise && \
  python3 scripts/gen-scenes.py > Sources/Shuuchuu/Resources/scenes.json && \
  cat Sources/Shuuchuu/Resources/scenes.json
```
Expected output:
```json
[
  {
    "id": "plasma",
    "title": "Plasma",
    "thumbnail": "plasma.jpg",
    "kind": "shader"
  }
]
```

- [ ] **Step 5: Verify the build still succeeds**

```bash
cd /Users/dan/playground/x-noise && swift build 2>&1 | tail -10
```
Expected: build succeeds. The `.metal`, `.jpg`, and `.json` files are picked up as `process` resources by the existing `Sources/Shuuchuu/Resources` declaration in `Package.swift`.

- [ ] **Step 6: Commit**

```bash
cd /Users/dan/playground/x-noise && \
  git add scripts/gen-scenes.py && \
  git commit -m "Scenes: add gen-scenes.py asset-catalog generator"
```

(Note: `Resources/shaders/` and `scenes.json` are gitignored from Task 1, so they are not committed — that's intentional.)

---

## Task 7: `ShaderRenderer` real implementation

**Files:**
- Create: `Sources/Shuuchuu/Scenes/ShaderRenderer.swift`

No unit tests — Metal-bound. Validated by manual smoke test once the UI is wired (Task 14). The compile path is exercised the moment the user picks any shader.

- [ ] **Step 1: Implement `ShaderRenderer`**

Create `Sources/Shuuchuu/Scenes/ShaderRenderer.swift`:

```swift
import Foundation
import Metal

@MainActor
public final class ShaderRenderer: ShaderRendering {
    public let device: MTLDevice
    public let queue: MTLCommandQueue
    private let vertexFunction: MTLFunction
    private var pipelineCache: [String: MTLRenderPipelineState] = [:]

    private static let vertexSource = """
    #include <metal_stdlib>
    using namespace metal;

    vertex float4 sceneVertex(uint vid [[vertex_id]]) {
        // Single fullscreen triangle covering the viewport at NDC corners.
        float2 p = float2((vid == 1) ? 3.0 : -1.0,
                          (vid == 2) ? -3.0 : 1.0);
        return float4(p, 0.0, 1.0);
    }
    """

    public init?() {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else {
            return nil
        }
        do {
            let vertLib = try device.makeLibrary(source: Self.vertexSource,
                                                 options: nil)
            guard let vertFn = vertLib.makeFunction(name: "sceneVertex") else {
                return nil
            }
            self.device = device
            self.queue = queue
            self.vertexFunction = vertFn
        } catch {
            print("[ShaderRenderer] failed to compile shared vertex stage: \(error)")
            return nil
        }
    }

    public func warm(_ sceneId: String) throws {
        _ = try cachedPipeline(for: sceneId)
    }

    public func pipeline(for sceneId: String) throws -> MTLRenderPipelineState {
        try cachedPipeline(for: sceneId)
    }

    private func cachedPipeline(for sceneId: String) throws -> MTLRenderPipelineState {
        if let cached = pipelineCache[sceneId] { return cached }

        guard let url = Bundle.module.url(forResource: sceneId,
                                          withExtension: "metal"),
              let source = try? String(contentsOf: url, encoding: .utf8) else {
            throw ShaderRendererError.sourceNotFound(sceneId: sceneId)
        }

        let fragLib: MTLLibrary
        do {
            fragLib = try device.makeLibrary(source: source, options: nil)
        } catch {
            throw ShaderRendererError.compileFailed(
                sceneId: sceneId,
                message: String(describing: error)
            )
        }

        guard let fragFn = fragLib.makeFunction(name: "sceneMain") else {
            throw ShaderRendererError.missingFunction(sceneId: sceneId,
                                                      function: "sceneMain")
        }

        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = vertexFunction
        desc.fragmentFunction = fragFn
        desc.colorAttachments[0].pixelFormat = .bgra8Unorm

        let pipeline = try device.makeRenderPipelineState(descriptor: desc)
        pipelineCache[sceneId] = pipeline
        return pipeline
    }
}
```

- [ ] **Step 2: Verify the build succeeds**

```bash
cd /Users/dan/playground/x-noise && swift build 2>&1 | tail -10
```
Expected: build succeeds. (The renderer isn't wired in yet; this is just type-checking.)

- [ ] **Step 3: Commit**

```bash
cd /Users/dan/playground/x-noise && \
  git add Sources/Shuuchuu/Scenes/ShaderRenderer.swift && \
  git commit -m "Scenes: add ShaderRenderer with shared vertex stage and pipeline cache"
```

---

## Task 8: `ShaderDrawDelegate`

**Files:**
- Create: `Sources/Shuuchuu/Scenes/ShaderDrawDelegate.swift`

- [ ] **Step 1: Implement the delegate**

Create `Sources/Shuuchuu/Scenes/ShaderDrawDelegate.swift`:

```swift
import Foundation
import MetalKit
import simd

/// Per-MTKView delegate that owns one pipeline + start time and binds the three
/// uniform buffers each frame. Stateless across frames otherwise.
final class ShaderDrawDelegate: NSObject, MTKViewDelegate {
    private let pipeline: MTLRenderPipelineState
    private let queue: MTLCommandQueue
    private let startTime: CFTimeInterval
    private var resolution = SIMD2<Float>(1, 1)

    /// Updated by the host on each `updateNSView` so live hue-slider changes
    /// in `DesignSettings` flow through to the shader.
    var accent: SIMD4<Float> = .init(1, 1, 1, 1)

    init(pipeline: MTLRenderPipelineState,
         queue: MTLCommandQueue,
         startTime: CFTimeInterval) {
        self.pipeline = pipeline
        self.queue = queue
        self.startTime = startTime
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        resolution = SIMD2<Float>(Float(size.width), Float(size.height))
    }

    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let descriptor = view.currentRenderPassDescriptor,
              let buffer = queue.makeCommandBuffer(),
              let encoder = buffer.makeRenderCommandEncoder(descriptor: descriptor)
        else { return }

        var time = Float(CACurrentMediaTime() - startTime)
        var res = resolution
        var ac = accent

        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(&time,
                                 length: MemoryLayout<Float>.size,
                                 index: 0)
        encoder.setFragmentBytes(&res,
                                 length: MemoryLayout<SIMD2<Float>>.size,
                                 index: 1)
        encoder.setFragmentBytes(&ac,
                                 length: MemoryLayout<SIMD4<Float>>.size,
                                 index: 2)
        encoder.drawPrimitives(type: .triangle,
                               vertexStart: 0,
                               vertexCount: 3)
        encoder.endEncoding()
        buffer.present(drawable)
        buffer.commit()
    }
}
```

- [ ] **Step 2: Verify the build succeeds**

```bash
cd /Users/dan/playground/x-noise && swift build 2>&1 | tail -10
```
Expected: build succeeds.

- [ ] **Step 3: Commit**

```bash
cd /Users/dan/playground/x-noise && \
  git add Sources/Shuuchuu/Scenes/ShaderDrawDelegate.swift && \
  git commit -m "Scenes: add ShaderDrawDelegate that binds time/resolution/accent"
```

---

## Task 9: `SceneScrim` view

**Files:**
- Create: `Sources/Shuuchuu/UI/Components/SceneScrim.swift`

- [ ] **Step 1: Implement the scrim**

Create `Sources/Shuuchuu/UI/Components/SceneScrim.swift`:

```swift
import SwiftUI

/// Thin two-stop gradient overlay that keeps the popover UI legible against
/// busy shader backgrounds. Dark band at the top (under the FOCUS title) and
/// a heavier dark band at the bottom (under the mix list).
struct SceneScrim: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [.black.opacity(0.25), .clear],
                startPoint: .top,
                endPoint: UnitPoint(x: 0.5, y: 0.30)
            )
            LinearGradient(
                colors: [.clear, .black.opacity(0.45)],
                startPoint: UnitPoint(x: 0.5, y: 0.70),
                endPoint: .bottom
            )
        }
        .allowsHitTesting(false)
    }
}
```

- [ ] **Step 2: Build**

```bash
cd /Users/dan/playground/x-noise && swift build 2>&1 | tail -10
```
Expected: build succeeds.

- [ ] **Step 3: Commit**

```bash
cd /Users/dan/playground/x-noise && \
  git add Sources/Shuuchuu/UI/Components/SceneScrim.swift && \
  git commit -m "Scenes: add SceneScrim gradient overlay"
```

---

## Task 10: `SceneBackground` + `SceneHostView` with crossfade

**Files:**
- Create: `Sources/Shuuchuu/UI/Components/SceneBackground.swift`

- [ ] **Step 1: Implement host view + representable**

Create `Sources/Shuuchuu/UI/Components/SceneBackground.swift`:

```swift
import SwiftUI
import MetalKit
import simd

struct SceneBackground: NSViewRepresentable {
    @EnvironmentObject var scene: SceneController
    @EnvironmentObject var design: DesignSettings
    let renderer: ShaderRenderer

    func makeNSView(context: Context) -> SceneHostView {
        SceneHostView(renderer: renderer)
    }

    func updateNSView(_ view: SceneHostView, context: Context) {
        view.setAccent(accentVector(design.accent))
        if let active = scene.active {
            view.show(active: active)
        } else {
            view.clear()
        }
    }

    private func accentVector(_ color: Color) -> SIMD4<Float> {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? .white
        return SIMD4<Float>(Float(ns.redComponent),
                            Float(ns.greenComponent),
                            Float(ns.blueComponent),
                            Float(ns.alphaComponent))
    }
}

final class SceneHostView: NSView {
    private let renderer: ShaderRenderer
    private var frontView: MTKView?
    private var frontDelegate: ShaderDrawDelegate?
    private var currentId: String?

    init(renderer: ShaderRenderer) {
        self.renderer = renderer
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    // MARK: - Lifecycle

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // SwiftUI calls this when the popover opens (window != nil) and closes (nil).
        // Pause the render loop while the popover is dismissed so the GPU stays idle.
        let paused = (window == nil)
        frontView?.isPaused = paused
    }

    // MARK: - Show / clear

    func show(active: SceneController.Active) {
        guard active.id != currentId else { return }
        currentId = active.id

        let pipeline: MTLRenderPipelineState
        do {
            pipeline = try renderer.pipeline(for: active.id)
        } catch {
            print("[SceneHostView] pipeline build failed for \(active.id): \(error)")
            clear()
            return
        }

        let delegate = ShaderDrawDelegate(pipeline: pipeline,
                                          queue: renderer.queue,
                                          startTime: active.startTime)
        let mtk = MTKView(frame: bounds, device: renderer.device)
        mtk.colorPixelFormat = .bgra8Unorm
        mtk.framebufferOnly = true
        mtk.translatesAutoresizingMaskIntoConstraints = false
        mtk.wantsLayer = true
        mtk.layer?.opacity = 0
        mtk.delegate = delegate
        addSubview(mtk)
        NSLayoutConstraint.activate([
            mtk.topAnchor.constraint(equalTo: topAnchor),
            mtk.leadingAnchor.constraint(equalTo: leadingAnchor),
            mtk.trailingAnchor.constraint(equalTo: trailingAnchor),
            mtk.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        let oldView = frontView
        frontView = mtk
        frontDelegate = delegate

        crossfade(in: mtk, out: oldView)
    }

    func clear() {
        let oldId = currentId
        currentId = nil
        guard let oldView = frontView else { return }
        frontView = nil
        frontDelegate = nil
        crossfade(in: nil, out: oldView)
        _ = oldId
    }

    func setAccent(_ accent: SIMD4<Float>) {
        frontDelegate?.accent = accent
    }

    // MARK: - Crossfade

    private func crossfade(in newView: MTKView?, out oldView: NSView?) {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            newView?.animator().layer?.opacity = 1
            oldView?.animator().layer?.opacity = 0
        }, completionHandler: { [weak oldView] in
            oldView?.removeFromSuperview()
        })
    }
}
```

- [ ] **Step 2: Build**

```bash
cd /Users/dan/playground/x-noise && swift build 2>&1 | tail -10
```
Expected: build succeeds. (`SceneController` and `DesignSettings` env objects don't exist in this view's tree until Task 12 — but the build only typechecks, it doesn't validate environment wiring.)

- [ ] **Step 3: Commit**

```bash
cd /Users/dan/playground/x-noise && \
  git add Sources/Shuuchuu/UI/Components/SceneBackground.swift && \
  git commit -m "Scenes: add SceneBackground + SceneHostView with crossfade"
```

---

## Task 11: Wire scenes into `AppModel`

**Files:**
- Modify: `Sources/Shuuchuu/AppModel.swift`
- Modify: `Sources/Shuuchuu/ShuuchuuApp.swift`

- [ ] **Step 1: Read both files first**

```bash
cd /Users/dan/playground/x-noise && \
  awk '/^public final class AppModel|init\(/{flag=1} flag{print; if(/^}/) exit}' \
    Sources/Shuuchuu/AppModel.swift | head -80
```

This shows the AppModel constructor signature.

- [ ] **Step 2: Add stored properties to `AppModel`**

In `Sources/Shuuchuu/AppModel.swift`, find the property block (near the existing `let soundtracksLibrary: SoundtracksLibrary`) and add:

```swift
let scenes: ScenesLibrary
let shaderRenderer: ShaderRenderer
let scene: SceneController
```

In the `AppModel.init(...)` parameter list, add three matching parameters and store them:

```swift
public init(
    catalog: Catalog,
    state: MixState,
    mixer: MixingController,
    cache: AudioCache,
    focusSettings: FocusSettings,
    session: FocusSession,
    design: DesignSettings,
    favorites: Favorites,
    prefs: Preferences,
    savedMixes: SavedMixes,
    soundtracksLibrary: SoundtracksLibrary,
    soundtrackController: WebSoundtrackControlling,
    scenes: ScenesLibrary,
    shaderRenderer: ShaderRenderer,
    scene: SceneController
) {
    // ... existing assignments ...
    self.scenes = scenes
    self.shaderRenderer = shaderRenderer
    self.scene = scene
}
```

(Order matters only at call sites — pass new params last to minimize churn.)

- [ ] **Step 3: Wire construction in `AppModel.live(...)`**

In `Sources/Shuuchuu/ShuuchuuApp.swift`, locate the `extension AppModel { static func live(...) }` body and add three lines just before the `AppModel(...)` call:

```swift
let scenesLibrary = ScenesLibrary()
guard let shaderRenderer = ShaderRenderer() else {
    fatalError("ShaderRenderer init failed — no Metal device on this Mac")
}
let scene = SceneController(library: scenesLibrary,
                            renderer: shaderRenderer)
```

Then pass them to the existing `AppModel(...)` initializer:

```swift
let model = AppModel(
    catalog: catalog,
    state: state,
    mixer: mixer,
    cache: cache,
    focusSettings: focusSettings,
    session: session,
    design: design,
    favorites: favorites,
    prefs: prefs,
    savedMixes: savedMixes,
    soundtracksLibrary: soundtracksLibrary,
    soundtrackController: soundtrackController,
    scenes: scenesLibrary,
    shaderRenderer: shaderRenderer,
    scene: scene
)
```

`fatalError` here is acceptable: every macOS 26 supported Mac has a Metal device. If the project later targets a hardware tier without Metal, swap the `guard` for a feature-disable path.

- [ ] **Step 4: Build**

```bash
cd /Users/dan/playground/x-noise && swift build 2>&1 | tail -20
```
Expected: build succeeds.

- [ ] **Step 5: Run existing tests to ensure nothing regressed**

```bash
cd /Users/dan/playground/x-noise && swift test 2>&1 | tail -30
```
Expected: all existing tests still pass plus the new SceneTests, ScenesLibraryTests, SceneControllerTests.

- [ ] **Step 6: Commit**

```bash
cd /Users/dan/playground/x-noise && \
  git add Sources/Shuuchuu/AppModel.swift \
          Sources/Shuuchuu/ShuuchuuApp.swift && \
  git commit -m "Scenes: wire ScenesLibrary, ShaderRenderer, SceneController into AppModel"
```

---

## Task 12: Wire `SceneBackground` + `SceneScrim` into `PopoverView`

**Files:**
- Modify: `Sources/Shuuchuu/UI/PopoverView.swift`

- [ ] **Step 1: Read the current `PopoverView`**

```bash
cd /Users/dan/playground/x-noise && cat Sources/Shuuchuu/UI/PopoverView.swift
```

- [ ] **Step 2: Replace the body's ZStack to insert the new layers**

In `Sources/Shuuchuu/UI/PopoverView.swift`, modify the `body` to add `SceneBackground` and `SceneScrim` underneath the existing layers, and inject the new env objects:

```swift
import SwiftUI

struct PopoverView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var design: DesignSettings

    private let size = CGSize(width: 340, height: 540)

    var body: some View {
        ZStack {
            // SceneBackground draws first so Wallpaper sits on top of it.
            SceneBackground(renderer: model.shaderRenderer)
                .frame(width: size.width, height: size.height)

            Wallpaper(mode: design.wallpaper)
                .frame(width: size.width, height: size.height)

            SceneScrim()
                .frame(width: size.width, height: size.height)
                .opacity(model.scene.activeSceneId == nil ? 0 : 1)

            FocusPage()
                .frame(width: size.width, height: size.height)

            if model.page == .sounds {
                ZStack {
                    Wallpaper(mode: design.wallpaper)
                    SoundsPage()
                }
                .frame(width: size.width, height: size.height)
                .transition(.move(edge: .trailing))
                .zIndex(1)
            }

            if model.page == .settings {
                ZStack {
                    Wallpaper(mode: design.wallpaper)
                    SettingsPage()
                }
                .frame(width: size.width, height: size.height)
                .transition(.move(edge: .trailing))
                .zIndex(1)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .contentShape(Rectangle())
        .onHover { _ in }
        .focusEffectDisabled()
        .preferredColorScheme(.dark)
        .environmentObject(model.state)
        .environmentObject(model.session)
        .environmentObject(model.mixer)
        .environmentObject(model.focusSettings)
        .environmentObject(model.favorites)
        .environmentObject(model.savedMixes)
        .environmentObject(model.soundtracksLibrary)
        .environmentObject(model.scenes)
        .environmentObject(model.scene)
    }
}
```

The inserted lines:
- `SceneBackground(renderer: model.shaderRenderer)` as the first layer in the ZStack.
- `SceneScrim()` as the third layer, opacity-gated on `activeSceneId == nil`.
- `.environmentObject(model.scenes)` and `.environmentObject(model.scene)` at the bottom.

The Sounds and Settings overlays already render their own `Wallpaper`, which obscures the scene when those pages are active — that is the intended behavior (scene only shows under the Focus page).

- [ ] **Step 3: Build**

```bash
cd /Users/dan/playground/x-noise && swift build 2>&1 | tail -10
```
Expected: build succeeds.

- [ ] **Step 4: Smoke-launch the app**

```bash
cd /Users/dan/playground/x-noise && pkill -x Shuuchuu; swift run &
sleep 3
```
Expected: app launches, menubar icon appears, popover opens to Focus page with no visible change yet (active scene is nil → SceneBackground renders empty → Wallpaper shows through). Click around to verify nothing crashes. Then `pkill -x Shuuchuu`.

- [ ] **Step 5: Commit**

```bash
cd /Users/dan/playground/x-noise && \
  git add Sources/Shuuchuu/UI/PopoverView.swift && \
  git commit -m "Scenes: render SceneBackground + SceneScrim under FocusPage"
```

---

## Task 13: `ScenePicker` UI

**Files:**
- Create: `Sources/Shuuchuu/UI/Components/ScenePicker.swift`

- [ ] **Step 1: Implement the picker**

Create `Sources/Shuuchuu/UI/Components/ScenePicker.swift`:

```swift
import SwiftUI

struct ScenePicker: View {
    let scenes: [Scene]
    let activeId: String?
    let onSelect: (String?) -> Void

    private static let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Scenes")
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 14)
                .padding(.top, 14)

            if scenes.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVGrid(columns: Self.columns, spacing: 12) {
                        noneTile
                        ForEach(scenes) { scene in
                            sceneTile(scene)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 14)
                }
                .scrollIndicators(.never)
            }
        }
        .frame(width: 280, height: 360)
        .background(.regularMaterial)
    }

    private var noneTile: some View {
        Button { onSelect(nil) } label: {
            VStack(spacing: 4) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.black.opacity(0.4))
                    Image(systemName: "circle.slash")
                        .foregroundStyle(.white.opacity(0.5))
                }
                .frame(height: 75)
                .overlay(activeId == nil ? selectionRing : nil)
                Text("None")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }

    private func sceneTile(_ scene: Scene) -> some View {
        Button { onSelect(scene.id) } label: {
            VStack(spacing: 4) {
                thumbnail(scene)
                    .frame(height: 75)
                    .overlay(activeId == scene.id ? selectionRing : nil)
                Text(scene.title)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func thumbnail(_ scene: Scene) -> some View {
        if let img = thumbnailImage(scene) {
            Image(nsImage: img)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black.opacity(0.5))
        }
    }

    private func thumbnailImage(_ scene: Scene) -> NSImage? {
        // SPM `process` resources flatten paths; thumbnails live alongside .metal
        // files but appear at the bundle root. Look up by stem.
        let stem = (scene.thumbnail as NSString).deletingPathExtension
        guard let url = Bundle.module.url(forResource: stem,
                                          withExtension: "jpg") else {
            return nil
        }
        return NSImage(contentsOf: url)
    }

    private var selectionRing: some View {
        RoundedRectangle(cornerRadius: 8)
            .strokeBorder(Color.accentColor, lineWidth: 2)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Text("No scenes installed.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Text("Drop .metal files into\nSources/Shuuchuu/Resources/shaders/")
                .font(.system(size: 10))
                .multilineTextAlignment(.center)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(20)
    }
}
```

- [ ] **Step 2: Build**

```bash
cd /Users/dan/playground/x-noise && swift build 2>&1 | tail -10
```
Expected: build succeeds.

- [ ] **Step 3: Commit**

```bash
cd /Users/dan/playground/x-noise && \
  git add Sources/Shuuchuu/UI/Components/ScenePicker.swift && \
  git commit -m "Scenes: add ScenePicker grid view with None tile + empty state"
```

---

## Task 14: Add scene chip to `FocusPage` header

**Files:**
- Modify: `Sources/Shuuchuu/UI/Pages/FocusPage.swift`

- [ ] **Step 1: Read the current header**

```bash
cd /Users/dan/playground/x-noise && \
  sed -n '1,60p' Sources/Shuuchuu/UI/Pages/FocusPage.swift
```

- [ ] **Step 2: Add scene chip state and view**

At the top of the `FocusPage` struct (with the other `@State` declarations), add:

```swift
@State private var sceneChipHover = false
@State private var scenePickerPresented = false
```

In the existing `header` computed property, insert the scene chip immediately before the existing settings (gear) Button:

```swift
private var header: some View {
    HStack(alignment: .top, spacing: 10) {
        if settings.pomodoroEnabled {
            VStack(alignment: .leading, spacing: 0) {
                Text("FOCUS")
                    .font(.system(size: 12, weight: .semibold))
                    .kerning(0.72)
                    .xnText(.secondary)
                SessionDots(total: session.totalSessions, current: session.currentSession)
                    .padding(.top, 8)
            }
        }
        Spacer()
        sceneChip                                // NEW
        Button(action: { model.goTo(.settings) }) {
            Image(systemName: "gearshape")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(settingsHover ? Color.primary : Color.primary.opacity(0.45))
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .onHover { settingsHover = $0 }
    }
    .padding(.horizontal, 16)
    .padding(.top, 14)
}
```

Then add `sceneChip` as a private computed property near the existing `minimalIcon` helper:

```swift
private var sceneChip: some View {
    Button { scenePickerPresented = true } label: {
        Image(systemName: "paintbrush.pointed")
            .font(.system(size: 13, weight: .regular))
            .foregroundStyle(sceneChipHover ? Color.primary : Color.primary.opacity(0.45))
            .frame(width: 28, height: 28)
            .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .onHover { sceneChipHover = $0 }
    .help("Scene")
    .popover(isPresented: $scenePickerPresented, arrowEdge: .top) {
        ScenePicker(
            scenes: model.scenes.scenes,
            activeId: model.scene.activeSceneId,
            onSelect: { id in
                model.scene.setScene(id)
                scenePickerPresented = false
            }
        )
    }
}
```

- [ ] **Step 3: Build**

```bash
cd /Users/dan/playground/x-noise && swift build 2>&1 | tail -10
```
Expected: build succeeds.

- [ ] **Step 4: Smoke-launch — pick the plasma shader**

```bash
cd /Users/dan/playground/x-noise && pkill -x Shuuchuu; swift run &
sleep 3
```

Manually:
1. Click the menubar icon to open the popover.
2. Click the new paintbrush chip in the Focus header.
3. Click the "Plasma" tile.
4. Watch for the plasma shader fading in behind the timer over ~200 ms.
5. Click the chip again, click "None", watch it fade out.
6. Pick Plasma again, dismiss the popover, reopen — Plasma should still be active (persistence + `viewDidMoveToWindow` resumes the render loop).
7. `pkill -x Shuuchuu`.

If anything fails, look at console output for `[SceneController]` or `[SceneHostView]` log lines.

- [ ] **Step 5: Commit**

```bash
cd /Users/dan/playground/x-noise && \
  git add Sources/Shuuchuu/UI/Pages/FocusPage.swift && \
  git commit -m "FocusPage: add scene chip + ScenePicker popover"
```

---

## Task 15: Add the four remaining starter shaders

**Files:**
- Create: `Sources/Shuuchuu/Resources/shaders/aurora.metal`
- Create: `Sources/Shuuchuu/Resources/shaders/starfield.metal`
- Create: `Sources/Shuuchuu/Resources/shaders/soft-waves.metal`
- Create: `Sources/Shuuchuu/Resources/shaders/rainfall.metal`
- (Placeholder JPGs for each, replaced in Task 16)

Each `.metal` file is self-contained — only `<metal_stdlib>` is included.

- [ ] **Step 1: Write `aurora.metal`**

```metal
#include <metal_stdlib>
using namespace metal;

static float hash(float n) { return fract(sin(n) * 43758.5453); }

static float vnoise(float2 x) {
    float2 p = floor(x);
    float2 f = fract(x);
    f = f * f * (3.0 - 2.0 * f);
    float n = p.x + p.y * 57.0;
    return mix(mix(hash(n + 0.0),  hash(n + 1.0),  f.x),
               mix(hash(n + 57.0), hash(n + 58.0), f.x), f.y);
}

fragment float4 sceneMain(float4 pos             [[position]],
                          constant float  &time       [[buffer(0)]],
                          constant float2 &resolution [[buffer(1)]],
                          constant float4 &accent     [[buffer(2)]]) {
    float2 uv = pos.xy / resolution;
    float band = 0.0;
    for (int i = 0; i < 4; i++) {
        float fi = float(i);
        float yc = 0.30 + 0.18 * fi + 0.06 * sin(time * 0.25 + fi * 1.7);
        float n  = vnoise(float2(uv.x * 3.0 + time * 0.10 + fi,
                                 time * 0.05 + fi));
        float wave = exp(-pow((uv.y - yc) * 7.0, 2.0)) * (0.5 + 0.5 * n);
        band += wave * (0.7 - 0.1 * fi);
    }
    band = clamp(band, 0.0, 1.5);
    float3 base = mix(float3(0.02, 0.02, 0.06), accent.rgb, band);
    base += 0.02 * vnoise(uv * 200.0);   // sparse stars
    return float4(clamp(base, 0.0, 1.0), 1.0);
}
```

- [ ] **Step 2: Write `starfield.metal`**

```metal
#include <metal_stdlib>
using namespace metal;

static float hash21(float2 p) {
    p = fract(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

fragment float4 sceneMain(float4 pos             [[position]],
                          constant float  &time       [[buffer(0)]],
                          constant float2 &resolution [[buffer(1)]],
                          constant float4 &accent     [[buffer(2)]]) {
    float2 uv = pos.xy / resolution;
    float aspect = resolution.x / resolution.y;
    uv.x *= aspect;

    float3 col = float3(0.01, 0.01, 0.04);
    for (int layer = 0; layer < 3; layer++) {
        float fl = float(layer);
        float scale = 4.0 + fl * 6.0;
        float speed = 0.02 + fl * 0.04;
        float2 p = uv * scale;
        p.x += time * speed;
        float2 g = floor(p);
        float2 f = fract(p);
        float h = hash21(g);
        float r = (h < 0.985) ? 0.0 : 1.0;
        float d = length(f - 0.5);
        float star = r * smoothstep(0.10, 0.0, d);
        float twinkle = 0.6 + 0.4 * sin(time * 2.0 + h * 30.0);
        col += float3(0.7, 0.8, 1.0) * star * twinkle * (1.0 - 0.25 * fl);
    }
    col = mix(col, accent.rgb * 0.05, 0.4);
    return float4(col, 1.0);
}
```

- [ ] **Step 3: Write `soft-waves.metal`**

```metal
#include <metal_stdlib>
using namespace metal;

fragment float4 sceneMain(float4 pos             [[position]],
                          constant float  &time       [[buffer(0)]],
                          constant float2 &resolution [[buffer(1)]],
                          constant float4 &accent     [[buffer(2)]]) {
    float2 uv = pos.xy / resolution;
    float v = 0.0;
    for (int i = 0; i < 4; i++) {
        float fi = float(i);
        float k = 6.0 + fi * 2.5;
        v += sin(uv.x * k + time * (0.4 + fi * 0.15) + fi) / (1.0 + fi);
    }
    float band = exp(-pow((uv.y - 0.5 - 0.05 * v) * 6.0, 2.0));
    float3 base = mix(float3(0.02, 0.03, 0.07),
                      accent.rgb,
                      band);
    base += 0.05 * float3(0.2, 0.4, 1.0) * (1.0 - uv.y);
    return float4(clamp(base, 0.0, 1.0), 1.0);
}
```

- [ ] **Step 4: Write `rainfall.metal`**

```metal
#include <metal_stdlib>
using namespace metal;

static float hash11(float p) {
    p = fract(p * 0.1031);
    p *= p + 33.33;
    p *= p + p;
    return fract(p);
}

fragment float4 sceneMain(float4 pos             [[position]],
                          constant float  &time       [[buffer(0)]],
                          constant float2 &resolution [[buffer(1)]],
                          constant float4 &accent     [[buffer(2)]]) {
    float2 uv = pos.xy / resolution;
    float3 col = mix(float3(0.02, 0.03, 0.06),
                     float3(0.06, 0.07, 0.13),
                     uv.y);

    float strands = 80.0;
    for (int i = 0; i < 80; i++) {
        float fi = float(i);
        float lane = fi / strands;
        float seed = hash11(fi);
        float speed = 0.6 + 0.4 * seed;
        float xOff = lane + 0.04 * sin(time * 0.4 + fi);
        float yPos = fract(time * speed + seed) * 1.4 - 0.2;
        float2 c = float2(xOff, yPos);
        float dx = abs(uv.x - c.x);
        float dy = uv.y - c.y;
        float streak = exp(-dx * 600.0) * smoothstep(0.0, 0.12, dy) * smoothstep(0.20, 0.12, dy);
        col += float3(0.55, 0.65, 0.85) * streak * 0.6;
    }

    col = mix(col, accent.rgb * 0.7, 0.05);
    return float4(clamp(col, 0.0, 1.0), 1.0);
}
```

- [ ] **Step 5: Drop placeholder JPGs**

Same approach as Task 6 — any tiny JPG at each path. The real screenshots come in Task 16.

```bash
cd /Users/dan/playground/x-noise && \
  for n in aurora starfield soft-waves rainfall; do \
    python3 -c "from PIL import Image; Image.new('RGB',(260,148),(40,30,80)).save('Sources/Shuuchuu/Resources/shaders/$n.jpg', 'JPEG', quality=75)" \
      || cp Sources/Shuuchuu/Resources/shaders/plasma.jpg Sources/Shuuchuu/Resources/shaders/$n.jpg; \
  done
```

- [ ] **Step 6: Regenerate scenes.json**

```bash
cd /Users/dan/playground/x-noise && \
  python3 scripts/gen-scenes.py > Sources/Shuuchuu/Resources/scenes.json && \
  cat Sources/Shuuchuu/Resources/scenes.json
```
Expected: 5 entries (aurora, plasma, rainfall, soft-waves, starfield), kind:"shader".

- [ ] **Step 7: Build and smoke-test all five**

```bash
cd /Users/dan/playground/x-noise && pkill -x Shuuchuu; swift run &
sleep 3
```

Manually open the picker and click each shader in turn. Each should compile (~50–200 ms first time) and crossfade in. If any compile fails, the chip falls back to None and the console logs the error.

- [ ] **Step 8: Commit**

```bash
cd /Users/dan/playground/x-noise && \
  git add scripts/gen-scenes.py 2>/dev/null; \
  git commit --allow-empty -m "Scenes: add aurora/starfield/soft-waves/rainfall starter shaders"
```

(`--allow-empty` because the .metal/.jpg/.json files are gitignored — the commit captures only the `--allow-empty` marker plus any helper changes. Adjust message if anything tracked is also part of this task.)

---

## Task 16: Replace placeholder thumbnails with real screenshots

**Files:**
- Modify: `Sources/Shuuchuu/Resources/shaders/<id>.jpg` (×5, gitignored)

- [ ] **Step 1: Generate real thumbnails**

For each shader:

1. `pkill -x Shuuchuu; swift run &`
2. Open the popover, pick the shader.
3. Wait ~2 s for the animation to settle into a representative frame.
4. Take a screenshot of just the popover window: `Cmd-Shift-4` then `Space`, click the popover. The screenshot lands in `~/Desktop/`.
5. Crop to 16:9 and downscale to 260×148 with `sips`:

   ```bash
   sips -c 1080 1920 ~/Desktop/Screen\ Shot*.png --out /tmp/raw.png
   sips -z 148 260 -s format jpeg -s formatOptions 75 /tmp/raw.png \
        --out /Users/dan/playground/x-noise/Sources/Shuuchuu/Resources/shaders/<id>.jpg
   ```

   Adjust the `-c` first-pass crop to match the popover aspect (340×540 logical → 1.59:1 portrait, but thumbnails are 16:9 landscape — so crop a representative landscape strip from the middle of the screenshot).

6. Verify the file is < 30 KB:
   ```bash
   ls -lh /Users/dan/playground/x-noise/Sources/Shuuchuu/Resources/shaders/<id>.jpg
   ```

Repeat for `plasma`, `aurora`, `starfield`, `soft-waves`, `rainfall`.

- [ ] **Step 2: Re-launch and verify the picker**

```bash
cd /Users/dan/playground/x-noise && pkill -x Shuuchuu; swift run &
sleep 3
```

Open the picker. Each tile should now show a real preview of its shader. Selection ring should land on the active one. Picking each scene should crossfade in.

- [ ] **Step 3: Final end-to-end check**

Manual checklist:
- Pick None → SceneScrim disappears, Wallpaper visible.
- Pick a shader → SceneScrim opacity fades in, shader animates behind UI.
- Switch shaders → 200 ms crossfade.
- Dismiss popover (click elsewhere) → reopen → previous shader still active and animating from where it left off (start time preserved).
- Quit and relaunch (`pkill -x Shuuchuu; swift run`) → previously active shader auto-restores.
- Pick a shader, navigate to Sounds page (the chip is in Focus header so you can't open the picker from Sounds; that's intentional) → Sounds page covers the scene with its own Wallpaper. Navigate back to Focus → scene visible again.

- [ ] **Step 4: Final commit**

```bash
cd /Users/dan/playground/x-noise && \
  git commit --allow-empty -m "Scenes: ship v1 starter set with real thumbnails"
```

(All shader assets are gitignored. The empty commit marks the feature as shipped in the history.)

---

## Done

Five shader scenes wired into the Focus header chip, persisted across launches, never touching the audio engine, with crossfade transitions and pause-on-popover-dismiss. Image and video kinds remain in the spec's deferred list.

When you're ready to add image scenes:
1. Add `case image` to `SceneKind`.
2. Extend `gen-scenes.py` to recognize `.jpg`/`.heic`/`.png` source files (not thumbnails).
3. Extend `SceneController.Active` (or add a sibling type) to carry image data instead of a startTime.
4. Add an `ImageHostView` (or branch in `SceneHostView`) that sets `layer.contents = nsImage` instead of attaching an MTKView.
5. New tests for image kind paths in `SceneControllerTests`.

Video scenes follow the same shape with `AVQueuePlayer` + `AVPlayerLooper`.
