# YouTube Ad-Bypass Report

**Date:** 2026-04-28
**Context:** Soundtracks v1 (shipped 2026-04-27) lets users paste YouTube URLs as focus soundtracks. YouTube ads interrupt playback, breaking the "background audio for focus sessions" use case. This report captures the constraint space, what we tried, and the realistic options for fully ad-free playback.

---

## TL;DR

There is **no clean way** to play arbitrary YouTube videos ad-free in our embedded WKWebView. Every path is a trade-off:

| Path | Any video? | User effort | Maintenance | Risk |
|---|---|---|---|---|
| Cosmetic mute/skip *(shipped)* | yes | none | low | **music still pauses during ads** |
| **A. Network-level ad blocking** | mostly | none | high | YouTube anti-adblock wall |
| **B. Safari cookie sync (YT Premium)** | yes | Full Disk Access + Premium | medium | brittle to macOS / Safari updates |
| **C. Direct stream extraction** (yt-dlp-style) | yes | none | very high | YouTube TOS, ongoing arms race |
| **Spotify Premium** *(already shipped)* | yes (Spotify content) | sign in once | none | none — recommended path |

**Recommendation:** position **Spotify Premium as the supported ad-free music path**. For YouTube, ship **A (network ad-block)** if "paste any video, no ads" is a hard requirement, with explicit acceptance of the maintenance burden.

---

## 1. The Constraint

YouTube's player serves ads on the same `<video>` DOM element used for the actual content. When an ad fires, YouTube swaps the element's source to the ad video, plays it, then swaps back. We cannot prevent this from inside the page without preventing the ad request itself.

**Three layers of enforcement to consider:**

1. **Embed restrictions (errors 101 / 150 / 152).** Publisher disables iframe embedding. Already worked around: we fall back to loading `youtube.com/watch?v=<id>` directly when the embed errors. See `WebSoundtrackController.handlePlaybackError`.
2. **Ad insertion at playback.** YouTube inserts pre-roll / mid-roll ads regardless of how the page is loaded. This is what blocks the "background audio" UX.
3. **Sign-in gate.** Google blocks WKWebView sign-ins. We cannot ask the user to sign in within our app.

This report is about layer 2.

## 2. What's Currently Shipped

`Sources/XNoise/Resources/soundtracks/youtube-control.js`:

- Detects ads via `.html5-video-player.ad-showing` class
- Mutes audio while ads play (so the user hears silence, not the ad)
- Auto-clicks `.ytp-ad-skip-button*` when present
- Fast-forwards `currentTime = duration - 0.1` for VOD content with finite duration
- CSS-hides static promo elements (banners, end-screen overlays, in-feed display ads)

**Honest assessment:** this is **cosmetic, not functional**. For unskippable ads on live streams (`duration = Infinity`), the user's music is replaced by silence for 15–30 seconds. The ad is still requested, fetched, played by the browser, and counted as an impression by YouTube. We just hide it from the user's senses.

The mute logic should probably stay (zero cost, occasionally helps), but it does not solve the actual problem.

## 3. The Three Real Paths

### A. Network-level ad blocking (`WKContentRuleList`)

**How it works.** Configure WKWebView to block requests to YouTube's ad-serving hosts at the network layer:

- `doubleclick.net`
- `googlesyndication.com`
- `googleadservices.com`
- `youtube.com/api/stats/ads`
- `youtube.com/pagead/*`

Combined with DOM-level logic to dismiss YouTube's "we detected an ad blocker" interstitial when it appears.

**Pros.**
- Works for any video, no user input
- Saves bandwidth (ads never fetched)
- Same approach as uBlock Origin / Brave / etc.

**Cons.**
- YouTube has been actively detecting and challenging ad blockers since ~2023
- Anti-adblock wall, when triggered, halts playback entirely until dismissed
- Detection methods change every few months — we'd need to patch the rule list and DOM-dismissal script in lockstep
- Ethical / TOS gray (less so for the user, more so for us as the app vendor)

**Effort to ship:** ~1–2 hours initial. Ongoing: occasional same-day patches when YouTube updates detection.

**Reliability:** ~80–95% depending on YouTube's current detection state. Fluctuates week to week.

### B. Safari cookie sync (YouTube Premium)

**How it works.** Read the user's Safari cookie file (`~/Library/Containers/com.apple.Safari/Data/Library/Cookies/Cookies.binarycookies`), parse out cookies for `.youtube.com`, and inject them into our `WKHTTPCookieStore`. Our WKWebView is then authenticated as the user's Safari YouTube session — including their Premium subscription.

**Why this is the only way to use Premium.** YouTube's Premium status is enforced by session cookies, not API tokens. Google blocks WKWebView sign-ins. So we can't authenticate inside our app — but we can copy authentication that happened *outside* our app.

**Pros.**
- Works completely: Premium membership recognized, no ads, full features
- One-time setup (Full Disk Access prompt on first use)
- No arms race with YouTube — we're using legitimate auth

