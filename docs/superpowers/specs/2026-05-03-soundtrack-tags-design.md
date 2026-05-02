# Soundtrack Tags — Design Spec

**Date:** 2026-05-03
**Status:** Draft, approved in brainstorming session
**Audience:** Engineering plan
**Target:** macOS 26+ menubar popover (340×540pt)
**Builds on:** [`2026-04-27-soundtracks-design.md`](2026-04-27-soundtracks-design.md)

---

## 1. Overview

The soundtracks library has no organization beyond insertion order. As users accumulate YouTube and Spotify entries, finding "the lo-fi one I was using last week" becomes a scroll-and-squint exercise. This spec adds **free-form tags** to soundtracks plus a chip-bar filter on the Soundtracks tab.

Tags are scoped to soundtracks only — the ambient mix and saved mixes are out of scope.

### Goals

- Let users label soundtracks with up to 3 free-form tags.
- Filter the Soundtracks tab by tag intersection (multi-select).
- Keep the collapsed-row visual unchanged — tags surface only inside the active row's expanded view and on the chip bar.

### Non-goals

- Tags on catalog tracks or saved mixes.
- A separate tag-management screen.
- Renaming a tag globally across soundtracks (workaround: untag the old one, add the new one on each soundtrack).
- Per-tag colors or icons.
- Suggested or smart tags (no LLM, no inference).
- Tag-driven recommendation or auto-activation.

---

## 2. Data model

```swift
struct WebSoundtrack {
    // ... existing fields
    var tags: [String]   // lowercase, deduplicated, ordered (insertion order), max 3
}
```

- **Free-form, lowercase-normalized.** `"Lo-Fi"` and `"lo-fi"` collapse to one tag — no fragmentation from casing or whitespace. Trim leading/trailing whitespace on commit.
- **Hard cap of 3 tags per soundtrack.** Enforced on write; decode also clamps to the first 3 as a safety net.
- **Stored on the soundtrack, not as a separate library entity.** The "tags in use" set is derived as the union across all soundtracks.
- **Persistence:** rides existing `shuuchuu.savedSoundtracks` JSON encoding. `tags` decodes with default `[]` for back-compat with v1 entries.

---

## 3. UI

### 3.1 Chip bar (filter)

Rendered above the soundtrack list, below the section header on the Soundtracks tab.

```
┌───────────────────────────────────────────┐
│  MY SOUNDTRACKS   8                  +    │
│  [ lo-fi ] [ study ] [ rain ] [ class…]…  │  ← horizontal scroll
├───────────────────────────────────────────┤
│  <rows>                                   │
└───────────────────────────────────────────┘
```

- **Source:** union of tags across all soundtracks. Sort: descending by usage count, ties broken by alphabetical.
- **Inactive chip:** `white/4%` fill, `white/8%` border, `10pt white/65%` text, 10pt corner radius, ~6×3pt padding.
- **Active chip:** `accent/15%` fill, accent border 1pt, accent text. Tap an active chip to deselect.
- **Multi-select = intersection.** With chips `lo-fi` + `study` both active, only soundtracks tagged with **both** appear. (Empty intersection is fine; see §3.4.)
- **Visibility:** chip bar is hidden when the union of tags is empty (no soundtrack has any tag yet).
- **Horizontal scroll** with native macOS scroll-indicator-on-hover semantics. No wrap.
- **No "Untagged" chip.** Default (no chips active) shows everything; that's how you find untagged ones.

### 3.2 Tag editor (in expanded row)

The expanded active-row view (§4.5 of the soundtracks spec) currently shows the iframe + `Done` button. Add a tag editor strip **below the iframe, above the `Done` button**.

```
┌─────────────────────────────────────┐
│ ▶  Lo-fi beats…   ▶ Active   ⋯   ⌃ │
│    youtube                           │
│  ┌───────────────────────────────┐  │
│  │   <iframe>                    │  │
│  └───────────────────────────────┘  │
│  Tags  [ lo-fi ×] [ study ×] [+ add]│  ← editor strip
│                          [ Done ]   │
└─────────────────────────────────────┘
```

- **Layout:** `Tags` label `10pt white/45%`, then chips, then `+ add` chip, all on one horizontally-scrolling line.
- **Tag chip in editor:** same visual as the filter chip's *inactive* state, plus a trailing `×` glyph (`8pt white/45%`). Tapping `×` removes the tag instantly with a 150ms fade.
- **`+ add` chip:** dashed-border variant. When tapped, becomes an inline text field (replaces the chip in place); type a name, `Return` adds it, `Esc` cancels. Empty / whitespace-only input is no-op. Losing focus while non-empty commits (treated like `Return`); losing focus while empty cancels.
- **Autocomplete dropdown.** As the user types, suggest matching tags from the library-wide union (case-insensitive prefix match), max 5 results, dismissed on `Esc` or click-out. `Tab` or click-suggestion completes the value.
- **Cap behavior.** When the soundtrack already has 3 tags, the `+ add` chip is disabled (50% opacity) with help text `Up to 3 tags`. Removing a tag re-enables it.
- **Lowercase on commit.** `"Study"` is stored and rendered as `"study"`.
- **Duplicate within a soundtrack:** silently ignored (typing an already-present tag clears the input but adds nothing).
- **Editor is only available in the active row's expanded view.** To tag an inactive soundtrack, the user must activate it first (auto-activation on add covers the common new-entry case).

