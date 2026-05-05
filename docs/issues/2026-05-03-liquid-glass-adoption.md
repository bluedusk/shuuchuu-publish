# Liquid Glass adoption

**Status:** Deferred. Reverted prototype on 2026-05-03 because shaders appeared to break.
**Owner:** Unassigned.

## Problem

CLAUDE.md claims the UI uses Liquid Glass (`GlassEffectContainer`, `.glassEffect()`, `.buttonStyle(.glass)`), but a grep of `Sources/` turns up zero call sites of any of those APIs. What the codebase actually has is `GlassStyle.swift` — a hand-rolled five-layer recipe over `.ultraThinMaterial` / `.thinMaterial`. This is the macOS 11-era Materials API, not Liquid Glass.

Independent of the recipe question, the UI barely uses material/glass surfaces at all. `grep -rn "material" Sources/Shuuchuu/UI/` returns only **4 call sites** in the entire UI:

- `GlassStyle.swift` — the helper modifiers themselves (called only once: `SettingsPage.swift:150` for the `⌥⌘ N` chip)
- `IconButton.swift:25` — back chevron buttons (peripheral)
- `SoundChip.swift:156` — off-state sound tile
- `ScenePicker.swift:37` — scene picker popover

Everything visible on `FocusPage` (timer ring, `MixChipRow` rows, play/clear/add buttons, header glyphs) uses `Color.black.opacity(...)` scrims and plain glyphs. There is no glass on the main surface to convert.

## What was tried (and reverted)

A toggle-gated prototype across 5 files:

1. `DesignSettings` — added `useSystemGlass: Bool` (persisted, default `false`)
2. `GlassStyle` — branched `.glassPanel` / `.glassChip` to use `.glassEffect(.regular, in: shape)` when toggle on
3. `IconButton` — branched to `.buttonStyle(.glass)` when toggle on
4. `PopoverView` — wrapped content in `GlassEffectContainer` when toggle on
5. `SettingsPage` — added "Use system Liquid Glass (experimental)" toggle row

Built clean. Toggling produced no visible change because the toggle only reached the 4 peripheral material surfaces above — none on `FocusPage`. The prototype was extended to `MixChipRow` / `SoundChip` / `ScenePicker` backgrounds, still with no clearly visible diff. The user reported shaders appeared broken, and the entire prototype was reverted.

Suspected cause of "broken shaders" was the `GlassEffectContainer` modifier in `PopoverView` wrapping the `SceneBackground(MTKView)` — even when the toggle was off, the `if/else` inside the `ViewModifier` could disrupt Metal rendering identity. Not confirmed before revert.

## What needs to happen before retrying

1. **Read Apple's actual Liquid Glass docs.** Context7 was down during this session; use WebFetch on `https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views` and the WWDC25 session "Build a SwiftUI app with the new design". Specifically answer:
   - What context does `.glassEffect()` need to render visibly? (vs silently looking like material)
   - Does it require `GlassEffectContainer` to ever look "alive"?
   - What does `.glassEffect(.regular.tint(...))` look like — is tint required for visibility against dark backdrops?
   - Apple HIG guidance on glass over animated/shader backgrounds: appropriate or anti-pattern?
2. **Decide whether glass should be added or recipe-swapped.** The honest finding is that the app's "Liquid Glass feel" is conveyed by the wallpaper / shader scenes showing through dark scrims, not by glass surfaces. Real Liquid Glass adoption may require *introducing* glass surfaces where there are none today (the timer card, the popover root, the mix-row container) — a design decision, not a recipe swap.
3. **Test `GlassEffectContainer` over MTKView in isolation** before re-introducing it at the popover root. If it interferes with Metal rendering, the container has to live below `SceneBackground` in the z-order, not above it.

## Files touched + reverted (verify clean)

- `Sources/Shuuchuu/UI/Design/DesignSettings.swift`
- `Sources/Shuuchuu/UI/Design/GlassStyle.swift`
- `Sources/Shuuchuu/UI/Components/IconButton.swift`
- `Sources/Shuuchuu/UI/Components/SoundChip.swift`
- `Sources/Shuuchuu/UI/Components/ScenePicker.swift`
- `Sources/Shuuchuu/UI/Components/MixChipRow.swift`
- `Sources/Shuuchuu/UI/PopoverView.swift`
- `Sources/Shuuchuu/UI/Pages/SettingsPage.swift`

`grep -rn "useSystemGlass\|glassEffect\|GlassEffectContainer" Sources/` should return zero matches in clean state.

## Out of scope for this issue

- The CLAUDE.md claim that the UI uses Liquid Glass APIs is currently false. Either fix the claim or fix the code — but don't conflate this issue with that doc cleanup.
