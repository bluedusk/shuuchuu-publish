# Soundtrack Tags Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let users tag saved soundtracks (free-form, max 3 per soundtrack) and filter the Soundtracks tab by tag intersection via a chip bar above the list.

**Architecture:** A `tags: [String]` field on `WebSoundtrack` (lowercase, normalized, capped at 3). A `SoundtracksFilterState` in-memory store on `AppModel` holds the user's selected filter chips (resets on launch). Three new SwiftUI components: `TagChipBar`, `TagEditorStrip`, `TagAutocompletePopover`. Filter chips above the list filter the existing `ForEach`; the editor lives inside the active row's expanded view, below the iframe.

**Tech Stack:** Swift 6 / SwiftUI / Combine. macOS 26+ menubar popover. Existing soundtracks subsystem (see `docs/superpowers/specs/2026-04-27-soundtracks-design.md`).

**Spec:** `docs/superpowers/specs/2026-05-03-soundtrack-tags-design.md`

---

## File map

**Modify:**
- `Sources/Shuuchuu/Models/WebSoundtrack.swift` — add `tags: [String]` with custom decode clamping to 3.
- `Sources/Shuuchuu/Models/SoundtracksLibrary.swift` — `setTags(id:tags:)`, `tagsInUse` derivation.
- `Sources/Shuuchuu/AppModel.swift` — `setSoundtrackTags(id:tags:)`, vend `filterState`.
- `Sources/Shuuchuu/UI/Pages/SoundtracksTab.swift` — render chip bar, apply filter to `ForEach`, empty-results state.
- `Sources/Shuuchuu/UI/Components/SoundtrackChipRow.swift` — embed `TagEditorStrip` inside the expanded view (below iframe, above Done).
- `Tests/ShuuchuuTests/SoundtrackPersistenceTests.swift` — extend round-trip cases to cover `tags`.

**Create:**
- `Sources/Shuuchuu/Models/SoundtracksFilterState.swift` — `@MainActor, ObservableObject` filter store.
- `Sources/Shuuchuu/UI/Components/TagChipBar.swift` — horizontal-scroll filter chip bar.
- `Sources/Shuuchuu/UI/Components/TagEditorStrip.swift` — chips with `×` + inline `+ add` text field.
- `Sources/Shuuchuu/UI/Components/TagAutocompletePopover.swift` — anchored suggestion list.
- `Sources/Shuuchuu/Models/TagNormalize.swift` — `normalize(_:) -> String` helper used by both model and editor.
- `Tests/ShuuchuuTests/WebSoundtrackTagsTests.swift` — normalization, cap, decode clamping.
- `Tests/ShuuchuuTests/SoundtracksLibraryTagsTests.swift` — `setTags`, `tagsInUse`, orphan removal.
- `Tests/ShuuchuuTests/SoundtracksFilterStateTests.swift` — toggle, intersection, orphan-tag handling.

---

## Conventions

- Build/run: `swift build` and `swift test --filter <suite>` from repo root.
- Single-line comments only when explaining a non-obvious decision; default to no comments.
- `@EnvironmentObject` for view-injected ObservableObjects.
- Each task ends with a `swift test` (or `swift build` for UI tasks) verification + a single commit. Commit messages use imperative present tense, no scope prefix.

---

### Task 1: TagNormalize helper

**Files:**
- Create: `Sources/Shuuchuu/Models/TagNormalize.swift`
- Test: `Tests/ShuuchuuTests/WebSoundtrackTagsTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `Tests/ShuuchuuTests/WebSoundtrackTagsTests.swift`:

```swift
import XCTest
@testable import Shuuchuu

final class WebSoundtrackTagsTests: XCTestCase {

    func testNormalizeLowercases() {
        XCTAssertEqual(TagNormalize.normalize("Lo-Fi"), "lo-fi")
    }

    func testNormalizeTrimsWhitespace() {
        XCTAssertEqual(TagNormalize.normalize("  study  "), "study")
    }

    func testNormalizeReturnsNilForEmpty() {
        XCTAssertNil(TagNormalize.normalize(""))
        XCTAssertNil(TagNormalize.normalize("   "))
    }

