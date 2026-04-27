# Soundtracks (YouTube / Spotify) — Design Spec

**Date:** 2026-04-27
**Status:** Draft, approved in brainstorming session
**Audience:** AI designer (visual/interaction design), then engineering plan
**Target:** macOS 26+ (Liquid Glass), Swift 6 / SwiftUI menubar popover (340×540pt)

---

## 1. Overview

Today the app plays only its own ambient catalog through `AVAudioEngine`. Users want to also play YouTube and Spotify soundtracks (lo-fi mixes, ambient albums, focus playlists) inside the same focus surface — without leaving the popover. This feature adds **Soundtracks**: paste-a-link YouTube and Spotify embeds that the user manages from the Sounds page and controls from the Focus page, hosted by a hidden long-lived `WKWebView`, driven by a JS bridge for play/pause/volume, and mirrored to the pomodoro session the same way the existing mix is.

The reference UX is Momentum dashboard's Sounds feature: paste a URL, get a tile that plays full content (Spotify requires a one-time login inside the embedded player; Premium is **not** required).

### Core model: a single active audio source

The app has exactly one audio source active at any time:

- **Idle.** Nothing playing.
- **Mix mode.** The user's ambient mix (one or more catalog tracks layered through `AVAudioEngine`).
- **Soundtrack mode.** Exactly one online soundtrack (YouTube or Spotify) playing through a single `WKWebView`.

**Mix mode and soundtrack mode never overlap.** Activating one stops the other. There is no layering of two YouTube streams either — at most one soundtrack at a time. This single-source rule is the load-bearing simplification of the design.

### Goals

- Let users layer a YouTube or Spotify soundtrack into their focus session as an alternative to the ambient mix.
- Reuse the existing focus-session play/pause discipline so the active source pauses on break and resumes on focus.
- Keep playback alive when the popover dismisses (parity with the current mix engine).
- Persist the saved soundtrack library and the active mode across launches without auto-resuming external playback.

### Non-goals (defer)

- Layering soundtracks with the mix or with each other.
- Curated soundtrack catalog (paste-a-link only in v1).
- Suppressing YouTube ads or detecting Premium accounts.
- Sharing the system Safari/Chrome login session with our `WKWebView` (technically infeasible — see §11).
- Crossfade between mix and soundtrack on mode switch (hard switch in v1).
- Pulling track-name metadata back into our own UI for arbitrary reuse (we display the title in the row; the iframe stays the canonical "what's playing" surface for anything richer).
- Apple Music, SoundCloud, generic web URLs.
- Keyboard shortcuts.

---

## 2. Architecture

### 2.1 New types

```swift
struct WebSoundtrack: Identifiable, Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable { case youtube, spotify }
    let id: UUID
    let kind: Kind
    let url: String          // canonical embed URL (post-normalization)
    var title: String?       // best-effort, populated by the JS bridge
    var volume: Double       // 0.0–1.0, applied when this becomes active
    let addedAt: Date
}

enum AudioMode: Codable, Equatable, Sendable {
    case idle
    case mix
    case soundtrack(WebSoundtrack.ID)
}
```

### 2.2 New subsystem

- **`WebSoundtrackController`** — `@MainActor, ObservableObject`, peer of `MixingController`. Owns one hidden, long-lived `NSWindow` (off-screen, `.borderless`, `level = .normal`, `isExcludedFromWindowsMenu = true`, `ignoresMouseEvents = true`) holding **at most one** `WKWebView`. Activating a soundtrack reuses the web view (reload with the new embed URL) rather than tearing it down — fewer allocations, faster mode switches, login cookies persist.
- **JS bridge per provider**:
  - `.youtube`: YouTube IFrame Player API (`https://www.youtube.com/iframe_api`). Methods: `playVideo`, `pauseVideo`, `setVolume(0–100)`. Events: `onReady`, `onStateChange`, `onError`, `onPlaybackQualityChange`.
  - `.spotify`: Spotify IFrame API (`https://open.spotify.com/embed/iframe-api/v1`). Methods: `play`, `pause`, `setVolume(0–1)`. Events: `playback_update`, `playback_started`, `error`.
