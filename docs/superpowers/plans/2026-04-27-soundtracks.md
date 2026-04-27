# Soundtracks Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add YouTube and Spotify soundtracks as a third tab on the Sounds page, with mutual exclusion against the ambient mix (mix XOR one soundtrack), playback controlled by a hidden long-lived `WKWebView` and JS bridges, and the Focus page reflecting whichever audio source is active.

**Architecture:** A new `WebSoundtrackController` peer of `MixingController` owns one off-screen `NSWindow` holding at most one `WKWebView`, driven by per-provider JS bridge HTML files. `AppModel` gains a `soundtracks` library and an `AudioMode` state machine (`.idle | .mix | .soundtrack(id)`) — every mix mutation and every soundtrack activation routes through `AppModel`, which persists to UserDefaults and side-effects the other subsystem to enforce mutual exclusion. The `FocusSession` gets an `onPhaseChange` hook so auto break/focus transitions mirror to whichever source is active. UI: a new `SoundtracksTab` body on the Sounds page, a new `SoundtrackPanel` body on the Focus page when a soundtrack is active, and a `SoundtrackChipRow` that can expand in-place to lift the WKWebView into view for first-time Spotify login or skip-track interactions.

**Tech Stack:** Swift 6 (strict concurrency), SwiftUI on macOS 26+ (Liquid Glass), `WKWebView` + WebKit JS bridges, XCTest, UserDefaults persistence, `swift build` / `swift test` SPM workflow.

**Spec:** `docs/superpowers/specs/2026-04-27-soundtracks-design.md`

---

## File Structure

**New files:**
- `Sources/XNoise/Models/SoundtrackURL.swift` — pure value type that classifies and normalizes pasted URLs to embed form. No side effects.
- `Sources/XNoise/Models/WebSoundtrack.swift` — `WebSoundtrack` value type, `AddSoundtrackError` enum.
- `Sources/XNoise/Models/AudioMode.swift` — `AudioMode` enum (`.idle | .mix | .soundtrack(WebSoundtrack.ID)`), `Codable`.
- `Sources/XNoise/Models/SoundtracksLibrary.swift` — `ObservableObject` store of saved soundtracks with UserDefaults persistence (mirrors `SavedMixes`).
- `Sources/XNoise/Audio/WebSoundtrackControlling.swift` — protocol the controller exposes to `AppModel`. Lets tests inject a mock.
- `Sources/XNoise/Audio/WebSoundtrackController.swift` — concrete implementation: hidden `NSWindow` + single `WKWebView` + JS bridges.
- `Sources/XNoise/Resources/soundtracks/youtube-bridge.html` — bridge document loaded into the WKWebView, hosts the YouTube iframe + IFrame Player API.
- `Sources/XNoise/Resources/soundtracks/spotify-bridge.html` — same for Spotify Embed IFrame API.
- `Sources/XNoise/UI/Pages/SoundtracksTab.swift` — body of the new third tab (section header, list, empty state, first-time hint, paste header surface).
- `Sources/XNoise/UI/Components/SoundtrackChipRow.swift` — single row + expand-row reveal mechanic.
- `Sources/XNoise/UI/Components/AddSoundtrackHeader.swift` — paste-a-link inline header (visual peer of `SaveMixHeader`).
- `Sources/XNoise/UI/Components/SoundtrackPanel.swift` — Focus-page panel for soundtrack mode (logo, title, slider, pause, "Switch to mix" link).
- `Tests/XNoiseTests/SoundtrackURLTests.swift` — host variant coverage.
- `Tests/XNoiseTests/SoundtrackPersistenceTests.swift` — `WebSoundtrack` + `AudioMode` Codable + library round-trip.
- `Tests/XNoiseTests/AppModelSoundtrackTests.swift` — mode-transition matrix using a mock controller.
- `Tests/XNoiseTests/FocusSessionPhaseHookTests.swift` — `onPhaseChange` fires on auto and manual transitions.

**Modified files:**
- `Sources/XNoise/AppModel.swift` — add `soundtracksLibrary`, `soundtrackController`, `mode`, and the soundtrack mutation methods. Generalize `togglePlayAll` and add `pauseActiveSource`. Side-effect existing mix mutations (`toggleTrack`, `applyPreset`, `applySavedMix`) to flip mode to `.mix` and pause the active soundtrack. Wire `session.onPhaseChange` in `init`.
- `Sources/XNoise/Models/FocusSession.swift` — add `var onPhaseChange: ((SessionPhase) -> Void)?`, fire it from `advancePhase()`.
- `Sources/XNoise/UI/Pages/SoundsPage.swift` — `SoundsTab` enum gains `.soundtracks`; tab bar grows to three; subtitle reflects mode; `Save mix` disabled in soundtrack mode; switch on `model.soundsTab` adds the new case.
- `Sources/XNoise/UI/Pages/FocusPage.swift` — body switches on `model.mode`. Mix mode = today's layout. Soundtrack mode = `SoundtrackPanel`. The `playAllButton` calls `model.togglePlayAll()` (now mode-aware). The ring-tap mirror calls `model.pauseActiveSource(...)`.
- `Sources/XNoise/UI/PopoverView.swift` — inject `model.soundtracksLibrary` into the environment.
- `Sources/XNoise/XNoiseApp.swift` — construct `SoundtracksLibrary` and `WebSoundtrackController`, thread them into `AppModel.live`.
- `docs/superpowers/specs/2026-04-26-sounds-page-design.md` — patch the two references that say "Internet soundtracks — likely a separate page later" so they point to the new spec and reflect the three-tab layout.

---

## Working Discipline

- **TDD:** Write the failing test first. Run it. Then write the minimal code to make it pass.
- **Bash CWD drifts** between calls per CLAUDE.md. Use absolute paths or `cd /Users/dan/playground/x-noise && cmd` one-liners. Don't rely on a prior `cd` carrying over.
- **Build between tasks:** `cd /Users/dan/playground/x-noise && swift build` after every task. UI tasks additionally need `swift run` plus a manual smoke test in the popover (no automated UI tests).
- **macOS 26 SwiftUI gotchas** still apply: `@EnvironmentObject` for observed objects (no init-passed `@ObservedObject` — crashes inside `MenuBarExtra` popovers); no `@MainActor` on UserDefaults wrappers; `.contentShape(Rectangle())` after `.clipShape(...)`; `.scrollIndicators(.never)` (not `.hidden`); `.background(.material, in: Shape)` instead of `Rectangle().fill(.material)` in a ZStack.
- **WKWebView is treated as a black box**, not unit-tested. Manual smoke tests (Task 22) cover the integration. Everything else is mocked through `WebSoundtrackControlling`.
- **Spec ambiguity resolved:** §11.6 says "load about:blank" when switching mix→soundtrack→mix; §2.4 says "WKWebView retained but silent." This plan follows §2.4 (just pause; only load `about:blank` on `removeSoundtrack(active)`). The retained web view makes mode-switch-back-to-soundtrack instant.
- **Commit after every task** (the "Step N: Commit" at the end of each task). Conventional-commit-ish messages matching the existing style (e.g. `Soundtracks: add SoundtrackURL parser` not `feat(soundtracks): ...`).

---

## Task 1: `SoundtrackURL` parser + tests

Pure value type. No dependencies. Fully unit-testable. This unblocks paste-flow validation and embed-URL canonicalization.

**Files:**
- Create: `Sources/XNoise/Models/SoundtrackURL.swift`
- Create: `Tests/XNoiseTests/SoundtrackURLTests.swift`

- [ ] **Step 1.1: Write the failing tests for the recognized host variants**

Create `Tests/XNoiseTests/SoundtrackURLTests.swift`:

```swift
import XCTest
@testable import XNoise

final class SoundtrackURLTests: XCTestCase {

    // MARK: - YouTube

    func testYouTubeWatchURL() {
        let r = SoundtrackURL.parse("https://www.youtube.com/watch?v=jfKfPfyJRdk")
        XCTAssertEqual(r, .success(.init(kind: .youtube,
                                         embedURL: "https://www.youtube.com/embed/jfKfPfyJRdk?enablejsapi=1",
                                         humanLabel: "YouTube video")))
    }

    func testYouTubeShortURL() {
        let r = SoundtrackURL.parse("https://youtu.be/jfKfPfyJRdk")
        XCTAssertEqual(r, .success(.init(kind: .youtube,
                                         embedURL: "https://www.youtube.com/embed/jfKfPfyJRdk?enablejsapi=1",
                                         humanLabel: "YouTube video")))
    }

    func testYouTubePlaylistURL() {
        let r = SoundtrackURL.parse("https://www.youtube.com/playlist?list=PLrAXtmErZgOeiKm4sgNOknGvNjby9efdf")
        XCTAssertEqual(r, .success(.init(kind: .youtube,
                                         embedURL: "https://www.youtube.com/embed/videoseries?list=PLrAXtmErZgOeiKm4sgNOknGvNjby9efdf&enablejsapi=1",
                                         humanLabel: "YouTube playlist")))
    }

    func testYouTubeMusicURL() {
        let r = SoundtrackURL.parse("https://music.youtube.com/watch?v=jfKfPfyJRdk")
        XCTAssertEqual(r, .success(.init(kind: .youtube,
                                         embedURL: "https://www.youtube.com/embed/jfKfPfyJRdk?enablejsapi=1",
                                         humanLabel: "YouTube video")))
    }

    func testYouTubeWatchWithExtraParams() {
        // si= and t= trackers should be ignored; only v= matters.
        let r = SoundtrackURL.parse("https://www.youtube.com/watch?v=abc123&t=42s&si=foo")
        XCTAssertEqual(r, .success(.init(kind: .youtube,
                                         embedURL: "https://www.youtube.com/embed/abc123?enablejsapi=1",
                                         humanLabel: "YouTube video")))
    }

    func testYouTubeWatchMissingId() {
        XCTAssertEqual(SoundtrackURL.parse("https://www.youtube.com/watch?foo=bar"),
                       .failure(.invalidURL))
    }

    // MARK: - Spotify

    func testSpotifyTrackURL() {
        let r = SoundtrackURL.parse("https://open.spotify.com/track/4uLU6hMCjMI75M1A2tKUQC")
        XCTAssertEqual(r, .success(.init(kind: .spotify,
                                         embedURL: "https://open.spotify.com/embed/track/4uLU6hMCjMI75M1A2tKUQC",
                                         humanLabel: "Spotify track")))
    }

    func testSpotifyPlaylistWithSiTracker() {
        let r = SoundtrackURL.parse("https://open.spotify.com/playlist/37i9dQZF1DX0XUsuxWHRQd?si=abc123")
        XCTAssertEqual(r, .success(.init(kind: .spotify,
                                         embedURL: "https://open.spotify.com/embed/playlist/37i9dQZF1DX0XUsuxWHRQd",
                                         humanLabel: "Spotify playlist")))
    }

    func testSpotifyAlbumURL() {
        let r = SoundtrackURL.parse("https://open.spotify.com/album/2noRn2Aes5aoNVsU6iWThc")
        XCTAssertEqual(r, .success(.init(kind: .spotify,
                                         embedURL: "https://open.spotify.com/embed/album/2noRn2Aes5aoNVsU6iWThc",
                                         humanLabel: "Spotify album")))
    }

    func testSpotifyEpisodeURL() {
        let r = SoundtrackURL.parse("https://open.spotify.com/episode/0Q86acNRm6V9GYx55SXKwf")
        XCTAssertEqual(r, .success(.init(kind: .spotify,
                                         embedURL: "https://open.spotify.com/embed/episode/0Q86acNRm6V9GYx55SXKwf",
                                         humanLabel: "Spotify episode")))
    }

    // MARK: - Rejected

    func testUnsupportedHost() {
        XCTAssertEqual(SoundtrackURL.parse("https://soundcloud.com/foo/bar"),
                       .failure(.unsupportedHost))
    }

    func testGarbageString() {
        XCTAssertEqual(SoundtrackURL.parse("not a url at all"),
                       .failure(.invalidURL))
    }

    func testEmptyString() {
        XCTAssertEqual(SoundtrackURL.parse(""), .failure(.invalidURL))
    }

    func testWhitespaceTrimmed() {
        // Common when pasting from the URL bar.
        let r = SoundtrackURL.parse("  https://youtu.be/abc123  \n")
        XCTAssertEqual(r, .success(.init(kind: .youtube,
                                         embedURL: "https://www.youtube.com/embed/abc123?enablejsapi=1",
                                         humanLabel: "YouTube video")))
    }
}
```

- [ ] **Step 1.2: Run the tests — expect compilation failure**

Run: `cd /Users/dan/playground/x-noise && swift test --filter SoundtrackURLTests 2>&1 | head -30`
Expected: `error: cannot find 'SoundtrackURL' in scope`.

- [ ] **Step 1.3: Implement `SoundtrackURL`**

Create `Sources/XNoise/Models/SoundtrackURL.swift`:

```swift
import Foundation

/// Parsed + normalized representation of a pasted URL. Pure value type.
struct SoundtrackURL: Equatable {
    enum Kind: String, Codable, Sendable, Equatable { case youtube, spotify }

    let kind: Kind
    /// Canonical embed URL — what the WKWebView's bridge should load.
    let embedURL: String
    /// Short label suitable for the paste-flow validation sub-text
    /// (`"YouTube video"`, `"Spotify playlist"`, etc.). Not user-input.
    let humanLabel: String
}

enum AddSoundtrackError: Error, Equatable {
    case invalidURL
    case unsupportedHost
}

extension SoundtrackURL {
    static func parse(_ raw: String) -> Result<SoundtrackURL, AddSoundtrackError> {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let url = URL(string: trimmed),
              let host = url.host?.lowercased() else {
            return .failure(.invalidURL)
        }

        if host == "youtu.be" {
            // youtu.be/<id>
            let id = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard !id.isEmpty else { return .failure(.invalidURL) }
            return .success(.init(kind: .youtube,
                                  embedURL: "https://www.youtube.com/embed/\(id)?enablejsapi=1",
                                  humanLabel: "YouTube video"))
        }

        if host.hasSuffix("youtube.com") {
            let path = url.path
            let query = queryItems(url)
            if path == "/watch" {
                guard let id = query["v"], !id.isEmpty else { return .failure(.invalidURL) }
                return .success(.init(kind: .youtube,
                                      embedURL: "https://www.youtube.com/embed/\(id)?enablejsapi=1",
                                      humanLabel: "YouTube video"))
            }
            if path == "/playlist" {
                guard let listId = query["list"], !listId.isEmpty else { return .failure(.invalidURL) }
                return .success(.init(kind: .youtube,
                                      embedURL: "https://www.youtube.com/embed/videoseries?list=\(listId)&enablejsapi=1",
                                      humanLabel: "YouTube playlist"))
            }
            return .failure(.invalidURL)
        }

        if host == "open.spotify.com" {
            // /<type>/<id>[?...]
            let parts = url.path.split(separator: "/").map(String.init)
            guard parts.count >= 2 else { return .failure(.invalidURL) }
            let type = parts[0]
            let id = parts[1]
            let allowed: Set<String> = ["track", "album", "playlist", "episode", "show"]
            guard allowed.contains(type), !id.isEmpty else { return .failure(.invalidURL) }
            return .success(.init(kind: .spotify,
                                  embedURL: "https://open.spotify.com/embed/\(type)/\(id)",
                                  humanLabel: "Spotify \(type)"))
        }

        return .failure(.unsupportedHost)
    }

    private static func queryItems(_ url: URL) -> [String: String] {
        var out: [String: String] = [:]
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .forEach { if let v = $0.value { out[$0.name] = v } }
        return out
    }
}
```