    func testNormalizeListDeduplicatesPreservingOrder() {
        XCTAssertEqual(
            TagNormalize.normalize(list: ["Study", "lo-fi", "STUDY", "rain"]),
            ["study", "lo-fi", "rain"]
        )
    }

    func testNormalizeListClampsToThree() {
        XCTAssertEqual(
            TagNormalize.normalize(list: ["a", "b", "c", "d", "e"]),
            ["a", "b", "c"]
        )
    }

    func testNormalizeListDropsEmpties() {
        XCTAssertEqual(
            TagNormalize.normalize(list: ["", "study", "  "]),
            ["study"]
        )
    }
}
```

- [ ] **Step 2: Run tests — verify they fail**

```
swift test --filter WebSoundtrackTagsTests
```

Expected: compile error — `TagNormalize` undefined.

- [ ] **Step 3: Implement `TagNormalize`**

Create `Sources/Shuuchuu/Models/TagNormalize.swift`:

```swift
import Foundation

enum TagNormalize {
    static let maxTagsPerSoundtrack = 3

    /// Lowercased, trimmed. Returns nil if the result is empty.
    static func normalize(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Normalize each entry, drop empties, dedupe preserving first-occurrence
    /// order, then clamp to `maxTagsPerSoundtrack`.
    static func normalize(list: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for raw in list {
            guard let n = normalize(raw), !seen.contains(n) else { continue }
            seen.insert(n)
            out.append(n)
            if out.count == maxTagsPerSoundtrack { break }
        }
        return out
    }
}
```

- [ ] **Step 4: Run tests — verify they pass**

```
swift test --filter WebSoundtrackTagsTests
```

Expected: 6 tests pass.

- [ ] **Step 5: Commit**

```
git add Sources/Shuuchuu/Models/TagNormalize.swift Tests/ShuuchuuTests/WebSoundtrackTagsTests.swift
git commit -m "Add TagNormalize for soundtrack tag normalization"
```

---

### Task 2: WebSoundtrack.tags field

**Files:**
- Modify: `Sources/Shuuchuu/Models/WebSoundtrack.swift`
- Modify: `Tests/ShuuchuuTests/SoundtrackPersistenceTests.swift`

- [ ] **Step 1: Write the failing tests**

Append to `Tests/ShuuchuuTests/SoundtrackPersistenceTests.swift` (above the `extension` block):

```swift
    func testWebSoundtrackTagsRoundTrip() throws {
        let original = WebSoundtrack(
            id: UUID(),
            kind: .youtube,
            url: "https://www.youtube.com/embed/abc?enablejsapi=1",
            title: "lofi",
            volume: 0.5,
            addedAt: Date(timeIntervalSince1970: 1_700_000_000),
            tags: ["lo-fi", "study"]
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(WebSoundtrack.self, from: data)
        XCTAssertEqual(decoded.tags, ["lo-fi", "study"])
    }

    func testWebSoundtrackDecodesMissingTagsAsEmpty() throws {
        let json = """
        {
          "id":"11111111-2222-3333-4444-555555555555",
          "kind":"youtube",
          "url":"https://www.youtube.com/embed/abc?enablejsapi=1",
          "volume":0.5,
          "addedAt":700000000
        }
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(WebSoundtrack.self, from: json)
        XCTAssertEqual(decoded.tags, [])
    }

    func testWebSoundtrackDecodeClampsTagsToThree() throws {
        let json = """
        {
          "id":"11111111-2222-3333-4444-555555555555",
          "kind":"youtube",
          "url":"https://www.youtube.com/embed/abc?enablejsapi=1",
          "volume":0.5,
          "addedAt":700000000,
          "tags":["a","b","c","d","e"]
        }
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(WebSoundtrack.self, from: json)
        XCTAssertEqual(decoded.tags, ["a", "b", "c"])
    }
```

- [ ] **Step 2: Run tests — verify they fail**

```
swift test --filter SoundtrackPersistenceTests
```

Expected: compile errors — `WebSoundtrack.init` has no `tags` parameter; `decoded.tags` undefined.

- [ ] **Step 3: Add `tags` to `WebSoundtrack`**

Edit `Sources/Shuuchuu/Models/WebSoundtrack.swift`. Replace the entire struct with:

```swift
struct WebSoundtrack: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let kind: SoundtrackURL.Kind
    let url: String
    var title: String?
    var volume: Double
    let addedAt: Date
    var tags: [String]

    init(
        id: UUID,
        kind: SoundtrackURL.Kind,
        url: String,
        title: String?,
        volume: Double,
        addedAt: Date,
        tags: [String] = []
    ) {
        self.id = id
        self.kind = kind
        self.url = url
        self.title = title
        self.volume = volume
        self.addedAt = addedAt
        self.tags = TagNormalize.normalize(list: tags)
    }

    private enum CodingKeys: String, CodingKey {
        case id, kind, url, title, volume, addedAt, tags
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        kind = try c.decode(SoundtrackURL.Kind.self, forKey: .kind)
        url = try c.decode(String.self, forKey: .url)
        title = try c.decodeIfPresent(String.self, forKey: .title)
        volume = try c.decode(Double.self, forKey: .volume)
        addedAt = try c.decode(Date.self, forKey: .addedAt)
        let raw = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        tags = TagNormalize.normalize(list: raw)
    }
}
```

(The `extension WebSoundtrack` with `youtubeVideoId` etc. is unchanged — leave it as-is below.)

- [ ] **Step 4: Run tests — verify they pass**

```
swift test --filter SoundtrackPersistenceTests --filter WebSoundtrackTagsTests
```

Expected: all green (existing 8 + new 3 + Task 1's 6).

- [ ] **Step 5: Commit**

```
git add Sources/Shuuchuu/Models/WebSoundtrack.swift Tests/ShuuchuuTests/SoundtrackPersistenceTests.swift
git commit -m "Add tags field to WebSoundtrack with decode clamping"
```

---

### Task 3: SoundtracksLibrary.setTags + tagsInUse

**Files:**
- Modify: `Sources/Shuuchuu/Models/SoundtracksLibrary.swift`
- Create: `Tests/ShuuchuuTests/SoundtracksLibraryTagsTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `Tests/ShuuchuuTests/SoundtracksLibraryTagsTests.swift`:

```swift
import XCTest
@testable import Shuuchuu

@MainActor
final class SoundtracksLibraryTagsTests: XCTestCase {

    private func ephemeralLib() -> SoundtracksLibrary {
        let suite = "test.tags.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        return SoundtracksLibrary(defaults: d)
    }

    private func add(_ lib: SoundtracksLibrary, _ raw: String) -> WebSoundtrack {
        switch SoundtrackURL.parse(raw) {
        case .success(let p): return lib.add(parsed: p)
        case .failure(let e): fatalError("\(e)")
        }
    }

    func testSetTagsNormalizesAndPersists() {
        let lib = ephemeralLib()
        let a = add(lib, "https://youtu.be/abc")
        lib.setTags(id: a.id, tags: ["Study", "lo-fi", "study"])
        XCTAssertEqual(lib.entry(id: a.id)?.tags, ["study", "lo-fi"])
    }

    func testSetTagsClampsToThree() {
        let lib = ephemeralLib()
        let a = add(lib, "https://youtu.be/abc")
        lib.setTags(id: a.id, tags: ["a", "b", "c", "d"])
        XCTAssertEqual(lib.entry(id: a.id)?.tags, ["a", "b", "c"])
    }

    func testTagsInUseEmptyByDefault() {
        let lib = ephemeralLib()
        _ = add(lib, "https://youtu.be/abc")
        XCTAssertEqual(lib.tagsInUse, [])
    }

    func testTagsInUseSortsByUsageThenAlpha() {
        let lib = ephemeralLib()
        let a = add(lib, "https://youtu.be/aaa")
        let b = add(lib, "https://youtu.be/bbb")
        let c = add(lib, "https://youtu.be/ccc")
        lib.setTags(id: a.id, tags: ["lo-fi", "study"])
        lib.setTags(id: b.id, tags: ["lo-fi", "rain"])
        lib.setTags(id: c.id, tags: ["lo-fi"])
        // lo-fi: 3, study: 1, rain: 1 — ties alpha → rain, study
        XCTAssertEqual(lib.tagsInUse, ["lo-fi", "rain", "study"])
    }

    func testTagsInUseDropsOrphans() {
        let lib = ephemeralLib()
        let a = add(lib, "https://youtu.be/abc")
        lib.setTags(id: a.id, tags: ["rain"])
        XCTAssertEqual(lib.tagsInUse, ["rain"])
        lib.setTags(id: a.id, tags: [])
        XCTAssertEqual(lib.tagsInUse, [])
    }
}
```

- [ ] **Step 2: Run tests — verify they fail**

```
swift test --filter SoundtracksLibraryTagsTests
```

Expected: compile errors — `setTags` and `tagsInUse` undefined.

- [ ] **Step 3: Add `setTags` and `tagsInUse` to `SoundtracksLibrary`**

In `Sources/Shuuchuu/Models/SoundtracksLibrary.swift`, add these methods inside the class (e.g., after `setTitle`):

```swift
    func setTags(id: UUID, tags: [String]) {
        guard let i = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[i].tags = TagNormalize.normalize(list: tags)
    }

    /// Union of tags in use across all soundtracks, sorted by usage count
    /// (descending) with ties broken alphabetically.
    var tagsInUse: [String] {
        var counts: [String: Int] = [:]
        for entry in entries {
            for tag in entry.tags { counts[tag, default: 0] += 1 }
        }
        return counts.keys.sorted { lhs, rhs in
            let lc = counts[lhs]!, rc = counts[rhs]!
            return lc == rc ? lhs < rhs : lc > rc
        }
    }
```

- [ ] **Step 4: Run tests — verify they pass**

```
swift test --filter SoundtracksLibraryTagsTests
```

Expected: 5 tests pass.

- [ ] **Step 5: Commit**

```
git add Sources/Shuuchuu/Models/SoundtracksLibrary.swift Tests/ShuuchuuTests/SoundtracksLibraryTagsTests.swift
git commit -m "Add setTags and tagsInUse to SoundtracksLibrary"
```

---

### Task 4: SoundtracksFilterState

**Files:**
- Create: `Sources/Shuuchuu/Models/SoundtracksFilterState.swift`
- Create: `Tests/ShuuchuuTests/SoundtracksFilterStateTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `Tests/ShuuchuuTests/SoundtracksFilterStateTests.swift`:

```swift
import XCTest
@testable import Shuuchuu

@MainActor
final class SoundtracksFilterStateTests: XCTestCase {

