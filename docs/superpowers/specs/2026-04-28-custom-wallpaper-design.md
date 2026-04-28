# Custom Wallpaper — Design Spec

**Date:** 2026-04-28
**Status:** Draft
**Audience:** Engineering (small feature; no separate design pass needed)
**Target:** macOS 26+, Swift 6 / SwiftUI menubar popover (340×540pt)

---

## 1. Overview

Today the popover background is one of five built-in aurora gradients (`default`, `sunset`, `forest`, `sky`, `mono`) selected from `Settings → Wallpaper`. This spec adds a sixth option — **Custom** — that lets the user pick any image from disk and use it as the popover background, with a slider that controls how blurred it appears.

### Goals

- Let the user pick a personal image (photo, art, screenshot) as the popover background.
- Let the user dial in a blur radius from "sharp" to "abstract wash" so the image never fights with foreground UI.
- Persist the selection across launches without re-prompting.
- Stay inside `Wallpaper` + `DesignSettings` — no new subsystems.

### Non-goals (defer)

- Multiple saved custom wallpapers / a wallpaper library. (Single slot, replace to change.)
- Per-mode blur for the aurora gradients. (Gradients are already soft; blur slider only applies to `.custom`.)
- Tinting or color grading the custom image.
- Animated/video wallpapers.
- iCloud sync of the wallpaper file.
- Cropping / repositioning UI. (We `scaledToFill()` and center-crop.)
- Drag-and-drop onto the popover. (`NSOpenPanel` only — drop targets in a 340pt popover are awkward.)

---

## 2. User flow

1. User opens `Settings → Wallpaper`.
2. The radio row gains a sixth option: **Custom**.
3. Selecting **Custom** when no image is set opens an `NSOpenPanel` immediately. If the user cancels, mode reverts to whatever it was before.
4. Once an image is set, the row shows two extra controls beneath the radio group (only when `.custom` is selected):
   - **Image** — small thumbnail + "Change…" button (re-opens `NSOpenPanel`).
   - **Blur** — slider, `0…40pt`, default `12pt`, with the current value shown as `"12pt"` on the right.
5. The popover background updates live as the slider moves.
6. Selection persists across launches; if the cached file is missing on launch, mode silently falls back to `.defaultMode`.

---

## 3. Data model changes

### `WallpaperMode` (`DesignSettings.swift`)

Add a case:

```swift
enum WallpaperMode: String, CaseIterable, Codable, Identifiable {
    case defaultMode = "default"
    case sunset, forest, sky, mono
    case custom
    // …
    var display: String {
        switch self {
        // …
        case .custom: return "custom"
        }
    }
}
```

### `DesignSettings`

Add one published property and one persisted key:

```swift
@Published var wallpaperBlur: Double { didSet { defaults.set(wallpaperBlur, forKey: K.wallpaperBlur) } }
// init: defaults.object(forKey: K.wallpaperBlur) as? Double ?? 12
// K.wallpaperBlur = "x-noise.ui.wallpaperBlur"
```

The image bytes themselves do **not** live in `UserDefaults`. They're written to a fixed path on disk (next section). `DesignSettings` exposes a computed accessor:

```swift
var customWallpaperURL: URL { /* ~/Library/Application Support/x-noise/wallpaper.image */ }
var customWallpaperExists: Bool { FileManager.default.fileExists(atPath: customWallpaperURL.path) }
```

There is **no** stored property for the image — the file's presence on disk is the source of truth, so we never need to invalidate a cached `NSImage`.

---

## 4. Storage

**Path:** `~/Library/Application Support/x-noise/wallpaper.image`

- Single fixed filename — picking a new image overwrites in place.
- No file extension is needed; `NSImage(contentsOf:)` decodes by content, not extension. We preserve the user's bytes verbatim (no re-encoding) so HEIC/PNG/JPEG/WebP all work and we don't bloat large images by converting to PNG.
- Same parent directory as the catalog cache (`x-noise/`); create with `withIntermediateDirectories: true` if missing.
- Picking an image: copy via `FileManager.default.copyItem(at:to:)` after removing any existing file. No security-scoped bookmarks — the copy means we don't depend on the original surviving.

**Why not bookmarks:** the user's source file could move/rename/be on an external drive; a copy is ~MB of disk for a permanent UI element and trades nothing useful for considerable complexity.

**Why not `UserDefaults` blob:** `UserDefaults` is a plist; embedding multi-MB image data there is the wrong tool and slows every defaults read.

---

## 5. UI

### Settings page

In `SettingsPage.swift`, the existing `stackedRow(title: "Wallpaper")` grows:

```
┌─ Wallpaper ─────────────────────────────────┐
│ ◉ Default  ○ Sunset  ○ Forest  ○ Sky        │
│ ○ Mono     ○ Custom                          │
│                                              │
│ ▸ shown only when Custom is selected:        │
│   ┌──────┐                                   │
│   │ thumb│  Change…                          │
│   └──────┘                                   │
│                                              │
│   Blur                                  12pt │
│   [─────●──────────────────────]            │
└─────────────────────────────────────────────┘
```

- Thumbnail is a 56×40pt rounded-rect render of the current `wallpaper.image` (use `Image(nsImage:).resizable().scaledToFill()` clipped to a 6pt corner radius).
- "Change…" is a small `.buttonStyle(.glass)` button that opens `NSOpenPanel`.
- Blur slider mirrors the existing slider patterns in `SettingsPage` (`stackedRow(title: "Blur", trailing: "\(Int(design.wallpaperBlur))pt")`).