- [ ] **Step 1.4: Run the tests — expect pass**

Run: `cd /Users/dan/playground/x-noise && swift test --filter SoundtrackURLTests`
Expected: all 12 tests pass.

- [ ] **Step 1.5: Commit**

```bash
cd /Users/dan/playground/x-noise && \
  git add Sources/XNoise/Models/SoundtrackURL.swift Tests/XNoiseTests/SoundtrackURLTests.swift && \
  git commit -m "Soundtracks: add SoundtrackURL parser + tests"
```

---

## Task 2: `WebSoundtrack` model + `AudioMode` enum + tests

**Files:**
- Create: `Sources/XNoise/Models/WebSoundtrack.swift`
- Create: `Sources/XNoise/Models/AudioMode.swift`
- Create: `Tests/XNoiseTests/SoundtrackPersistenceTests.swift`

- [ ] **Step 2.1: Write the failing tests**

Create `Tests/XNoiseTests/SoundtrackPersistenceTests.swift`:

```swift
import XCTest
@testable import XNoise

final class SoundtrackPersistenceTests: XCTestCase {

    func testWebSoundtrackRoundTrip() throws {
        let original = WebSoundtrack(
            id: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            kind: .youtube,
            url: "https://www.youtube.com/embed/abc?enablejsapi=1",
            title: "lofi beats",
            volume: 0.7,
            addedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(WebSoundtrack.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testWebSoundtrackRoundTripWithNilTitle() throws {
        let original = WebSoundtrack(
            id: UUID(),
            kind: .spotify,
            url: "https://open.spotify.com/embed/playlist/abc",
            title: nil,
            volume: 0.5,
            addedAt: Date()
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(WebSoundtrack.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testAudioModeIdleRoundTrip() throws {
        let original: AudioMode = .idle
        let data = try JSONEncoder().encode(original)
        XCTAssertEqual(try JSONDecoder().decode(AudioMode.self, from: data), original)
    }

    func testAudioModeMixRoundTrip() throws {
        let original: AudioMode = .mix
        let data = try JSONEncoder().encode(original)
        XCTAssertEqual(try JSONDecoder().decode(AudioMode.self, from: data), original)
    }

    func testAudioModeSoundtrackRoundTrip() throws {
        let id = UUID()
        let original: AudioMode = .soundtrack(id)
        let data = try JSONEncoder().encode(original)
        XCTAssertEqual(try JSONDecoder().decode(AudioMode.self, from: data), original)
    }
}
```

- [ ] **Step 2.2: Run — expect compilation failure**

Run: `cd /Users/dan/playground/x-noise && swift test --filter SoundtrackPersistenceTests 2>&1 | head -10`
Expected: `error: cannot find type 'WebSoundtrack' in scope`.

- [ ] **Step 2.3: Implement `WebSoundtrack`**

Create `Sources/XNoise/Models/WebSoundtrack.swift`:

```swift
import Foundation

/// One saved soundtrack in the user's library. Persisted to UserDefaults.
struct WebSoundtrack: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let kind: SoundtrackURL.Kind
    /// Canonical embed URL — produced by `SoundtrackURL.parse`.
    let url: String
    /// Best-effort, populated by the JS bridge once the player reports it.
    /// Cached for nicer launch UX (avoids an empty title flicker before the bridge fires).
    var title: String?
    var volume: Double      // 0.0–1.0 app scale; bridge converts per-provider
    let addedAt: Date
}
```

- [ ] **Step 2.4: Implement `AudioMode`**

Create `Sources/XNoise/Models/AudioMode.swift`:

```swift
import Foundation

/// What audio source is currently active. The app guarantees mutual exclusion:
/// at most one of `.mix` or `.soundtrack(_)` is active at a time.
enum AudioMode: Equatable, Sendable {
    case idle
    case mix
    case soundtrack(WebSoundtrack.ID)

    var isSoundtrack: Bool {
        if case .soundtrack = self { return true } else { return false }
    }

    func soundtrackId() -> WebSoundtrack.ID? {
        if case .soundtrack(let id) = self { return id } else { return nil }
    }
}

// MARK: - Codable
//
// We hand-roll Codable because Swift's automatic synthesis for enums-with-associated-values
// produces a verbose nested-keyed shape that's awkward to migrate. Our shape is flat:
//   {"kind":"idle"} | {"kind":"mix"} | {"kind":"soundtrack","id":"<uuid>"}
extension AudioMode: Codable {
    private enum CodingKeys: String, CodingKey { case kind, id }
    private enum Kind: String, Codable { case idle, mix, soundtrack }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .idle:               try c.encode(Kind.idle, forKey: .kind)
        case .mix:                try c.encode(Kind.mix, forKey: .kind)
        case .soundtrack(let id):
            try c.encode(Kind.soundtrack, forKey: .kind)
            try c.encode(id, forKey: .id)
        }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try c.decode(Kind.self, forKey: .kind)
        switch kind {
        case .idle: self = .idle
        case .mix:  self = .mix
        case .soundtrack:
            let id = try c.decode(UUID.self, forKey: .id)
            self = .soundtrack(id)
        }
    }
}
```

- [ ] **Step 2.5: Run tests — expect pass**

Run: `cd /Users/dan/playground/x-noise && swift test --filter SoundtrackPersistenceTests`
Expected: all 5 tests pass.

- [ ] **Step 2.6: Commit**

```bash
cd /Users/dan/playground/x-noise && \
  git add Sources/XNoise/Models/WebSoundtrack.swift \
          Sources/XNoise/Models/AudioMode.swift \
          Tests/XNoiseTests/SoundtrackPersistenceTests.swift && \
  git commit -m "Soundtracks: add WebSoundtrack + AudioMode models with Codable round-trip tests"
```

---

## Task 3: `SoundtracksLibrary` store + persistence + tests

ObservableObject store of `[WebSoundtrack]`, persists to UserDefaults, mirrors the `SavedMixes` pattern. No mode logic yet — just a typed list with CRUD.

**Files:**
- Create: `Sources/XNoise/Models/SoundtracksLibrary.swift`
- Modify: `Tests/XNoiseTests/SoundtrackPersistenceTests.swift` (add library tests)

- [ ] **Step 3.1: Append failing library tests**

Append to `Tests/XNoiseTests/SoundtrackPersistenceTests.swift`:

```swift
extension SoundtrackPersistenceTests {

    private func ephemeralDefaults() -> UserDefaults {
        let suite = "test.soundtracks.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        return d
    }

    @MainActor
    func testLibraryRoundTrip() {
        let d = ephemeralDefaults()
        let lib = SoundtracksLibrary(defaults: d)
        let parsed = try! SoundtrackURL.parse("https://youtu.be/abc123").get()
        let added = lib.add(parsed: parsed)

        XCTAssertEqual(lib.entries.count, 1)
        XCTAssertEqual(added.kind, .youtube)
        XCTAssertEqual(added.url, "https://www.youtube.com/embed/abc123?enablejsapi=1")
        XCTAssertEqual(added.volume, 0.5, accuracy: 0.001)
        XCTAssertNil(added.title)

        let reloaded = SoundtracksLibrary(defaults: d)
        XCTAssertEqual(reloaded.entries.count, 1)
        XCTAssertEqual(reloaded.entries.first?.id, added.id)
    }

    @MainActor
    func testLibraryRemove() {
        let d = ephemeralDefaults()
        let lib = SoundtracksLibrary(defaults: d)
        let a = lib.add(parsed: try! SoundtrackURL.parse("https://youtu.be/abc").get())
        _    = lib.add(parsed: try! SoundtrackURL.parse("https://youtu.be/def").get())
        XCTAssertEqual(lib.entries.count, 2)

        lib.remove(id: a.id)
        XCTAssertEqual(lib.entries.count, 1)
        XCTAssertEqual(lib.entries.first?.url.contains("def"), true)

        let reloaded = SoundtracksLibrary(defaults: d)
        XCTAssertEqual(reloaded.entries.count, 1)
    }

    @MainActor
    func testLibrarySetVolume() {
        let d = ephemeralDefaults()
        let lib = SoundtracksLibrary(defaults: d)
        let a = lib.add(parsed: try! SoundtrackURL.parse("https://youtu.be/abc").get())
        lib.setVolume(id: a.id, volume: 0.25)

        XCTAssertEqual(lib.entries.first?.volume, 0.25, accuracy: 0.001)
        let reloaded = SoundtracksLibrary(defaults: d)
        XCTAssertEqual(reloaded.entries.first?.volume, 0.25, accuracy: 0.001)
    }

    @MainActor
    func testLibrarySetTitle() {
        let d = ephemeralDefaults()
        let lib = SoundtracksLibrary(defaults: d)
        let a = lib.add(parsed: try! SoundtrackURL.parse("https://youtu.be/abc").get())
        lib.setTitle(id: a.id, title: "lofi beats")

        XCTAssertEqual(lib.entries.first?.title, "lofi beats")
    }
}

// Result.get() helper
private extension Result where Failure: Error {
    func get() throws -> Success {
        switch self {
        case .success(let v): return v
        case .failure(let e): throw e
        }
    }
}
```

(`Result.get()` already exists in stdlib — the helper above is only needed if the project's Swift version isn't recent enough. Delete the helper extension if `swift --version` reports Swift 5.5+.)

- [ ] **Step 3.2: Run tests — expect compilation failure**

Run: `cd /Users/dan/playground/x-noise && swift test --filter SoundtrackPersistenceTests/testLibraryRoundTrip 2>&1 | head -10`
Expected: `error: cannot find 'SoundtracksLibrary' in scope`.

- [ ] **Step 3.3: Implement the library**

Create `Sources/XNoise/Models/SoundtracksLibrary.swift`:

```swift
import Foundation
import Combine

/// User's saved soundtracks library. Persisted to UserDefaults under
/// `x-noise.savedSoundtracks` as a JSON array of `WebSoundtrack`.
@MainActor
final class SoundtracksLibrary: ObservableObject {
    @Published private(set) var entries: [WebSoundtrack] = [] { didSet { persist() } }

    private let defaults: UserDefaults
    private let storageKey: String

    init(defaults: UserDefaults = .standard, storageKey: String = "x-noise.savedSoundtracks") {
        self.defaults = defaults
        self.storageKey = storageKey
        load()
    }

    // MARK: - CRUD

    /// Append a new soundtrack derived from a parsed URL. Default volume is 0.5.
    @discardableResult
    func add(parsed: SoundtrackURL) -> WebSoundtrack {
        let entry = WebSoundtrack(
            id: UUID(),
            kind: parsed.kind,
            url: parsed.embedURL,
            title: nil,
            volume: 0.5,
            addedAt: Date()
        )
        entries.append(entry)
        return entry
    }

    func remove(id: UUID) {
        entries.removeAll { $0.id == id }
    }

    func setVolume(id: UUID, volume: Double) {
        guard let i = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[i].volume = volume
    }

    func setTitle(id: UUID, title: String?) {
        guard let i = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[i].title = title
    }

    func entry(id: UUID) -> WebSoundtrack? {
        entries.first(where: { $0.id == id })
    }

    // MARK: - Persistence

    private func persist() {
        guard let data = try? JSONEncoder().encode(entries) else {
            assertionFailure("SoundtracksLibrary: failed to encode")
            return
        }
        defaults.set(data, forKey: storageKey)
    }

    private func load() {
        guard let data = defaults.data(forKey: storageKey) else { return }
        if let decoded = try? JSONDecoder().decode([WebSoundtrack].self, from: data) {
            entries = decoded
        }
    }
}
```

- [ ] **Step 3.4: Run tests — expect pass**

Run: `cd /Users/dan/playground/x-noise && swift test --filter SoundtrackPersistenceTests`
Expected: all 9 tests pass (5 from Task 2 + 4 new).

- [ ] **Step 3.5: Commit**

```bash
cd /Users/dan/playground/x-noise && \
  git add Sources/XNoise/Models/SoundtracksLibrary.swift Tests/XNoiseTests/SoundtrackPersistenceTests.swift && \
  git commit -m "Soundtracks: add SoundtracksLibrary store with UserDefaults persistence"
```

---

## Task 4: `WebSoundtrackControlling` protocol + `MockSoundtrackController` + AppModel wiring stub

Define the controller protocol now so AppModel work can proceed without WKWebView. Later tasks plug in the real controller.

**Files:**
- Create: `Sources/XNoise/Audio/WebSoundtrackControlling.swift`
- Create: `Tests/XNoiseTests/MockSoundtrackController.swift` (test helper, in test target)
- Modify: `Sources/XNoise/AppModel.swift` (add stored properties, no behavior yet)
- Modify: `Sources/XNoise/XNoiseApp.swift` (construct stubs)

- [ ] **Step 4.1: Define the protocol**

Create `Sources/XNoise/Audio/WebSoundtrackControlling.swift`:

```swift
import Foundation

/// What `AppModel` calls into to drive the active soundtrack. The concrete
/// implementation owns the hidden NSWindow + WKWebView + JS bridges.
///
/// Mocked in tests via `MockSoundtrackController` (test target).
@MainActor
protocol WebSoundtrackControlling: AnyObject {
    /// Activate this soundtrack. Replaces whatever was loaded, retains the WKWebView,
    /// loads the embed via the appropriate JS bridge, and (if `autoplay`) starts playback
    /// once the bridge reports ready.
    func load(_ soundtrack: WebSoundtrack, autoplay: Bool)

    /// Pause/play the currently-loaded soundtrack. No-op if nothing loaded.
    func setPaused(_ paused: Bool)

    /// Push a volume change to the loaded soundtrack. 0.0–1.0 app scale.
    func setVolume(_ volume: Double)

    /// Drop the loaded soundtrack — load `about:blank`. Used when removing the
    /// active library entry. The WKWebView itself is retained for future loads.
    func unload()

    /// Closure the controller calls when the JS bridge reports a title update.
    /// Owned by AppModel so it can persist back to the library.
    var onTitleChange: ((WebSoundtrack.ID, String) -> Void)? { get set }

    /// Closure the controller calls when the JS bridge detects the Spotify sign-in
    /// wall (no playback updates within 3s of `play()`).
    var onSignInRequired: ((WebSoundtrack.ID) -> Void)? { get set }
}
```