- **Cookie persistence** — `WKWebsiteDataStore.default()`. The user's one-time Spotify login persists across app launches.
- **Autoplay policy** — `WKWebViewConfiguration.mediaTypesRequiringUserActionForPlayback = []` so the bridge can call `play()` programmatically without a synthetic gesture.

### 2.3 AppModel additions

`AppModel` becomes the single owner of `AudioMode`:

```swift
@Published var soundtracks: [WebSoundtrack]   // library
@Published var mode: AudioMode                 // current source

func addSoundtrack(url: String) -> Result<WebSoundtrack, AddSoundtrackError>
func removeSoundtrack(_ id: UUID)              // if active → mode = .idle
func setSoundtrackVolume(_ id: UUID, _ volume: Double)
func activateSoundtrack(_ id: UUID)            // mode = .soundtrack(id); pause mix
func deactivateSoundtrack()                    // mode = .idle
```

The existing mix mutations (`toggleTrack`, `applyPreset`, etc.) are extended to set `mode = .mix` and stop the active soundtrack as a side effect. There is no public "switch to mix" method — switching is a side effect of touching mix surfaces.

All mutations route through `AppModel`, persist to UserDefaults, and call into the relevant subsystem. Calling `MixingController` or `WebSoundtrackController` directly bypasses both persistence and the cross-mode side effects, same convention as today.

### 2.4 Mode transition rules (single source of truth)

| User action | New mode | Side effect |
|---|---|---|
| Tap a sound on Sounds tab | `.mix` | Soundtrack `pause()` → `WKWebView` retained but silent |
| Apply a saved mix on Mixes tab | `.mix` | Same |
| Tap an inactive soundtrack on Soundtracks tab | `.soundtrack(id)` | Mix tracks pause via `MixingController.pauseAll()`, mix state preserved |
| Tap the **active** soundtrack on Soundtracks tab | `.idle` | Soundtrack pauses; mix stays paused |
| Remove the active soundtrack | `.idle` | Web view loads `about:blank` |
| Remove the last mix track while in `.mix` | `.idle` | (existing mix-empty behavior) |
| Add a soundtrack while in `.mix` | unchanged (`.mix`) | New soundtrack is loaded but not active |
| Add a soundtrack while in `.idle` or `.soundtrack` | `.soundtrack(newId)` | Auto-activate the new one (the user just expressed intent) |

**Why no auto-fallback from soundtrack to mix.** When the user explicitly stops a soundtrack (taps it again or removes it), they get silence. Auto-resuming the mix would surprise them and waste a moment of "wait, what's that other sound." If they want the mix back, they tap a sound or apply a saved mix.

---

## 3. UI placement

### 3.1 Sounds page gets a third tab

Today's Sounds page has two tabs (`Sounds` | `Mixes`) — see `docs/superpowers/specs/2026-04-26-sounds-page-design.md`. We add a third:

```
┌───────────────────────────────────────────┐
│ ‹  SOUNDS                  [Save mix]     │  ← existing header
│    3 in current mix                        │
├───────────────────────────────────────────┤
│   Sounds   │   Mixes   │   Soundtracks    │  ← tab bar (was 2 tabs)
├───────────────────────────────────────────┤
│ <tab body>                                 │
└───────────────────────────────────────────┘
```

The Save-mix flow continues to apply only to mix mode — the button is disabled when `mode == .soundtrack` (a soundtrack is not a mix). The "N in current mix" subtitle continues to count mix tracks; in soundtrack mode it reads `playing soundtrack` instead.

### 3.2 Focus page reflects current mode

The Focus page shows controls for whichever source is active.