### Selection behavior

When the user taps the **Custom** radio:

- If `customWallpaperExists` — switch mode to `.custom` directly.
- Otherwise — open `NSOpenPanel` configured for image content types (`UTType.image`); on success, copy the file and switch mode to `.custom`; on cancel, do not change mode.

```swift
let panel = NSOpenPanel()
panel.allowedContentTypes = [.image]
panel.allowsMultipleSelection = false
panel.canChooseDirectories = false
if panel.runModal() == .OK, let src = panel.url {
    try? FileManager.default.removeItem(at: design.customWallpaperURL)
    try? FileManager.default.copyItem(at: src, to: design.customWallpaperURL)
    design.wallpaper = .custom
    design.objectWillChange.send()  // force Wallpaper view to re-read from disk
}
```

The `objectWillChange.send()` is the trick that makes "replace image, keep mode" repaint — the mode didn't change, but the file did.

### Wallpaper view (`Wallpaper.swift`)

Extend the `body` to branch on mode:

```swift
var body: some View {
    Group {
        if mode == .custom, let nsImage = loadCustomImage() {
            Image(nsImage: nsImage)
                .resizable()
                .scaledToFill()
                .blur(radius: blur, opaque: true)   // opaque: true avoids edge transparency
                .clipped()
        } else {
            auroraBody  // existing gradient + blobs
        }
    }
    .ignoresSafeArea()
}
```

Two new params on the view:

```swift
struct Wallpaper: View {
    let mode: WallpaperMode
    var blur: Double = 0           // ignored unless mode == .custom
    var customImageURL: URL? = nil // injected by PopoverView
    // …
}
```

`PopoverView` updates its three call sites to pass `blur: design.wallpaperBlur` and `customImageURL: design.customWallpaperURL`.

`loadCustomImage()` reads `NSImage(contentsOf: customImageURL)` once per body computation. Cheap on macOS for typical wallpaper sizes; if it shows up in profiles we can hoist into a `@State` cache keyed by URL+mtime.

### Missing-file fallback

If `mode == .custom` but the file is gone (user manually deleted it, app moved between machines, etc.), `loadCustomImage()` returns nil and we fall through to `auroraBody` rendering the **default** mode's blobs/gradient. We do not silently mutate `design.wallpaper` — the user's selection is preserved, so dropping a new file at the same path restores the custom view immediately.

---

## 6. Blur

- Range: `0…40pt`, default `12pt`, step `1`.
- Apply via `.blur(radius: blur, opaque: true)`. `opaque: true` is important: without it the blur leaks transparency at the popover corners, which then composites with the system menubar and looks like a halo.
- Blur is rendered after `scaledToFill()` so the image fills the popover even when extreme blur values would otherwise shrink the visible content.
- Only applies when `mode == .custom`. The aurora gradients are already low-frequency by construction; adding blur there would just look muddy.

---

## 7. Edge cases

| Case | Behavior |
|---|---|
| User picks a non-image file | `NSOpenPanel` filters by `UTType.image`; not reachable. |
| User picks a 50MB image | Copied as-is. macOS's image pipeline downsamples on render; we don't re-encode. |
| User picks an image, then deletes the source on disk | No effect — we copied it. |
| User manually deletes `wallpaper.image` while app runs | Next view repaint falls back to default gradient (silent). |
| User picks **Custom** with no file present, cancels panel | Mode stays on prior selection. |
| User picks **Custom**, picks file, then later picks another built-in mode | Custom file stays on disk; switching back to **Custom** uses it without re-prompting. |
| Image has alpha (transparent PNG) | We render against the popover's underlying material; alpha shows through. Acceptable; no special handling. |
| Image is animated (GIF/APNG) | We get the first frame via `NSImage`. Animation is non-goal. |

---

## 8. Persistence summary

| Key | Type | Default | Stored where |
|---|---|---|---|
| `x-noise.ui.wallpaper` | `String` (raw) | `"default"` | `UserDefaults` |
| `x-noise.ui.wallpaperBlur` | `Double` | `12` | `UserDefaults` |
| custom image bytes | binary | — | `~/Library/Application Support/x-noise/wallpaper.image` |

---

## 9. Test surface

Unit tests (extend `Tests/XNoiseTests/`):

- `DesignSettings`: `wallpaperBlur` round-trips through `UserDefaults`.
- `DesignSettings`: `customWallpaperURL` returns a path under Application Support / `x-noise/`.
- `DesignSettings`: `customWallpaperExists` reflects file presence (use a temp `UserDefaults` + temp directory; inject path).

Manual / preview:

- Settings page renders thumbnail + blur slider only when `.custom` is selected.
- Switching modes back and forth doesn't lose the custom file.
- Blur slider repaints the popover live.

---

## 10. Implementation order

1. `WallpaperMode.custom` + `wallpaperBlur` on `DesignSettings` + `customWallpaperURL` accessor.
2. `Wallpaper` view branches on mode; reads image from disk; applies blur.
3. `PopoverView` plumbs `blur` and `customImageURL` through to all three `Wallpaper(...)` call sites.
4. `SettingsPage` — extend Wallpaper row: thumbnail, "Change…" button, blur slider (conditional on `.custom`).
5. `NSOpenPanel` flow: pick → copy → set mode → notify.
6. Missing-file fallback path in `Wallpaper`.
7. Tests for `DesignSettings` additions.
8. Manual verification: relaunch (`pkill -x XNoise && swift run`), exercise all 7 cases in §7.