    func testEmptyByDefault() {
        let f = SoundtracksFilterState()
        XCTAssertTrue(f.selected.isEmpty)
        XCTAssertFalse(f.isActive)
    }

    func testToggleAddsAndRemoves() {
        let f = SoundtracksFilterState()
        f.toggle("lo-fi")
        XCTAssertEqual(f.selected, ["lo-fi"])
        f.toggle("study")
        XCTAssertEqual(f.selected, ["lo-fi", "study"])
        f.toggle("lo-fi")
        XCTAssertEqual(f.selected, ["study"])
    }

    func testIsActiveTrueWhenAnyTagSelected() {
        let f = SoundtracksFilterState()
        f.toggle("lo-fi")
        XCTAssertTrue(f.isActive)
    }

    func testMatchesIntersection() {
        let f = SoundtracksFilterState()
        f.toggle("lo-fi")
        f.toggle("study")
        XCTAssertTrue(f.matches(tags: ["lo-fi", "study", "rain"]))
        XCTAssertFalse(f.matches(tags: ["lo-fi"]))
        XCTAssertFalse(f.matches(tags: []))
    }

    func testMatchesEverythingWhenInactive() {
        let f = SoundtracksFilterState()
        XCTAssertTrue(f.matches(tags: []))
        XCTAssertTrue(f.matches(tags: ["anything"]))
    }