- **Mix mode (today's layout, unchanged):** ring + mix toolbar (`▶ 🗑 +`) + scrollable list of `MixChipRow`s.
- **Soundtrack mode:** ring + a single soundtrack panel below the hairline (logo, title, sub-line, volume slider, pause, "Switch to mix" link if there are saved mix tracks to fall back to). No add/remove affordances on Focus — those live on the Soundtracks tab.
- **Idle:** ring + the existing "No sounds playing — tap Select below" placeholder.

Toggling between modes is implicit (driven by Sounds-page interaction), but Focus has one explicit affordance: a "Switch to mix" link inside the soundtrack panel, visible only when the user has a non-empty saved mix loaded. Tapping it sets `mode = .mix`, resumes the previously-paused mix tracks.

The play-all button on Focus toggles play/pause on whichever source is active. In `.idle`, it is disabled.

---

## 4. Soundtracks tab

### 4.1 Anatomy

```
┌───────────────────────────────────────────┐
│ ‹  SOUNDS                                  │
│    playing soundtrack                       │
├───────────────────────────────────────────┤
│   Sounds   │   Mixes   │   Soundtracks*    │  *active
├───────────────────────────────────────────┤
│  MY SOUNDTRACKS   3                  +     │  ← section header w/ add
│  ┌─────────────────────────────────────┐  │
│  │ ▶  Lo-fi beats…   ▶ Active   ⋯       │  │  ← active soundtrack
│  │     youtube                          │  │
│  └─────────────────────────────────────┘  │
│  ┌─────────────────────────────────────┐  │
│  │ ▶  Late Night Tales         ⋯       │  │
│  │     spotify · sign-in saved          │  │
│  └─────────────────────────────────────┘  │
│  ┌─────────────────────────────────────┐  │
│  │ ▶  classical study…         ⋯       │  │
│  │     youtube                          │  │
│  └─────────────────────────────────────┘  │
└───────────────────────────────────────────┘
```

Section header style matches the rest of the app (`10pt SF Pro semibold uppercase 0.08em white/40%`), with a count and a trailing `+` button identical to the Mixes tab pattern.

### 4.2 Soundtrack row

Visual cadence matches `MixChipRow` so all three tabs feel related, but functionally simpler: a soundtrack row is **a tile-like activator**, not a multi-control panel. Volume and pause live on the Focus page when the soundtrack is active.

- **Row container.** ~52pt tall (taller than `MixChipRow` because it's a two-line layout), 12pt corner radius, 12×10pt internal padding. `white/4%` fill, `white/8%` border.
- **Leading glyph.** 22×22pt rounded square with the provider mark. Designer chooses between full-color (YouTube red `#FF0000`, Spotify green `#1DB954`) and monochrome SF Symbols (`play.rectangle.fill` / `music.note`); engineering accommodates either.
- **Two-line meta.**
  - **Title** — `12pt white, semibold`. Populated by the JS bridge (`getVideoData().title` for YouTube, `playback_update.name` for Spotify). Until the bridge fires, fall back to a parsed-URL stub (`YouTube video`, `Spotify playlist`, etc.). Tail-truncates.
  - **Sub-line** — `10.5pt white/45%`, lowercase: `youtube` or `spotify`. May append a status fragment in `accent` color when relevant: `· offline`, `· unavailable`, `· sign-in required`, or `· sign-in saved` (faint, for the first 24h after a successful Spotify login as a confidence cue).
- **Trailing.** `⋯` button (22pt) opens a context menu with `Delete` (and `Open in browser` as a quality-of-life nicety). Right-click on the row body opens the same menu.
- **Active indicator.** When this row's id matches `mode == .soundtrack(id)`:
  - Border thickens to 1.5pt and shifts to accent.
  - A small `▶ Active` chip appears in the meta column (same style as the "currently loaded" chip on the Mixes tab — `9pt semibold uppercase, accent color, accent/15% pill`).

### 4.3 Tap behaviour

- Tap the row body when **inactive** → activate. Sets `mode = .soundtrack(id)`. Auto-plays once the bridge reports ready.
- Tap the row body when **active** → deactivate. Sets `mode = .idle`. Pauses the web view.
- Tap `⋯` → context menu. (Tap on `⋯` does NOT toggle activation.)
- Long-press / right-click → same as `⋯`.

The "tap the active row to stop it" interaction is intentional — it makes activation feel like a toggle, mirroring how Sounds-tab tiles toggle membership in the active mix. The visual `▶ Active` chip provides the affordance.

### 4.4 Empty state

```
┌───────────────────────────────────────────┐
│  MY SOUNDTRACKS   0                  +    │
│                                            │
│  ┌ - - - - - - - - - - - - - - - - - ┐    │
│    No saved soundtracks yet                │
│    Paste a YouTube or Spotify link         │
│  └ - - - - - - - - - - - - - - - - - ┘    │
└───────────────────────────────────────────┘
```

Dashed-border card, two centered lines (`11pt white/45%` heading, `10pt white/35%` hint). Same shape as the empty state on the Mixes tab.

### 4.5 Expand-row reveal (Spotify login + skip-track)

Tapping the row's title or `▶` chip activates the soundtrack as described. But there are two cases where the user genuinely needs to **see and interact with the iframe**:

1. **First-time Spotify login.** The bridge reports the sign-in wall (no `playback_update` events fire within 3s of `controller.play()`).
2. **Skip a track / scrub / browse the playlist** (escape valve for any time the user wants the provider's own controls).

Both cases use the same affordance: an inline expansion of the active row, in place, that reveals the iframe.

```
┌───────────────────────────────────────────┐
│  ┌─────────────────────────────────────┐  │
│  │ ▶  Late Night Tales   ▶ Active  ⋯ ⌃│  │
│  │     spotify · sign-in required       │  │
│  │  ─────────────────────────────────   │  │
│  │  ┌───────────────────────────────┐  │  │
│  │  │                               │  │  │
│  │  │   <Spotify embed iframe>      │  │  │
│  │  │   (220pt tall, full width)    │  │  │
│  │  │                               │  │  │
│  │  └───────────────────────────────┘  │  │
│  │                          [ Done ]   │  │
│  └─────────────────────────────────────┘  │
└───────────────────────────────────────────┘
```

- Trigger: a small `⌃` chevron in the row's trailing area. Tap to expand; tap again (or `Done`) to collapse.
- For the first-time Spotify case, the chevron auto-pulses with a subtle accent glow once the bridge reports `sign-in required`. Sub-line reads `spotify · sign-in required`. After successful login, the chevron stops pulsing and sub-line flips to `spotify · sign-in saved` (for 24h), then `spotify`.
- The expanded iframe is **the same `WKWebView`** the controller already owns — it's lifted into the row when expanded and returned to the hidden window when collapsed (use `webView.removeFromSuperview()` and re-add to the hidden window's contentView). This guarantees a single WebKit process and preserves audio continuity across expand/collapse.
- While expanded, the user sees the provider's full UI and can sign in, skip tracks, scrub, queue, etc. Volume control on the row continues to work.
- One soundtrack row is expandable at a time (the active one). Inactive rows show no chevron.

### 4.6 Adding a soundtrack — paste flow

The `+` button on the Soundtracks section header opens an inline paste field, replacing the section-header strip in place (similar to the existing save-mix pattern in `SaveMixHeader`).

```
┌───────────────────────────────────────────┐
│  ┌────────────────────────────────┐ Cancel│
│  │ Paste a YouTube or Spotify URL │   Add │
│  └────────────────────────────────┘       │
└───────────────────────────────────────────┘
```

- **Background tint.** `accent/6%` wash, same as save-mix.
- **Input.** Auto-focused, `13pt white`, accent-tinted 1pt border, 8pt radius, 6×10pt padding. Placeholder `Paste a YouTube or Spotify URL`.
- **Validation states (live, debounced 200ms while typing):**
  - Empty → Add disabled, no error text.
  - Recognizable URL → Add enabled, sub-text reads `YouTube video`, `YouTube playlist`, `Spotify playlist`, etc. in `10pt white/55%`.
  - Recognizable URL but unsupported host → Add disabled, sub-text reads `Only YouTube and Spotify are supported in this version` in `10pt accent`.
  - Garbled input → Add disabled, no error text (don't yell at mid-paste users).
- **On Add:** call `model.addSoundtrack(url:)`, dismiss the entry header, the new row animates in (10pt fade + 4pt translate). If the user is currently `.idle` or `.soundtrack(otherId)`, **the new soundtrack auto-activates** (the user just expressed intent — playing it is the obvious next step). If the user is in `.mix`, the new row appears but does not steal the active source; the user can tap it later.
- **On error returned from controller** (e.g., embed failed to load): the row appears with sub-line `· unavailable` in `accent`.

### 4.7 First-time Spotify hint

The first time a user successfully **adds** a Spotify soundtrack, a one-shot inline note appears under the Soundtracks tab content (above the empty state or below the last row, doesn't matter):

> First time? Tap **⌃** on a Spotify soundtrack to sign in. Your login is saved on this device after that.

Dismiss-on-tap, persisted to a `hasSeenSpotifyLoginHint` UserDefaults flag.

---

## 5. Focus page in soundtrack mode

When `mode == .soundtrack(id)`, the Focus page replaces its mix toolbar and mix list with a single soundtrack panel.

```
┌───────────────────────────────────────────┐
│ FOCUS                              [⚙]    │
│ ● ● ● ○                                   │
├───────────────────────────────────────────┤
│         ┌───── 12:34 ─────┐               │
│         └─────────────────┘               │
├───────────────────────────────────────────┤
│  ▶  ▶  Lo-fi beats…              ⏸       │  ← play-all + soundtrack panel
│      youtube · ───●────                   │  ← provider + volume slider
│                                            │
│              Switch to mix                 │  ← faint link, only if mix exists
└───────────────────────────────────────────┘
```

- The `▶`/`⏸` button on the left is the existing `playAllButton`, repurposed: it toggles play/pause on the active soundtrack via the JS bridge.
- The soundtrack panel: provider glyph (22pt), title (`12pt white`), sub-line `youtube`/`spotify`, thumbless volume slider (`MiniVolumeSlider`, ~120pt wide), pause icon. No remove (use Soundtracks tab) and no add.
- "Switch to mix" — `11pt white/45%`, plain text link, centered. Visible only when `state.tracks.count > 0`. Tap → `model.setModeToMix()` — the previously-loaded mix tracks resume at their saved volumes.
- All other Focus-page chrome (header, ring, dots) is unchanged.

The soundtrack panel does **not** include a volume slider when `mode != .soundtrack` — there's no widget to anchor it. Volume edits made on the Focus panel persist to the soundtrack's `volume` field on the library entry.

---

## 6. Playback control

### 6.1 Play / pause

Whichever source is active responds to:

- **Focus page play-all button** → toggles play/pause on the active source.
- **Focus session ring tap** (`session.toggle()`) → starts/pauses the focus session, mirrors to whichever source is active. Same `setAllPaused` discipline as today, generalized.
- **Auto phase transition** (focus → break, break → focus) → mirrors to the active source.
- **Soundtrack expand-row's iframe controls** → these are out-of-band; the user's clicks inside the iframe directly drive WebKit. Our bridge state listener (`onStateChange` for YouTube, `playback_update` for Spotify) keeps our `paused`-flavored UI in sync after the fact.

### 6.2 Volume

- Mix tracks: per-track sliders on the Focus mix list (existing) + a master via `mixer.outputVolume`.
- Active soundtrack: volume slider on the Focus soundtrack panel, persisted to `WebSoundtrack.volume`. Driven via JS bridge per provider scale.

There is no unified master between mix and soundtrack volumes. Because they never play simultaneously, the practical confusion is small — the only time the user notices is "I switched to a soundtrack and it's loud / quiet relative to my mix." The persisted per-soundtrack volume eliminates that within a single soundtrack.

### 6.3 Popover-closed behavior

Whichever source is active **keeps playing** when the popover dismisses. The hidden NSWindow keeps the WKWebView alive; the existing `AVAudioEngine` already keeps the mix alive. No change here.

---

## 7. Persistence

Three UserDefaults keys:

- `x-noise.savedMix` — existing mix state. Unchanged.
- `x-noise.savedSoundtracks` — JSON array of `WebSoundtrack`s (the library).
- `x-noise.audioMode` — JSON-encoded `AudioMode`. Distinguishes `idle` / `mix` / `soundtrack(id)`.

On launch:
1. Decode all three keys.
2. Reconstruct mix tracks (existing).
3. Recreate the WKWebView in the hidden NSWindow if `audioMode == .soundtrack(id)` and the id resolves to a saved soundtrack — load the embed but **do not autoplay**. Parity with mix behavior.
4. The `Preferences.resumeOnLaunch` flag is intentionally **not** extended to soundtracks in v1; an external soundtrack autoplaying before the user opens the popover is more surprising than helpful.
5. If `audioMode == .soundtrack(id)` but the id is no longer in the library (data corruption / library was edited externally), fall back to `mode = .idle`.

The `title` field on each `WebSoundtrack` is a cache; on reload it's overwritten by the next bridge `titleChanged` event.

---

## 8. Edge cases

- **Network offline at launch.** Web views fail to load embeds. Affected rows show `· offline` in the sub-line. When network returns (`NWPathMonitor`), trigger a single reload pass.
- **Embed becomes unavailable** (deleted video, private playlist). Bridge fires error → sub-line shows `· unavailable` in `accent`. Row stays until the user removes it; activating an unavailable soundtrack keeps `mode = .idle` and surfaces an inline error in the row for ~3s.
- **Spotify login expires.** Sub-line shows `· sign-in required`; chevron auto-pulses on the active row. Tapping the chevron expands the iframe; user re-signs in inside the iframe; cookies refresh.
- **YouTube ad mid-focus.** No suppression in v1. Documented limitation.
- **User pauses focus, expands the iframe to skip a track, resumes focus.** Manual interactions inside the iframe are observable via the bridge's state listener; we mirror back so our UI shows the right play/pause icon. The `pausedByFocus` transient flag (similar to mix behavior) disambiguates "user paused this directly" from "focus paused this."
- **App quit with a soundtrack playing.** Web view and host NSWindow torn down in `applicationWillTerminate`. No fade.
- **System sleep / wake.** Web view naturally pauses on sleep. `Preferences.resumeOnWake` does **not** extend to soundtracks in v1.
- **Headphones plug/unplug.** Pre-existing scope item. Soundtracks behave however WebKit behaves (typically continue playing).
- **Same URL added twice.** Allowed — they're independent library entries with distinct UUIDs. Activating either still respects the one-at-a-time rule. (Could add a soft "you already have this" warning in v2.)
- **User removes the active soundtrack.** Mode falls back to `.idle`. Web view loads `about:blank`. The mix is **not** auto-resumed (consistent with §2.4).
- **User taps a sound on Sounds tab while a soundtrack is playing.** Mode flips to `.mix`. Soundtrack pauses (web view retained). The sound is added to the mix and starts immediately. No confirmation — the user's intent is clear from the action.
- **Focus session ends mid-soundtrack.** Soundtrack pauses on break and resumes on focus, same as mix tracks. End of pomodoro cycle (long break ends, no further sessions) — soundtrack pauses, no auto-restart.

---

## 9. Visual style & tokens

Inherits existing tokens (see `Sources/XNoise/UI/Design/Tokens.swift` and the Sounds-page spec for the established palette).

- **Soundtracks section header.** `MY SOUNDTRACKS   N` matches `MY MIXES   N` style: `10pt SF Pro semibold uppercase 0.08em white/40%`, count `10pt regular white/30%`. Trailing `+` uses the `minimalIcon` pattern.
- **Provider tints.** Used only on the leading 22×22pt glyph on each row. Bulk of the row stays neutral.
- **Active chip.** `▶ Active`, `9pt semibold uppercase accent, accent/15% pill background`. Identical to the Mixes-tab "currently loaded" chip.
- **Status sub-line tints.** Default `white/45%`. Status fragments (`· offline`, `· sign-in required`, `· unavailable`) tint `accent`.
- **Expand-row iframe container.** 220pt tall, full row width minus 12pt horizontal padding, 8pt corner radius, `white/2%` background to make the embed visually contained but not fight the row.
- **Switch-to-mix link.** `11pt white/45%`, no underline, accent on hover.

---

## 10. State summary

| Surface | State | Visual |
|---|---|---|
| Tab bar | Soundtracks tab default | Standard tab styling, count badge optional |
| Soundtracks tab | Empty | Dashed-border empty card, "Paste a YouTube or Spotify link" |
| Soundtracks tab | Has rows | List of soundtrack rows, `+` in header |
| Paste header | Default | `accent/6%` wash, accent-bordered input, Cancel / Add |
| Paste header | Validating ok | Sub-text shows source type, Add enabled |
| Paste header | Unsupported host | Sub-text in accent, Add disabled |
| Soundtrack row | Inactive | `white/4%` fill, no chip |
| Soundtrack row | Active | accent border 1.5pt + `▶ Active` chip + `⌃` chevron |
| Soundtrack row | Active + login required | Same + chevron auto-pulses + sub-line `· sign-in required` |
| Soundtrack row | Expanded | Iframe revealed inline, 220pt tall, `Done` button |
| Soundtrack row | Offline / unavailable | Sub-line status fragment in accent |
| First-time Spotify hint | One-shot | Inline note, dismiss-on-tap |
| Focus page | Mix mode | Today's layout |
| Focus page | Soundtrack mode | Single soundtrack panel + Switch-to-mix link |
| Focus page | Idle | Today's empty state |
| Focus play-all | Active source playing | `pause.fill` |
| Focus play-all | Active source paused | `play.fill` |
| Focus play-all | `.idle` | Disabled |
| Save-mix button | Soundtrack mode | Disabled |

---

## 11. Implementation notes (engineering, not designer)

### 11.1 New files

- `Sources/XNoise/Models/WebSoundtrack.swift` — `WebSoundtrack`, `AudioMode`, `AddSoundtrackError`, `SoundtrackURL` (parser).
- `Sources/XNoise/Audio/WebSoundtrackController.swift` — hidden NSWindow + single WKWebView + provider bridges + activation/deactivation logic.
- `Sources/XNoise/Resources/soundtracks/youtube-bridge.html` — bridge document loaded by WKWebView, hosts the YouTube iframe and exposes `WKScriptMessageHandler` calls.
- `Sources/XNoise/Resources/soundtracks/spotify-bridge.html` — same for Spotify IFrame API.
- `Sources/XNoise/UI/Pages/SoundtracksTab.swift` — the new tab body.
- `Sources/XNoise/UI/Components/SoundtrackChipRow.swift` — row component (collapsed + expanded states).
- `Sources/XNoise/UI/Components/AddSoundtrackHeader.swift` — paste-a-link header (visual peer of `SaveMixHeader`).
- `Sources/XNoise/UI/Components/SoundtrackPanel.swift` — the Focus-page panel for soundtrack mode.

### 11.2 Hidden NSWindow

Create at `NSRect(x: -10000, y: -10000, width: 1, height: 1)`, `level = .normal`, `isExcludedFromWindowsMenu = true`, `ignoresMouseEvents = true`, `isReleasedWhenClosed = false`. The contentView holds the `WKWebView` (full-bleed when collapsed, since the user can't see it anyway). When the row is expanded on the Soundtracks tab, the web view is reparented into the row's container; on collapse, it returns to the hidden window. Use `wantsLayer = true` and `webView.translatesAutoresizingMaskIntoConstraints = false` when reparenting.

### 11.3 JS bridges

Bridges are static HTML files loaded as `loadFileURL(_:allowingReadAccessTo:)` for the WKWebView's main document. The bridge HTML includes the provider's API script and exposes a small `bridge` object that posts JSON messages via `webkit.messageHandlers.xnoise.postMessage(...)`. The Swift side conforms to `WKScriptMessageHandler` and routes events back into `WebSoundtrackController`. Event names: `ready`, `stateChange`, `error`, `titleChanged`, `signInRequired` (computed in JS by watching for the absence of `playback_update` after `play()`).

### 11.4 SoundtrackURL parser

Pure value type; static `parse(_ raw: String) -> Result<SoundtrackURL, AddSoundtrackError>`. Recognized hosts:

- YouTube: `youtube.com/watch?v=…`, `youtu.be/…`, `youtube.com/playlist?list=…`, `m.youtube.com/...`, `music.youtube.com/...`
- Spotify: `open.spotify.com/{track,album,playlist,episode,show}/<id>` (with or without trailing query string)

Normalizes to embed form. Anything else returns `.unsupportedHost`.

### 11.5 FocusSession phase-change hook

Today the auto phase transition does not mirror to audio (only the manual ring tap does — see `FocusPage.ringTap` in `Sources/XNoise/UI/Pages/FocusPage.swift`). Add an `onPhaseChange: ((FocusSession.Phase) -> Void)?` closure that `AppModel` wires up at construction. The closure routes through a single `pauseActiveSource(_ paused: Bool)` method on `AppModel` that does the right thing based on `mode`:

- `.idle` → no-op
- `.mix` → `state.setAllPaused(paused)` + `mixer.reconcileNow()`
- `.soundtrack(id)` → `controller.setPaused(paused)`

### 11.6 Mode transition implementation

`AppModel.activateSoundtrack(_ id: UUID)`:

```
1. If mode == .soundtrack(id), no-op (idempotent).
2. If mode == .soundtrack(otherId), tell controller to pause + reload to new URL.
3. If mode == .mix, call mixer.pauseAll() (preserves per-track state).
4. Set mode = .soundtrack(id), persist.
5. Tell controller to load + play (or just play if already loaded for this id).
6. If a focus session is currently running, the soundtrack starts playing immediately on bridge `ready`.
```

`AppModel.toggleTrack(_ trackId: String)` (existing) gains a side-effect:

```
1. If mode == .soundtrack, tell controller to pause + load about:blank, then mode = .mix.
2. Existing toggle-track logic runs.
```

Same kind of side-effect lives on `applyPreset` and any other mix mutation.

### 11.7 Tests

- `SoundtrackURLTests` — host variants enumerated in §11.4, including `youtu.be` short links, Spotify with `?si=...` trackers, music.youtube.com.
- `WebSoundtrackPersistenceTests` — encode/decode `WebSoundtrack` (handles missing optional `title`, empty array, AudioMode round-trip including the associated-value `.soundtrack(UUID)` case).
- `AppModelSoundtrackTests` — full mode-transition matrix (every cell of the table in §2.4). Mock the controller behind a protocol so tests don't need a WKWebView.
- `FocusSessionPhaseHookTests` — auto phase transitions fire `onPhaseChange`; mix and soundtrack modes both react correctly under fake clock.
- WKWebView itself is **not** unit-tested. Manual smoke test in the implementation plan.

### 11.8 Existing constraints from CLAUDE.md still apply

- `@EnvironmentObject` for observed objects, no init-passed `@ObservedObject`.
- No `@MainActor` on UserDefaults wrappers.
- `.contentShape` after `.clipShape`.
- WKWebView audio runs on WebKit's own threads; everything else stays on `@MainActor`.

### 11.9 Update other docs

The existing Sounds-page design doc (`docs/superpowers/specs/2026-04-26-sounds-page-design.md`) currently lists "Internet soundtracks (YouTube/Spotify) — likely a separate page later" in §1 non-goals and §10. Patch both references to point to this spec instead. Tab bar diagrams in §2 and §3 should grow to three tabs.
