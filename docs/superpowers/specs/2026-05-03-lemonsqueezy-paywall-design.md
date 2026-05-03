# LemonSqueezy paywall — design

Date: 2026-05-03
Status: Spec, awaiting review

## Summary

Add license-key-based paywall to Shuuchuu. App is free for a 5-day trial, then locks until the user enters a valid LemonSqueezy license key. License is bound to up to 3 Macs per purchase. Online activation; soft online revalidation thereafter.

## Product decisions (settled)

| Decision | Choice |
|---|---|
| Monetization | One-time purchase, lifetime access |
| Gating shape | Paid app with trial — end-to-end gating |
| Trial length | 5 days |
| Trial-end behavior | Hard lockout — no audio, no soundtrack, no timer; popover shows `LockedView` |
| License delivery | Manual key paste in-app (no magic-link / no URL scheme) |
| Online check cadence | Activate online; revalidate on launch *softly* (network errors never lock the user out — only an explicit `valid:false` from LS does) |
| Devices per license | 3 (LS `activation_limit = 3`) |

## Architecture

Three new types, all Sendable, all following existing controller patterns. Mirrors how `Catalog`, `Favorites`, `SavedMixes`, `MixingController` are structured.

### `LicenseController` — `@MainActor, ObservableObject`

Single source of truth for entitlement. Sibling to `Catalog`/`Favorites`/`SavedMixes` inside `AppModel`.

- `@Published var state: LicenseState`
- `var isUnlocked: Bool { state.isUnlocked }` — read by `AppModel` and the UI
- Public actions:
  - `startTrialIfNeeded()` — synchronous; reads Keychain, sets initial state
  - `activate(key: String) async throws` — calls `/v1/licenses/activate`
  - `revalidate() async` — calls `/v1/licenses/validate`, soft-fail
  - `deactivateThisDevice() async throws` — calls `/v1/licenses/deactivate`, then clears Keychain
  - `signOut()` — local-only; clears license fields, transitions to `.trialExpired` (trial clock has burned)
- Owns: a `LemonSqueezyClient` instance, a `LicenseStorage` instance, and a 60s `Timer.publish` that watches the trial clock and flips `.trial → .trialExpired` mid-session.

### `LemonSqueezyClient` — `actor`

Thin wrapper around three LS endpoints. All POST, `Content-Type: application/x-www-form-urlencoded`, JSON responses. No API key — the license key is the credential.

```
POST https://api.lemonsqueezy.com/v1/licenses/activate
  body: license_key=<key>&instance_name=<machine_name>
  → 200 { activated: true, instance: { id }, license_key: { status, activation_limit, activation_usage } }
  → 200 { activated: false, error: "<message>" }   // already at limit, etc.

POST https://api.lemonsqueezy.com/v1/licenses/validate
  body: license_key=<key>&instance_id=<id>
  → 200 { valid: true|false, license_key: { status: "active|inactive|expired|disabled" }, ... }

POST https://api.lemonsqueezy.com/v1/licenses/deactivate
  body: license_key=<key>&instance_id=<id>
  → 200 { deactivated: true }
```

`instance_name` is `Host.current().localizedName ?? "Mac"` — surfaces in the user's LS dashboard so they know which Mac to deactivate when they hit the 3-device cap.

Uses `URLSession.shared`, `Codable` request/response types, throws `LSError` for typed errors.

### `LicenseStorage` — Keychain wrapper

One service: `com.bluedusk.shuuchuu.license`. Stores:

- `licenseKey` — the LS license string
- `instanceId` — returned from `/activate`
- `trialStartedAt` — ISO 8601 timestamp, set on first launch with no key
- `lastValidated` — ISO 8601 timestamp of last successful `/validate`
- `lastSeenWallclock` — monotonically-increasing timestamp; clock-rollback defense

Trial start lives in Keychain rather than UserDefaults so it survives `defaults delete` and a Library/Preferences wipe. Not bulletproof against a determined user, but raises the bar past "delete a plist".

### `Constants.swift` additions

```swift
enum License {
  static let storeURL = URL(string: "https://shuuchuu.lemonsqueezy.com/buy/<variant-id>")!
  static let apiBase  = URL(string: "https://api.lemonsqueezy.com/v1/licenses")!
  static let trialDuration: TimeInterval = 5 * 24 * 60 * 60
  static let activationLimit = 3
  static let keychainService = "com.bluedusk.shuuchuu.license"
}
```