    func testReconcileDropsOrphanedSelections() {
        let f = SoundtracksFilterState()
        f.toggle("lo-fi")
        f.toggle("study")
        f.reconcile(against: ["lo-fi", "rain"])
        XCTAssertEqual(f.selected, ["lo-fi"])
    }

    func testClear() {
        let f = SoundtracksFilterState()
        f.toggle("lo-fi")
        f.toggle("study")
        f.clear()
        XCTAssertTrue(f.selected.isEmpty)
    }
}
```

- [ ] **Step 2: Run tests — verify they fail**

```
swift test --filter SoundtracksFilterStateTests
```

Expected: compile error — `SoundtracksFilterState` undefined.

- [ ] **Step 3: Implement `SoundtracksFilterState`**

Create `Sources/Shuuchuu/Models/SoundtracksFilterState.swift`:

```swift
import Foundation
import Combine

@MainActor
final class SoundtracksFilterState: ObservableObject {
    @Published private(set) var selected: [String] = []

    var isActive: Bool { !selected.isEmpty }

    func toggle(_ tag: String) {
        guard let n = TagNormalize.normalize(tag) else { return }
        if let i = selected.firstIndex(of: n) {
            selected.remove(at: i)
        } else {
            selected.append(n)
        }
    }

    func clear() { selected.removeAll() }