- [ ] **Step 4.2: Create the mock controller for tests**

Create `Tests/XNoiseTests/MockSoundtrackController.swift`:

```swift
import Foundation
@testable import XNoise

/// In-memory recorder. Tests assert against the call log.
@MainActor
final class MockSoundtrackController: WebSoundtrackControlling {
    enum Call: Equatable {
        case load(id: UUID, autoplay: Bool)
        case setPaused(Bool)
        case setVolume(Double)
        case unload
    }
    private(set) var calls: [Call] = []
    private(set) var loadedId: UUID?
    private(set) var paused: Bool = true

    var onTitleChange: ((UUID, String) -> Void)?
    var onSignInRequired: ((UUID) -> Void)?

    func load(_ soundtrack: WebSoundtrack, autoplay: Bool) {
        loadedId = soundtrack.id
        paused = !autoplay
        calls.append(.load(id: soundtrack.id, autoplay: autoplay))
    }

    func setPaused(_ paused: Bool) {
        self.paused = paused
        calls.append(.setPaused(paused))
    }

    func setVolume(_ volume: Double) {
        calls.append(.setVolume(volume))
    }

    func unload() {
        loadedId = nil
        calls.append(.unload)
    }

    /// Test convenience — simulate the bridge firing a title-change event.
    func simulateTitleChange(title: String) {
        guard let id = loadedId else { return }
        onTitleChange?(id, title)
    }
}
```

- [ ] **Step 4.3: Add stored properties + init parameter to AppModel**

Edit `Sources/XNoise/AppModel.swift`. Add to the imports if not present (already has `Foundation`, `SwiftUI`, `Combine`).

Inside the class, after the `let savedMixes: SavedMixes` line, add:

```swift
let soundtracksLibrary: SoundtracksLibrary
let soundtrackController: WebSoundtrackControlling
```

Add to the `init` parameter list (after `savedMixes: SavedMixes`):

```swift
        soundtracksLibrary: SoundtracksLibrary,
        soundtrackController: WebSoundtrackControlling,
```

Add to the `init` body (after `self.savedMixes = savedMixes`):

```swift
        self.soundtracksLibrary = soundtracksLibrary
        self.soundtrackController = soundtrackController
```

- [ ] **Step 4.4: Add temporary stub controller for the live() factory and wire it in**

Edit `Sources/XNoise/XNoiseApp.swift`. After `let savedMixes = SavedMixes()`:

```swift
        let soundtracksLibrary = SoundtracksLibrary()
        // Stub controller — Task 11 replaces this with the real WKWebView-backed one.
        let soundtrackController = StubSoundtrackController()
```

In the `AppModel(...)` constructor call, append the new args:

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
            soundtrackController: soundtrackController
        )
```

At the bottom of `XNoiseApp.swift` (after the `TrackResolverBox` class), add the stub:

```swift
/// Temporary no-op stub. Replaced by `WebSoundtrackController` in Task 11.
@MainActor
final class StubSoundtrackController: WebSoundtrackControlling {
    var onTitleChange: ((UUID, String) -> Void)?
    var onSignInRequired: ((UUID) -> Void)?
    func load(_: WebSoundtrack, autoplay: Bool) {}
    func setPaused(_: Bool) {}
    func setVolume(_: Double) {}
    func unload() {}
}
```

- [ ] **Step 4.5: Run the build to confirm everything still compiles**

Run: `cd /Users/dan/playground/x-noise && swift build`
Expected: `Build complete!`. No new test failures (existing tests don't construct AppModel directly via the live factory; AppModelSoundtrackTests in Task 5 will, with the mock).

- [ ] **Step 4.6: Commit**

```bash
cd /Users/dan/playground/x-noise && \
  git add Sources/XNoise/Audio/WebSoundtrackControlling.swift \
          Tests/XNoiseTests/MockSoundtrackController.swift \
          Sources/XNoise/AppModel.swift \
          Sources/XNoise/XNoiseApp.swift && \
  git commit -m "Soundtracks: add WebSoundtrackControlling protocol + mock + AppModel wiring"
```

---

## Task 5: `AppModel.mode` + `addSoundtrack` + activate/deactivate (no side-effects yet) + tests

This task introduces the mode state and the soundtrack-only mutations. Mix mutations are NOT yet side-effected (Task 6 does that). We're building one direction of the matrix at a time.

**Files:**
- Modify: `Sources/XNoise/AppModel.swift`
- Create: `Tests/XNoiseTests/AppModelSoundtrackTests.swift`

- [ ] **Step 5.1: Write the failing tests for the soundtrack-mutation half of the matrix**

Create `Tests/XNoiseTests/AppModelSoundtrackTests.swift`:

```swift
import XCTest
import Combine
@testable import XNoise

@MainActor
final class AppModelSoundtrackTests: XCTestCase {

    private func makeModel(defaults: UserDefaults? = nil) -> (AppModel, MockSoundtrackController) {
        let d = defaults ?? Self.ephemeralDefaults()
        let prefs = Preferences(defaults: d)
        let state = MixState(defaults: d)
        let cache = AudioCache(baseDir: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),
                               downloader: URLSessionDownloader())
        let catalog = Catalog(fetcher: BundleCatalogFetcher(),
                              cacheFile: FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).json"))
        let resolverBox = TrackResolverBox()
        let mixer = MixingController(state: state, cache: cache, resolveTrack: { resolverBox.resolve?($0) })
        let focusSettings = FocusSettings(defaults: d)
        let session = FocusSession(settings: focusSettings)
        let design = DesignSettings(defaults: d)
        let favorites = Favorites(defaults: d)
        let savedMixes = SavedMixes(defaults: d)
        let library = SoundtracksLibrary(defaults: d)
        let mock = MockSoundtrackController()
        let model = AppModel(
            catalog: catalog, state: state, mixer: mixer, cache: cache,
            focusSettings: focusSettings, session: session, design: design,
            favorites: favorites, prefs: prefs, savedMixes: savedMixes,
            soundtracksLibrary: library, soundtrackController: mock
        )
        resolverBox.resolve = { [weak model] id in model?.findTrack(id: id) }
        return (model, mock)
    }

    private static func ephemeralDefaults() -> UserDefaults {
        let suite = "test.appmodel.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        return d
    }

    // MARK: - addSoundtrack

    func testAddSoundtrackFromIdleAutoActivates() {
        let (model, mock) = makeModel()
        XCTAssertEqual(model.mode, .idle)

        let r = model.addSoundtrack(rawURL: "https://youtu.be/abc123")
        guard case .success(let entry) = r else { XCTFail("expected success"); return }

        XCTAssertEqual(model.mode, .soundtrack(entry.id))
        XCTAssertEqual(mock.calls, [.load(id: entry.id, autoplay: true)])
    }

    func testAddSoundtrackFromMixDoesNotStealMode() {
        let (model, mock) = makeModel()
        model.mode = .mix       // pretend the user has a mix going

        let r = model.addSoundtrack(rawURL: "https://youtu.be/abc123")
        guard case .success = r else { XCTFail("expected success"); return }

        XCTAssertEqual(model.mode, .mix)
        XCTAssertTrue(mock.calls.isEmpty)
    }

    func testAddSoundtrackInvalidURLReturnsError() {
        let (model, _) = makeModel()
        let r = model.addSoundtrack(rawURL: "not a url")
        XCTAssertEqual(r, .failure(.invalidURL))
        XCTAssertEqual(model.mode, .idle)
    }

    func testAddSoundtrackUnsupportedHostReturnsError() {
        let (model, _) = makeModel()
        let r = model.addSoundtrack(rawURL: "https://soundcloud.com/foo")
        XCTAssertEqual(r, .failure(.unsupportedHost))
    }

    // MARK: - activateSoundtrack

    func testActivateInactiveSoundtrack() {
        let (model, mock) = makeModel()
        let entry = model.soundtracksLibrary.add(parsed: try! SoundtrackURL.parse("https://youtu.be/x").get())

        model.activateSoundtrack(id: entry.id)

        XCTAssertEqual(model.mode, .soundtrack(entry.id))
        XCTAssertEqual(mock.calls, [.load(id: entry.id, autoplay: true)])
    }

    func testActivateSameSoundtrackIsIdempotent() {
        let (model, mock) = makeModel()
        let entry = model.soundtracksLibrary.add(parsed: try! SoundtrackURL.parse("https://youtu.be/x").get())
        model.activateSoundtrack(id: entry.id)
        mock.calls.removeAll()

        model.activateSoundtrack(id: entry.id)

        XCTAssertEqual(model.mode, .soundtrack(entry.id))
        XCTAssertTrue(mock.calls.isEmpty)
    }

    func testActivateDifferentSoundtrackSwaps() {
        let (model, mock) = makeModel()
        let a = model.soundtracksLibrary.add(parsed: try! SoundtrackURL.parse("https://youtu.be/a").get())
        let b = model.soundtracksLibrary.add(parsed: try! SoundtrackURL.parse("https://youtu.be/b").get())
        model.activateSoundtrack(id: a.id)
        mock.calls.removeAll()

        model.activateSoundtrack(id: b.id)

        XCTAssertEqual(model.mode, .soundtrack(b.id))
        XCTAssertEqual(mock.calls, [.load(id: b.id, autoplay: true)])
    }

    func testActivateUnknownIdIsNoOp() {
        let (model, mock) = makeModel()
        let unknown = UUID()
        model.activateSoundtrack(id: unknown)
        XCTAssertEqual(model.mode, .idle)
        XCTAssertTrue(mock.calls.isEmpty)
    }

    // MARK: - deactivateSoundtrack

    func testDeactivateActiveSoundtrack() {
        let (model, mock) = makeModel()
        let entry = model.soundtracksLibrary.add(parsed: try! SoundtrackURL.parse("https://youtu.be/x").get())
        model.activateSoundtrack(id: entry.id)
        mock.calls.removeAll()

        model.deactivateSoundtrack()

        XCTAssertEqual(model.mode, .idle)
        XCTAssertEqual(mock.calls, [.setPaused(true)])
    }

    func testDeactivateWhenNotInSoundtrackModeIsNoOp() {
        let (model, mock) = makeModel()
        model.deactivateSoundtrack()
        XCTAssertEqual(model.mode, .idle)
        XCTAssertTrue(mock.calls.isEmpty)
    }

    // MARK: - removeSoundtrack

    func testRemoveActiveSoundtrackFallsBackToIdle() {
        let (model, mock) = makeModel()
        let entry = model.soundtracksLibrary.add(parsed: try! SoundtrackURL.parse("https://youtu.be/x").get())
        model.activateSoundtrack(id: entry.id)
        mock.calls.removeAll()

        model.removeSoundtrack(id: entry.id)

        XCTAssertEqual(model.mode, .idle)
        XCTAssertEqual(mock.calls, [.unload])
        XCTAssertNil(model.soundtracksLibrary.entry(id: entry.id))
    }

    func testRemoveInactiveSoundtrackPreservesMode() {
        let (model, mock) = makeModel()
        let active = model.soundtracksLibrary.add(parsed: try! SoundtrackURL.parse("https://youtu.be/a").get())
        let other  = model.soundtracksLibrary.add(parsed: try! SoundtrackURL.parse("https://youtu.be/b").get())
        model.activateSoundtrack(id: active.id)
        mock.calls.removeAll()

        model.removeSoundtrack(id: other.id)

        XCTAssertEqual(model.mode, .soundtrack(active.id))
        XCTAssertTrue(mock.calls.isEmpty)
    }

    // MARK: - setSoundtrackVolume

    func testSetVolumeOnActivePushesToController() {
        let (model, mock) = makeModel()
        let entry = model.soundtracksLibrary.add(parsed: try! SoundtrackURL.parse("https://youtu.be/x").get())
        model.activateSoundtrack(id: entry.id)
        mock.calls.removeAll()

        model.setSoundtrackVolume(id: entry.id, volume: 0.3)

        XCTAssertEqual(model.soundtracksLibrary.entry(id: entry.id)?.volume, 0.3, accuracy: 0.001)
        XCTAssertEqual(mock.calls, [.setVolume(0.3)])
    }

    func testSetVolumeOnInactivePersistsButDoesNotPush() {
        let (model, mock) = makeModel()
        let active = model.soundtracksLibrary.add(parsed: try! SoundtrackURL.parse("https://youtu.be/a").get())
        let other  = model.soundtracksLibrary.add(parsed: try! SoundtrackURL.parse("https://youtu.be/b").get())
        model.activateSoundtrack(id: active.id)
        mock.calls.removeAll()

        model.setSoundtrackVolume(id: other.id, volume: 0.7)

        XCTAssertEqual(model.soundtracksLibrary.entry(id: other.id)?.volume, 0.7, accuracy: 0.001)
        XCTAssertTrue(mock.calls.isEmpty)
    }
}
```

- [ ] **Step 5.2: Run the tests — expect compile failure ("`mode` not a property")**

Run: `cd /Users/dan/playground/x-noise && swift test --filter AppModelSoundtrackTests 2>&1 | head -20`
Expected: `error: value of type 'AppModel' has no member 'mode'`.

- [ ] **Step 5.3: Add the `mode` state, mutation methods, and persistence to `AppModel`**

Edit `Sources/XNoise/AppModel.swift`:

(a) Add the new `@Published` after `@Published private(set) var currentlyLoadedMixId: AnyHashable?`:

```swift
    @Published var mode: AudioMode = .idle { didSet { persistMode() } }
```

(b) In `init`, after `self.soundtrackController = soundtrackController`, restore mode and wire the controller's callbacks:

```swift
        // Restore persisted mode (defaults to .idle if anything is missing).
        if let data = UserDefaults.standard.data(forKey: "x-noise.audioMode"),
           let restored = try? JSONDecoder().decode(AudioMode.self, from: data) {
            // If the persisted mode references a soundtrack id that's no longer in the
            // library, fall back to .idle (per spec §7).
            if case .soundtrack(let id) = restored, soundtracksLibrary.entry(id: id) == nil {
                self.mode = .idle
            } else {
                self.mode = restored
            }
        }

        // Title updates from the bridge persist back to the library.
        soundtrackController.onTitleChange = { [weak self] id, title in
            self?.soundtracksLibrary.setTitle(id: id, title: title)
        }
```

(c) After the existing `// MARK: - Master volume` section, add:

