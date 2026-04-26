# Sounds Page Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Redesign the Sounds page into two tabs (Sounds, Mixes), add user-saved custom mixes with an inline save flow, add drag-to-volume on tiles, replace category-pill filtering with wrapping scroll-jump pills.

**Architecture:** A new `SavedMixes` model joins `Presets` as the data backing the new Mixes tab. `AppModel` gains tab state, save-mode state, and CRUD APIs. The `SoundsPage` becomes a tab container hosting two child views (`SoundsBrowseView`, `MixesView`) with a shared inline save header. Reusable components: `JumpPills`, `MixIconStack`, `MixRow`, `SaveMixHeader`. `SoundTile` gains a drag gesture for per-track volume. Existing audio engine, catalog, and persistence patterns are unchanged.

**Tech Stack:** Swift 6 (strict concurrency), SwiftUI on macOS 26+ (Liquid Glass), XCTest, UserDefaults persistence (matching `Favorites`/`MixState` patterns), `swift build`/`swift test` SPM workflow.

**Spec:** `docs/superpowers/specs/2026-04-26-sounds-page-design.md`

---

## File Structure

**New files:**
- `Sources/XNoise/Models/SavedMixes.swift` — `SavedMix` value type + `SavedMixes` `ObservableObject` store with UserDefaults persistence.
- `Sources/XNoise/Models/MixDisplay.swift` — unified view-model enum for `Mixes` tab rows (custom or preset).
- `Sources/XNoise/UI/Components/MixIconStack.swift` — overlapping mini-icon row, used by `MixRow` and `SaveMixHeader` preview.
- `Sources/XNoise/UI/Components/MixRow.swift` — vertical card row for the Mixes tab (handles custom + preset + active variants + inline delete confirm).
- `Sources/XNoise/UI/Components/JumpPills.swift` — wrapping pill row with active-section highlight; pure presentational.
- `Sources/XNoise/UI/Components/SaveMixHeader.swift` — inline header transform for the save flow (text field, preview row, duplicate-confirm sub-state).
- `Sources/XNoise/UI/Pages/SoundsBrowseView.swift` — body of the Sounds tab (sectioned grid, pinned favorites, jump-pills wired to scroll).
- `Sources/XNoise/UI/Pages/MixesView.swift` — body of the Mixes tab (My Mixes + Presets sections, empty state).
- `Tests/XNoiseTests/SavedMixesTests.swift` — round-trip persistence, duplicate-name handling, suffix generation.
- `Tests/XNoiseTests/AppModelSaveMixTests.swift` — save-mode state machine, `commitSaveMix`, `cancelSaveMix`, currently-loaded helper.

**Modified files:**
- `Sources/XNoise/AppModel.swift` — add `savedMixes` dependency, `soundsTab` state, `saveMode` state machine + APIs (`beginSaveMix`/`updateSaveName`/`commitSaveMix`/`overwriteExisting`/`saveAsNewWithSuffix`/`cancelSaveMix`/`deleteMix`), `currentlyLoadedMixId` helper. Remove `categoryFilter` (replaced by sectioned-grid + jump-pills).
- `Sources/XNoise/UI/Pages/SoundsPage.swift` — becomes a tab container: header + `SaveMixHeader` overlay + tab bar + body switcher. Old pills/grid/presetsStrip code is deleted (moved to the new child views).
- `Sources/XNoise/UI/Components/SoundTile.swift` — add horizontal drag-to-volume gesture on active tiles (4pt minimum distance promotes drag and suppresses tap).
- `Sources/XNoise/UI/Pages/FocusPage.swift` — add a "Save mix" button next to "Add sound"; route through the same `AppModel.beginSaveMix()`. Surface the `SaveMixHeader` overlay over the Focus header when active.
- `Sources/XNoise/UI/PopoverView.swift` — inject the new `SavedMixes` `ObservableObject` into the environment.
- `Sources/XNoise/XNoiseApp.swift` — construct `SavedMixes` and pass to `AppModel.live(...)`.

**Files removed (in last cleanup task):**
- `enum CategoryFilter` in `AppModel.swift` — no longer used as a filter; sectioning is derived directly from the catalog.

---

## Working Discipline