    /// True when the soundtrack's tag set is a superset of every selected tag.
    /// Empty selection matches everything.
    func matches(tags: [String]) -> Bool {
        guard isActive else { return true }
        let set = Set(tags)
        return selected.allSatisfy(set.contains)
    }

    /// Drop selections that no longer appear in `available`. Called by the view
    /// layer when the library's `tagsInUse` shrinks (e.g., last user of a tag
    /// was removed).
    func reconcile(against available: [String]) {
        let valid = Set(available)
        selected.removeAll { !valid.contains($0) }
    }
}
```

- [ ] **Step 4: Run tests — verify they pass**

```
swift test --filter SoundtracksFilterStateTests
```

Expected: 7 tests pass.

- [ ] **Step 5: Commit**

```
git add Sources/Shuuchuu/Models/SoundtracksFilterState.swift Tests/ShuuchuuTests/SoundtracksFilterStateTests.swift
git commit -m "Add SoundtracksFilterState for in-memory chip filter"
```

---

### Task 5: AppModel wiring

**Files:**
- Modify: `Sources/Shuuchuu/AppModel.swift`

- [ ] **Step 1: Add `setSoundtrackTags` and `soundtracksFilter`**

In `Sources/Shuuchuu/AppModel.swift`, near the other soundtrack mutators (around `setSoundtrackVolume`):

```swift
    let soundtracksFilter = SoundtracksFilterState()

    func setSoundtrackTags(id: UUID, tags: [String]) {
        soundtracksLibrary.setTags(id: id, tags: tags)
    }
```

The `let soundtracksFilter` declaration goes near other `let` peers (e.g., `let soundtracksLibrary` at line ~40). Since `SoundtracksFilterState` is `@MainActor` and `AppModel` is `@MainActor`, no extra annotation is needed.

- [ ] **Step 2: Build to verify wiring compiles**

```
swift build
```

Expected: clean build, no warnings.

- [ ] **Step 3: Inject `soundtracksFilter` into the SwiftUI environment**

In `Sources/Shuuchuu/UI/PopoverView.swift`, line 68 currently reads:

```swift
        .environmentObject(model.soundtracksLibrary)
```

Add a new line directly after it:

```swift
        .environmentObject(model.soundtracksFilter)
```

- [ ] **Step 4: Build**

```
swift build
```

Expected: clean.

- [ ] **Step 5: Commit**

```
git add Sources/Shuuchuu/AppModel.swift Sources/Shuuchuu/UI/PopoverView.swift
git commit -m "Wire SoundtracksFilterState into AppModel and view env"
```

---

### Task 6: TagChipBar component

**Files:**
- Create: `Sources/Shuuchuu/UI/Components/TagChipBar.swift`

- [ ] **Step 1: Implement `TagChipBar`**

Create `Sources/Shuuchuu/UI/Components/TagChipBar.swift`:

```swift
import SwiftUI

/// Horizontal-scrolling chip bar above the soundtrack list. One chip per tag in
/// `tags`. Tap to toggle `filter.selected`. Hidden by the parent when `tags` is
/// empty.
struct TagChipBar: View {
    let tags: [String]
    @ObservedObject var filter: SoundtracksFilterState
    @EnvironmentObject var design: DesignSettings

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(tags, id: \.self) { tag in
                    chip(tag)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
        }
    }