**Cons.**
- Requires user has YouTube Premium (paid subscription)
- Requires user grant Full Disk Access (security-sensitive)
- App must be unsandboxed (currently is, but blocks future MAS distribution)
- Safari cookie file format is reverse-engineered, not Apple-supported — could break on macOS updates
- Cookies expire and refresh; we'd need to re-sync periodically (e.g., on app launch)
- If user signs out in Safari, our WKWebView goes signed-out at next sync

**Effort to ship:** ~half-day initial. Ongoing: occasional fixes for macOS/Safari format changes.

**Reliability:** ~98% while it works. Bimodal — either fully working or fully broken.

### C. Direct stream extraction

**How it works.** Replicate what `yt-dlp` / NewPipe do: fetch the watch page, run YouTube's deobfuscation JS to derive a direct streaming URL for the audio track, play it through `AVAudioEngine` like our other tracks.

**Why this is the best UX (if it works).** No web view, no ads, no embed restrictions, no Premium needed. Streams play in the existing audio engine and mix cleanly with ambient sounds. Live streams work. The watch-page WKWebView would be unnecessary entirely for YouTube.

**Pros.**
- 100% reliable when extraction logic is current
- Best possible UX — instant start, no overhead, mixable with ambient tracks
- No web view dependency; lower memory; no ads; no restrictions

**Cons.**
- TOS gray zone (YouTube prohibits this in their TOS)
- Stream URLs expire (~6 hours typical) — need refresh logic
- YouTube re-obfuscates extraction every few weeks; libraries like yt-dlp track this with hundreds of contributors
- We'd be a one-person project chasing yt-dlp updates, OR shipping yt-dlp as a binary/Python dependency
- Bundling a Python interpreter + yt-dlp is a heavy dependency for a focus app
- Risk of YouTube IP-blocking the user's app session if detected

**Effort to ship:** ~2–3 days initial (Swift port of extraction OR yt-dlp bundling + invocation). Ongoing: significant — every YouTube update could break extraction.

**Reliability:** unpredictable. Can be 100% for months, then 0% for a day, then back.

## 4. What Was Considered and Rejected

- **Fictional baseURL (`x-noise.local`).** Set in earlier debugging; YouTube's IFrame API silently fails on unrecognized origins. Replaced with `https://www.youtube.com/` (same-origin with the embed iframe).
- **`youtube-nocookie.com` host.** Tried to bypass tracking-cookie restrictions. Did not bypass embed restrictions (errors 101/150/152) — those are at the playback layer.
- **Cosmetic mute/skip.** Shipped, but does not solve the actual problem (music still pauses during ads on live streams).
- **Per-video ad-presence detection + UI badges.** Rejected — burdensome curation cycle, bad UX.
- **`ASWebAuthenticationSession` for Google sign-in.** Returns OAuth tokens, but YouTube Premium is enforced at the cookie session layer, not API. Doesn't help.
- **YouTube Data API.** Doesn't expose ad-presence reliably; doesn't expose Premium status. Not useful.

## 5. Recommendation

**Tier the experience by audio source:**

1. **Spotify Premium** = "the supported ad-free path." Already shipping, login works in our WKWebView, no ads on Premium, no engineering work. **Position this in the UI as the recommended source for music.**

2. **YouTube without Premium** = "best effort, may have ads." Keep the cosmetic mute/skip we shipped. Don't add detection badges or curation friction. Users will discover ad-laden videos and self-curate.

3. **YouTube with Premium** = require either (a) **Path B (Safari cookie sync)** if the user can grant Full Disk Access, or (b) accept that we can't honor their subscription.

**Skip Path C unless we want to make YouTube extraction a primary feature.** It's the best UX but the worst engineering investment for a small focus app.

**Skip Path A unless "paste any video, no ads" is hard-required.** It works most of the time but the maintenance burden is real and the "we detected an ad blocker" wall is a worse UX than ads themselves when it triggers.

## 6. Open Questions

- Is YouTube Premium support important enough to ship Path B?
- Does the target user understand "use Spotify for music, YouTube for stuff that's already free" framing, or do they expect the app to make YouTube ad-free transparently?
- If we ship Path A, do we want to alert the user when the anti-adblock wall is detected (so they know why playback froze), or fail silently?

## 7. Code Pointers

- `Sources/XNoise/Audio/WebSoundtrackController.swift` — controller, embed-vs-watch fallback
- `Sources/XNoise/Resources/soundtracks/youtube-control.js` — injected user script, ad mute/skip logic
- `Sources/XNoise/Resources/soundtracks/youtube-bridge.html` — embed iframe bridge (used first)
- `Sources/XNoise/Resources/soundtracks/spotify-bridge.html` — Spotify embed bridge
- `docs/superpowers/specs/2026-04-27-soundtracks-design.md` — original soundtracks design