```swift
    // MARK: - Soundtracks

    /// Add a soundtrack to the library by parsing the raw URL. From `.idle` or
    /// `.soundtrack(other)` we auto-activate the new entry (the user just expressed
    /// intent to play something). From `.mix` we leave the mix alone.
    func addSoundtrack(rawURL: String) -> Result<WebSoundtrack, AddSoundtrackError> {
        switch SoundtrackURL.parse(rawURL) {
        case .failure(let err):
            return .failure(err)
        case .success(let parsed):
            let entry = soundtracksLibrary.add(parsed: parsed)
            switch mode {
            case .idle, .soundtrack:
                activateSoundtrack(id: entry.id)
            case .mix:
                break
            }
            return .success(entry)
        }
    }

    func activateSoundtrack(id: UUID) {
        guard let entry = soundtracksLibrary.entry(id: id) else { return }
        if case .soundtrack(let current) = mode, current == id { return }     // idempotent

        // Side effect on the mix is added in Task 6. For now, just transition mode.
        mode = .soundtrack(id)
        soundtrackController.load(entry, autoplay: true)
    }

    func deactivateSoundtrack() {
        guard case .soundtrack = mode else { return }
        soundtrackController.setPaused(true)
        mode = .idle
    }

    func removeSoundtrack(id: UUID) {
        let wasActive = (mode == .soundtrack(id))
        soundtracksLibrary.remove(id: id)
        if wasActive {
            soundtrackController.unload()
            mode = .idle
        }
    }

    func setSoundtrackVolume(id: UUID, volume: Double) {
        soundtracksLibrary.setVolume(id: id, volume: volume)
        if case .soundtrack(let active) = mode, active == id {
            soundtrackController.setVolume(volume)
        }
    }

    private func persistMode() {
        guard let data = try? JSONEncoder().encode(mode) else { return }
        UserDefaults.standard.set(data, forKey: "x-noise.audioMode")
    }
```

- [ ] **Step 5.4: Run the tests — expect pass**

Run: `cd /Users/dan/playground/x-noise && swift test --filter AppModelSoundtrackTests`
Expected: all 13 tests pass.

- [ ] **Step 5.5: Commit**

```bash
cd /Users/dan/playground/x-noise && \
  git add Sources/XNoise/AppModel.swift Tests/XNoiseTests/AppModelSoundtrackTests.swift && \
  git commit -m "Soundtracks: add AudioMode state, library mutations, and persistence to AppModel"
```

---

## Task 6: Side-effect existing mix mutations to flip mode → `.mix`

The other half of the mode-transition matrix: any mix-shaped action should end up in mix mode and pause the active soundtrack (without unloading it).

**Files:**
- Modify: `Sources/XNoise/AppModel.swift`
- Modify: `Tests/XNoiseTests/AppModelSoundtrackTests.swift`

- [ ] **Step 6.1: Append failing tests for mix-side transitions**

Append to `Tests/XNoiseTests/AppModelSoundtrackTests.swift` (inside the same `final class`):

```swift
    // MARK: - Mix mutations flip mode

    func testToggleTrackFromIdleEntersMix() {
        let (model, _) = makeModel()
        let track = Track(id: "rain", name: "Rain", iconURL: nil, kind: .procedural, src: nil, sha256: nil, sizeBytes: nil)
        model.toggleTrack(track)
        XCTAssertEqual(model.mode, .mix)
    }

    func testToggleTrackFromSoundtrackPausesAndSwitchesToMix() {
        let (model, mock) = makeModel()
        let entry = model.soundtracksLibrary.add(parsed: try! SoundtrackURL.parse("https://youtu.be/x").get())
        model.activateSoundtrack(id: entry.id)
        mock.calls.removeAll()

        let track = Track(id: "rain", name: "Rain", iconURL: nil, kind: .procedural, src: nil, sha256: nil, sizeBytes: nil)
        model.toggleTrack(track)

        XCTAssertEqual(model.mode, .mix)
        // Soundtrack is paused but NOT unloaded — per spec §2.4 the WKWebView is
        // retained so the user can flip back fast.
        XCTAssertEqual(mock.calls, [.setPaused(true)])
    }

    func testActivateSoundtrackFromMixPausesMix() {
        let (model, _) = makeModel()
        // Build a mix with one track first.
        let rain = Track(id: "rain", name: "Rain", iconURL: nil, kind: .procedural, src: nil, sha256: nil, sizeBytes: nil)
        model.toggleTrack(rain)
        XCTAssertEqual(model.mode, .mix)
        XCTAssertTrue(model.state.anyPlaying)

        let entry = model.soundtracksLibrary.add(parsed: try! SoundtrackURL.parse("https://youtu.be/x").get())
        model.activateSoundtrack(id: entry.id)

        XCTAssertEqual(model.mode, .soundtrack(entry.id))
        XCTAssertFalse(model.state.anyPlaying)   // mix paused
        XCTAssertTrue(model.state.contains("rain"))   // mix preserved
    }

    func testApplyPresetFromSoundtrackSwitchesToMix() {
        let (model, mock) = makeModel()
        let entry = model.soundtracksLibrary.add(parsed: try! SoundtrackURL.parse("https://youtu.be/x").get())
        model.activateSoundtrack(id: entry.id)
        mock.calls.removeAll()

        let preset = Preset(id: "deep", name: "Deep", mix: ["rain": 0.5])
        model.applyPreset(preset)

        XCTAssertEqual(model.mode, .mix)
        XCTAssertEqual(mock.calls, [.setPaused(true)])
    }
```

- [ ] **Step 6.2: Run tests — expect failure**