    private func chip(_ tag: String) -> some View {
        let active = filter.selected.contains(tag)
        return Button(action: { filter.toggle(tag) }) {
            Text(tag)
                .font(.system(size: 10))
                .foregroundStyle(active ? design.accent : Color.white.opacity(0.65))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Capsule()
                        .fill(active ? design.accent.opacity(0.15)
                                     : Color.white.opacity(0.04))
                )
                .overlay(
                    Capsule()
                        .strokeBorder(
                            active ? design.accent : Color.white.opacity(0.08),
                            lineWidth: 1
                        )
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
```

- [ ] **Step 2: Build**

```
swift build
```

Expected: clean (the component isn't referenced yet).

- [ ] **Step 3: Commit**

```
git add Sources/Shuuchuu/UI/Components/TagChipBar.swift
git commit -m "Add TagChipBar component"
```

---

### Task 7: TagAutocompletePopover component

**Files:**
- Create: `Sources/Shuuchuu/UI/Components/TagAutocompletePopover.swift`

- [ ] **Step 1: Implement `TagAutocompletePopover`**

Create `Sources/Shuuchuu/UI/Components/TagAutocompletePopover.swift`:

```swift
import SwiftUI

/// Suggestion list for the inline tag input. Caller owns input state; this view
/// renders matches and emits `onPick` when the user taps one.
struct TagAutocompletePopover: View {
    let suggestions: [String]
    let onPick: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(suggestions.prefix(5), id: \.self) { tag in
                Button(action: { onPick(tag) }) {
                    Text(tag)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.white.opacity(0.85))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(minWidth: 120, maxWidth: 200)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.black.opacity(0.85))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        )
    }

    /// Filters `pool` by case-insensitive prefix match against `query`,
    /// excluding any tag in `exclude`. Caps at 5 results.
    static func suggestions(query: String, pool: [String], exclude: Set<String>) -> [String] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return [] }
        return pool
            .filter { !exclude.contains($0) && $0.hasPrefix(q) }
            .prefix(5)
            .map { $0 }
    }
}
```

- [ ] **Step 2: Build**

```
swift build
```

Expected: clean.

- [ ] **Step 3: Commit**

```
git add Sources/Shuuchuu/UI/Components/TagAutocompletePopover.swift
git commit -m "Add TagAutocompletePopover suggestion list"
```

---

### Task 8: TagEditorStrip component

**Files:**
- Create: `Sources/Shuuchuu/UI/Components/TagEditorStrip.swift`

- [ ] **Step 1: Implement `TagEditorStrip`**

Create `Sources/Shuuchuu/UI/Components/TagEditorStrip.swift`:

```swift
import SwiftUI

/// Inline tag editor for a single soundtrack. Shown inside the active row's
/// expanded view (below the iframe). Renders chips with `×` removal and a
/// `+ add` chip that becomes a text field with autocomplete.
struct TagEditorStrip: View {
    let tags: [String]
    let pool: [String]                  // for autocomplete (library-wide tagsInUse)
    let onChange: ([String]) -> Void

    @EnvironmentObject var design: DesignSettings
    @State private var editing = false
    @State private var draft = ""
    @FocusState private var inputFocused: Bool

    private var atCap: Bool { tags.count >= TagNormalize.maxTagsPerSoundtrack }

    private var suggestions: [String] {
        TagAutocompletePopover.suggestions(
            query: draft,
            pool: pool,
            exclude: Set(tags)
        )
    }

    var body: some View {
        HStack(spacing: 6) {
            Text("Tags")
                .font(.system(size: 10))
                .foregroundStyle(Color.white.opacity(0.45))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(tags, id: \.self) { tag in
                        chip(tag)
                    }
                    if editing {
                        inputField
                    } else {
                        addChip
                    }
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    private func chip(_ tag: String) -> some View {
        HStack(spacing: 4) {
            Text(tag)
                .font(.system(size: 10))
                .foregroundStyle(Color.white.opacity(0.75))
            Button(action: { remove(tag) }) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.45))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(Color.white.opacity(0.04)))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
        .transition(.opacity)
    }

    private var addChip: some View {
        Button(action: beginEditing) {
            HStack(spacing: 3) {
                Image(systemName: "plus").font(.system(size: 9, weight: .semibold))
                Text("add").font(.system(size: 10))
            }
            .foregroundStyle(Color.white.opacity(atCap ? 0.22 : 0.45))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .overlay(
                Capsule()
                    .strokeBorder(
                        Color.white.opacity(0.25),
                        style: StrokeStyle(lineWidth: 1, dash: [3, 2])
                    )
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(atCap)
        .help(atCap ? "Up to 3 tags" : "")
    }

    private var inputField: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField("", text: $draft)
                .textFieldStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(Color.white)
                .frame(width: 80)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.white.opacity(0.06)))
                .overlay(Capsule().strokeBorder(design.accent, lineWidth: 1))
                .focused($inputFocused)
                .onSubmit(commit)
                .onExitCommand { cancelEditing() }
                .onChange(of: inputFocused) { _, focused in
                    if !focused { commit() }
                }

