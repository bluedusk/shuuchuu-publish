# Sounds Page — Design Spec

**Date:** 2026-04-26
**Status:** Draft, approved in brainstorming session
**Audience:** AI designer (visual/interaction design), then engineering plan
**Target:** macOS 26+ (Liquid Glass), Swift 6 / SwiftUI menubar popover (340×540pt)

---

## 1. Overview

The Sounds page is the user's surface for picking what plays. Today it conflates three concepts on one scrolling view: pick a sound, browse a category, apply a preset. This redesign separates those concepts into two tabs and adds a third concept — **custom mixes** — that the user can save, recall, and delete.

### Three layers the page must support

1. **Categories** — taxonomy for browsing the sound catalog (Weather, Water, Nature, Ambient, Noise, etc.). The catalog can grow; new categories may appear.
2. **Presets** — built-in named combinations of sounds (Deep Focus, Sleep, Cabin, etc.). Curated, never mutated.
3. **Custom mixes** — user-saved combinations. The user names them when saving and can delete them later.

### Goals

- One predictable place to **browse and pick individual sounds**.
- One predictable place to **load and manage saved mixes** (custom + built-in).
- Make "save the current mix" a frictionless, non-modal action accessible from both the Sounds page and the Focus page.
- Scale visually and conceptually as the catalog and the user's saved mix list grow.

### Non-goals (defer)

- Renaming saved mixes after creation. (Lifecycle: save + delete only. Re-save with same name overwrites with confirmation.)
- Reordering custom mixes. (Implicit order: most-recently-saved first.)
- Editing presets.
- Internet soundtracks (YouTube/Spotify) — covered by the separate spec at `docs/superpowers/specs/2026-04-27-soundtracks-design.md` (third tab on this same page).
- Search across the catalog (called out as a near-term future addition; not in this spec).
- Audition / preview-on-hover (also future addition).
- Per-mix snapshot of master volume.

---

## 2. Information architecture

Two tabs at the top of the page:

```
┌───────────────────────────────────────────┐
│ ‹  SOUNDS                  [Save mix]     │  ← page header (preserved)
│    3 in current mix                        │
├───────────────────────────────────────────┤
│   Sounds   │   Mixes   │   Soundtracks    │  ← tab bar
├───────────────────────────────────────────┤
│ <tab-specific body>                        │
└───────────────────────────────────────────┘
```

- **Sounds tab** = browse & pick individual sounds. Tap a tile to add/remove from the current mix.
- **Mixes tab** = browse & load saved combinations. Tap a row to apply.

The **page header** (left chevron, "SOUNDS" eyebrow, "N in current mix" subtitle, "Save mix" trailing button) stays consistent across both tabs. The "Save mix" button is enabled only when the current mix has ≥1 track.

### Why two tabs

A single scrolling view trying to host all three layers (sounds, custom mixes, presets) cluttered the 540pt viewport and forced custom mixes into a horizontal chip strip with no room for preview info. Splitting on the orthogonal axis — *"am I picking a sound or applying a whole vibe?"* — makes each surface focused and gives both room to grow.

---

## 3. Sounds tab

### 3.1 Anatomy

```
┌───────────────────────────────────────────┐
│ ‹  SOUNDS                  [Save mix]     │
│    3 in current mix                        │
├───────────────────────────────────────────┤
│       Sounds*       │       Mixes          │  *active
├───────────────────────────────────────────┤
│  [★] [Weather*] [Water] [Nature] [Ambient] │  ← jump-pills
│  [Noise] [Binaural] [Voices]               │  (wraps to row 2)
├───────────────────────────────────────────┤
│  ★ FAVORITES                               │  ← sticky-ish section header
│  ┌──┐ ┌──┐ ┌──┐ ┌──┐                      │
│  │🌧│ │🔥│                                │  ← favorites grid
│  └──┘ └──┘                                 │
│                                            │
│  WEATHER                                   │
│  ┌──┐ ┌──┐ ┌──┐ ┌──┐                      │
│  │🌧│ │⛈│ │🌬│ │🌧│                       │
│  └──┘ └──┘ └──┘ └──┘                      │
│                                            │
│  WATER                                     │
│  ┌──┐ ┌──┐ ┌──┐ ┌──┐                      │
│  │🌊│ │💧│ │🐚│ │🛶│                       │
│  └──┘ └──┘ └──┘ └──┘                      │
│        ⋮                                   │
└───────────────────────────────────────────┘
```

### 3.2 Wrapping jump-pills

