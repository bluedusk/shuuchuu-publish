# Popover Resize → Phone Aspect — Design Spec

**Date:** 2026-04-28
**Status:** Draft
**Audience:** Engineering (small change with UI-review implications)
**Target:** macOS 26+, Swift 6 / SwiftUI menubar popover

---

## 1. Overview

The Shuuchuu popover is currently **340×540pt** (17:27 ≈ 0.630). This spec resizes it to **340×604pt** (9:16 = 0.5625) so the window matches a phone aspect ratio. Motivation: phone-shot photos are the most common source for the upcoming custom wallpaper feature (`docs/superpowers/specs/2026-04-28-custom-wallpaper-design.md`); a 9:16 popover makes those images fit with negligible crop, and gives every page +64pt of vertical room.

### Goals

- Switch to a 9:16 popover (340×604pt).
- Audit every page for layout regressions caused by the extra vertical space.
- Keep all existing widths unchanged (340pt) — no horizontal layout work.

### Non-goals (defer)

- Going further to 19.5:9 (340×737pt). Modern iPhones, but crowds 13" laptops (MacBook Air 13" has ~800pt usable vertical; a 737pt popover at the menubar nearly fills the display). Revisit if user feedback wants it.
- Making the popover user-resizable.
- Changing the width.
- Per-page max-height constraints (let everything stretch naturally first; we tighten what looks sparse).

---

## 2. The change

### Single source of truth

`Sources/Shuuchuu/UI/PopoverView.swift`:

```swift
private let size = CGSize(width: 340, height: 540)   // before
private let size = CGSize(width: 340, height: 604)   // after
```

This drives all five `.frame(width: size.width, height: size.height)` callsites in `PopoverView.swift` plus the outer container frame. **Nothing else baked the height in** — verified via `grep -rn "540" Sources/`.

### Width references to keep an eye on

`FocusPage.swift:83` has a hard-coded `.frame(width: 340)`. Width is unchanged in this resize, so it stays correct, but flag it for the next time we move the width.

---

## 3. Per-page audit

The popover hosts five pages plus shared chrome. Each gets +64pt of vertical room. Expected outcomes:

| Page | What's there | Expected with +64pt | Action |
|---|---|---|---|
| `FocusPage` | Pomodoro ring, controls, mix chips | Ring stays centered; bottom controls drift down. May feel bottom-heavy. | Verify spacing; consider lifting the ring slightly with a top spacer ratio change if it looks off. |
| `SoundsPage` (Sounds tab) | Scrolling category list | Free real estate — list shows ~2 more rows. | None; just a win. |
| `SoundsPage` (Mixes tab) | Scrolling mix list | Same as above. | None. |
| `SoundsPage` (Soundtracks tab) | Scrolling soundtrack list | Same as above. | None. |
| `SettingsPage` | Long form — scrolling | Same as above. | None. |
| Header / nav chrome | Page title, tabs, back button | Pinned to top; unaffected. | None. |

Verification: run `pkill -x Shuuchuu && swift run`, open the popover, walk through every page including all three Sounds tabs. Look specifically for:

- Bottom-anchored controls floating in space.
- Vertical centering that now looks too high or too low.
- Scroll views whose content height was previously close to the popover height — these used to scroll, may not anymore (not a bug, just confirm).

---

## 4. Wallpaper interaction

The aurora `Wallpaper` view (`Wallpaper.swift`) uses unit-point blob centers (`.init(x: 0.20, y: 0.30)` etc.), so blob positions scale with the new height automatically. No tuning needed — verify visually that none of the modes look obviously stretched.

For the upcoming custom wallpaper:

- 9:16 photos hit `scaledToFill()` at exactly the popover aspect → essentially zero crop. This is the primary motivation.
- Other aspects still center-crop as designed in the wallpaper spec.

---

## 5. Risks

- **13" laptops still fit fine.** 604pt + ~24pt menubar = ~628pt; well under the ~800pt usable height on a 13" MacBook Air.
- **Bottom-anchored layouts** are the highest-risk regression. `FocusPage` is the prime suspect — eyeball it after the change.
- **No tests catch this.** UI is preview-only per `CLAUDE.md`. Manual verification only.

---

## 6. Implementation order

1. Update `size` in `PopoverView.swift` to `CGSize(width: 340, height: 604)`.
2. `pkill -x Shuuchuu && swift run`; walk through every page per §3.
3. If `FocusPage` looks bottom-heavy, adjust the spacer ratios there (separate commit so the resize is reverted-safe).
4. Confirm aurora wallpaper modes still look right at the new height.
5. Land before starting the custom wallpaper implementation, so the wallpaper feature is built against the final popover dimensions.