### 3.3 Collapsed row

**Unchanged.** Tags do not appear on the collapsed soundtrack row in any form. This keeps the row dense and matches the user's preference for a clean default.

### 3.4 Empty / edge states

- **No tags on any soundtrack.** Chip bar hidden. Editor in expanded view shows only `[+ add]`.
- **Filter active, zero matches.** In place of the row list:
  ```
  No soundtracks match the selected tags
  Clear filters
  ```
  `11pt white/45%` for the heading, `10pt accent` for the action, both centered. `Clear filters` deselects every chip.
- **Tag becomes orphaned** (last soundtrack with tag `"rain"` untags or is removed) → `"rain"` disappears from the chip bar at next render. Autocomplete keeps suggesting it **for the rest of the session** so a quick re-tag is one keystroke away; on next launch the tag is gone (no persistence beyond what's on a soundtrack).
- **Active filter chip becomes orphaned** (the tag has zero soundtracks) → the chip is removed from the bar; the filter state (other active chips) is preserved.
- **Soundtrack removed while it had tags** → tags vanish with the soundtrack; orphan-rule above applies.

---

## 4. Interactions

### 4.1 Adding a tag

1. User activates a soundtrack (already auto-activates on add per §4.6 of the soundtracks spec).
2. User taps the `⌃` chevron on the active row.
3. Row expands; user sees iframe + tag editor strip.
4. User taps `+ add`, types `study`, presses `Return`.
5. Chip `[study ×]` appears in the editor; chip bar above the list updates if `study` wasn't yet present.

### 4.2 Removing a tag

1. In the expanded editor, user taps the `×` on a chip.
2. Chip fades out over 150ms.
3. If that was the last soundtrack using the tag, the chip bar drops the tag at the next render.

### 4.3 Filtering

1. User taps a chip in the bar above the list.
2. Chip activates; list filters to soundtracks tagged with that tag.
3. User taps a second chip; list now shows soundtracks tagged with **both**.
4. User taps an active chip to deselect; list updates.
5. User opens the Soundtracks tab next time — filter state is **not** persisted across launches (the chip bar resets to no selection on each app launch).

---

## 5. Persistence

- **Tags ride existing `shuuchuu.savedSoundtracks` JSON.** No new UserDefaults key.
- **Filter chip selection is in-memory only** (resets on launch). The user re-applies the filter as needed; this avoids "why is my list filtered?" surprise after a relaunch.

---

## 6. Visual style

Inherits the soundtracks-spec palette and scale (§9 of the soundtracks design).

| Element | Style |
|---|---|
| Filter chip (inactive) | `white/4%` fill, `white/8%` border, `10pt white/65%` text, 10pt radius |
| Filter chip (active) | `accent/15%` fill, accent border 1pt, accent text |
| Editor tag chip | Same as filter chip inactive + trailing `×` `8pt white/45%` |
| `+ add` chip | Dashed `white/25%` border, `white/45%` text, 10pt radius |
| `+ add` chip (disabled) | 50% opacity, `Up to 3 tags` help text |
| `Tags` label | `10pt white/45%`, leading the editor strip |
| Empty-results note | `11pt white/45%` heading + `10pt accent` `Clear filters` action |
| Autocomplete dropdown | `white/8%` fill, `white/12%` border, 8pt radius, max 5 rows × 22pt |

---

## 7. Implementation notes (engineering)

### 7.1 New / modified types

- `WebSoundtrack.tags: [String]` — added with `Codable` default `[]`.
- `SoundtracksLibrary` gets a derived `tagsInUse: [String]` (sorted by usage desc, then alpha) and a `setTags(id:tags:)` mutator that normalizes (lowercase, trim, dedupe, clamp to 3).
- `SoundtracksFilterState` (`@MainActor, ObservableObject`) — owns the in-memory selected-tag set; lives on `AppModel` peer to other UI state. Resets on launch.

### 7.2 New components

- `Sources/Shuuchuu/UI/Components/TagChipBar.swift` — horizontal-scroll chip row, both inactive and active variants.
- `Sources/Shuuchuu/UI/Components/TagEditorStrip.swift` — chips + `× ` + `+ add` inline editor + autocomplete popover.
- `Sources/Shuuchuu/UI/Components/TagAutocompletePopover.swift` — anchor on the inline text field; max 5 matches.

### 7.3 Tests

- `WebSoundtrackTagsTests` — normalization (case, whitespace, dedupe, 3-cap), Codable round-trip with and without `tags` field, decode of >3 tags clamps.
- `SoundtracksLibraryTagsTests` — `setTags`, `tagsInUse` ordering and orphan removal.
- `SoundtracksFilterStateTests` — toggle, intersection semantics, orphan-tag removal preserving other selections.
- UI is preview-only per the existing convention.

### 7.4 Existing constraints from CLAUDE.md still apply

- `@EnvironmentObject` for observed objects in views.
- No `@MainActor` on UserDefaults wrappers.
- `.contentShape` after `.clipShape`.

---

## 8. Out of scope (deferred)

- Renaming a tag across all soundtracks at once.
- Per-tag color or icon assignment.
- Tag-based suggestions / smart tags.
- Tagging mixes or catalog tracks.
- Persisting the active filter across launches.
- Showing tags on the collapsed row (revisit if discoverability complaints appear).