`<variant-id>` is filled in once the LemonSqueezy product is created.

### Wiring into `AppModel`

`AppModel.init` creates `licenseController` alongside the other subsystems.

`AppModel.bootstrap()`:
1. `licenseController.startTrialIfNeeded()` — synchronous, reads Keychain, publishes initial state.
2. If `state == .licensed`: `Task { await licenseController.revalidate() }` — fire-and-forget, soft.
3. Catalog load and other bootstrap continue concurrently.

The following `AppModel` methods early-return when `!licenseController.isUnlocked`:
- `toggleTrack`, `togglePlayAll`, `togglePause`, `setTrackVolume`
- `applyPreset`, `applySavedMix`, `saveCurrentMix`, `removeSavedMix`
- `setSoundtrackEntry`, `togglePauseSoundtrack`, `addSoundtrack`
- `FocusSession.start/pause/resume`

The UI layer never calls these in the locked state because `LockedView` replaces `FocusPage`, but the early-return is defense-in-depth.

## State machine

```
LicenseState (enum):
  .uninitialized                                       // before bootstrap reads Keychain
  .trial(startedAt: Date)                              // within 5 days of first launch
  .trialExpired                                        // hard lockout, no key entered
  .licensed(key: String, instanceId: String, lastValidated: Date)
  .revoked(reason: RevokeReason)                       // LS returned valid=false (refunded/disabled)

RevokeReason: .disabled | .expired | .refunded
isUnlocked: { .trial, .licensed → true; rest → false }
```

### Transitions

- **`startTrialIfNeeded()`** (called once per launch, very early):
  - If Keychain has `licenseKey`: enter `.licensed` with `lastValidated` from Keychain (or distant past if missing). Let `revalidate()` confirm.
  - Else if Keychain has `trialStartedAt`:
    - If `now - trialStartedAt < 5 days`: enter `.trial(startedAt:)`.
    - Else: enter `.trialExpired`.
  - Else (first ever launch): write `now` as `trialStartedAt`, enter `.trial(startedAt: now)`.

- **`activate(key:)`** (from `ActivationSheet`):
  1. Validate key format locally — fast-fail for empty/wrong-shape input without a network round-trip.
  2. POST `/v1/licenses/activate`.
  3. On `200 + activated:true`: write `licenseKey` + `instanceId` + `lastValidated=now` to Keychain. Transition to `.licensed`.
  4. On `200 + activated:false` with `activation_limit_reached`: throw `LSError.activationLimitReached`. Stay in current state.
  5. On other failures: throw typed `LSError`. Stay in current state.

- **`revalidate()`** (from `bootstrap()` after `startTrialIfNeeded`):
  - Only runs when state is `.licensed`.
  - POST `/v1/licenses/validate` with stored key + instance_id.
  - On `valid:true`: update `lastValidated` in memory and Keychain.
  - On `valid:false` with `status: "disabled"`: transition to `.revoked(.disabled)`.
  - On `valid:false` with `status: "expired"`: transition to `.revoked(.expired)`.
  - **On any network error / non-2xx / unparseable response: log, do nothing.** Soft-revalidation rule.

- **`deactivateThisDevice()`** (from Settings → "Sign out of this Mac"):
  1. POST `/v1/licenses/deactivate`.
  2. On success OR network failure: clear Keychain license fields (key + instanceId + lastValidated). Keep `trialStartedAt` — the trial clock has already burned.
  3. Transition to `.trialExpired`. (User must enter another key or buy a new one.)
  4. If the call failed, log it; the user pressed sign-out and we honour that locally.

- **Trial timer tick** (`Timer.publish(every: 60)`):
  - When in `.trial(startedAt:)` and `now - startedAt >= 5 days`: transition to `.trialExpired`.
  - Idempotent; no-op in any other state.

- **License entered during trial:** `activate(key:)` succeeds → transition to `.licensed`. Trial clock becomes irrelevant.

### Edge case: clock rollback

To prevent extending the trial by setting the system clock backwards: every read of "now" inside `LicenseController` uses `effectiveNow = max(Date(), lastSeenWallclock)`, where `lastSeenWallclock` is persisted to Keychain and updated each time `effectiveNow > lastSeenWallclock`. Going backwards becomes a no-op for trial accounting. Cost: ~10 lines.