            if !suggestions.isEmpty {
                TagAutocompletePopover(
                    suggestions: suggestions,
                    onPick: { pick in
                        draft = pick
                        commit()
                    }
                )
            }
        }
    }

    private func beginEditing() {
        guard !atCap else { return }
        draft = ""
        editing = true
        DispatchQueue.main.async { inputFocused = true }
    }

    private func commit() {
        guard editing else { return }
        defer { cancelEditing() }
        guard let n = TagNormalize.normalize(draft), !tags.contains(n) else { return }
        guard !atCap else { return }
        onChange(tags + [n])
    }

    private func cancelEditing() {
        editing = false
        draft = ""
    }

    private func remove(_ tag: String) {
        withAnimation(.easeOut(duration: 0.15)) {
            onChange(tags.filter { $0 != tag })
        }
    }
}
```

- [ ] **Step 2: Build**

```
swift build
```

Expected: clean.

- [ ] **Step 3: Commit**

```
git add Sources/Shuuchuu/UI/Components/TagEditorStrip.swift
git commit -m "Add TagEditorStrip with chip removal and inline add field"
```

---

### Task 9: Wire TagEditorStrip into expanded row

**Files:**
- Modify: `Sources/Shuuchuu/UI/Components/SoundtrackChipRow.swift`

The row currently shows the iframe + a Done button when `isExpanded`. Insert the editor strip between them.

- [ ] **Step 1: Add inputs and callback to `SoundtrackChipRow`**

In `Sources/Shuuchuu/UI/Components/SoundtrackChipRow.swift`, extend the struct's stored properties (right under `let onDelete: () -> Void`):

```swift
    let pool: [String]
    let onTagsChange: ([String]) -> Void
```

- [ ] **Step 2: Insert the editor strip in the expanded view**

Inside `body`, replace the existing `if isExpanded { ... }` block with:

```swift
            if isExpanded {
                controller.playerView()
                    .frame(height: 220)
                    .padding(.horizontal, 8)
                    .padding(.top, 8)

                TagEditorStrip(
                    tags: soundtrack.tags,
                    pool: pool,
                    onChange: onTagsChange
                )

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
                .padding(.top, 4)
                .padding(.bottom, 4)
            }
```

- [ ] **Step 3: Build (will fail at the call site)**

```
swift build
```

Expected: error in `SoundtracksTab.swift` — missing `pool` / `onTagsChange` arguments. That's fine; Task 10 fixes it.

---

### Task 10: Wire chip bar + editor into SoundtracksTab

**Files:**
- Modify: `Sources/Shuuchuu/UI/Pages/SoundtracksTab.swift`

- [ ] **Step 1: Add `@EnvironmentObject` for filter state**

In `Sources/Shuuchuu/UI/Pages/SoundtracksTab.swift`, near the other env objects:

```swift
    @EnvironmentObject var filter: SoundtracksFilterState
```

- [ ] **Step 2: Compute filtered entries and the tag pool**

Add these computed properties to the struct:

```swift
    private var pool: [String] { library.tagsInUse }

    private var filteredEntries: [WebSoundtrack] {
        guard filter.isActive else { return library.entries }
        return library.entries.filter { filter.matches(tags: $0.tags) }
    }