Pills serve as a **visible table of contents and a scroll-jump shortcut** — not as filters. All categories are always visible at a glance. The pills row sits below the tab bar on a slightly darker substrate, visually separated from the scroll area.

- Pills wrap to a second (or third) row as needed. **No horizontal scroller.**
- The first pill is always **★** (Favorites), styled in warm gold so it reads as personalization, not a category. Hidden when the user has no favorites (so the pill doesn't act as a dead jump target).
- Tapping a pill smooth-scrolls the body to that section. The pill of the currently-visible section is highlighted in the accent color.
- Highlight follows scroll position: the section whose label is closest to the top of the viewport is the "current" one.
- Pill style:
  - Default: `padding 4×9pt`, transparent fill, 1pt border at `white/8%`, label at `white/50%`.
  - Current: same metrics, `accent/18%` fill, accent-tinted border, label `white`.
  - Star: same metrics, label `gold/90%`.
- Pills row total padding: `10pt top, 8pt bottom, 12pt sides`. With one row, height ≈ `38pt`. Each extra row adds ~`24pt`.

### 3.3 Sectioned grid

- All categories always visible; user scrolls vertically through them.
- Section header style: `10pt SF Pro semibold uppercase, 0.08em kern, white/40%`, padding `12pt top / 14pt sides / 4pt bottom`. The "★ FAVORITES" header uses gold tint instead.
- The **Favorites section is pinned at the top** of the scroll area and is auto-hidden if the user has no favorites. (Don't surface an empty section.)
- Grid: `4 columns, 6pt gap, 12pt horizontal padding`. Tile aspect ratio 1:1, ~`73pt` per tile at the popover width.
- **Tile design preserved** from the current `SoundTile` (icon + name + volume bar reserved space + favorite star top-right). The accent gradient on the on-state is unchanged.
- Tap a tile = add (with default volume 0.5) or remove from current mix.
- Star tap = toggle favorite (does not affect mix membership).
- **Drag horizontally on an active tile = adjust volume.** The visible bar at the bottom of the tile updates in real time. The drag zone is the entire tile body (not just the 2pt bar) — drag distance maps linearly across the tile width to the 0.0–1.0 range. The gesture only activates when the tile is on; off-tiles ignore drag (a tap-then-drag becomes "add then immediately set volume," which is fine).
- Tap-vs-drag disambiguation: any drag exceeding ~4pt promotes to a volume gesture and suppresses the toggle. Lift-without-drag is a tap.
- A subtle one-time hint can be shown the first time a user activates a tile ("Drag to adjust volume"); not required for v1.

### 3.4 Behavior notes

- Scroll uses `.scrollIndicators(.never)` — no scroll bar, no cursor flips on edges (per the macOS 26 SwiftUI gotchas in CLAUDE.md).
- The pills bar stays pinned at the top of the page (does not scroll out of view). It's part of the page chrome, not the scroll content.
- When the user lands on the page after a fresh launch, the body is scrolled to the top (★ Favorites if any, otherwise Weather).

---

## 4. Mixes tab

### 4.1 Anatomy

```
┌───────────────────────────────────────────┐
│ ‹  SOUNDS                  [Save mix]     │
│    3 in current mix                        │
├───────────────────────────────────────────┤
│   Sounds   │   Mixes*  │   Soundtracks    │  *active
├───────────────────────────────────────────┤
│  MY MIXES   3                              │  ← section header w/ count
│  ┌─────────────────────────────────────┐  │
│  │ 🌧⛈🌬   Rainy night          ⋯       │  │  ← mix row
│  │         3 sounds · Rain · Thunder…  │  │
│  └─────────────────────────────────────┘  │
│  ┌─────────────────────────────────────┐  │
│  │ ☕⌨    Cafe deep work        ⋯       │  │
│  │         2 sounds · Cafe · Keys      │  │
│  └─────────────────────────────────────┘  │
│  ┌─────────────────────────────────────┐  │
│  │ 🔥🌬🦗  Cabin evening  ▶ Active ⋯    │  │  ← currently loaded
│  │         3 sounds · Fire · Wind…     │  │
│  └─────────────────────────────────────┘  │
│                                            │
│  PRESETS    5                              │
│  ┌─────────────────────────────────────┐  │
│  │ 🌧🟫    Deep Focus                   │  │
│  │         2 sounds · Rain · Brown     │  │
│  └─────────────────────────────────────┘  │
│         ⋮                                  │
└───────────────────────────────────────────┘
```

### 4.2 Mix row anatomy

A mix row is a horizontal card, full-width inside the 12pt body padding, with internal padding `10pt vertical, 12pt horizontal`. Corner radius 12pt.

Three slots, left to right:

1. **Stacked track icons** — fixed width ~`56pt`. Up to 3 mini-icons (22×22pt, 6pt corner radius), each overlapping the previous by ~6pt with a 1.5pt cut-out border that matches the row background, producing a clean overlap. If the mix has 4+ tracks, the third icon shows "+N" instead.
2. **Meta** — flexes to fill. Two lines:
   - **Name** — `12pt, semibold, white`. Truncates with tail ellipsis.
   - **Sub-line** — `10.5pt, white/45%`, format: `"3 sounds · Rain · Thunder · Wind"`. Truncates with tail ellipsis. Long mixes show first 2-3 names then ellipsize.
3. **Trailing** — `⋯` icon button (22pt square), opens a context menu. Custom mixes only (presets have no trailing button).

### 4.3 Custom-mix vs preset visual distinction

- **Custom mixes** use the standard row background (`white/4%`, `white/8%` border).
- **Presets** use a faintly accent-tinted row background (`accent/4%`, `accent/12%` border). Subtle — they should not feel demoted, just clearly distinguished.
- A small `PRESET` tag is **not** required since the section header ("PRESETS") and the tint already disambiguate.

### 4.4 Currently-loaded indicator

When the active mix exactly matches a saved mix or preset (same set of track ids, regardless of per-track volume — see open question below), highlight that row:

- Border thickens to 1.5pt and shifts to accent color.
- A small `▶ Active` chip appears in the meta column, after the sub-line (right-aligned on its own micro-row), in `9pt semibold uppercase, accent color, accent/15% pill background`. The `⋯` button is unaffected.
- At most one row is "Active" at a time.

This is a non-interactive affordance — the user doesn't toggle it; it derives from current MixState.

### 4.5 Section ordering

- "MY MIXES" always above "PRESETS" — the user's stuff comes first.
- Within "MY MIXES," sort by **most-recently-saved first**.
- Within "PRESETS," preserve the existing static order from `Presets.all`.

### 4.6 Section headers

- Style identical to Sounds tab section headers (`10pt semibold uppercase, white/40%, 0.08em kern`).
- Header includes a small grey count: `MY MIXES   3` where the count is `10pt regular, white/30%`.

### 4.7 Empty states

- **No custom mixes yet:** "MY MIXES" section is replaced by a 16pt-tall dashed-border empty card spanning the body width:
  ```
  ┌ - - - - - - - - - - - - - - - - - ┐
    No saved mixes yet
    Build a mix on the Sounds tab and tap "Save mix"
  └ - - - - - - - - - - - - - - - - - ┘
  ```
  Text: `11pt, white/45%`, two lines, centered. The hint line `10pt, white/35%`. Section label "MY MIXES   0" still appears above.
- **Empty current mix when on Mixes tab:** Tab still shows full preset list. (Loading a preset replaces whatever is there, including "nothing.")

### 4.8 Interactions

- **Tap a mix row** → apply the mix. Same semantics as the existing `applyPreset`: replace current mix wholesale, clear master-paused.
- **Right-click or tap `⋯` on a custom mix** → context menu with `Delete`. Confirm via a tiny inline confirmation (the row collapses to "Delete 'Rainy night'? [Cancel] [Delete]" inline) — no system alert.
- **Right-click on a preset** → no-op (or show a disabled "Built-in preset" item for clarity).

---

## 5. Save mix flow

### 5.1 Trigger locations

The "Save mix" affordance lives in two places, both behaving identically:

1. **Sounds page header** — trailing button, present on both tabs. Disabled when current mix has 0 tracks.
2. **Focus page** — small text button beside the existing "+ Add sound" button. Same disabled state.

### 5.2 Inline header transform

Tap "Save mix" → the page header (the row containing the chevron, "SOUNDS" eyebrow, mix-count subtitle, and the Save button) is replaced in-place by a name-entry header. The tab bar and body below remain interactive — the user can keep tweaking the mix during save mode. The preview row is **live**: as the user toggles tiles or volumes, the preview updates and the saved snapshot reflects the mix at the moment "Save" is pressed (not at the moment "Save mix" was first tapped).

The chevron back-button is hidden during save mode. To leave Sounds without saving, the user must Cancel first.

```
┌───────────────────────────────────────────┐
│ ┌─────────────────────────┐ Cancel  Save  │  ← name-entry header
│ │ Late night focus        │               │
│ └─────────────────────────┘               │
├───────────────────────────────────────────┤
│ SAVING  🌧 Rain · ⛈ Thunder · 🌬 Wind    │  ← preview row
├───────────────────────────────────────────┤
│   Sounds   │   Mixes   │   Soundtracks    │
│        ⋮                                   │
└───────────────────────────────────────────┘
```

- **Background tint:** the entry header and preview row both sit on a faint accent wash (`accent/6%`) so it visually reads as "you are in a save flow."
- **Name input:** `13pt, white text, accent-tinted 1pt border, 8pt corner radius, 6×10pt padding`. Auto-focused, placeholder `"Name this mix…"`. Selects all on focus if a value is pre-filled.
- **Cancel button:** plain text, `11pt, white/55%, 6×8pt padding`. Esc shortcut.
- **Save button:** filled accent, `11pt semibold, white, 6×12pt padding, 8pt radius`. Enter shortcut. Disabled until name is non-empty (after trimming whitespace).
- **Preview row:** below the entry header, on the same accent wash. Format: `SAVING  🌧 Rain · ⛈ Thunder · 🌬 Wind`. The "SAVING" eyebrow is `10pt semibold uppercase white/55%`; the icon list is `10pt white/70%`. Truncates with tail ellipsis if many tracks.
- **On Save:** persist the mix (track ids + per-track volumes), restore the normal page header, optionally show a 1.5s "Saved as 'Late night focus'" toast at the bottom of the popover (small, dismisses on tap or auto-fade).

### 5.3 Validation

- **Empty name:** Save button stays disabled. No inline error needed.
- **Duplicate name:** If `name.trimmed` already exists in custom mixes, on Save click the entry header transitions into a tiny inline confirm:
  ```
  ┌───────────────────────────────────────┐
  │ Overwrite "Late night focus"?         │
  │              [ Save as new ] [ Overwrite ] │
  └───────────────────────────────────────┘
  ```
  Same accent wash. "Save as new" appends ` (2)`, ` (3)`, etc. "Overwrite" replaces the existing mix with the new track set.
- **Whitespace handling:** Trim leading/trailing whitespace before save.
- **Length:** Soft cap 40 chars in the input field; longer names truncate visually in the rows but are stored intact.

### 5.4 Cancel / dismiss

- Esc, "Cancel" tap, or tapping outside the entry header (on the body or tab bar) cancels. No confirmation — the user can just retype.
- Switching tabs while in save mode also cancels.

---

## 6. Delete flow

Triggered from the `⋯` menu or right-click on a custom mix row.

```
┌───────────────────────────────────────┐
│ Delete "Rainy night"?  [Cancel] [Delete] │
└───────────────────────────────────────┘
```

- The mix row visually morphs into the confirm strip (same height, same border radius).
- "Delete" button uses a destructive red tint (`red/80%` fill, white text).
- Confirm or Cancel restores the row (or removes it).

No undo flow in v1.

---

## 7. Visual style & tokens

Inherits the existing app tokens:

- **Background:** dark popover gradient (`#1a1f2e → #0f1219`), 18pt corner radius.
- **Accent:** comes from `DesignSettings.accent` (user-customizable hue).
- **Glass panels:** Liquid Glass via `GlassEffectContainer` / `.glassEffect()` for any floating chrome (the pills bar substrate qualifies).
- **Typography:** SF Pro Text. Section labels `10pt semibold 0.08em uppercase white/40%`. Eyebrows `12pt semibold 0.06em uppercase white/55%`. Body row names `12pt`. Sub-lines `10.5pt white/45%`.
- **Borders:** hairlines `white/8–12%`. Dividers between header/tabs/pills are 1pt at `white/6%`.
- **Spacing scale:** 4 / 6 / 8 / 10 / 12 / 14pt. Tile gap 6pt, section padding 12pt, body horizontal padding 12pt.

---

## 8. State summary

| Surface | State | Visual |
|---|---|---|
| Sounds tab pills | Default | `accent/0`, white/50% label |
| Sounds tab pills | Current section | `accent/18%` fill, accent border, white label |
| Sounds tab pills | Star (favs) | gold/90% label |
| Tile | Off | `white/4%` fill, white/10% border |
| Tile | On | accent gradient fill, white/40% border, soft glow |
| Tile | Dragging (volume) | accent border tightens to 1.5pt; volume bar pulses brighter while the gesture is active |
| Tile | Favorite (star) | gold star top-right |
| Mix row | Default (custom) | `white/4%` fill |
| Mix row | Default (preset) | `accent/4%` fill |
| Mix row | Currently loaded | accent border 1.5pt + `▶ Active` chip |
| Mix row | Deleting | inline confirm strip |
| Save header | Default | accent/6% wash, accent-bordered input |
| Save header | Duplicate confirm | same wash, two action buttons |
| Save toast | Success | bottom-floating glass chip, 1.5s |

---

## 9. Edge cases

- **Catalog still loading** when user opens Sounds tab: show the existing offline/loading indicator pattern (already handled by Catalog state). Pills row may render with placeholders or just hide until ready.
- **Saved mix references a track that's no longer in catalog** (track removed in a future catalog update): on apply, silently skip the missing track. Show a gentle inline note in the row sub-line: "2 of 3 sounds available".
- **User saves a mix with 1 track:** allowed.
- **User saves a mix with same track set but different volumes as an existing mix:** treat as new — names are the only uniqueness constraint.
- **Currently-loaded indicator on near-match:** match by track-id set only (ignore volumes). If user tweaks volumes after applying a mix, indicator stays. This avoids flicker on volume drag.
- **Save trigger when on Mixes tab:** same inline header transform — header is shared across both tabs, so the entry overlay covers the whole page header regardless of which tab body is showing.
- **Save trigger when current mix is empty:** button is disabled (visually muted).

---

## 10. Out of scope (called out as future features worth considering)

These are deliberately deferred. The architecture should not preclude them.

- **Search.** Once the catalog grows past ~30 tracks per category, a search field becomes valuable. Likely placement: a search-icon button in the page header that expands inline (replacing the "Save mix" button momentarily) and filters the grid in real time.
- **Audition / preview-on-hover.** Currently the user must add a track to the mix to hear it. A hover-to-preview mode (or a dedicated "headphones" icon on each tile) would let them sample without committing.
- **Per-mix master-volume snapshot.** Saved mixes currently capture only per-track volumes; the master volume comes from the user's session. Could optionally capture and restore master too.
- **Mix vibe icon.** Saved mixes could pick from a small set of mood glyphs (☕ moon flame leaf) for faster visual recognition independent of the track icon stack.
- **Recently played row.** Auto-pin the last 1–2 mixes the user loaded above "MY MIXES."
- **Mix import/export.** JSON export to share a mix with another user.
- **Internet soundtracks (YouTube/Spotify)** — implemented as a third tab on this page; see `docs/superpowers/specs/2026-04-27-soundtracks-design.md`.
- **Reordering custom mixes.** Drag-to-reorder. Out of scope per the lifecycle decision (sort is recency-only).
- **Renaming custom mixes.** Out of scope per the lifecycle decision (re-save under same name + Overwrite is the workaround).

---

## 11. Implementation notes (engineering, not designer)

These are hints for the implementation plan; the AI designer can ignore section 11.

- **New model:** `SavedMixes` (alongside `Presets`). Persisted to UserDefaults under `x-noise.savedMixes`. Each entry: `{ id: UUID, name: String, tracks: [MixTrack], createdAt: Date }`. Sort by `createdAt` desc for display.
- **CategoryFilter enum** is no longer used as a filter; replace with a category-section model derived from the catalog. The old enum can be repurposed or deleted; verify no other call sites depend on filtering semantics.
- **Section anchoring** for the jump-pills uses SwiftUI `ScrollViewReader` + `.id(...)` per section. Highlighted-pill follows the topmost visible section header (use `GeometryReader` or `onScrollGeometryChange` on macOS 26).
- **Save trigger duplication** between Sounds and Focus: both pages dispatch through the same `AppModel.beginSaveMix()` / `commitSaveMix(name:)` API; the inline header is a shared overlay component owned by `PopoverView` so it can render above whichever page is current.
- **Currently-loaded match:** compute a `Set<String>` of current track ids and compare against each saved/preset mix's track-id set. Cache per-mix sets; recompute only when MixState changes.
- **Tests:** add `SavedMixesTests` (round-trip persistence, duplicate-name behavior), and extend `AppModelTests` with `beginSaveMix` / `commitSaveMix` flows.
- **Tile drag-to-volume:** `SoundTile` gains a `DragGesture(minimumDistance: 4)` that suppresses the tap when promoted. While active, route per-frame deltas through `model.setTrackVolume`. Off-state tiles short-circuit the gesture (no-op). Test with `AppModelTests` covering rapid tap-vs-drag arbitration.
- **Existing constraints** from CLAUDE.md still apply: `@EnvironmentObject` for observed objects (no init-passed `@ObservedObject`), no `@MainActor` on UserDefaults wrappers, `.contentShape` after `.clipShape`, etc.