## UI surfaces

### 1. `LockedView` (new file: `Sources/Shuuchuu/UI/Pages/LockedView.swift`)

Replaces `FocusPage` body when `!licenseController.isUnlocked`. Same popover dimensions, same Liquid Glass styling. Layout:

- 集中 logo + headline. State-dependent string:
  - `.trialExpired` → "Your 5-day trial has ended."
  - `.revoked(.refunded)` → "This license was refunded."
  - `.revoked(.disabled)` → "This license is no longer active."
  - `.revoked(.expired)` → "This license has expired."
- Subline (state-dependent).
- Two buttons (`.glassProminent`):
  - **"Buy Shuuchuu"** → opens `Constants.License.storeURL` via `NSWorkspace.shared.open(_:)`.
  - **"Enter license key"** → presents `ActivationSheet`.

The menubar logo gets a small lock glyph overlay when locked, so users see entitlement state without opening the popover.

### 2. `ActivationSheet` (new file: `Sources/Shuuchuu/UI/Components/ActivationSheet.swift`)

Small modal presented from `LockedView` and from `SettingsPage`'s License section.

- Header: "Enter license key"
- One field: `TextField("XXXX-XXXX-XXXX-XXXX")` — monospaced, autocorrect off, autocapitalize off, paste-friendly.
- One button: **Activate** — disabled when field empty or while a request is in flight. Shows a spinner during.
- Calls `licenseController.activate(key:)`.
- On success: sheet dismisses, popover swaps back to `FocusPage`.
- On error: inline error message under the field, mapped from typed `LSError` (see Error handling).

### 3. Settings → "License" section (additions to `Sources/Shuuchuu/UI/Pages/SettingsPage.swift`)

State-dependent rendering:

- **Trial:** "Trial — N days remaining" + "Enter license key" button (presents `ActivationSheet`).
- **Licensed:** masked key (`XXXX-…-EFGH`), "Activated on this Mac on `<date>`", "Sign out of this Mac" button (presents confirm alert, then calls `deactivateThisDevice()`).
- **Locked / Revoked:** state-explainer line + "Enter license key" button.

### 4. Trial-end-imminent nudge

On day 4 and day 5 of the trial, an unobtrusive pill at the bottom of `FocusPage` reads "Trial ends tomorrow · Buy". One pill, dismissable per session, comes back next launch. No modal popups during the trial.

## Bootstrap & flow diagrams

### App launch
```
AppModel.bootstrap():
  1. licenseController.startTrialIfNeeded()
       reads Keychain synchronously
       publishes .trial / .trialExpired / .licensed / .revoked
       UI renders correct surface immediately
  2. if state == .licensed:
       Task { await licenseController.revalidate() }
       (fire-and-forget; UI never waits)
  3. Catalog load + other bootstrap proceed concurrently
```

### Activation
```
User pastes key in ActivationSheet
  → LicenseController.activate(key:)
  → local format check (length + allowed chars)
  → LemonSqueezyClient.activate(key, instance_name)
  → POST /v1/licenses/activate
  → on 200 activated:true:
       LicenseStorage.write(key, instanceId, lastValidated=now)
       state = .licensed(...)
       sheet dismisses
  → on failure:
       throw LSError
       sheet renders inline message
```

### Deactivation
```
Settings → "Sign out of this Mac" → confirm alert
  → LicenseController.deactivateThisDevice()
  → LemonSqueezyClient.deactivate(key, instanceId)
  → on success OR network failure:
       LicenseStorage.clearLicenseFields()
       state = .trialExpired
  → log network failure if any
```

## Error handling

### `LSError` typed enum (thrown from `LemonSqueezyClient`)

```swift
enum LSError: Error {
  case network(URLError)
  case malformedResponse
  case licenseNotFound
  case activationLimitReached
  case licenseDisabled
  case licenseExpired
  case alreadyActivatedOnThisMachine  // /activate called when instance_id already on file (recovery path)
  case server(status: Int, body: String)
}
```

### Activation-sheet user-facing strings

| Error | Message |
|---|---|
| `network` | "Couldn't reach the license server. Check your connection and try again." |
| `licenseNotFound` | "We couldn't find that license. Double-check the key from your purchase email." |
| `activationLimitReached` | "This license is already on 3 Macs. Sign out from one in its Shuuchuu Settings, then try again." |
| `licenseDisabled` | "This license is no longer active. Contact support if this is unexpected." |
| anything else | "Activation failed. Please try again." |