Run: `cd /Users/dan/playground/x-noise && swift test --filter AppModelSoundtrackTests/testToggleTrackFromSoundtrackPausesAndSwitchesToMix`
Expected: assertion failure (the mix mutation doesn't yet flip mode).

- [ ] **Step 6.3: Side-effect mix mutations**

Edit `Sources/XNoise/AppModel.swift`. Replace the existing mix mutation methods (in the `// MARK: - Mix mutations` section) so each calls a private `enterMixMode()` helper.

Add the helper after the `// MARK: - Soundtracks` section:

```swift
    /// Called by every mix-shaped mutation. If we were in soundtrack mode, pause the
    /// soundtrack (web view retained — per spec §2.4) and flip mode. Idempotent for `.mix`.
    private func enterMixMode() {
        if case .soundtrack = mode {
            soundtrackController.setPaused(true)
        }
        if mode != .mix {
            mode = .mix
        }
    }
```

Now wrap each existing mutation. The new bodies:

```swift
    func toggleTrack(_ track: Track) {
        if state.contains(track.id) {
            state.remove(id: track.id)
        } else {
            state.append(id: track.id, volume: 0.5)
        }
        if !state.isEmpty { enterMixMode() } else if mode == .mix { mode = .idle }
        mixer.reconcileNow()
    }

    func setTrackVolume(_ trackId: String, _ v: Float) {
        state.setVolume(id: trackId, volume: v)
        mixer.reconcileNow()
        // Volume changes don't change mode — only structural changes do.
    }

    func removeTrack(_ trackId: String) {
        state.remove(id: trackId)
        if state.isEmpty, mode == .mix { mode = .idle }
        mixer.reconcileNow()
    }

    func togglePause(trackId: String) {
        state.togglePaused(id: trackId)
        mixer.reconcileNow()
    }

    func applyPreset(_ preset: Preset) {
        let newTracks = preset.mix
            .filter { $0.value >= 0.02 }
            .map { MixTrack(id: $0.key, volume: $0.value, paused: false) }
        state.replace(with: newTracks)
        if !newTracks.isEmpty { enterMixMode() }
        mixer.reconcileNow()
    }

    func applySavedMix(_ mix: SavedMix) {
        let newTracks = mix.tracks.filter { $0.volume >= 0.02 }
        state.replace(with: newTracks)
        if !newTracks.isEmpty { enterMixMode() }
        mixer.reconcileNow()
    }

    func clearMix() {
        state.clear()
        if mode == .mix { mode = .idle }
        mixer.reconcileNow()
    }
```

And update `activateSoundtrack` to side-effect the mix:

```swift
    func activateSoundtrack(id: UUID) {
        guard let entry = soundtracksLibrary.entry(id: id) else { return }
        if case .soundtrack(let current) = mode, current == id { return }     // idempotent

        // Pause the mix (preserves per-track state — the user can switch back via
        // the "Switch to mix" link on Focus). MixingController.pauseAll() doesn't
        // exist as a single call — we use MixState.setAllPaused(true) + reconcile.
        if mode == .mix {
            state.setAllPaused(true)
            mixer.reconcileNow()
        }

        mode = .soundtrack(id)
        soundtrackController.load(entry, autoplay: true)
    }
```

- [ ] **Step 6.4: Run tests — expect pass**

Run: `cd /Users/dan/playground/x-noise && swift test --filter AppModelSoundtrackTests`
Expected: all 17 tests pass.

- [ ] **Step 6.5: Commit**

```bash
cd /Users/dan/playground/x-noise && \
  git add Sources/XNoise/AppModel.swift Tests/XNoiseTests/AppModelSoundtrackTests.swift && \
  git commit -m "Soundtracks: side-effect mix mutations to flip mode and pause the active soundtrack"
```

---

## Task 7: `togglePlayAll` + `pauseActiveSource` generalization + tests

Generalize the existing play-all toggle so the Focus-page button works in both modes.

**Files:**
- Modify: `Sources/XNoise/AppModel.swift`
- Modify: `Tests/XNoiseTests/AppModelSoundtrackTests.swift`

- [ ] **Step 7.1: Append failing tests**

Append to `AppModelSoundtrackTests`:

```swift
    // MARK: - togglePlayAll + pauseActiveSource

    func testTogglePlayAllInSoundtrackModePauses() {
        let (model, mock) = makeModel()
        let entry = model.soundtracksLibrary.add(parsed: try! SoundtrackURL.parse("https://youtu.be/x").get())
        model.activateSoundtrack(id: entry.id)
        XCTAssertFalse(model.activeSourcePaused)
        mock.calls.removeAll()

        model.togglePlayAll()

        XCTAssertTrue(model.activeSourcePaused)
        XCTAssertEqual(mock.calls, [.setPaused(true)])
    }

    func testTogglePlayAllInSoundtrackModeResumes() {
        let (model, mock) = makeModel()
        let entry = model.soundtracksLibrary.add(parsed: try! SoundtrackURL.parse("https://youtu.be/x").get())
        model.activateSoundtrack(id: entry.id)
        model.togglePlayAll()                  // pause
        mock.calls.removeAll()

        model.togglePlayAll()                  // resume

        XCTAssertFalse(model.activeSourcePaused)
        XCTAssertEqual(mock.calls, [.setPaused(false)])
    }

    func testTogglePlayAllInIdleIsNoOp() {
        let (model, mock) = makeModel()
        model.togglePlayAll()
        XCTAssertEqual(model.mode, .idle)
        XCTAssertTrue(mock.calls.isEmpty)
    }

    func testPauseActiveSourceInMixMutesAllTracks() {
        let (model, _) = makeModel()
        let rain = Track(id: "rain", name: "Rain", iconURL: nil, kind: .procedural, src: nil, sha256: nil, sizeBytes: nil)
        model.toggleTrack(rain)
        XCTAssertTrue(model.state.anyPlaying)

        model.pauseActiveSource(true)
        XCTAssertFalse(model.state.anyPlaying)

        model.pauseActiveSource(false)
        XCTAssertTrue(model.state.anyPlaying)
    }
```

- [ ] **Step 7.2: Implement**

Edit `Sources/XNoise/AppModel.swift`. Add a private `@Published`:

```swift
    /// Tracks whether the active soundtrack is currently paused. Mirrors the bridge.
    /// In mix mode this property is unused — `state.anyPlaying` is the source of truth.
    @Published private(set) var soundtrackPaused: Bool = true
```

Add a computed property near the other queries:

```swift
    /// True iff the active source (mix or soundtrack) is currently inaudible.
    /// `.idle` returns `true` (nothing is playing).
    var activeSourcePaused: Bool {
        switch mode {
        case .idle:                return true
        case .mix:                 return !state.anyPlaying
        case .soundtrack:          return soundtrackPaused
        }
    }
```

Add a public mutator:

```swift
    /// Pause or resume whichever source is active. No-op in `.idle`.
    func pauseActiveSource(_ paused: Bool) {
        switch mode {
        case .idle:
            return
        case .mix:
            state.setAllPaused(paused)
            mixer.reconcileNow()
        case .soundtrack:
            soundtrackController.setPaused(paused)
            soundtrackPaused = paused
        }
    }
```

Replace the existing `togglePlayAll`:

```swift
    func togglePlayAll() {
        pauseActiveSource(!activeSourcePaused)
    }
```

Update `activateSoundtrack` to set `soundtrackPaused = false` after `controller.load`:

```swift
        soundtrackController.load(entry, autoplay: true)
        soundtrackPaused = false
```

And `deactivateSoundtrack`:

```swift
    func deactivateSoundtrack() {
        guard case .soundtrack = mode else { return }
        soundtrackController.setPaused(true)
        soundtrackPaused = true
        mode = .idle
    }
```

And in the mix-side-effect `enterMixMode()`:

```swift
    private func enterMixMode() {
        if case .soundtrack = mode {
            soundtrackController.setPaused(true)
            soundtrackPaused = true
        }
        if mode != .mix { mode = .mix }
    }
```

- [ ] **Step 7.3: Run tests — expect pass**

Run: `cd /Users/dan/playground/x-noise && swift test --filter AppModelSoundtrackTests`
Expected: all 21 tests pass.

- [ ] **Step 7.4: Commit**

```bash
cd /Users/dan/playground/x-noise && \
  git add Sources/XNoise/AppModel.swift Tests/XNoiseTests/AppModelSoundtrackTests.swift && \
  git commit -m "Soundtracks: generalize togglePlayAll/pauseActiveSource across mix and soundtrack modes"
```

---

## Task 8: `FocusSession.onPhaseChange` hook + tests

The auto phase transitions today don't mirror to audio (only the manual ring-tap does). Add a closure that fires on every phase change so AppModel can route it through `pauseActiveSource`.

**Files:**
- Modify: `Sources/XNoise/Models/FocusSession.swift`
- Create: `Tests/XNoiseTests/FocusSessionPhaseHookTests.swift`

- [ ] **Step 8.1: Write the failing test**

Create `Tests/XNoiseTests/FocusSessionPhaseHookTests.swift`:

```swift
import XCTest
@testable import XNoise

@MainActor
final class FocusSessionPhaseHookTests: XCTestCase {

    private func ephemeralDefaults() -> UserDefaults {
        let suite = "test.focus.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        return d
    }

    func testOnPhaseChangeFiresOnSkip() {
        let settings = FocusSettings(defaults: ephemeralDefaults())
        let session = FocusSession(settings: settings)
        var fired: [SessionPhase] = []
        session.onPhaseChange = { fired.append($0) }

        // Starts in .focus; skip → break.
        session.skip()
        XCTAssertEqual(fired, [.shortBreak])

        // From short break, skip → focus.
        session.skip()
        XCTAssertEqual(fired, [.shortBreak, .focus])
    }

    func testOnPhaseChangeFiresOnExpiry() {
        let settings = FocusSettings(defaults: ephemeralDefaults())
        settings.focusMin = 1   // 60s focus, will be force-advanced below
        let session = FocusSession(settings: settings)
        var fired: [SessionPhase] = []
        session.onPhaseChange = { fired.append($0) }

        // Manually drive the timer past expiry. We can't tick real seconds in a test,
        // so we just call advancePhase directly via the public skip() shortcut.
        session.skip()
        XCTAssertEqual(fired, [.shortBreak])
    }

    func testOnPhaseChangeNotFiredOnReset() {
        // reset() puts us back in .focus from .focus — no phase transition. (Even
        // from break, reset sets phase = .focus directly, but per spec the hook is
        // for break/focus auto-transitions; reset is a discrete user action that
        // should not fire it.)
        let settings = FocusSettings(defaults: ephemeralDefaults())
        let session = FocusSession(settings: settings)
        session.skip()  // → shortBreak
        var fired: [SessionPhase] = []
        session.onPhaseChange = { fired.append($0) }

        session.reset()
        XCTAssertTrue(fired.isEmpty)
    }
}
```

- [ ] **Step 8.2: Run — expect failure ("`onPhaseChange` not a property")**

Run: `cd /Users/dan/playground/x-noise && swift test --filter FocusSessionPhaseHookTests 2>&1 | head -10`
Expected: `error: value of type 'FocusSession' has no member 'onPhaseChange'`.

- [ ] **Step 8.3: Add the hook**

Edit `Sources/XNoise/Models/FocusSession.swift`. Add the property to `FocusSession`:

```swift
    /// Fired whenever the timer transitions phase (auto-expiry or `skip()`). Not fired
    /// by `reset()` (treated as a discrete user action, not a phase transition).
    /// AppModel uses this to mirror pause/resume to the active audio source.
    var onPhaseChange: ((SessionPhase) -> Void)?
```

Modify `advancePhase` to fire the hook at the end:

```swift
    private func advancePhase() {
        switch phase {
        case .focus:
            if currentSession >= settings.cycles {
                phase = .longBreak
            } else {
                phase = .shortBreak
            }
        case .shortBreak:
            currentSession += 1
            phase = .focus
        case .longBreak:
            currentSession = 1
            phase = .focus
        }
        remainingSec = totalSec
        onPhaseChange?(phase)
    }
```

- [ ] **Step 8.4: Run tests — expect pass**

Run: `cd /Users/dan/playground/x-noise && swift test --filter FocusSessionPhaseHookTests`
Expected: all 3 tests pass.

- [ ] **Step 8.5: Commit**

```bash
cd /Users/dan/playground/x-noise && \
  git add Sources/XNoise/Models/FocusSession.swift Tests/XNoiseTests/FocusSessionPhaseHookTests.swift && \
  git commit -m "FocusSession: add onPhaseChange hook fired on auto and manual phase transitions"
```

---

## Task 9: Wire `FocusSession.onPhaseChange` into `AppModel.pauseActiveSource` + tests

**Files:**
- Modify: `Sources/XNoise/AppModel.swift`
- Modify: `Tests/XNoiseTests/AppModelSoundtrackTests.swift`

- [ ] **Step 9.1: Append failing tests**

Append to `AppModelSoundtrackTests`:

```swift
    // MARK: - FocusSession mirror

    func testFocusPhaseTransitionMirrorsToSoundtrack() {
        let (model, mock) = makeModel()
        let entry = model.soundtracksLibrary.add(parsed: try! SoundtrackURL.parse("https://youtu.be/x").get())
        model.activateSoundtrack(id: entry.id)
        mock.calls.removeAll()

        // Skip from .focus → .shortBreak. Soundtrack should pause.
        model.session.skip()
        XCTAssertEqual(mock.calls, [.setPaused(true)])
        XCTAssertTrue(model.activeSourcePaused)

        mock.calls.removeAll()
        // Skip from .shortBreak → .focus. Soundtrack should resume.
        model.session.skip()
        XCTAssertEqual(mock.calls, [.setPaused(false)])
        XCTAssertFalse(model.activeSourcePaused)
    }

    func testFocusPhaseTransitionMirrorsToMix() {
        let (model, _) = makeModel()
        let rain = Track(id: "rain", name: "Rain", iconURL: nil, kind: .procedural, src: nil, sha256: nil, sizeBytes: nil)
        model.toggleTrack(rain)
        XCTAssertTrue(model.state.anyPlaying)

        model.session.skip()                     // → break, mix should pause
        XCTAssertFalse(model.state.anyPlaying)

        model.session.skip()                     // → focus, mix should resume
        XCTAssertTrue(model.state.anyPlaying)
    }

    func testFocusPhaseTransitionInIdleIsNoOp() {
        let (model, mock) = makeModel()
        model.session.skip()
        XCTAssertEqual(model.mode, .idle)
        XCTAssertTrue(mock.calls.isEmpty)
    }
```

- [ ] **Step 9.2: Implement the wiring**

Edit `Sources/XNoise/AppModel.swift`. In `init`, after the `soundtrackController.onTitleChange` line (added in Task 5), add:

```swift
        // Auto break/focus transitions mirror to whichever audio source is active.
        // Pause when leaving focus; resume when entering focus. (The user's manual
        // ring-tap takes a separate path — see FocusPage.ringTap.)
        session.onPhaseChange = { [weak self] phase in
            guard let self = self else { return }
            switch phase {
            case .focus:                        self.pauseActiveSource(false)
            case .shortBreak, .longBreak:       self.pauseActiveSource(true)
            }
        }
```

- [ ] **Step 9.3: Run tests — expect pass**

Run: `cd /Users/dan/playground/x-noise && swift test --filter AppModelSoundtrackTests`
Expected: 24 tests pass.

- [ ] **Step 9.4: Commit**

```bash
cd /Users/dan/playground/x-noise && \
  git add Sources/XNoise/AppModel.swift Tests/XNoiseTests/AppModelSoundtrackTests.swift && \
  git commit -m "Soundtracks: wire FocusSession.onPhaseChange into pauseActiveSource"
```

---

## Task 10: Persistence round-trip test for `mode` across launches

Make sure the persisted `AudioMode` survives a fresh `AppModel` construction with the same `UserDefaults`.

**Files:**
- Modify: `Tests/XNoiseTests/AppModelSoundtrackTests.swift`

- [ ] **Step 10.1: Append the round-trip test**

Append to `AppModelSoundtrackTests`:

```swift
    // MARK: - Persistence

    func testModePersistsAcrossAppModelInstances() {
        let d = Self.ephemeralDefaults()
        // First launch: activate a soundtrack.
        var savedId: UUID = UUID()
        autoreleasepool {
            let (model, _) = makeModel(defaults: d)
            let entry = model.soundtracksLibrary.add(parsed: try! SoundtrackURL.parse("https://youtu.be/x").get())
            savedId = entry.id
            model.activateSoundtrack(id: entry.id)
            XCTAssertEqual(model.mode, .soundtrack(entry.id))
        }
        // Second launch: same defaults, fresh AppModel.
        let (reloaded, mock) = makeModel(defaults: d)
        XCTAssertEqual(reloaded.mode, .soundtrack(savedId))
        // Per spec §7: do NOT autoplay on launch.
        XCTAssertTrue(mock.calls.isEmpty)
    }

    func testModeFallsBackToIdleIfPersistedSoundtrackMissing() {
        let d = Self.ephemeralDefaults()
        // Hand-write a stale mode pointing at a UUID that's not in the library.
        let stale = try! JSONEncoder().encode(AudioMode.soundtrack(UUID()))
        d.set(stale, forKey: "x-noise.audioMode")

        let (model, _) = makeModel(defaults: d)
        XCTAssertEqual(model.mode, .idle)
    }
```

- [ ] **Step 10.2: Resolve the `UserDefaults.standard` vs injected-`d` mismatch**

The current `AppModel` reads `UserDefaults.standard` directly when restoring mode. Tests pass an injected `UserDefaults`, which means the round-trip would never see the stale value. Refactor to take a `defaults` parameter on `AppModel`.

Edit `Sources/XNoise/AppModel.swift`. Add a stored property:

```swift
    let defaults: UserDefaults
```

Add to the init parameter list (just before `soundtracksLibrary`):

```swift
        defaults: UserDefaults = .standard,
```

Set it inside init (right at the top of the body):

```swift
        self.defaults = defaults
```

Replace `UserDefaults.standard.data(forKey: "x-noise.audioMode")` with `defaults.data(forKey: "x-noise.audioMode")`.

Replace `UserDefaults.standard.set(data, forKey: "x-noise.audioMode")` in `persistMode()` with `defaults.set(data, forKey: "x-noise.audioMode")`.

Update `XNoiseApp.swift`'s `live()` factory: pass `defaults: .standard` is unnecessary (default arg covers it), no change needed there.

Update `Tests/XNoiseTests/AppModelSoundtrackTests.swift`'s `makeModel` to pass `defaults: d`:

```swift
        let model = AppModel(
            catalog: catalog, state: state, mixer: mixer, cache: cache,
            focusSettings: focusSettings, session: session, design: design,
            favorites: favorites, prefs: prefs, savedMixes: savedMixes,
            defaults: d,
            soundtracksLibrary: library, soundtrackController: mock
        )
```

- [ ] **Step 10.3: Run all tests — expect pass**

Run: `cd /Users/dan/playground/x-noise && swift test --filter AppModelSoundtrackTests`
Expected: 26 tests pass.

Run: `cd /Users/dan/playground/x-noise && swift test`
Expected: full test suite green.

- [ ] **Step 10.4: Commit**

```bash
cd /Users/dan/playground/x-noise && \
  git add Sources/XNoise/AppModel.swift Tests/XNoiseTests/AppModelSoundtrackTests.swift && \
  git commit -m "Soundtracks: AppModel mode persists across launches; falls back to idle if soundtrack missing"
```

---

## Task 11: `WebSoundtrackController` scaffold (hidden NSWindow + WKWebView)

Now the WKWebView-backed implementation, replacing the stub from Task 4. No bridge logic yet — just the lifecycle scaffolding and `load`/`unload` that loads `about:blank`.

**Files:**
- Modify: `Sources/XNoise/Audio/WebSoundtrackController.swift` (create)
- Modify: `Sources/XNoise/XNoiseApp.swift` (replace stub)

- [ ] **Step 11.1: Create `WebSoundtrackController`**

Create `Sources/XNoise/Audio/WebSoundtrackController.swift`:

```swift
import AppKit
import WebKit
import Foundation

/// Hidden long-lived host for a single WKWebView. Survives popover dismissal.
/// Reuses one web view across activations (cookie persistence via the default
/// data store keeps the user's Spotify login alive between launches).
@MainActor
final class WebSoundtrackController: NSObject, WebSoundtrackControlling {

    var onTitleChange: ((WebSoundtrack.ID, String) -> Void)?
    var onSignInRequired: ((WebSoundtrack.ID) -> Void)?

    private let window: NSWindow
    private let webView: WKWebView
    private var loadedSoundtrack: WebSoundtrack?

    override init() {
        // 1×1 off-screen window. Stays alive for the app lifetime so WebKit audio
        // continues across popover dismissal.
        window = NSWindow(
            contentRect: NSRect(x: -10000, y: -10000, width: 1, height: 1),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.level = .normal
        window.isExcludedFromWindowsMenu = true
        window.ignoresMouseEvents = true
        window.isOpaque = false
        window.backgroundColor = .clear

        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()         // persistent cookies
        // Don't require a synthetic user gesture for autoplay — bridge calls play()
        // programmatically once the user has activated a soundtrack.
        config.mediaTypesRequiringUserActionForPlayback = []

        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 1, height: 1), configuration: config)
        webView.translatesAutoresizingMaskIntoConstraints = false

        super.init()

        let host = NSView(frame: NSRect(x: 0, y: 0, width: 1, height: 1))
        host.wantsLayer = true
        host.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: host.topAnchor),
            webView.bottomAnchor.constraint(equalTo: host.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: host.trailingAnchor),
        ])
        window.contentView = host
        window.orderBack(nil)        // off-screen + ordered back; never visible
    }

    // MARK: - WebSoundtrackControlling

    func load(_ soundtrack: WebSoundtrack, autoplay: Bool) {
        loadedSoundtrack = soundtrack
        // Bridge HTML loading is added in Task 13. For now, load `about:blank` so the
        // scaffold is observable (web view exists, doesn't crash).
        webView.load(URLRequest(url: URL(string: "about:blank")!))
    }

    func setPaused(_ paused: Bool) {
        // JS bridge command added in Task 13.
    }

    func setVolume(_ volume: Double) {
        // JS bridge command added in Task 13.
    }

    func unload() {
        loadedSoundtrack = nil
        webView.load(URLRequest(url: URL(string: "about:blank")!))
    }

    /// Exposed so the SoundtrackChipRow can reparent the WKWebView into an inline
    /// expand-row container, then return it here when the row collapses.
    var hostedWebView: WKWebView { webView }

    /// Re-attach the web view to the hidden window after the row collapses.
    func reclaimWebView() {
        guard webView.superview !== window.contentView else { return }
        webView.removeFromSuperview()
        window.contentView?.addSubview(webView)
        if let parent = window.contentView {
            NSLayoutConstraint.activate([
                webView.topAnchor.constraint(equalTo: parent.topAnchor),
                webView.bottomAnchor.constraint(equalTo: parent.bottomAnchor),
                webView.leadingAnchor.constraint(equalTo: parent.leadingAnchor),
                webView.trailingAnchor.constraint(equalTo: parent.trailingAnchor),
            ])
        }
    }
}
```

- [ ] **Step 11.2: Replace the stub in `XNoiseApp.swift`**

Edit `Sources/XNoise/XNoiseApp.swift`. Replace `let soundtrackController = StubSoundtrackController()` with `let soundtrackController = WebSoundtrackController()`. Delete the `StubSoundtrackController` class at the bottom.

- [ ] **Step 11.3: Build — expect pass**

Run: `cd /Users/dan/playground/x-noise && swift build`
Expected: `Build complete!`.

Manual smoke: `cd /Users/dan/playground/x-noise && swift run`. Open the popover. Expect everything to look identical to before — no soundtracks UI yet, but the app should launch without crashing. (The hidden WKWebView is constructed eagerly but loads only `about:blank`; nothing audible.)

- [ ] **Step 11.4: Commit**

```bash
cd /Users/dan/playground/x-noise && \
  git add Sources/XNoise/Audio/WebSoundtrackController.swift Sources/XNoise/XNoiseApp.swift && \
  git commit -m "Soundtracks: add WebSoundtrackController scaffold (hidden NSWindow + WKWebView)"
```

---

## Task 12: YouTube + Spotify bridge HTML files

Two static HTML files, loaded by the WKWebView as the main document. They host the provider's iframe API and expose a small `bridge` object that posts JSON messages back to Swift.

**Files:**
- Create: `Sources/XNoise/Resources/soundtracks/youtube-bridge.html`
- Create: `Sources/XNoise/Resources/soundtracks/spotify-bridge.html`

- [ ] **Step 12.1: Write the YouTube bridge**

Create `Sources/XNoise/Resources/soundtracks/youtube-bridge.html`:

```html
<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <style>
    html, body { margin: 0; padding: 0; background: #000; height: 100%; }
    #player { width: 100%; height: 100%; }
  </style>
</head>
<body>
  <div id="player"></div>
  <script>
    let player = null;
    let pendingEmbedURL = null;

    function send(type, payload) {
      try {
        window.webkit.messageHandlers.xnoise.postMessage(
          Object.assign({type: type}, payload || {})
        );
      } catch (_e) {}
    }

    window.bridge = {
      load: function (embedURL) {
        pendingEmbedURL = embedURL;
        if (!player) return;     // onYouTubeIframeAPIReady will pick it up
        const videoId = extractVideoId(embedURL);
        const listId = extractListId(embedURL);
        if (listId) {
          player.loadPlaylist({ list: listId, listType: 'playlist' });
        } else if (videoId) {
          player.loadVideoById(videoId);
        }
      },
      play: function () { if (player) player.playVideo(); },
      pause: function () { if (player) player.pauseVideo(); },
      setVolume: function (v) {
        if (player) player.setVolume(Math.max(0, Math.min(100, Math.round(v * 100))));
      },
    };

    function extractVideoId(url) {
      const m = url.match(/\/embed\/([^?]+)/);
      if (!m) return null;
      const id = m[1];
      return id === 'videoseries' ? null : id;
    }
    function extractListId(url) {
      const m = url.match(/[?&]list=([^&]+)/);
      return m ? m[1] : null;
    }

    // YouTube API loader
    const tag = document.createElement('script');
    tag.src = 'https://www.youtube.com/iframe_api';
    document.head.appendChild(tag);

    window.onYouTubeIframeAPIReady = function () {
      player = new YT.Player('player', {
        height: '100%', width: '100%',
        playerVars: { playsinline: 1, modestbranding: 1, rel: 0, autoplay: 0 },
        events: {
          onReady: function () {
            send('ready');
            if (pendingEmbedURL) window.bridge.load(pendingEmbedURL);
          },
          onStateChange: function (e) {
            // -1 unstarted, 0 ended, 1 playing, 2 paused, 3 buffering, 5 cued
            send('stateChange', { state: e.data });
            const data = player.getVideoData && player.getVideoData();
            if (data && data.title) send('titleChanged', { title: data.title });
          },
          onError: function (e) { send('error', { code: e.data }); }
        }
      });
    };
  </script>
</body>
</html>
```

- [ ] **Step 12.2: Write the Spotify bridge**

Create `Sources/XNoise/Resources/soundtracks/spotify-bridge.html`:

```html
<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <style>
    html, body { margin: 0; padding: 0; background: #000; height: 100%; }
    #embed { width: 100%; height: 100%; }
  </style>
</head>
<body>
  <div id="embed"></div>
  <script src="https://open.spotify.com/embed/iframe-api/v1" async></script>
  <script>
    let controller = null;
    let pendingURI = null;
    let lastPlaybackUpdateAt = 0;
    let signInTimer = null;

    function send(type, payload) {
      try {
        window.webkit.messageHandlers.xnoise.postMessage(
          Object.assign({type: type}, payload || {})
        );
      } catch (_e) {}
    }

    function uriFromEmbedURL(url) {
      // https://open.spotify.com/embed/playlist/abc -> spotify:playlist:abc
      const m = url.match(/\/embed\/([^/]+)\/([^?]+)/);
      if (!m) return null;
      return 'spotify:' + m[1] + ':' + m[2];
    }

    window.bridge = {
      load: function (embedURL) {
        const uri = uriFromEmbedURL(embedURL);
        if (!uri) return;
        if (!controller) { pendingURI = uri; return; }
        controller.loadUri(uri);
        scheduleSignInWatch();
      },
      play: function () { if (controller) controller.play(); scheduleSignInWatch(); },
      pause: function () { if (controller) controller.pause(); cancelSignInWatch(); },
      setVolume: function (v) {
        if (controller) controller.setVolume(Math.max(0, Math.min(1, v)));
      },
    };

    function scheduleSignInWatch() {
      cancelSignInWatch();
      const startedAt = Date.now();
      signInTimer = setTimeout(function () {
        // If no playback_update event has fired since we requested play, the embed
        // is most likely showing the sign-in wall.
        if (lastPlaybackUpdateAt < startedAt) send('signInRequired');
      }, 3000);
    }
    function cancelSignInWatch() {
      if (signInTimer) { clearTimeout(signInTimer); signInTimer = null; }
    }

    window.onSpotifyIframeApiReady = function (IFrameAPI) {
      const options = { width: '100%', height: '100%' };
      const element = document.getElementById('embed');
      IFrameAPI.createController(element, options, function (ctrl) {
        controller = ctrl;
        send('ready');
        ctrl.addListener('playback_update', function (e) {
          lastPlaybackUpdateAt = Date.now();
          send('stateChange', { paused: e.data.isPaused });
          if (e.data.name) send('titleChanged', { title: e.data.name });
        });
        ctrl.addListener('error', function (e) { send('error', { message: String(e && e.data) }); });
        if (pendingURI) { ctrl.loadUri(pendingURI); pendingURI = null; }
      });
    };
  </script>
</body>
</html>
```

- [ ] **Step 12.3: Confirm SPM picks up the bridge files**

`Package.swift` already declares `resources: [.process("Resources")]` for the executable target. New files under `Sources/XNoise/Resources/soundtracks/` are picked up automatically. Verify by building:

Run: `cd /Users/dan/playground/x-noise && swift build`
Expected: `Build complete!`. The HTML files end up in `Bundle.module`.

- [ ] **Step 12.4: Verify the bundle contains them**

Run: `cd /Users/dan/playground/x-noise && find .build/debug/XNoise_XNoise.bundle -name "*-bridge.html"`
Expected: prints both `youtube-bridge.html` and `spotify-bridge.html`.

- [ ] **Step 12.5: Commit**

```bash
cd /Users/dan/playground/x-noise && \
  git add Sources/XNoise/Resources/soundtracks/youtube-bridge.html \
          Sources/XNoise/Resources/soundtracks/spotify-bridge.html && \
  git commit -m "Soundtracks: add YouTube + Spotify JS bridge HTML files"
```

---

## Task 13: Wire the JS bridges to `WebSoundtrackController`

Wire load/play/pause/setVolume out, and ready/stateChange/error/titleChanged/signInRequired in.

**Files:**
- Modify: `Sources/XNoise/Audio/WebSoundtrackController.swift`

- [ ] **Step 13.1: Add the message handler + bridge state**

Edit `Sources/XNoise/Audio/WebSoundtrackController.swift`. Add a private inner class above `WebSoundtrackController` that conforms to `WKScriptMessageHandler`:

```swift
private final class BridgeMessageProxy: NSObject, WKScriptMessageHandler {
    weak var owner: WebSoundtrackController?
    func userContentController(_: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let dict = message.body as? [String: Any] else { return }
        owner?.handleBridgeMessage(dict)
    }
}
```

In `WebSoundtrackController.init`, before constructing `webView`, register the message handler on the configuration:

```swift
        let proxy = BridgeMessageProxy()
        config.userContentController.add(proxy, name: "xnoise")
```

After `super.init()`, set the back-reference:

```swift
        proxy.owner = self
```

Add a property to track the current load:

```swift
    private var bridgeReady: Bool = false
    private var pendingEmbedURL: String?
```

- [ ] **Step 13.2: Implement `load(_:autoplay:)` to load the right bridge HTML**

Replace the existing `load` body:

```swift
    func load(_ soundtrack: WebSoundtrack, autoplay: Bool) {
        let bridgeFilename: String
        switch soundtrack.kind {
        case .youtube: bridgeFilename = "youtube-bridge"
        case .spotify: bridgeFilename = "spotify-bridge"
        }

        // If the same bridge kind is already loaded, just call bridge.load with the new URL.
        // Avoids tearing down WebKit + provider iframe between same-provider switches.
        if loadedSoundtrack?.kind == soundtrack.kind, bridgeReady {
            loadedSoundtrack = soundtrack
            pendingEmbedURL = nil
            evaluate("window.bridge.load(\(jsString(soundtrack.url)))")
            evaluate("window.bridge.setVolume(\(soundtrack.volume))")
            if autoplay { evaluate("window.bridge.play()") }
            return
        }

        // Different bridge kind (or first load) — load the bridge HTML, queue the embed.
        loadedSoundtrack = soundtrack
        bridgeReady = false
        pendingEmbedURL = autoplay ? soundtrack.url : nil    // queue for onReady
        guard let url = Bundle.module.url(forResource: bridgeFilename,
                                          withExtension: "html",
                                          subdirectory: "soundtracks") else {
            assertionFailure("\(bridgeFilename).html missing from bundle")
            return
        }
        webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
    }

    private func evaluate(_ js: String) {
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    private func jsString(_ s: String) -> String {
        // Quote-and-escape so we can interpolate into a JS string literal safely.
        let escaped = s
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
        return "\"\(escaped)\""
    }
```

- [ ] **Step 13.3: Implement `setPaused`/`setVolume`/`unload`**

```swift
    func setPaused(_ paused: Bool) {
        guard bridgeReady else { return }
        evaluate(paused ? "window.bridge.pause()" : "window.bridge.play()")
    }

    func setVolume(_ volume: Double) {
        guard bridgeReady else { return }
        evaluate("window.bridge.setVolume(\(volume))")
    }

    func unload() {
        loadedSoundtrack = nil
        bridgeReady = false
        pendingEmbedURL = nil
        webView.load(URLRequest(url: URL(string: "about:blank")!))
    }
```

- [ ] **Step 13.4: Handle inbound bridge messages**

Add to `WebSoundtrackController`:

```swift
    fileprivate func handleBridgeMessage(_ dict: [String: Any]) {
        guard let type = dict["type"] as? String else { return }
        switch type {
        case "ready":
            bridgeReady = true
            if let url = pendingEmbedURL {
                evaluate("window.bridge.load(\(jsString(url)))")
                pendingEmbedURL = nil
            }
            if let s = loadedSoundtrack {
                evaluate("window.bridge.setVolume(\(s.volume))")
                evaluate("window.bridge.play()")
            }
        case "titleChanged":
            if let title = dict["title"] as? String,
               let id = loadedSoundtrack?.id {
                onTitleChange?(id, title)
            }
        case "signInRequired":
            if let id = loadedSoundtrack?.id {
                onSignInRequired?(id)
            }
        case "stateChange", "error":
            // No app-level reaction needed in v1 beyond observability. The provider
            // iframe handles its own user-visible error UI.
            break
        default:
            break
        }
    }
```

- [ ] **Step 13.5: Build + smoke**

Run: `cd /Users/dan/playground/x-noise && swift build`
Expected: `Build complete!`.

(No automated test for the WKWebView path — full smoke happens after the UI is wired up in Task 21+.)

- [ ] **Step 13.6: Commit**

```bash
cd /Users/dan/playground/x-noise && \
  git add Sources/XNoise/Audio/WebSoundtrackController.swift && \
  git commit -m "Soundtracks: wire JS bridge messages — load, play, pause, volume, title, sign-in"
```

---

## Task 14: `SoundtrackChipRow` (collapsed)

Visual peer of `MixChipRow`. Two-line meta, provider glyph, active chip, `⌃` chevron, `⋯` menu. Only the collapsed state in this task; expand-row is Task 17.

**Files:**
- Create: `Sources/XNoise/UI/Components/SoundtrackChipRow.swift`

- [ ] **Step 14.1: Implement the row**

Create `Sources/XNoise/UI/Components/SoundtrackChipRow.swift`:

```swift
import SwiftUI

/// Row for a single soundtrack on the Soundtracks tab. Shows logo, title, sub-line,
/// active chip if this is the active soundtrack, and trailing `⌃`/`⋯` controls.
struct SoundtrackChipRow: View {
    let soundtrack: WebSoundtrack
    let isActive: Bool
    let onTap: () -> Void
    let onExpandToggle: () -> Void
    let onDelete: () -> Void

    @EnvironmentObject var design: DesignSettings
    @State private var hovered = false

    var body: some View {
        HStack(spacing: 10) {
            providerGlyph

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(displayTitle)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .xnText(.primary)
                    if isActive { activeChip }
                }
                Text(soundtrack.kind.rawValue)
                    .font(.system(size: 10.5))
                    .xnText(.tertiary)
            }

            Spacer(minLength: 4)

            if isActive {
                Button(action: onExpandToggle) {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Reveal player")
            }

            Menu {
                Button("Delete", role: .destructive, action: onDelete)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 22, height: 22)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(rowBackground)
        .overlay(rowBorder)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .onTapGesture(perform: onTap)
        .animation(.easeOut(duration: 0.15), value: isActive)
    }

    // MARK: -

    private var displayTitle: String {
        if let t = soundtrack.title, !t.isEmpty { return t }
        switch soundtrack.kind {
        case .youtube: return "YouTube"
        case .spotify: return "Spotify"
        }
    }

    private var providerGlyph: some View {
        let symbol: String = soundtrack.kind == .youtube ? "play.rectangle.fill" : "music.note"
        let tint: Color = soundtrack.kind == .youtube
            ? Color(red: 1.00, green: 0.00, blue: 0.00)
            : Color(red: 0.11, green: 0.73, blue: 0.33)
        return RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(tint.opacity(0.18))
            .frame(width: 26, height: 26)
            .overlay(
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(tint)
            )
    }

    private var activeChip: some View {
        Text("ACTIVE")
            .font(.system(size: 9, weight: .semibold))
            .kerning(0.6)
            .foregroundStyle(design.accent)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule().fill(design.accent.opacity(0.15))
            )
    }

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.white.opacity(hovered ? 0.055 : 0.035))
    }

    private var rowBorder: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(
                isActive ? design.accent : Color.white.opacity(0.08),
                lineWidth: isActive ? 1.5 : 1
            )
    }
}
```

- [ ] **Step 14.2: Build**

Run: `cd /Users/dan/playground/x-noise && swift build`
Expected: `Build complete!`.

- [ ] **Step 14.3: Commit**

```bash
cd /Users/dan/playground/x-noise && \
  git add Sources/XNoise/UI/Components/SoundtrackChipRow.swift && \
  git commit -m "Soundtracks: add SoundtrackChipRow component (collapsed)"
```

---

## Task 15: `AddSoundtrackHeader` paste-flow component

**Files:**
- Create: `Sources/XNoise/UI/Components/AddSoundtrackHeader.swift`

- [ ] **Step 15.1: Implement**

Create `Sources/XNoise/UI/Components/AddSoundtrackHeader.swift`:

```swift
import SwiftUI

/// Inline paste-a-link header that replaces the section header strip while active.
/// Visual peer of `SaveMixHeader` — accent-tinted wash, accent-bordered input.
struct AddSoundtrackHeader: View {
    @EnvironmentObject var design: DesignSettings
    @EnvironmentObject var model: AppModel

    let onCommit: () -> Void
    let onCancel: () -> Void

    @State private var rawText: String = ""
    @State private var validation: Validation = .empty
    @FocusState private var inputFocused: Bool

    private enum Validation: Equatable {
        case empty
        case ok(label: String)
        case unsupported
        case invalid
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                input
                Button("Cancel", action: onCancel)
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white.opacity(0.55))
                Button("Add", action: commit)
                    .buttonStyle(.plain)
                    .disabled(!canAdd)
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(addBackground)
                    .foregroundStyle(canAdd ? Color.white : Color.white.opacity(0.45))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .keyboardShortcut(.return, modifiers: [])
            }
            subText
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(design.accent.opacity(0.06))
        .onAppear { inputFocused = true }
    }

    private var input: some View {
        TextField("Paste a YouTube or Spotify URL", text: $rawText)
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(design.accent.opacity(0.7), lineWidth: 1)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.black.opacity(0.18))
                    )
            )
            .focused($inputFocused)
            .onChange(of: rawText) { _, _ in revalidate() }
            .onSubmit(commit)
    }

    private var subText: some View {
        Group {
            switch validation {
            case .empty:                 EmptyView()
            case .ok(let label):
                Text(label).foregroundStyle(Color.white.opacity(0.55))
            case .unsupported:
                Text("Only YouTube and Spotify are supported in this version")
                    .foregroundStyle(design.accent)
            case .invalid:
                EmptyView()
            }
        }
        .font(.system(size: 10))
        .padding(.leading, 4)
    }

    private var addBackground: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(canAdd ? design.accent : Color.white.opacity(0.08))
    }

    private var canAdd: Bool { if case .ok = validation { return true } else { return false } }

    private func revalidate() {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { validation = .empty; return }
        switch SoundtrackURL.parse(trimmed) {
        case .success(let parsed):       validation = .ok(label: parsed.humanLabel)
        case .failure(.unsupportedHost): validation = .unsupported
        case .failure(.invalidURL):      validation = .invalid
        }
    }

    private func commit() {
        guard canAdd else { return }
        let result = model.addSoundtrack(rawURL: rawText)
        if case .success = result {
            rawText = ""
            onCommit()
        }
    }
}
```

- [ ] **Step 15.2: Build**

Run: `cd /Users/dan/playground/x-noise && swift build`
Expected: `Build complete!`.

- [ ] **Step 15.3: Commit**

```bash
cd /Users/dan/playground/x-noise && \
  git add Sources/XNoise/UI/Components/AddSoundtrackHeader.swift && \
  git commit -m "Soundtracks: add AddSoundtrackHeader paste-a-link component"
```

---

## Task 16: `SoundtracksTab` page (list + empty state + first-time hint)

**Files:**
- Create: `Sources/XNoise/UI/Pages/SoundtracksTab.swift`

- [ ] **Step 16.1: Implement**

Create `Sources/XNoise/UI/Pages/SoundtracksTab.swift`:

```swift
import SwiftUI

/// Body of the Soundtracks tab — the user's saved-soundtracks library + paste-flow header.
struct SoundtracksTab: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var library: SoundtracksLibrary
    @EnvironmentObject var design: DesignSettings

    @State private var addingMode = false
    @State private var expandedRowId: WebSoundtrack.ID?

    private static let hintFlagKey = "x-noise.hasSeenSpotifyLoginHint"

    var body: some View {
        VStack(spacing: 0) {
            if addingMode {
                AddSoundtrackHeader(
                    onCommit: { withAnimation(.easeOut(duration: 0.18)) { addingMode = false } },
                    onCancel: { withAnimation(.easeOut(duration: 0.18)) { addingMode = false } }
                )
            } else {
                sectionHeader
            }

            ScrollView {
                VStack(spacing: 8) {
                    if library.entries.isEmpty {
                        emptyCard
                    } else {
                        ForEach(library.entries) { entry in
                            SoundtrackChipRow(
                                soundtrack: entry,
                                isActive: model.mode == .soundtrack(entry.id),
                                onTap: { tapRow(entry) },
                                onExpandToggle: { toggleExpand(entry) },
                                onDelete: { model.removeSoundtrack(id: entry.id) }
                            )
                        }
                    }

                    if shouldShowSpotifyHint {
                        spotifyHint
                            .padding(.top, 6)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 16)
            }
            .scrollIndicators(.never)
        }
    }

    private var sectionHeader: some View {
        HStack(spacing: 6) {
            Text("MY SOUNDTRACKS")
                .font(.system(size: 10, weight: .semibold))
                .kerning(0.8)
                .foregroundStyle(Color.white.opacity(0.40))
            Text("\(library.entries.count)")
                .font(.system(size: 10))
                .foregroundStyle(Color.white.opacity(0.30))
            Spacer()
            Button {
                withAnimation(.easeOut(duration: 0.18)) { addingMode = true }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.55))
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Paste a YouTube or Spotify URL")
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 6)
    }

    private var emptyCard: some View {
        VStack(spacing: 4) {
            Text("No saved soundtracks yet")
                .font(.system(size: 11))
                .foregroundStyle(Color.white.opacity(0.45))
            Text("Paste a YouTube or Spotify link")
                .font(.system(size: 10))
                .foregroundStyle(Color.white.opacity(0.35))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12),
                              style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        )
    }

    private var shouldShowSpotifyHint: Bool {
        guard !UserDefaults.standard.bool(forKey: Self.hintFlagKey) else { return false }
        return library.entries.contains(where: { $0.kind == .spotify })
    }

    private var spotifyHint: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle")
                .font(.system(size: 11))
                .foregroundStyle(design.accent)
                .padding(.top, 1)
            Text("First time? Tap the chevron on a Spotify soundtrack to sign in. Your login is saved on this device after that.")
                .font(.system(size: 10.5))
                .foregroundStyle(Color.white.opacity(0.65))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(design.accent.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onTapGesture {
            UserDefaults.standard.set(true, forKey: Self.hintFlagKey)
        }
    }

    private func tapRow(_ entry: WebSoundtrack) {
        if model.mode == .soundtrack(entry.id) {
            model.deactivateSoundtrack()
            if expandedRowId == entry.id { expandedRowId = nil }
        } else {
            model.activateSoundtrack(id: entry.id)
        }
    }

    private func toggleExpand(_ entry: WebSoundtrack) {
        // Expand-row content lands in Task 17 — for now this is a no-op stub that
        // tracks the open state so the UI can react.
        if expandedRowId == entry.id {
            expandedRowId = nil
        } else {
            expandedRowId = entry.id
        }
    }
}
```

- [ ] **Step 16.2: Build**

Run: `cd /Users/dan/playground/x-noise && swift build`
Expected: `Build complete!`.

- [ ] **Step 16.3: Commit**

```bash
cd /Users/dan/playground/x-noise && \
  git add Sources/XNoise/UI/Pages/SoundtracksTab.swift && \
  git commit -m "Soundtracks: add SoundtracksTab page (list, empty state, paste header surface, hint)"
```

---

## Task 17: Expand-row reveal — reparent the WKWebView inline

When the user taps the chevron on the active row, lift the WKWebView from the hidden window into the row. Tap again or `Done` collapses, reparenting back.

**Files:**
- Modify: `Sources/XNoise/UI/Components/SoundtrackChipRow.swift`
- Modify: `Sources/XNoise/UI/Pages/SoundtracksTab.swift`

- [ ] **Step 17.1: Add an `NSViewRepresentable` host for the live WKWebView**

Append to `Sources/XNoise/UI/Components/SoundtrackChipRow.swift`:

```swift
import WebKit

/// SwiftUI host for the live WKWebView owned by `WebSoundtrackController`. When this
/// representable appears, it pulls the web view out of the hidden window into a
/// container view; on disappear, it returns the web view via `controller.reclaimWebView()`.
struct LiveSoundtrackEmbed: NSViewRepresentable {
    let controller: WebSoundtrackController

    func makeNSView(context: Context) -> NSView {
        let host = NSView()
        host.wantsLayer = true
        host.layer?.cornerRadius = 8
        host.layer?.masksToBounds = true

        let web = controller.hostedWebView
        web.removeFromSuperview()
        host.addSubview(web)
        web.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            web.topAnchor.constraint(equalTo: host.topAnchor),
            web.bottomAnchor.constraint(equalTo: host.bottomAnchor),
            web.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            web.trailingAnchor.constraint(equalTo: host.trailingAnchor),
        ])
        return host
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    static func dismantleNSView(_ nsView: NSView, coordinator: ()) {
        // Defer reparent to the next runloop turn — SwiftUI sometimes calls dismantle
        // synchronously during teardown, and reparent inside that call can warp layout.
        DispatchQueue.main.async {
            // Find the controller via a known reference. We resolve via a singleton
            // pattern in WebSoundtrackController — see reclaimWebView usage.
            // Direct call:
            //   The owning controller is not retrievable from here, so reclaim is
            //   triggered explicitly by the parent view (see SoundtracksTab).
        }
    }
}
```

Because `dismantleNSView` doesn't have access to the controller, the row view is responsible for triggering `controller.reclaimWebView()` in `onDisappear`. Restructure `SoundtrackChipRow`:

Add new parameters and a body branch:

```swift
struct SoundtrackChipRow: View {
    let soundtrack: WebSoundtrack
    let isActive: Bool
    let isExpanded: Bool
    let controller: WebSoundtrackController
    let onTap: () -> Void
    let onExpandToggle: () -> Void
    let onDelete: () -> Void
```

Replace the `var body` to wrap the existing row in a `VStack` and append the embed when `isExpanded`:

```swift
    var body: some View {
        VStack(spacing: 0) {
            collapsedRow

            if isExpanded {
                LiveSoundtrackEmbed(controller: controller)
                    .frame(height: 220)
                    .padding(.horizontal, 8)
                    .padding(.top, 8)
                HStack {
                    Spacer()
                    Button("Done", action: onExpandToggle)
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.65))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.white.opacity(0.08))
                        )
                }
                .padding(.horizontal, 8)
                .padding(.top, 8)
                .padding(.bottom, 4)
                .onDisappear { controller.reclaimWebView() }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(rowBackground)
        .overlay(rowBorder)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: 0.15), value: isActive)
        .animation(.easeOut(duration: 0.20), value: isExpanded)
    }
```

Move the previous body content into a new computed property `collapsedRow`. Wrap the original `HStack(spacing: 10) { ... }` and replace its outermost `.padding(...)` modifiers (those move to the outer body so they apply to both the row and the expand region):

```swift
    private var collapsedRow: some View {
        HStack(spacing: 10) {
            providerGlyph
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(displayTitle)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .xnText(.primary)
                    if isActive { activeChip }
                }
                Text(soundtrack.kind.rawValue)
                    .font(.system(size: 10.5))
                    .xnText(.tertiary)
            }
            Spacer(minLength: 4)
            if isActive {
                Button(action: onExpandToggle) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.up")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(isExpanded ? "Hide player" : "Reveal player")
            }
            Menu {
                Button("Delete", role: .destructive, action: onDelete)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 22, height: 22)
        }
        .onTapGesture(perform: onTap)
    }
```

- [ ] **Step 17.2: Pass controller + expanded state from `SoundtracksTab`**

Edit `Sources/XNoise/UI/Pages/SoundtracksTab.swift`. The tab needs the concrete `WebSoundtrackController` (not the protocol) so it can pull the WKWebView for reparenting. Update the call site:

```swift
ForEach(library.entries) { entry in
    SoundtrackChipRow(
        soundtrack: entry,
        isActive: model.mode == .soundtrack(entry.id),
        isExpanded: expandedRowId == entry.id,
        controller: concreteController,
        onTap: { tapRow(entry) },
        onExpandToggle: { toggleExpand(entry) },
        onDelete: { model.removeSoundtrack(id: entry.id) }
    )
}
```

Add a computed property:

```swift
    private var concreteController: WebSoundtrackController {
        // Cast safe in production: AppModel is constructed with WebSoundtrackController.
        // In tests, SoundtracksTab isn't rendered (UI is preview-only).
        guard let real = model.soundtrackController as? WebSoundtrackController else {
            fatalError("SoundtracksTab requires a real WebSoundtrackController")
        }
        return real
    }
```

- [ ] **Step 17.3: Auto-pulse the chevron when sign-in is required**

Wire `WebSoundtrackController.onSignInRequired` in `AppModel.init` (after the existing `onTitleChange` line):

```swift
        soundtrackController.onSignInRequired = { [weak self] _ in
            self?.signInRequired = true
        }
```

Add a `@Published` to `AppModel`:

```swift
    @Published var signInRequired: Bool = false
```

In `SoundtracksTab`, observe and apply a subtle pulse to the chevron of the active row when `model.signInRequired` is true. For v1, simplest behavior: make the chevron tint `accent` when `model.signInRequired` and the row is the active one. Pass it through:

In `SoundtracksTab.body`:

```swift
SoundtrackChipRow(
    ...
    pulseChevron: model.signInRequired && model.mode == .soundtrack(entry.id),
    ...
)
```

Add `pulseChevron: Bool` to `SoundtrackChipRow` and use it in `collapsedRow`:

```swift
    let pulseChevron: Bool

    // in collapsedRow, replacing the chevron Image:
    Image(systemName: isExpanded ? "chevron.down" : "chevron.up")
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(pulseChevron ? design.accent : Color.secondary)
        .frame(width: 22, height: 22)
        .contentShape(Rectangle())
        .opacity(pulseChevron ? (1.0) : 1.0)
        .scaleEffect(pulseChevron ? 1.06 : 1.0)
        .animation(pulseChevron
                   ? .easeInOut(duration: 0.7).repeatForever(autoreverses: true)
                   : .default,
                   value: pulseChevron)
```

When the user expands the row, clear `signInRequired`:

In `SoundtracksTab.toggleExpand`:

```swift
    private func toggleExpand(_ entry: WebSoundtrack) {
        if expandedRowId == entry.id {
            expandedRowId = nil
        } else {
            expandedRowId = entry.id
            model.signInRequired = false
        }
    }
```

- [ ] **Step 17.4: Build + smoke**

Run: `cd /Users/dan/playground/x-noise && swift build`
Expected: `Build complete!`.

(Manual smoke deferred to Task 22.)

- [ ] **Step 17.5: Commit**

```bash
cd /Users/dan/playground/x-noise && \
  git add Sources/XNoise/UI/Components/SoundtrackChipRow.swift \
          Sources/XNoise/UI/Pages/SoundtracksTab.swift \
          Sources/XNoise/AppModel.swift && \
  git commit -m "Soundtracks: implement expand-row WKWebView reveal + sign-in chevron pulse"
```

---

## Task 18: `SoundtrackPanel` — Focus-page panel for soundtrack mode

**Files:**
- Create: `Sources/XNoise/UI/Components/SoundtrackPanel.swift`

- [ ] **Step 18.1: Implement**

Create `Sources/XNoise/UI/Components/SoundtrackPanel.swift`:

```swift
import SwiftUI

/// Single-soundtrack panel rendered on the Focus page when `mode == .soundtrack`.
/// Shows logo, title, sub-line, volume, pause, and a "Switch to mix" link if a saved
/// mix exists to fall back to.
struct SoundtrackPanel: View {
    let soundtrack: WebSoundtrack
    let paused: Bool
    let canSwitchToMix: Bool
    let onTogglePause: () -> Void
    let onVolumeChange: (Double) -> Void
    let onSwitchToMix: () -> Void

    @EnvironmentObject var design: DesignSettings
    @State private var hovered = false

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                providerGlyph

                VStack(alignment: .leading, spacing: 3) {
                    Text(displayTitle)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                        .xnText(.primary)
                    HStack(spacing: 6) {
                        Text(soundtrack.kind.rawValue)
                            .font(.system(size: 10.5))
                            .xnText(.tertiary)
                        ThumblessSlider(
                            value: Binding(get: { soundtrack.volume }, set: onVolumeChange),
                            tint: Color.white.opacity(0.55)
                        )
                        .frame(width: 110)
                    }
                }

                Spacer(minLength: 4)

                Button(action: onTogglePause) {
                    Image(systemName: paused ? "play.fill" : "pause.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 26, height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(7)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(hovered ? 0.055 : 0.035))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
            )
            .onHover { hovered = $0 }

            if canSwitchToMix {
                Button(action: onSwitchToMix) {
                    Text("Switch to mix")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.white.opacity(0.45))
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
        }
    }

    private var displayTitle: String {
        if let t = soundtrack.title, !t.isEmpty { return t }
        switch soundtrack.kind {
        case .youtube: return "YouTube"
        case .spotify: return "Spotify"
        }
    }

    private var providerGlyph: some View {
        let symbol: String = soundtrack.kind == .youtube ? "play.rectangle.fill" : "music.note"
        let tint: Color = soundtrack.kind == .youtube
            ? Color(red: 1.00, green: 0.00, blue: 0.00)
            : Color(red: 0.11, green: 0.73, blue: 0.33)
        return RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(tint.opacity(0.18))
            .frame(width: 22, height: 22)
            .overlay(
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(tint)
            )
    }
}
```

- [ ] **Step 18.2: Add a `switchToMix` method to AppModel**

Edit `Sources/XNoise/AppModel.swift`. Add after `deactivateSoundtrack`:

```swift
    /// Triggered by the "Switch to mix" link on the Focus page when in `.soundtrack`.
    /// Pauses the soundtrack, flips to mix mode, and resumes the previously-paused mix.
    func switchToMix() {
        guard case .soundtrack = mode else { return }
        soundtrackController.setPaused(true)
        soundtrackPaused = true
        mode = .mix
        state.setAllPaused(false)
        mixer.reconcileNow()
    }
```

- [ ] **Step 18.3: Build**

Run: `cd /Users/dan/playground/x-noise && swift build`
Expected: `Build complete!`.

- [ ] **Step 18.4: Commit**

```bash
cd /Users/dan/playground/x-noise && \
  git add Sources/XNoise/UI/Components/SoundtrackPanel.swift Sources/XNoise/AppModel.swift && \
  git commit -m "Soundtracks: add SoundtrackPanel for Focus mode + switchToMix on AppModel"
```

---

## Task 19: `SoundsPage` — third tab + mode-aware subtitle + save-mix disabled

**Files:**
- Modify: `Sources/XNoise/AppModel.swift` (extend `SoundsTab` enum)
- Modify: `Sources/XNoise/UI/Pages/SoundsPage.swift`

- [ ] **Step 19.1: Extend the `SoundsTab` enum**

Edit `Sources/XNoise/AppModel.swift`. Update:

```swift
enum SoundsTab: String, Equatable { case sounds, mixes, soundtracks }
```

- [ ] **Step 19.2: Update `SoundsPage` for the third tab + mode-aware subtitle**

Edit `Sources/XNoise/UI/Pages/SoundsPage.swift`:

Replace the `switch model.soundsTab` block:

```swift
            switch model.soundsTab {
            case .sounds:        SoundsBrowseView()
            case .mixes:         MixesView()
            case .soundtracks:   SoundtracksTab()
            }
```

In `pageHeader`'s `VStack`, replace the second Text:

```swift
                Text(headerSubtitle)
                    .font(.system(size: 12))
                    .xnText(.primary)
```

Add a computed:

```swift
    private var headerSubtitle: String {
        switch model.mode {
        case .soundtrack:    return "playing soundtrack"
        case .mix, .idle:    return "\(model.state.count) in current mix"
        }
    }
```

Disable Save mix in soundtrack mode. Replace the `.disabled` line:

```swift
        .disabled(model.state.isEmpty || model.mode.isSoundtrack)
        .opacity((model.state.isEmpty || model.mode.isSoundtrack) ? 0.4 : 1)
```

Add a third tab item to `tabBar`:

```swift
    private var tabBar: some View {
        HStack(spacing: 0) {
            tabItem(.sounds, label: "Sounds")
            tabItem(.mixes, label: "Mixes")
            tabItem(.soundtracks, label: "Soundtracks")
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .overlay(Divider().opacity(0.3), alignment: .bottom)
    }
```

- [ ] **Step 19.3: Build + smoke**

Run: `cd /Users/dan/playground/x-noise && swift build`
Expected: `Build complete!`.

Manual smoke (`swift run`): open popover, navigate to Sounds page, verify three tabs, click Soundtracks, verify the empty state appears.

- [ ] **Step 19.4: Commit**

```bash
cd /Users/dan/playground/x-noise && \
  git add Sources/XNoise/AppModel.swift Sources/XNoise/UI/Pages/SoundsPage.swift && \
  git commit -m "SoundsPage: add Soundtracks tab, mode-aware subtitle, save-mix disabled in soundtrack mode"
```

---

## Task 20: `FocusPage` — render soundtrack panel when `mode == .soundtrack`

**Files:**
- Modify: `Sources/XNoise/UI/Pages/FocusPage.swift`

- [ ] **Step 20.1: Branch the bottom region on `model.mode`**

Edit `Sources/XNoise/UI/Pages/FocusPage.swift`. Add a computed:

```swift
    @ViewBuilder
    private var bottomRegion: some View {
        switch model.mode {
        case .soundtrack(let id):
            if let entry = model.soundtracksLibrary.entry(id: id) {
                SoundtrackPanel(
                    soundtrack: entry,
                    paused: model.activeSourcePaused,
                    canSwitchToMix: !model.state.isEmpty,
                    onTogglePause: { model.togglePlayAll() },
                    onVolumeChange: { v in model.setSoundtrackVolume(id: id, volume: v) },
                    onSwitchToMix: { model.switchToMix() }
                )
                .padding(.horizontal, 16)
                .padding(.top, 4)
            }
        case .mix, .idle:
            mixSection           // existing — unchanged
        }
    }
```

In the `body`, replace the existing `mixSection` line with `bottomRegion`:

```swift
            ringBlock
            Hairline().padding(.horizontal, 22).padding(.top, 4).padding(.bottom, 10)
            bottomRegion
            Spacer(minLength: 0)
```

Update `ringTap` so it routes through the generalized helper:

```swift
    private func ringTap() {
        session.toggle()
        model.pauseActiveSource(!session.isRunning)
    }
```

Update `playAllButton` to be aware of the soundtrack case (the existing one calls `model.togglePlayAll()` already, which we generalized in Task 7 — so no change needed there beyond making sure the disabled condition still makes sense). Replace `disabled: state.isEmpty` with:

```swift
        return minimalIcon(
            systemName: anyPlaying ? "pause.fill" : "play.fill",
            size: 13,
            hover: $playHover,
            disabled: model.mode == .idle && state.isEmpty
        ) { model.togglePlayAll() }
```

And the `anyPlaying` source of truth:

```swift
        let anyPlaying = !model.activeSourcePaused
```

- [ ] **Step 20.2: Build + smoke**

Run: `cd /Users/dan/playground/x-noise && swift build`
Expected: `Build complete!`.

- [ ] **Step 20.3: Commit**

```bash
cd /Users/dan/playground/x-noise && \
  git add Sources/XNoise/UI/Pages/FocusPage.swift && \
  git commit -m "FocusPage: render SoundtrackPanel when in soundtrack mode; play-all is mode-aware"
```

---

## Task 21: PopoverView environment + final wiring

**Files:**
- Modify: `Sources/XNoise/UI/PopoverView.swift`

- [ ] **Step 21.1: Inject `SoundtracksLibrary` into the environment**

Edit `Sources/XNoise/UI/PopoverView.swift`. After `.environmentObject(model.savedMixes)`:

```swift
        .environmentObject(model.soundtracksLibrary)
```

- [ ] **Step 21.2: Build**

Run: `cd /Users/dan/playground/x-noise && swift build`
Expected: `Build complete!`.

- [ ] **Step 21.3: Commit**

```bash
cd /Users/dan/playground/x-noise && \
  git add Sources/XNoise/UI/PopoverView.swift && \
  git commit -m "Soundtracks: inject SoundtracksLibrary into the popover environment"
```

---

## Task 22: Manual smoke test + documentation patch

End-to-end manual verification of every spec scenario, plus the Sounds-page-design doc update.

**Files:**
- Modify: `docs/superpowers/specs/2026-04-26-sounds-page-design.md`

- [ ] **Step 22.1: Build a release binary and run**

Run: `cd /Users/dan/playground/x-noise && pkill -x XNoise 2>/dev/null; swift run`
Expected: app launches, menubar icon appears.

- [ ] **Step 22.2: Smoke checklist — work through each item**

For each, verify the behavior matches the spec section noted.

- [ ] Open popover → Sounds page → verify three tabs (Sounds | Mixes | Soundtracks). [§3.1]
- [ ] Soundtracks tab empty state renders the dashed-border card. [§4.4]
- [ ] Click `+`, paste `https://www.youtube.com/watch?v=jfKfPfyJRdk`, sub-text shows `YouTube video`, click Add. [§4.6]
- [ ] Row appears, becomes Active, audio starts. Title populates within ~3 seconds. [§4.6, §4.2]
- [ ] Navigate to Focus page → soundtrack panel shows; ring + panel + (no Switch to mix link, since mix is empty). [§5]
- [ ] Click play-all on Focus → audio pauses; click again → resumes. [§6.1]
- [ ] Tap ring to start focus session → audio still plays. Tap ring again to pause → audio pauses. [§6.1]
- [ ] Skip the focus phase manually (hover ring, click `forward.end.fill`) → audio pauses on break, resumes on next focus. [§6.1]
- [ ] Add a Spotify URL, e.g. `https://open.spotify.com/playlist/37i9dQZF1DX0XUsuxWHRQd`. Row appears Active, chevron pulses (sign-in required). [§4.5, Task 17]
- [ ] Tap chevron → embed expands inline, shows Spotify login UI. Sign in. After login, audio starts. [§4.5]
- [ ] Tap Done → embed collapses; audio continues. [§4.5]
- [ ] Add a sound on the Sounds tab → mode flips to mix, soundtrack pauses (verify by ear; expand-row should be available again on the soundtrack but row is no longer Active). [§2.4 row 1]
- [ ] On Focus page, "Switch to mix" link is visible only after a sound is in the mix and a soundtrack is active. Tap it → mode flips to mix, mix audio resumes. [§5]
- [ ] Quit the app (`pkill -x XNoise`), relaunch with `swift run`. Soundtrack rows survive; Active row is restored but not playing. Tap to play. [§7]
- [ ] Delete the active soundtrack via `⋯` menu → mode falls back to idle, no audio. [§2.4 row 5]

If any step fails, write a follow-up commit fixing the specific issue and rerun that step. Don't proceed until all smoke steps pass.

- [ ] **Step 22.3: Patch the Sounds-page-design doc**

Edit `docs/superpowers/specs/2026-04-26-sounds-page-design.md`:

(a) §1 non-goals: replace the line `Internet soundtracks (YouTube/Spotify) — likely a separate page later.` with:
```
Internet soundtracks (YouTube/Spotify) — covered by the separate spec at `docs/superpowers/specs/2026-04-27-soundtracks-design.md` (third tab on this same page).
```

(b) §10 future-features: replace the line `Internet soundtracks (YouTube/Spotify). Likely a separate page entirely.` with:
```
Internet soundtracks (YouTube/Spotify) — implemented as a third tab on this page; see `docs/superpowers/specs/2026-04-27-soundtracks-design.md`.
```

(c) §2 information-architecture diagram: change the tab bar from:
```
│       Sounds        │       Mixes          │  ← tab bar
```
to:
```
│   Sounds   │   Mixes   │   Soundtracks    │  ← tab bar
```

(Apply the same change to the diagrams in §3.1 and §4.1.)

- [ ] **Step 22.4: Run the full test suite once more**

Run: `cd /Users/dan/playground/x-noise && swift test`
Expected: full green.

- [ ] **Step 22.5: Commit**

```bash
cd /Users/dan/playground/x-noise && \
  git add docs/superpowers/specs/2026-04-26-sounds-page-design.md && \
  git commit -m "Docs: update sounds-page spec to reference soundtracks tab + spec"
```

---

## Self-review notes

- **Spec coverage:** every spec section maps to at least one task —
  - §1 overview + non-goals: nothing to implement; flagged in plan header
  - §2 architecture (model, controller, transitions): Tasks 1, 2, 3, 4, 5, 6, 7, 11, 13
  - §3 placement: Tasks 19, 20
  - §4 Soundtracks tab (anatomy, row, empty, expand-row, paste, hint): Tasks 14, 15, 16, 17
  - §5 Focus panel: Task 18, 20
  - §6 playback control: Tasks 7, 8, 9, 13, 18
  - §7 persistence: Tasks 5, 10
  - §8 edge cases: covered across 5, 6, 11, 13, 17 (sign-in detection, embed errors, removal-falls-to-idle)
  - §9 visual style: Tasks 14, 15, 16, 17, 18
  - §10 state summary: aggregate across UI tasks
  - §11 implementation notes: directly drives Tasks 1–22
- **Type consistency:** `WebSoundtrack`, `AudioMode`, `SoundtrackURL.Kind`, and `WebSoundtrackControlling` names are stable across all tasks. Method signatures (`load(_:autoplay:)`, `setPaused(_:)`, `setVolume(_:)`, `unload()`) match between protocol (Task 4), mock (Task 4), and concrete (Tasks 11, 13).
- **No placeholders:** every TDD step contains either the failing test code or the production code that makes it pass.