- **TDD:** Write the failing test first, run it, then write the minimal code to make it pass.
- **Bash CWD drifts:** Use absolute paths or `cd /Users/dan/playground/x-noise && cmd` one-liners (per CLAUDE.md). Don't rely on a prior `cd` carrying over.
- **Build between tasks:** Run `swift build` after every task. UI changes additionally need `swift run` to manually verify in the popover (no automated UI tests).
- **Don't touch the audio engine** — `AudioController`/`MixingController` stays untouched; route all mix mutations through `MixState` (see CLAUDE.md).
- **macOS 26 SwiftUI gotchas** still apply: `@EnvironmentObject` for observed objects (don't pass `@ObservedObject` through view inits — crashes inside `MenuBarExtra` popovers); no `@MainActor` on UserDefaults wrappers; `.contentShape(Rectangle())` after `.clipShape(...)`; `.scrollIndicators(.never)` (not `.hidden`).
- **Commit after every task** (the "Step N: Commit" at the end of each task).

---

## Task 1: `SavedMix` value type + `SavedMixes` store + persistence + tests

**Files:**
- Create: `Sources/XNoise/Models/SavedMixes.swift`
- Create: `Tests/XNoiseTests/SavedMixesTests.swift`

- [ ] **Step 1.1: Write the failing test for round-trip persistence**

Create `Tests/XNoiseTests/SavedMixesTests.swift`:

```swift
import XCTest
@testable import XNoise

final class SavedMixesTests: XCTestCase {
    private func ephemeralDefaults() -> UserDefaults {
        let suite = "test.savedmixes.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        return d
    }

    @MainActor
    func testSaveAndReload() {
        let d = ephemeralDefaults()
        let store = SavedMixes(defaults: d)
        let result = store.save(name: "Rainy night",
                                tracks: [MixTrack(id: "rain", volume: 0.6),
                                         MixTrack(id: "thunder", volume: 0.3)])
        guard case .saved(let mix) = result else {
            XCTFail("expected .saved, got \(result)"); return
        }
        XCTAssertEqual(mix.name, "Rainy night")
        XCTAssertEqual(mix.tracks.count, 2)

        let reloaded = SavedMixes(defaults: d)
        XCTAssertEqual(reloaded.mixes.count, 1)
        XCTAssertEqual(reloaded.mixes.first?.name, "Rainy night")
        XCTAssertEqual(reloaded.mixes.first?.tracks.map(\.id), ["rain", "thunder"])
    }
}
```

- [ ] **Step 1.2: Run the test — expect failure (no `SavedMixes` type)**

Run: `cd /Users/dan/playground/x-noise && swift test --filter SavedMixesTests/testSaveAndReload`
Expected: compilation error — `cannot find 'SavedMixes' in scope`.

- [ ] **Step 1.3: Implement `SavedMix` + `SavedMixes` minimally**

Create `Sources/XNoise/Models/SavedMixes.swift`:

```swift
import Foundation
import Combine

/// A user-saved mix: ordered list of (trackId, volume) plus a display name.
struct SavedMix: Identifiable, Equatable, Codable {
    let id: UUID
    var name: String
    var tracks: [MixTrack]
    let createdAt: Date

    init(id: UUID = UUID(), name: String, tracks: [MixTrack], createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.tracks = tracks
        self.createdAt = createdAt
    }
}

/// Result of attempting to save under a given name.
enum SaveMixResult: Equatable {
    case saved(SavedMix)
    case duplicate(existing: SavedMix)
}

/// User-saved mixes. Persists to UserDefaults; sorted most-recently-saved first for display.
@MainActor
final class SavedMixes: ObservableObject {
    @Published private(set) var mixes: [SavedMix] = []

    private let defaults: UserDefaults
    private let storageKey: String

    init(defaults: UserDefaults = .standard, storageKey: String = "x-noise.savedMixes") {
        self.defaults = defaults
        self.storageKey = storageKey
        load()
    }

    /// Attempt to save a new mix. Returns `.duplicate(existing:)` if a mix with the same
    /// trimmed name already exists; the caller decides whether to overwrite or save-as-new.
    func save(name: String, tracks: [MixTrack]) -> SaveMixResult {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let existing = mix(named: trimmed) {
            return .duplicate(existing: existing)
        }
        let mix = SavedMix(name: trimmed, tracks: tracks)
        mixes.insert(mix, at: 0)
        persist()
        return .saved(mix)
    }

    /// Replace the tracks of an existing mix with a new set, preserving id/name/createdAt.
    func overwrite(id: UUID, tracks: [MixTrack]) {
        guard let idx = mixes.firstIndex(where: { $0.id == id }) else { return }
        mixes[idx].tracks = tracks
        persist()
    }

    /// Save under a "(N)" suffix, picking the smallest N that doesn't collide.
    @discardableResult
    func saveWithUniqueSuffix(baseName: String, tracks: [MixTrack]) -> SavedMix {
        let base = baseName.trimmingCharacters(in: .whitespacesAndNewlines)
        var n = 2
        var candidate = "\(base) (\(n))"
        while mix(named: candidate) != nil {
            n += 1
            candidate = "\(base) (\(n))"
        }
        let mix = SavedMix(name: candidate, tracks: tracks)
        mixes.insert(mix, at: 0)
        persist()
        return mix
    }

    func delete(id: UUID) {
        mixes.removeAll { $0.id == id }
        persist()
    }

    func mix(named name: String) -> SavedMix? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return mixes.first(where: { $0.name == trimmed })
    }

    // MARK: - Persistence

    private func persist() {
        guard let data = try? JSONEncoder().encode(mixes) else {
            assertionFailure("SavedMixes: encode failed")
            return
        }
        defaults.set(data, forKey: storageKey)
    }

    private func load() {
        guard
            let data = defaults.data(forKey: storageKey),
            let decoded = try? JSONDecoder().decode([SavedMix].self, from: data)
        else { return }
        // Preserve stored order; on save we always insert at index 0, so storage is already
        // most-recent-first.
        mixes = decoded
    }
}
```

- [ ] **Step 1.4: Run the test — expect pass**

Run: `cd /Users/dan/playground/x-noise && swift test --filter SavedMixesTests/testSaveAndReload`
Expected: test passes.

- [ ] **Step 1.5: Add duplicate-name + suffix tests**

Append to `SavedMixesTests.swift`:

```swift
    @MainActor
    func testDuplicateReturnsExisting() {
        let store = SavedMixes(defaults: ephemeralDefaults())
        _ = store.save(name: "Rainy night",
                       tracks: [MixTrack(id: "rain", volume: 0.5)])
        let result = store.save(name: "Rainy night",
                                tracks: [MixTrack(id: "thunder", volume: 0.5)])
        guard case .duplicate(let existing) = result else {
            XCTFail("expected .duplicate, got \(result)"); return
        }
        XCTAssertEqual(existing.tracks.first?.id, "rain")  // unchanged
        XCTAssertEqual(store.mixes.count, 1)               // not added
    }

    @MainActor
    func testOverwriteReplacesTracks() {
        let store = SavedMixes(defaults: ephemeralDefaults())
        guard case .saved(let original) = store.save(name: "Mix",
                                                     tracks: [MixTrack(id: "rain", volume: 0.5)]) else {
            XCTFail(); return
        }
        store.overwrite(id: original.id,
                        tracks: [MixTrack(id: "thunder", volume: 0.7)])
        XCTAssertEqual(store.mixes.count, 1)
        XCTAssertEqual(store.mixes.first?.id, original.id)  // same identity
        XCTAssertEqual(store.mixes.first?.name, "Mix")
        XCTAssertEqual(store.mixes.first?.tracks.first?.id, "thunder")
    }

    @MainActor
    func testSaveWithUniqueSuffixPicksSmallestFree() {
        let store = SavedMixes(defaults: ephemeralDefaults())
        _ = store.save(name: "Mix", tracks: [MixTrack(id: "a", volume: 0.5)])
        _ = store.save(name: "Mix (2)", tracks: [MixTrack(id: "b", volume: 0.5)])
        let m = store.saveWithUniqueSuffix(baseName: "Mix",
                                           tracks: [MixTrack(id: "c", volume: 0.5)])
        XCTAssertEqual(m.name, "Mix (3)")
    }

    @MainActor
    func testWhitespaceTrimmedOnSave() {
        let store = SavedMixes(defaults: ephemeralDefaults())
        guard case .saved(let m) = store.save(name: "  spaced  ",
                                              tracks: [MixTrack(id: "x", volume: 0.5)]) else {
            XCTFail(); return
        }
        XCTAssertEqual(m.name, "spaced")
    }

    @MainActor
    func testDeleteRemoves() {
        let store = SavedMixes(defaults: ephemeralDefaults())
        guard case .saved(let m) = store.save(name: "Mix",
                                              tracks: [MixTrack(id: "a", volume: 0.5)]) else {
            XCTFail(); return
        }
        store.delete(id: m.id)
        XCTAssertTrue(store.mixes.isEmpty)
    }
```

- [ ] **Step 1.6: Run all SavedMixes tests — expect all pass**

Run: `cd /Users/dan/playground/x-noise && swift test --filter SavedMixesTests`
Expected: 5 tests pass.

- [ ] **Step 1.7: Commit**

```bash
cd /Users/dan/playground/x-noise && git add Sources/XNoise/Models/SavedMixes.swift Tests/XNoiseTests/SavedMixesTests.swift && git commit -m "Add SavedMixes model with save/overwrite/delete + suffix helper"
```

---

## Task 2: `MixDisplay` unified view-model

**Files:**
- Create: `Sources/XNoise/Models/MixDisplay.swift`

The Mixes tab needs to render two heterogeneous types (`SavedMix` and `Preset`) in the same row component. A small enum keeps `MixRow` simple.

- [ ] **Step 2.1: Add `MixDisplay`**

Create `Sources/XNoise/Models/MixDisplay.swift`:

```swift
import Foundation

/// Unified view-model for any mix the user can apply from the Mixes tab.
enum MixDisplay: Identifiable, Equatable {
    case custom(SavedMix)
    case preset(Preset)

    var id: AnyHashable {
        switch self {
        case .custom(let m): return m.id
        case .preset(let p): return p.id
        }
    }

    var name: String {
        switch self {
        case .custom(let m): return m.name
        case .preset(let p): return p.name
        }
    }

    /// Track ids in the order they should appear in the icon stack.
    var trackIds: [String] {
        switch self {
        case .custom(let m): return m.tracks.map(\.id)
        case .preset(let p): return Array(p.mix.keys).sorted()
        }
    }

    /// `[id: volume]` — used when applying the mix.
    var trackVolumes: [String: Float] {
        switch self {
        case .custom(let m):
            return Dictionary(uniqueKeysWithValues: m.tracks.map { ($0.id, $0.volume) })
        case .preset(let p):
            return p.mix
        }
    }

    var isCustom: Bool {
        if case .custom = self { return true } else { return false }
    }
}
```

- [ ] **Step 2.2: Verify it builds**

Run: `cd /Users/dan/playground/x-noise && swift build`
Expected: builds clean.

- [ ] **Step 2.3: Commit**

```bash
cd /Users/dan/playground/x-noise && git add Sources/XNoise/Models/MixDisplay.swift && git commit -m "Add MixDisplay view-model unifying SavedMix and Preset"
```

---

## Task 3: `AppModel` — add SavedMixes, tab state, save-mode machine, currently-loaded helper

**Files:**
- Modify: `Sources/XNoise/AppModel.swift`
- Modify: `Sources/XNoise/XNoiseApp.swift` (constructor wiring)
- Create: `Tests/XNoiseTests/AppModelSaveMixTests.swift`

This task expands `AppModel`'s surface. Old `categoryFilter` and `CategoryFilter` enum stay for now — they're removed in Task 11 (cleanup) once all UI users are gone.

- [ ] **Step 3.1: Write the failing test for `beginSaveMix` / `cancelSaveMix`**

Create `Tests/XNoiseTests/AppModelSaveMixTests.swift`:

```swift
import XCTest
@testable import XNoise

@MainActor
final class AppModelSaveMixTests: XCTestCase {
    private func makeModel() -> (AppModel, SavedMixes) {
        let suite = "test.appmodel.savemix.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)

        let saved = SavedMixes(defaults: d)
        let state = MixState(defaults: d)
        let prefs = Preferences(defaults: d)
        let design = DesignSettings(defaults: d)
        let favorites = Favorites(defaults: d)
        let focusSettings = FocusSettings(defaults: d)
        let session = FocusSession(settings: focusSettings)
        let cache = AudioCache(baseDir: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),
                               downloader: URLSessionDownloader())
        let resolverBox = TrackResolverBox()
        let mixer = MixingController(state: state, cache: cache, resolveTrack: { id in resolverBox.resolve?(id) })
        let catalog = Catalog(fetcher: BundleCatalogFetcher(),
                              cacheFile: FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).json"))
        let model = AppModel(
            catalog: catalog, state: state, mixer: mixer, cache: cache,
            focusSettings: focusSettings, session: session, design: design,
            favorites: favorites, prefs: prefs, savedMixes: saved
        )
        resolverBox.resolve = { [weak model] id in model?.findTrack(id: id) }
        return (model, saved)
    }

    func testBeginSaveMixEntersNamingMode() {
        let (model, _) = makeModel()
        model.state.append(id: "rain", volume: 0.5)
        model.beginSaveMix()
        if case .naming(let text) = model.saveMode {
            XCTAssertEqual(text, "")
        } else {
            XCTFail("expected .naming, got \(model.saveMode)")
        }
    }

    func testCancelSaveMixReturnsInactive() {
        let (model, _) = makeModel()
        model.state.append(id: "rain", volume: 0.5)
        model.beginSaveMix()
        model.cancelSaveMix()
        XCTAssertEqual(model.saveMode, .inactive)
    }

    func testCommitSaveMixPersistsAndExits() {
        let (model, store) = makeModel()
        model.state.append(id: "rain", volume: 0.5)
        model.beginSaveMix()
        model.updateSaveName("Rainy")
        model.commitSaveMix()
        XCTAssertEqual(model.saveMode, .inactive)
        XCTAssertEqual(store.mixes.first?.name, "Rainy")
        XCTAssertEqual(store.mixes.first?.tracks.first?.id, "rain")
    }

    func testCommitSaveMixDuplicateEntersConflictMode() {
        let (model, store) = makeModel()
        _ = store.save(name: "Existing", tracks: [MixTrack(id: "rain", volume: 0.5)])
        model.state.append(id: "thunder", volume: 0.5)
        model.beginSaveMix()
        model.updateSaveName("Existing")
        model.commitSaveMix()
        if case .confirmingOverwrite(let text, let existing) = model.saveMode {
            XCTAssertEqual(text, "Existing")
            XCTAssertEqual(existing.tracks.first?.id, "rain")
        } else {
            XCTFail("expected .confirmingOverwrite, got \(model.saveMode)")
        }
    }

    func testOverwriteExistingReplacesTracksAndExits() {
        let (model, store) = makeModel()
        guard case .saved(let original) = store.save(name: "Existing",
                                                     tracks: [MixTrack(id: "rain", volume: 0.5)]) else {
            XCTFail(); return
        }
        model.state.append(id: "thunder", volume: 0.5)
        model.beginSaveMix()
        model.updateSaveName("Existing")
        model.commitSaveMix()
        model.overwriteExisting()
        XCTAssertEqual(model.saveMode, .inactive)
        XCTAssertEqual(store.mixes.count, 1)
        XCTAssertEqual(store.mixes.first?.id, original.id)
        XCTAssertEqual(store.mixes.first?.tracks.first?.id, "thunder")
    }

    func testSaveAsNewWithSuffixCreatesNewMix() {
        let (model, store) = makeModel()
        _ = store.save(name: "Existing", tracks: [MixTrack(id: "rain", volume: 0.5)])
        model.state.append(id: "thunder", volume: 0.5)
        model.beginSaveMix()
        model.updateSaveName("Existing")
        model.commitSaveMix()
        model.saveAsNewWithSuffix()
        XCTAssertEqual(model.saveMode, .inactive)
        XCTAssertEqual(store.mixes.count, 2)
        XCTAssertTrue(store.mixes.contains(where: { $0.name == "Existing (2)" }))
    }

    func testCurrentlyLoadedMixIdMatchesByTrackIdSet() {
        let (model, store) = makeModel()
        guard case .saved(let m) = store.save(name: "Pair",
                                              tracks: [MixTrack(id: "rain", volume: 0.5),
                                                       MixTrack(id: "thunder", volume: 0.5)]) else {
            XCTFail(); return
        }
        model.state.append(id: "thunder", volume: 0.9)  // different volume
        model.state.append(id: "rain",    volume: 0.1)  // different order
        XCTAssertEqual(model.currentlyLoadedMixId, AnyHashable(m.id))
    }
}
```

- [ ] **Step 3.2: Run the test — expect failure (missing APIs)**

Run: `cd /Users/dan/playground/x-noise && swift test --filter AppModelSaveMixTests`
Expected: compilation error — `AppModel` has no `savedMixes`/`saveMode`/`beginSaveMix`/etc.

- [ ] **Step 3.3: Add `SaveMode` and update `AppModel`**

Edit `Sources/XNoise/AppModel.swift`. Add the `SaveMode` enum near `SoundsTab`, add `savedMixes` injection, `soundsTab` and `saveMode` published state, and the new methods. The existing `categoryFilter` field stays for now.

Add near the top of the file (above `AppModel`):

```swift
/// Which tab of the Sounds page is active.
enum SoundsTab: String, Equatable { case sounds, mixes }

/// State machine for the inline save-mix flow.
enum SaveMode: Equatable {
    case inactive
    case naming(text: String)
    case confirmingOverwrite(text: String, existing: SavedMix)

    var isActive: Bool { self != .inactive }
}
```

In the `AppModel` class, change the initializer to accept `savedMixes` and store it:

```swift
let savedMixes: SavedMixes
```

Add to the existing init parameter list (alphabetical/logical order — append at end):
```swift
init(
    catalog: Catalog,
    state: MixState,
    mixer: MixingController,
    cache: AudioCache,
    focusSettings: FocusSettings,
    session: FocusSession,
    design: DesignSettings,
    favorites: Favorites,
    prefs: Preferences,
    savedMixes: SavedMixes
) {
    self.catalog = catalog
    self.state = state
    self.mixer = mixer
    self.cache = cache
    self.focusSettings = focusSettings
    self.session = session
    self.design = design
    self.favorites = favorites
    self.prefs = prefs
    self.savedMixes = savedMixes
    self.mixer.masterVolume = prefs.volume
}
```

Add the new published state next to the existing `@Published var page`:

```swift
@Published var soundsTab: SoundsTab = .sounds
@Published var saveMode: SaveMode = .inactive
```

Add the new methods (anywhere inside `AppModel`, e.g. below `applyPreset`):

```swift
// MARK: - Save mix flow

func beginSaveMix() {
    guard !state.isEmpty else { return }
    saveMode = .naming(text: "")
}

func updateSaveName(_ text: String) {
    switch saveMode {
    case .naming:
        saveMode = .naming(text: text)
    case .confirmingOverwrite:
        // Editing the name from the conflict screen returns to plain naming mode.
        saveMode = .naming(text: text)
    case .inactive:
        return
    }
}

func commitSaveMix() {
    guard case .naming(let raw) = saveMode else { return }
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    let result = savedMixes.save(name: trimmed, tracks: state.tracks)
    switch result {
    case .saved:
        saveMode = .inactive
    case .duplicate(let existing):
        saveMode = .confirmingOverwrite(text: trimmed, existing: existing)
    }
}

func overwriteExisting() {
    guard case .confirmingOverwrite(_, let existing) = saveMode else { return }
    savedMixes.overwrite(id: existing.id, tracks: state.tracks)
    saveMode = .inactive
}

func saveAsNewWithSuffix() {
    guard case .confirmingOverwrite(let text, _) = saveMode else { return }
    _ = savedMixes.saveWithUniqueSuffix(baseName: text, tracks: state.tracks)
    saveMode = .inactive
}

func cancelSaveMix() {
    saveMode = .inactive
}

func deleteMix(id: UUID) {
    savedMixes.delete(id: id)
}

// MARK: - Currently-loaded helper

/// Returns the id (UUID for SavedMix or String for Preset) of the mix whose track-id set
/// matches the current MixState. Volume differences and ordering are ignored. Nil if no
/// match (or the active mix is empty).
var currentlyLoadedMixId: AnyHashable? {
    guard !state.tracks.isEmpty else { return nil }
    let active = Set(state.tracks.map(\.id))
    if let m = savedMixes.mixes.first(where: { Set($0.tracks.map(\.id)) == active }) {
        return AnyHashable(m.id)
    }
    if let p = Presets.all.first(where: { Set($0.mix.keys) == active }) {
        return AnyHashable(p.id)
    }
    return nil
}
```

- [ ] **Step 3.4: Update `XNoiseApp.swift` to construct `SavedMixes`**

Edit `Sources/XNoise/XNoiseApp.swift`. In `AppModel.live(...)`, add a `savedMixes` line and pass it:

Replace the section that builds `favorites` through `AppModel(...)` with:

```swift
let favorites = Favorites()
let savedMixes = SavedMixes()
// resolveTrack is captured weakly via a closure so MixingController doesn't
// pin AppModel — but the closure must be set after AppModel is built. So we
// build the model first with a temporary controller, then thread the resolver.
// Simpler: build a small mutable resolver box that we wire in after init.
let resolverBox = TrackResolverBox()
let mixer = MixingController(state: state, cache: cache, resolveTrack: { id in
    resolverBox.resolve?(id)
})
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
    savedMixes: savedMixes
)
```

- [ ] **Step 3.5: Run the new tests — expect all pass**

Run: `cd /Users/dan/playground/x-noise && swift test --filter AppModelSaveMixTests`
Expected: 7 tests pass.

- [ ] **Step 3.6: Run the full test suite — expect clean (don't regress others)**

Run: `cd /Users/dan/playground/x-noise && swift test`
Expected: all tests pass; no warnings about the new code.

- [ ] **Step 3.7: Commit**

```bash
cd /Users/dan/playground/x-noise && git add Sources/XNoise/AppModel.swift Sources/XNoise/XNoiseApp.swift Tests/XNoiseTests/AppModelSaveMixTests.swift && git commit -m "AppModel: add SavedMixes, save-mode state machine, currently-loaded helper"
```

---

## Task 4: `MixIconStack` component

**Files:**
- Create: `Sources/XNoise/UI/Components/MixIconStack.swift`

A small overlapping row of mini-icons (max 3 visible, "+N" if more), used in `MixRow` and the save-flow preview row.

- [ ] **Step 4.1: Create the component**

Create `Sources/XNoise/UI/Components/MixIconStack.swift`:

```swift
import SwiftUI

/// Overlapping row of up to 3 mini track icons. If more tracks exist, the last slot shows
/// "+N" instead. Each icon is 22×22pt with a 6pt corner radius and a 1.5pt cut-out border
/// in the row's background color so overlap reads cleanly.
struct MixIconStack: View {
    let trackIds: [String]
    /// The color the icon borders cut out to. Should match the parent row's fill so overlaps
    /// look like punches, not seams. Defaults to clear (no cut-out).
    var rowBackground: Color = .clear

    private let maxVisible = 3
    private let iconSize: CGFloat = 22
    private let overlap: CGFloat = 6  // pt of horizontal overlap between adjacent icons

    var body: some View {
        let visible = Array(trackIds.prefix(maxVisible))
        let overflow = max(0, trackIds.count - maxVisible)
        HStack(spacing: -overlap) {
            ForEach(Array(visible.enumerated()), id: \.offset) { _, id in
                iconBubble(systemName: TrackIconMap.icon(for: id).symbol)
            }
            if overflow > 0 {
                iconBubble(text: "+\(overflow)")
            }
        }
    }

    private func iconBubble(systemName: String? = nil, text: String? = nil) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.white.opacity(0.06))
            if let systemName {
                Image(systemName: systemName)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.white.opacity(0.85))
            } else if let text {
                Text(text)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
        .frame(width: iconSize, height: iconSize)
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(rowBackground, lineWidth: 1.5)
        )
    }
}
```

- [ ] **Step 4.2: Verify it builds**

Run: `cd /Users/dan/playground/x-noise && swift build`
Expected: builds clean.

- [ ] **Step 4.3: Commit**

```bash
cd /Users/dan/playground/x-noise && git add Sources/XNoise/UI/Components/MixIconStack.swift && git commit -m "Add MixIconStack overlapping mini-icon row component"
```

---

## Task 5: `MixRow` component

**Files:**
- Create: `Sources/XNoise/UI/Components/MixRow.swift`

A vertical card row used in the Mixes tab. Handles three flavors visually (custom / preset / active) and an inline delete-confirm sub-state for custom mixes.

- [ ] **Step 5.1: Create the component**

Create `Sources/XNoise/UI/Components/MixRow.swift`:

```swift
import SwiftUI

/// Vertical card row for the Mixes tab. Renders a `MixDisplay` (custom or preset),
/// optionally highlighted as the currently-loaded mix. Custom mixes get an inline
/// delete-confirm overlay when the user opens the ⋯ menu and chooses Delete.
struct MixRow: View {
    let mix: MixDisplay
    let isActive: Bool
    /// Resolves a track id to a display name for the sub-line. Tracks not in the catalog
    /// (e.g. removed in an update) are omitted from the sub-line.
    let trackName: (String) -> String?
    let onApply: () -> Void
    let onDelete: () -> Void

    @EnvironmentObject var design: DesignSettings
    @State private var confirmingDelete = false

    var body: some View {
        if confirmingDelete {
            confirmRow
        } else {
            applyRow
        }
    }

    private var rowBackground: Color {
        switch mix {
        case .custom: return Color.white.opacity(0.04)
        case .preset: return XNTokens.accent(hue: design.accentHue).opacity(0.07)
        }
    }

    private var rowBorder: Color {
        if isActive { return design.accent.opacity(0.6) }
        switch mix {
        case .custom: return Color.white.opacity(0.08)
        case .preset: return design.accent.opacity(0.18)
        }
    }

    private var applyRow: some View {
        Button(action: onApply) {
            HStack(spacing: 10) {
                MixIconStack(trackIds: mix.trackIds, rowBackground: solidRowBg)
                    .frame(width: 56, alignment: .leading)
                VStack(alignment: .leading, spacing: 1) {
                    Text(mix.name)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                        .xnText(.primary)
                    Text(subline)
                        .font(.system(size: 10.5))
                        .lineLimit(1)
                        .xnText(.tertiary)
                    if isActive {
                        Text("▶ ACTIVE")
                            .font(.system(size: 9, weight: .semibold))
                            .kerning(0.5)
                            .foregroundStyle(design.accent)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(
                                Capsule().fill(design.accent.opacity(0.15))
                            )
                            .padding(.top, 2)
                    }
                }
                Spacer(minLength: 0)
                if mix.isCustom {
                    Menu {
                        Button("Delete", role: .destructive) {
                            confirmingDelete = true
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(.white.opacity(0.5))
                            .frame(width: 22, height: 22)
                            .contentShape(Rectangle())
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .frame(width: 22, height: 22)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(rowBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(rowBorder, lineWidth: isActive ? 1.5 : 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// A solid color matching the row fill, used for icon-bubble cut-outs.
    private var solidRowBg: Color {
        // Liquid Glass over a wallpaper makes computing a literal compositor color hard;
        // approximate with a near-popover-bg solid so the cut-outs read as a clean punch.
        Color(red: 0.10, green: 0.12, blue: 0.16)
    }

    private var subline: String {
        let resolved = mix.trackIds.compactMap(trackName)
        let total = mix.trackIds.count
        let available = resolved.count
        // If catalog is missing some tracks, surface that explicitly per spec §9.
        let countText: String
        if available < total {
            countText = "\(available) of \(total) sounds available"
        } else {
            countText = "\(total) sound\(total == 1 ? "" : "s")"
        }
        let names = resolved.prefix(3).joined(separator: " · ")
        return names.isEmpty ? countText : "\(countText) · \(names)"
    }

    private var confirmRow: some View {
        HStack(spacing: 8) {
            Text("Delete \"\(mix.name)\"?")
                .font(.system(size: 12))
                .xnText(.primary)
                .lineLimit(1)
            Spacer(minLength: 0)
            Button("Cancel") { confirmingDelete = false }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .xnText(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            Button {
                onDelete()
                confirmingDelete = false
            } label: {
                Text("Delete")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.red.opacity(0.85)))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.red.opacity(0.45), lineWidth: 1)
        )
    }
}
```

- [ ] **Step 5.2: Verify it builds**

Run: `cd /Users/dan/playground/x-noise && swift build`
Expected: builds clean. (Some warnings about `_ = existing` are fine if any appear.)

- [ ] **Step 5.3: Commit**

```bash
cd /Users/dan/playground/x-noise && git add Sources/XNoise/UI/Components/MixRow.swift && git commit -m "Add MixRow component with active state and inline delete confirm"
```

---

## Task 6: `MixesView` (the Mixes tab body)

**Files:**
- Create: `Sources/XNoise/UI/Pages/MixesView.swift`

Two stacked sections (`MY MIXES`, `PRESETS`), with a dashed empty card when the user has no saved mixes.

- [ ] **Step 6.1: Create the view**

Create `Sources/XNoise/UI/Pages/MixesView.swift`:

```swift
import SwiftUI

/// Body of the Mixes tab. Renders MY MIXES (user-saved) above PRESETS (built-in),
/// each as a stack of MixRow cards.
struct MixesView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var savedMixes: SavedMixes

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                sectionHeader(title: "MY MIXES", count: savedMixes.mixes.count)
                if savedMixes.mixes.isEmpty {
                    emptyCard
                } else {
                    VStack(spacing: 6) {
                        ForEach(savedMixes.mixes) { mix in
                            MixRow(
                                mix: .custom(mix),
                                isActive: model.currentlyLoadedMixId == AnyHashable(mix.id),
                                trackName: { id in model.findTrack(id: id)?.name },
                                onApply: { model.applySavedMix(mix) },
                                onDelete: { model.deleteMix(id: mix.id) }
                            )
                        }
                    }
                    .padding(.horizontal, 12)
                }

                sectionHeader(title: "PRESETS", count: Presets.all.count)
                VStack(spacing: 6) {
                    ForEach(Presets.all) { preset in
                        MixRow(
                            mix: .preset(preset),
                            isActive: model.currentlyLoadedMixId == AnyHashable(preset.id),
                            trackName: { id in model.findTrack(id: id)?.name },
                            onApply: { model.applyPreset(preset) },
                            onDelete: {}  // presets don't surface delete
                        )
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
        }
        .scrollIndicators(.never)
    }

    private func sectionHeader(title: String, count: Int) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .kerning(0.8)
                .xnText(.tertiary)
            Text("\(count)")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.30))
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 6)
    }

    private var emptyCard: some View {
        VStack(spacing: 4) {
            Text("No saved mixes yet")
                .font(.system(size: 11))
                .xnText(.tertiary)
            Text("Build a mix on the Sounds tab and tap \"Save mix\"")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.35))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .padding(.horizontal, 12)
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    Color.white.opacity(0.12),
                    style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                )
        )
        .padding(.horizontal, 12)
    }
}
```

- [ ] **Step 6.2: Add `applySavedMix` to `AppModel`**

Edit `Sources/XNoise/AppModel.swift`. Add this method next to `applyPreset`:

```swift
func applySavedMix(_ mix: SavedMix) {
    let newTracks = mix.tracks.filter { $0.volume >= 0.02 }
    state.replace(with: newTracks, masterPaused: false)
}
```

- [ ] **Step 6.3: Verify it builds**

Run: `cd /Users/dan/playground/x-noise && swift build`
Expected: builds clean.

- [ ] **Step 6.4: Commit**

```bash
cd /Users/dan/playground/x-noise && git add Sources/XNoise/UI/Pages/MixesView.swift Sources/XNoise/AppModel.swift && git commit -m "Add MixesView (My Mixes + Presets sections, empty state) and applySavedMix"
```

---

## Task 7: `JumpPills` component

**Files:**
- Create: `Sources/XNoise/UI/Components/JumpPills.swift`

A wrapping pill row. Pure presentational — caller passes the section list, the current section id, and an `onTap` callback.

- [ ] **Step 7.1: Create the component**

Create `Sources/XNoise/UI/Components/JumpPills.swift`:

```swift
import SwiftUI

/// Section descriptor for the jump-pill nav. The id must match the `.id(...)` set on the
/// section header in the scroll body so `ScrollViewReader.scrollTo` can locate it.
struct JumpSection: Identifiable, Equatable {
    let id: String
    let title: String
    /// If true, this pill is rendered in warm gold (used for ★ Favorites).
    let isStar: Bool

    init(id: String, title: String, isStar: Bool = false) {
        self.id = id
        self.title = title
        self.isStar = isStar
    }
}

/// Wrapping pill row pinned beneath the tab bar on the Sounds tab. Each pill is a tap target
/// that scroll-jumps to the corresponding section. The pill matching `currentSectionId`
/// is highlighted in the accent color.
struct JumpPills: View {
    let sections: [JumpSection]
    let currentSectionId: String?
    let onTap: (String) -> Void

    @EnvironmentObject var design: DesignSettings

    var body: some View {
        FlowLayout(spacing: 4) {
            ForEach(sections) { section in
                pill(section)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(Color.black.opacity(0.15))
        .overlay(Divider().opacity(0.3), alignment: .bottom)
    }

    private func pill(_ section: JumpSection) -> some View {
        let isCurrent = section.id == currentSectionId
        let label = section.isStar ? "★" : section.title
        return Button { onTap(section.id) } label: {
            Text(label)
                .font(.system(size: 10.5, weight: .medium))
                .kerning(0.2)
                .padding(.horizontal, section.isStar ? 7 : 9)
                .padding(.vertical, 4)
                .foregroundStyle(pillForeground(section: section, isCurrent: isCurrent))
                .background(
                    Capsule().fill(isCurrent ? design.accent.opacity(0.18) : Color.clear)
                )
                .overlay(
                    Capsule().strokeBorder(
                        isCurrent ? design.accent.opacity(0.45)
                                  : Color.white.opacity(0.08),
                        lineWidth: 1
                    )
                )
        }
        .buttonStyle(.plain)
    }

    private func pillForeground(section: JumpSection, isCurrent: Bool) -> Color {
        if isCurrent { return .white }
        if section.isStar { return Color(red: 1.0, green: 0.83, blue: 0.42) }
        return Color.white.opacity(0.55)
    }
}

/// Minimal flow layout — wraps children to multiple rows when they exceed the proposed width.
/// macOS 13+; we target 26 so this is fine.
struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rows: [[CGSize]] = [[]]
        var rowWidth: CGFloat = 0
        var totalHeight: CGFloat = 0
        var currentRowHeight: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            let extraWidth = rows[rows.count - 1].isEmpty ? 0 : spacing
            if rowWidth + extraWidth + size.width > maxWidth, !rows[rows.count - 1].isEmpty {
                totalHeight += currentRowHeight + spacing
                rows.append([])
                rowWidth = 0
                currentRowHeight = 0
            }
            rows[rows.count - 1].append(size)
            rowWidth += extraWidth + size.width
            currentRowHeight = max(currentRowHeight, size.height)
        }
        totalHeight += currentRowHeight
        let usedWidth = min(maxWidth, rows.map { row in
            row.enumerated().reduce(0.0) { $0 + $1.element.width + ($1.offset == 0 ? 0 : spacing) }
        }.max() ?? 0)
        return CGSize(width: usedWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x != bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            sub.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
```

- [ ] **Step 7.2: Verify it builds**

Run: `cd /Users/dan/playground/x-noise && swift build`
Expected: builds clean.

- [ ] **Step 7.3: Commit**

```bash
cd /Users/dan/playground/x-noise && git add Sources/XNoise/UI/Components/JumpPills.swift && git commit -m "Add JumpPills wrapping nav with FlowLayout"
```

---

## Task 8: `SoundsBrowseView` (the Sounds tab body)

**Files:**
- Create: `Sources/XNoise/UI/Pages/SoundsBrowseView.swift`

Sectioned grid (★ Favorites pinned at top, then catalog categories) with the `JumpPills` bar wired to scroll position.

- [ ] **Step 8.1: Create the view**

Create `Sources/XNoise/UI/Pages/SoundsBrowseView.swift`:

```swift
import SwiftUI

/// Body of the Sounds tab. Sectioned grid of tiles by catalog category, with a ★ Favorites
/// section pinned at the top (auto-hidden if empty). The JumpPills bar is wired to the
/// scroll position — tapping a pill scroll-jumps to that section, and the pill matching
/// the currently topmost section is highlighted.
struct SoundsBrowseView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var favorites: Favorites
    @EnvironmentObject var state: MixState

    @State private var currentSectionId: String?

    private let cols = Array(repeating: GridItem(.flexible(), spacing: 6), count: 4)

    private struct Section: Identifiable, Equatable {
        let id: String
        let title: String
        let isStar: Bool
        let tracks: [Track]
    }

    private var sections: [Section] {
        var result: [Section] = []
        let favTracks = model.allTracks.map(\.track).filter { favorites.contains($0.id) }
        if !favTracks.isEmpty {
            result.append(.init(id: "favorites", title: "★ FAVORITES", isStar: true, tracks: favTracks))
        }
        for cat in model.categories {
            result.append(.init(id: cat.id, title: cat.name.uppercased(), isStar: false, tracks: cat.tracks))
        }
        return result
    }

    private var jumpSections: [JumpSection] {
        sections.map { JumpSection(id: $0.id, title: $0.title.replacingOccurrences(of: "★ ", with: ""), isStar: $0.isStar) }
    }

    var body: some View {
        VStack(spacing: 0) {
            JumpPills(
                sections: jumpSections,
                currentSectionId: currentSectionId,
                onTap: { id in
                    withAnimation(.easeInOut(duration: 0.25)) {
                        scrollProxy?.scrollTo(id, anchor: .top)
                    }
                }
            )
            scrollBody
        }
        .onAppear {
            if currentSectionId == nil { currentSectionId = sections.first?.id }
        }
    }

    @State private var scrollProxy: ScrollViewProxy?

    private var scrollBody: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(sections) { section in
                        sectionView(section)
                            .id(section.id)
                            .background(
                                GeometryReader { geo in
                                    Color.clear.preference(
                                        key: SectionMinYKey.self,
                                        value: [section.id: geo.frame(in: .named("soundsScroll")).minY]
                                    )
                                }
                            )
                    }
                }
                .padding(.bottom, 12)
            }
            .scrollIndicators(.never)
            .coordinateSpace(name: "soundsScroll")
            .onPreferenceChange(SectionMinYKey.self) { frames in
                // The "current" section is the last one whose minY <= 1 (i.e. has crossed the
                // scroll-area top). If none have crossed yet, fall back to the first section.
                let crossed = frames.filter { $0.value <= 1 }
                let pick = crossed.max(by: { $0.value < $1.value })?.key ?? sections.first?.id
                if pick != currentSectionId { currentSectionId = pick }
            }
            .onAppear { scrollProxy = proxy }
        }
    }

    private func sectionView(_ section: Section) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(section.title)
                .font(.system(size: 10, weight: .semibold))
                .kerning(0.8)
                .foregroundStyle(section.isStar ? Color(red: 1.0, green: 0.83, blue: 0.42).opacity(0.7)
                                                : Color.white.opacity(0.40))
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 4)

            LazyVGrid(columns: cols, spacing: 6) {
                ForEach(section.tracks) { track in
                    let mixTrack = state.track(track.id)
                    SoundTile(
                        track: track,
                        isOn: mixTrack != nil,
                        volume: mixTrack?.volume ?? 0,
                        isFavorite: favorites.contains(track.id),
                        onTap: { model.toggleTrack(track) },
                        onVolumeChange: { v in model.setTrackVolume(track.id, v) },
                        onToggleFav: { favorites.toggle(track.id) }
                    )
                }
            }
            .padding(.horizontal, 12)
        }
    }
}

/// Reports each section's minY in the scroll's coordinate space so SoundsBrowseView can
/// decide which section is currently topmost.
private struct SectionMinYKey: PreferenceKey {
    static var defaultValue: [String: CGFloat] = [:]
    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}
```

- [ ] **Step 8.2: Verify it builds**

Note: this references `SoundTile.init(...)` with a new `onVolumeChange` parameter that doesn't exist yet — that's added in Task 9. Build will fail until Task 9 is also applied. Do not commit a half-broken state — proceed straight to Task 9 and commit them together at the end of Task 9.

Run: `cd /Users/dan/playground/x-noise && swift build`
Expected: compilation error — `extra argument 'onVolumeChange' in call`. This is intentional; Task 9 fixes it.

- [ ] **Step 8.3: Move on to Task 9 without committing**

Do not commit yet. Task 9 modifies `SoundTile`'s init to add `onVolumeChange`, restoring the build.

---

## Task 9: `SoundTile` drag-to-volume gesture

**Files:**
- Modify: `Sources/XNoise/UI/Components/SoundTile.swift`

Add a horizontal drag gesture that promotes after 4pt of movement, suppressing the toggle tap. Maps drag x within the tile's width to 0.0–1.0 volume.

- [ ] **Step 9.1: Update `SoundTile` to add `onVolumeChange` and the drag gesture**

Replace the existing `Sources/XNoise/UI/Components/SoundTile.swift` with:

```swift
import SwiftUI

/// Pressable sound tile on the Sounds page. On when active in the mix.
/// Shows a favorite star in the top-right.
///
/// Gestures:
///   - Tap (lift without drag) toggles the track in/out of the mix.
///   - When on, dragging horizontally on the tile body sets the per-track volume —
///     the visible bar at the bottom updates in real time. A 4pt minimum distance
///     promotes the gesture and suppresses the tap.
struct SoundTile: View {
    let track: Track
    let isOn: Bool
    let volume: Float
    let isFavorite: Bool
    let onTap: () -> Void
    let onVolumeChange: (Float) -> Void
    let onToggleFav: () -> Void

    @EnvironmentObject var design: DesignSettings
    @State private var dragActive = false

    private var icon: TrackIcon { TrackIconMap.icon(for: track.id) }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            tileButton
            favoriteStar
        }
    }

    private var tileButton: some View {
        GeometryReader { geo in
            tileContent
                .gesture(volumeDragGesture(width: geo.size.width))
                .simultaneousGesture(tapGesture)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private var tapGesture: some Gesture {
        TapGesture().onEnded {
            // The drag gesture's onChanged sets dragActive=true after promotion; we only
            // fire tap if no drag was promoted. SwiftUI will deliver tap only when no
            // drag occurred past the minimum distance.
            if !dragActive { onTap() }
        }
    }

    private func volumeDragGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                guard isOn, width > 0 else { return }
                dragActive = true
                let raw = Float(value.location.x / width)
                let clamped = max(0, min(1, raw))
                onVolumeChange(clamped)
            }
            .onEnded { _ in
                // Defer the reset so the simultaneous tap recognizer (if any) sees dragActive.
                DispatchQueue.main.async { dragActive = false }
            }
    }

    private var tileContent: some View {
        VStack(spacing: 5) {
            Spacer(minLength: 0)
            iconGlyph
            nameLabel
            Spacer(minLength: 0)
            // Always reserve the volume-bar slot so the tile height stays stable
            // when toggling on/off — only the visibility changes.
            volumeBar
                .opacity(isOn ? 1 : 0)
        }
        .padding(6)
        .frame(maxWidth: .infinity)
        .background(tileBackground)
        .overlay(tileBorder)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(Rectangle())
        .shadow(color: isOn ? design.accent.opacity(0.45) : .clear, radius: 6, y: 3)
    }

    private var iconGlyph: some View {
        Image(systemName: icon.symbol)
            .font(.system(size: 22, weight: .light))
            .foregroundStyle(isOn ? Color.white : .primary.opacity(0.75))
    }

    private var nameLabel: some View {
        Text(track.name)
            .font(.system(size: 11, weight: .regular))
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .foregroundStyle(isOn ? Color.white : .primary.opacity(0.7))
    }

    private var volumeBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.25))
                Capsule()
                    .fill(Color.white)
                    .frame(width: geo.size.width * Double(volume))
                    .shadow(color: .white.opacity(dragActive ? 1.0 : 0.9), radius: dragActive ? 5 : 3)
            }
            .frame(height: 2)
        }
        .frame(height: 2)
        .padding(.horizontal, 6)
    }

    @ViewBuilder
    private var tileBackground: some View {
        if isOn {
            LinearGradient(
                colors: [design.accent.opacity(0.88), design.accentDark.opacity(0.88)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        } else {
            Color.white.opacity(0.04)
                .background(.ultraThinMaterial)
        }
    }

    private var tileBorder: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(
                isOn && dragActive ? Color.white.opacity(0.6) : Color.white.opacity(isOn ? 0.40 : 0.15),
                lineWidth: isOn && dragActive ? 1.5 : 1
            )
    }

    private var favoriteStar: some View {
        Button(action: onToggleFav) {
            Image(systemName: isFavorite ? "star.fill" : "star")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(starColor)
                .padding(5)
        }
        .buttonStyle(.plain)
    }

    private var starColor: Color {
        if isFavorite { return Color(red: 1.0, green: 0.83, blue: 0.42) }
        return isOn ? Color.white.opacity(0.55) : .secondary.opacity(0.65)
    }
}
```

- [ ] **Step 9.2: Verify it builds**

Run: `cd /Users/dan/playground/x-noise && swift build`
Expected: builds clean. (`SoundsBrowseView` from Task 8 now compiles too.)

- [ ] **Step 9.3: Run all tests — expect clean**

Run: `cd /Users/dan/playground/x-noise && swift test`
Expected: all tests pass.

- [ ] **Step 9.4: Commit Tasks 8 + 9 together**

```bash
cd /Users/dan/playground/x-noise && git add Sources/XNoise/UI/Pages/SoundsBrowseView.swift Sources/XNoise/UI/Components/SoundTile.swift && git commit -m "Add SoundsBrowseView (sectioned grid + jump-pills) and SoundTile drag-to-volume"
```

---

## Task 10: `SaveMixHeader` component

**Files:**
- Create: `Sources/XNoise/UI/Components/SaveMixHeader.swift`

Two visual sub-states: naming (text field + Cancel + Save + live preview row) and confirming-overwrite (overwrite question + two action buttons).

- [ ] **Step 10.1: Create the component**

Create `Sources/XNoise/UI/Components/SaveMixHeader.swift`:

```swift
import SwiftUI

/// Inline header that replaces the Sounds-page header during save mode. Two sub-states
/// per `AppModel.saveMode`:
///   - .naming(text:): text field + Cancel + Save + live preview row showing current mix.
///   - .confirmingOverwrite(text:existing:): "Overwrite "X"?" + [Save as new] [Overwrite].
struct SaveMixHeader: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var design: DesignSettings
    @EnvironmentObject var state: MixState
    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            switch model.saveMode {
            case .naming(let text):
                namingHeader(text: text)
                previewRow
            case .confirmingOverwrite(let text, let existing):
                confirmHeader(text: text, existing: existing)
            case .inactive:
                EmptyView()
            }
        }
        .background(design.accent.opacity(0.06))
    }

    private func namingHeader(text: String) -> some View {
        HStack(spacing: 8) {
            TextField("Name this mix…", text: Binding(
                get: { text },
                set: { model.updateSaveName($0) }
            ))
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.black.opacity(0.35))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(design.accent.opacity(0.45), lineWidth: 1)
            )
            .focused($nameFocused)
            .onSubmit { model.commitSaveMix() }
            .onAppear { nameFocused = true }

            Button("Cancel") { model.cancelSaveMix() }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .xnText(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 6)
                .keyboardShortcut(.cancelAction)

            Button(action: { model.commitSaveMix() }) {
                Text("Save")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(design.accent.opacity(0.85))
                    )
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.defaultAction)
            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var previewRow: some View {
        HStack(spacing: 6) {
            Text("SAVING")
                .font(.system(size: 10, weight: .semibold))
                .kerning(0.6)
                .xnText(.secondary)
            Text(previewText)
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
    }

    private var previewText: String {
        let names = state.tracks.compactMap { model.findTrack(id: $0.id)?.name }
        return names.joined(separator: " · ")
    }

    private func confirmHeader(text: String, existing: SavedMix) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Overwrite \"\(existing.name)\"?")
                .font(.system(size: 12, weight: .medium))
                .xnText(.primary)
            HStack(spacing: 6) {
                Spacer(minLength: 0)
                Button("Save as new") { model.saveAsNewWithSuffix() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .xnText(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.white.opacity(0.05))
                    )
                Button(action: { model.overwriteExisting() }) {
                    Text("Overwrite")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(design.accent.opacity(0.85))
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}
```

- [ ] **Step 10.2: Verify it builds**

Run: `cd /Users/dan/playground/x-noise && swift build`
Expected: builds clean.

- [ ] **Step 10.3: Commit**

```bash
cd /Users/dan/playground/x-noise && git add Sources/XNoise/UI/Components/SaveMixHeader.swift && git commit -m "Add SaveMixHeader inline transform with naming + confirm sub-states"
```

---

## Task 11: `SoundsPage` container — tabs + save header overlay + body switcher

**Files:**
- Modify: `Sources/XNoise/UI/Pages/SoundsPage.swift`

Replace the entire body. The page becomes: page header (or `SaveMixHeader` overlay when `model.saveMode != .inactive`) → tab bar → switching child view.

- [ ] **Step 11.1: Replace `SoundsPage`**

Replace the contents of `Sources/XNoise/UI/Pages/SoundsPage.swift` with:

```swift
import SwiftUI

/// Container for the Sounds page. Hosts two child views (SoundsBrowseView, MixesView)
/// behind a tab bar. The page header is replaced by SaveMixHeader during save mode.
struct SoundsPage: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var design: DesignSettings

    var body: some View {
        VStack(spacing: 0) {
            if model.saveMode.isActive {
                SaveMixHeader()
            } else {
                pageHeader
            }
            tabBar
            switch model.soundsTab {
            case .sounds: SoundsBrowseView()
            case .mixes:  MixesView()
            }
        }
    }

    private var pageHeader: some View {
        HStack(spacing: 8) {
            IconButton(systemName: "chevron.left") { model.goTo(.focus) }
            VStack(alignment: .leading, spacing: 1) {
                Text("SOUNDS")
                    .font(.system(size: 12, weight: .semibold))
                    .kerning(0.72)
                    .xnText(.secondary)
                Text("\(model.state.count) in current mix")
                    .font(.system(size: 12))
                    .xnText(.primary)
            }
            Spacer()
            saveButton
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .overlay(Divider().opacity(0.3), alignment: .bottom)
    }

    private var saveButton: some View {
        Button { model.beginSaveMix() } label: {
            Text("Save mix")
                .font(.system(size: 11, weight: .medium))
                .xnText(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.white.opacity(0.03))
                        )
                )
        }
        .buttonStyle(.plain)
        .disabled(model.state.isEmpty)
        .opacity(model.state.isEmpty ? 0.4 : 1)
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            tabItem(.sounds, label: "Sounds")
            tabItem(.mixes, label: "Mixes")
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .overlay(Divider().opacity(0.3), alignment: .bottom)
    }

    private func tabItem(_ tab: SoundsTab, label: String) -> some View {
        let isOn = model.soundsTab == tab
        return Button {
            // Switching tabs cancels an in-flight save (per spec §5.4).
            if model.saveMode.isActive { model.cancelSaveMix() }
            withAnimation(.easeOut(duration: 0.18)) { model.soundsTab = tab }
        } label: {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isOn ? Color.white : Color.white.opacity(0.45))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .padding(.bottom, 2)
                .overlay(
                    Rectangle()
                        .fill(isOn ? design.accent : Color.clear)
                        .frame(height: 1.5)
                        .padding(.top, 28),
                    alignment: .top
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
```

- [ ] **Step 11.2: Update `PopoverView` to inject `SavedMixes`**

Edit `Sources/XNoise/UI/PopoverView.swift`. In the chain of `.environmentObject(...)` modifiers at the bottom of `body`, add `.environmentObject(model.savedMixes)`. The chain should look like:

```swift
.environmentObject(model.state)
.environmentObject(model.session)
.environmentObject(model.mixer)
.environmentObject(model.focusSettings)
.environmentObject(model.favorites)
.environmentObject(model.savedMixes)
```

- [ ] **Step 11.3: Verify it builds**

Run: `cd /Users/dan/playground/x-noise && swift build`
Expected: builds clean.

- [ ] **Step 11.4: Manually verify in the popover**

Run: `cd /Users/dan/playground/x-noise && pkill -x XNoise; swift run` (background OK).
Click the menubar icon, navigate Focus → Sounds. Verify:
- Tab bar shows Sounds (active) / Mixes.
- Sounds tab: jump-pills row visible above the grid; tap a pill to jump; pill highlights as you scroll.
- Mixes tab: empty "MY MIXES" card + PRESETS list; tapping a preset applies it.
- "Save mix" button enabled only when mix has tracks; tapping shows the inline naming header with the preview row updating live as you toggle tiles.
- Esc cancels save; Enter (with a name) saves; entering an existing name → confirm sub-state.
- Drag horizontally on an active tile changes its volume in real time.

- [ ] **Step 11.5: Commit**

```bash
cd /Users/dan/playground/x-noise && git add Sources/XNoise/UI/Pages/SoundsPage.swift Sources/XNoise/UI/PopoverView.swift && git commit -m "Sounds page: tab container + inline save header overlay"
```

---

## Task 12: Focus page — add Save mix button + save header overlay

**Files:**
- Modify: `Sources/XNoise/UI/Pages/FocusPage.swift`

Add a "Save mix" text button beside "Add sound" that calls `model.beginSaveMix()`. Also surface `SaveMixHeader` over the Focus header when `model.saveMode.isActive`.

- [ ] **Step 12.1: Update `FocusPage`**

Edit `Sources/XNoise/UI/Pages/FocusPage.swift`:

Find the existing `header` computed var and wrap it so it's replaced by `SaveMixHeader` during save mode. Replace the top of `body` (the part starting with `VStack(spacing: 0) { header ...`) with:

```swift
var body: some View {
    VStack(spacing: 0) {
        if model.saveMode.isActive {
            SaveMixHeader()
        } else {
            header
        }
        ringBlock
        Hairline().padding(.horizontal, 22).padding(.top, 4).padding(.bottom, 10)
        mixSection
        Spacer(minLength: 0)
    }
    .padding(.bottom, 6)
}
```

In `mixSection`, find the row that has `playAllButton` and `addSoundButton`. Add a `saveMixButton` between them:

```swift
private var mixSection: some View {
    VStack(spacing: 8) {
        HStack {
            playAllButton
            Spacer()
            saveMixButton
            addSoundButton
        }
        .padding(.horizontal, 16)

        mixList
            .padding(.horizontal, 16)
    }
}

private var saveMixButton: some View {
    Button(action: { model.beginSaveMix() }) {
        Text("Save mix")
            .font(.system(size: 11, weight: .medium))
            .xnText(.secondary)
    }
    .buttonStyle(.plain)
    .disabled(state.isEmpty)
    .opacity(state.isEmpty ? 0.4 : 1)
    .padding(.trailing, 12)
}
```

- [ ] **Step 12.2: Verify it builds**

Run: `cd /Users/dan/playground/x-noise && swift build`
Expected: builds clean.

- [ ] **Step 12.3: Manually verify**

Run: `cd /Users/dan/playground/x-noise && pkill -x XNoise; swift run`.
Verify on the Focus page:
- "Save mix" button appears between "Pause all" and "+ Add sound", disabled when mix is empty.
- Tapping it replaces the Focus header with the inline name input. Cancel/Save behave as on the Sounds page.
- Saving navigates back to the normal Focus header; the new mix appears in the Mixes tab.

- [ ] **Step 12.4: Commit**

```bash
cd /Users/dan/playground/x-noise && git add Sources/XNoise/UI/Pages/FocusPage.swift && git commit -m "Focus page: add Save mix button + inline save header overlay"
```

---

## Task 13: Cleanup — remove unused `CategoryFilter`, presets strip, and `categoryFilter` state

**Files:**
- Modify: `Sources/XNoise/AppModel.swift`

The new design no longer uses `CategoryFilter` — sectioning is derived from the catalog. Remove the dead state/enum.

- [ ] **Step 13.1: Confirm no other call sites**

Run: `cd /Users/dan/playground/x-noise && grep -rn "CategoryFilter\|categoryFilter" Sources/ Tests/`
Expected: matches only inside `AppModel.swift`. (If matches appear elsewhere, fix those first by deleting/replacing the references; the new UI does not use them.)

- [ ] **Step 13.2: Delete the field and enum**

In `Sources/XNoise/AppModel.swift`, delete:
- The line `@Published var categoryFilter: CategoryFilter = .all`
- The entire `enum CategoryFilter` at the bottom of the file.

Also update `allTracks` since it returned `(Track, CategoryFilter)`. Replace the existing computed property with:

```swift
/// All tracks flattened across catalog categories.
var allTracks: [(track: Track, categoryId: String)] {
    categories.flatMap { cat in
        cat.tracks.map { t in (t, cat.id) }
    }
}
```

- [ ] **Step 13.3: Update `SoundsBrowseView` to use the new `allTracks` shape**

In `Sources/XNoise/UI/Pages/SoundsBrowseView.swift`, the line:
```swift
let favTracks = model.allTracks.map(\.track).filter { favorites.contains($0.id) }
```
already uses `.track` so it remains correct after the tuple rename. Verify nothing else in that file references `.filter` (the old `CategoryFilter` value); it should not.

- [ ] **Step 13.4: Verify it builds**

Run: `cd /Users/dan/playground/x-noise && swift build`
Expected: builds clean.

- [ ] **Step 13.5: Run the full test suite**

Run: `cd /Users/dan/playground/x-noise && swift test`
Expected: all tests pass.

- [ ] **Step 13.6: Commit**

```bash
cd /Users/dan/playground/x-noise && git add Sources/XNoise/AppModel.swift && git commit -m "Remove unused CategoryFilter enum and categoryFilter state"
```

---

## Task 14: Final smoke pass

- [ ] **Step 14.1: Full build + test**

Run: `cd /Users/dan/playground/x-noise && swift build && swift test`
Expected: clean build, all tests pass.

- [ ] **Step 14.2: Manual end-to-end flow**

Run: `cd /Users/dan/playground/x-noise && pkill -x XNoise; swift run`. Walk through:

1. Focus page renders unchanged at first launch.
2. Click "+ Add sound" → Sounds tab loads.
3. Tab bar shows Sounds (active) / Mixes. Click Mixes → empty MY MIXES card + PRESETS list.
4. Click Sounds. Tap a few tiles to add them. Drag horizontally on an active tile → its volume bar moves; verify audible change.
5. Tap "Save mix" → header collapses to a name field. Type "Test mix" → preview row updates as you toggle tiles. Press Enter → header restores. Switch to Mixes → "Test mix" appears at top of MY MIXES with track icon stack and sub-line.
6. Tap "Test mix" → mix loads (verify track set matches). The row gets the accent border + ▶ ACTIVE chip.
7. Click ⋯ on Test mix → Delete → inline confirm → Delete → row disappears.
8. Try saving with an existing preset name (e.g., "Deep Focus") → confirm sub-state appears with [Save as new] [Overwrite]. Save as new → "Deep Focus (2)" appears. Overwrite a saved mix → saved mix tracks update without changing id/name.
9. Esc / Cancel during naming returns to the normal header.
10. Save button disabled when current mix is empty.

- [ ] **Step 14.3: Commit any final fixes**

If issues surfaced, fix and commit each as a focused change.

```bash
cd /Users/dan/playground/x-noise && git status
```
Expected: clean working tree.