```

- [ ] **Step 3: Render the chip bar and apply the filter**

Replace the existing `ScrollView { ... }` block in `body` with:

```swift
            if !pool.isEmpty {
                TagChipBar(tags: pool, filter: filter)
            }

            ScrollView {
                VStack(spacing: 8) {
                    if library.entries.isEmpty {
                        emptyCard
                    } else if filter.isActive && filteredEntries.isEmpty {
                        noMatchesCard
                    } else {
                        ForEach(filteredEntries) { entry in
                            SoundtrackChipRow(
                                soundtrack: entry,
                                isActive: model.mode == .soundtrack(entry.id),
                                isExpanded: expandedRowId == entry.id,
                                controller: model.soundtrackController,
                                pulseChevron: model.signInRequired && model.mode == .soundtrack(entry.id),
                                onTap: { tapRow(entry) },
                                onExpandToggle: { toggleExpand(entry) },
                                onDelete: { model.removeSoundtrack(id: entry.id) },
                                pool: pool,
                                onTagsChange: { tags in
                                    model.setSoundtrackTags(id: entry.id, tags: tags)
                                }
                            )
                        }
                    }

                    if shouldShowSpotifyHint {
                        spotifyHint.padding(.top, 6)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 16)
            }
            .scrollIndicators(.never)
```

- [ ] **Step 4: Add the no-matches card**

Add this computed property next to `emptyCard`:

```swift
    private var noMatchesCard: some View {
        VStack(spacing: 4) {
            Text("No soundtracks match the selected tags")
                .font(.system(size: 11))
                .foregroundStyle(Color.white.opacity(0.45))
            Button(action: { filter.clear() }) {
                Text("Clear filters")
                    .font(.system(size: 10))
                    .foregroundStyle(design.accent)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
```

- [ ] **Step 5: Reconcile filter when the pool changes**

Add this modifier on the outer `VStack` in `body`:

```swift
        .onChange(of: pool) { _, newPool in
            filter.reconcile(against: newPool)
        }
```

- [ ] **Step 6: Build**

```
swift build
```

Expected: clean.

- [ ] **Step 7: Run all tests**

```
swift test
```

Expected: 99 baseline tests + 6 + 3 + 5 + 7 = 120 pass. Adjust the count if other tasks landed in parallel; the requirement is "no failures, no decrease."

- [ ] **Step 8: Commit**

```
git add Sources/Shuuchuu/UI/Components/SoundtrackChipRow.swift Sources/Shuuchuu/UI/Pages/SoundtracksTab.swift
git commit -m "Render TagChipBar and inline TagEditorStrip on Soundtracks tab"
```

---

### Task 11: Manual smoke test

- [ ] **Step 1: Relaunch the app**

```
pkill -x Shuuchuu; swift run
```

Expected: build succeeds, app launches, 集中 logo appears in menubar.

- [ ] **Step 2: Walk the happy path**

Open the popover, navigate to Sounds → Soundtracks tab.

1. **No tags state** — chip bar is hidden if no soundtrack has tags.
2. **Add a soundtrack** (paste a YouTube URL). It auto-activates.
3. **Tap the `⌃` chevron** to expand the row.
4. **Tap `+ add`**, type `study`, press Return. Chip `[study ×]` appears in the editor; chip bar above shows `[ study ]`.
5. **Type a second tag** `lo-fi`. Editor now shows two chips.
6. **Add a third tag.** `+ add` chip greys out with tooltip `Up to 3 tags`.
7. **Try to add a fourth.** Confirm the chip stays disabled.
8. **Remove a tag** via its `×`. `+ add` re-enables.
9. **Tap a chip in the chip bar** above the list. List filters. Tap a second chip — list narrows further (intersection).
10. **Add a chip selection that no soundtrack matches** — the no-matches card appears with `Clear filters`. Tap it; filter clears, full list returns.
11. **Add a tag, then remove the soundtrack that had it.** Confirm the chip drops from the chip bar.
12. **Quit and relaunch.** Confirm tags persist; confirm the filter chip-bar selection does NOT persist (chips start unselected).

- [ ] **Step 3: Note any defects**

If any step misbehaves, write the symptom and the affected file, then either fix inline (with a follow-up commit) or open a follow-up task.

- [ ] **Step 4: Final commit (if fixes were needed)**

If smoke uncovered fixes:

```
git add <fixed files>
git commit -m "Fix <specific defect> uncovered in tags smoke test"
```

If no fixes were needed, skip — Task 10's commit is the last one.

---

## Self-review checklist (for the implementer)

Before marking complete:

- All `swift test` filters pass; no warnings introduced.
- Manual smoke (Task 11) walked end-to-end without surprises.
- No `TODO` / `FIXME` left behind.
- `git status` clean (or only the intentional uncommitted scene/shader files from before this plan started).
- Plan checklist items in this file all checked off.