### Revalidate (background, soft)

| Outcome | Behavior |
|---|---|
| `valid:true` | Update `lastValidated`. Stay `.licensed`. |
| `valid:false` + `status:"disabled"` | Transition to `.revoked(.disabled)`. |
| `valid:false` + `status:"expired"` | Transition to `.revoked(.expired)`. |
| network error / malformed / non-2xx | Log + ignore. Stay `.licensed`. |

The user can never lose access from a network glitch. Only an explicit `valid:false` from LS revokes.

### Keychain write failures

Rare (user denies access). Surface a one-time banner: "Shuuchuu can't save your license to the Keychain. Activation will need to be repeated next launch." Trial-clock in this case stays in-memory; effectively resets on relaunch. Acceptable failure mode.

### Logging

All LS interactions go through `os.Logger(subsystem: "com.bluedusk.shuuchuu", category: "license")`.

- License key is **never logged** — only last 4 chars (`…EFGH`).
- `instance_id` is logged in full (it's not a credential).
- No analytics, no crash reporting (existing app has none).

## Testing

Unit tests in `Tests/ShuuchuuTests/`, alongside existing `*Tests.swift` files:

- **`LicenseStateTests.swift`** — state machine transitions: trial start, trial-clock expiry at 5 days, licensed-after-activate, revoke-on-validate-false, soft-fail on network error, clock-rollback no-op.
- **`LemonSqueezyClientTests.swift`** — uses a `URLProtocol` stub to inject canned responses. Covers each `LSError` path: `licenseNotFound`, `activationLimitReached`, `licenseDisabled`, `network`, `malformedResponse`. Verifies request body encoding (form-urlencoded, correct field names).
- **`LicenseStorageTests.swift`** — Keychain round-trip via a fake `KeychainBackend` protocol (so we don't pollute the real keychain in CI). Verifies writes, reads, clears.
- **`LicenseControllerTests.swift`** — integration test of controller + fake client + fake storage. Covers: activation success path, activation-failure-stays-in-trial, revalidate-soft-fail, deactivate-clears-keys, trial-timer-tick.
- **`AppModelGatingTests.swift`** — verifies the gated `AppModel` methods early-return when `licenseController.isUnlocked == false`.

UI is preview-only (existing project convention — no snapshot tests).

## Implementation file list

New files:
- `Sources/Shuuchuu/License/LicenseController.swift`
- `Sources/Shuuchuu/License/LicenseState.swift`
- `Sources/Shuuchuu/License/LemonSqueezyClient.swift`
- `Sources/Shuuchuu/License/LicenseStorage.swift`
- `Sources/Shuuchuu/UI/Pages/LockedView.swift`
- `Sources/Shuuchuu/UI/Components/ActivationSheet.swift`
- `Tests/ShuuchuuTests/LicenseStateTests.swift`
- `Tests/ShuuchuuTests/LemonSqueezyClientTests.swift`
- `Tests/ShuuchuuTests/LicenseStorageTests.swift`
- `Tests/ShuuchuuTests/LicenseControllerTests.swift`
- `Tests/ShuuchuuTests/AppModelGatingTests.swift`

Modified files:
- `Sources/Shuuchuu/AppModel.swift` — wire `LicenseController`, gate user-action methods.
- `Sources/Shuuchuu/Constants.swift` — add `License` enum constants.
- `Sources/Shuuchuu/UI/Pages/FocusPage.swift` — swap to `LockedView` when locked; trial-end-imminent pill.
- `Sources/Shuuchuu/UI/Pages/SettingsPage.swift` — add License section.
- `Sources/Shuuchuu/ShuuchuuApp.swift` — menubar lock-glyph overlay when locked.

## Out of scope (deliberately deferred)

- Magic-link activation via custom URL scheme (`shuuchuu://activate?key=...`).
- License-recovery flow ("I lost my key"). Goes through LemonSqueezy's own customer portal.
- Receipts / invoices view inside the app.
- Webhook handler for refunds (covered by soft revalidate-on-launch).
- Educational discount, family plans, gift codes.
- Mac App Store distribution (uses StoreKit, not LemonSqueezy — incompatible model).
- Analytics on conversion / activation funnel.
