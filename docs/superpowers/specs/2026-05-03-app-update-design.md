# In-app self-update (Sparkle) — design

Date: 2026-05-03
Status: Spec, awaiting review

## Summary

Add Sparkle-based in-app updates to Shuuchuu so shipped builds can pull a newer version, verify the EdDSA signature, and replace themselves without the user re-downloading from a website. Mirror the x-island implementation: thin `@Observable` wrapper around `SPUStandardUpdaterController`, beta channel via a UserDefaults flag, GitHub Releases as the binary host, an `appcast.xml` checked into the repo on `main` (served via `raw.githubusercontent.com`), and a one-command `release.sh` that signs, notarises, zips, uploads, and bumps the appcast.

This is *only* the auto-update feature. The LemonSqueezy paywall is a separate spec (`2026-05-03-lemonsqueezy-paywall-design.md`) and is unaffected.

## Product decisions (settled)

| Decision | Choice |
|---|---|
| Update framework | Sparkle 2.9+ via SPM |
| Distribution | GitHub Releases zip; Homebrew cask deferred |
| Appcast hosting | `https://raw.githubusercontent.com/bluedusk/x-noise/main/appcast.xml` (checked-in file, no extra infra) |
| Channels | Stable + Beta. Beta toggle hidden behind 5-tap reveal on the version row in Settings; backed by `UserDefaults["app.betaUpdates"]` |
| Settings UI | Full "Updates" section: current version, "Check now", auto-check toggle, auto-install toggle, "What's new" link, beta reveal |
| Menubar nudge | Tiny dot overlay on the 集中 logo when an update is available |
| Code signing | Developer ID + notarytool, hardened runtime; entitlements file holds only `com.apple.security.network.client` (unsandboxed for v1) |
| Auto-check defaults | Enabled, every 24 h, auto-download off (user confirms before install) |

## Architecture

### `UpdateChecker` — `@MainActor ObservableObject`

Mirror of `Sources/xIslandApp/UpdateChecker.swift`, but using `ObservableObject` + `@Published` instead of `@Observable` to match Shuuchuu's existing controller pattern (`Catalog`, `LicenseController`, `Favorites`, etc. are all `ObservableObject`). One file: `Sources/Shuuchuu/Update/UpdateChecker.swift`.

```swift
@MainActor
final class UpdateChecker: NSObject, ObservableObject {
    static let releasesURL = URL(string: "https://github.com/bluedusk/x-noise/releases")!

    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var hasUpdate = false
    @Published private(set) var latestVersion: String?
    @Published private(set) var lastCheckDate: Date?

    private var controller: SPUStandardUpdaterController!
    private var canCheckCancellable: AnyCancellable?

    override init() {
        super.init()
        controller = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
    }

    func startIfNeeded()       // call once from AppModel.bootstrap()
    func checkForUpdates()      // user-initiated "Check now"
}
```

`startIfNeeded` calls `try controller.updater.start()` and KVO-bridges `\.canCheckForUpdates` and `\.lastUpdateCheckDate` to the `@Published` properties so SwiftUI re-renders correctly.

Auto-check / auto-install / interval are read from Info.plist by Sparkle itself (`SUEnableAutomaticChecks`, `SUAutomaticallyUpdate`, `SUScheduledCheckInterval`) — no first-launch permission prompt.

### `SPUUpdaterDelegate` extension

Two delegate methods we implement:

- `allowedChannels(for:)` → `["beta"]` if `UserDefaults["app.betaUpdates"] == true`, else `[]` (stable only).
- `updater(_:didFindValidUpdate:)` → set `hasUpdate = true`, `latestVersion = item.displayVersionString` on the main actor.
- `updaterDidNotFindUpdate(_:error:)` → clear flags.

We do **not** need x-island's `startObservingSparkleWindows` z-order hack: Shuuchuu's Settings UI lives inside a `NSPopover`, not a `.floating` `NSWindow`, so Sparkle's update dialog will become key and dismiss the popover automatically — which is the desired behavior.

### Wiring into `AppModel`

`AppModel.init` constructs `let updates = UpdateChecker()` alongside the other subsystems. `AppModel.bootstrap()` appends:

```swift
updates.startIfNeeded()
```

after the existing `license.startTrialIfNeeded()` call. No ordering requirement vs. catalog/audio bootstrap — Sparkle does its first scheduled check on a timer, not synchronously.

`AppModel` exposes a thin shim used by the Settings UI:

```swift
func triggerUpdateCheck() { updates.checkForUpdates() }
```

(This pattern mirrors x-island's `model.triggerUpdateCheck()` so the UI never reaches into `updates` directly.)

### Info.plist additions

Append to `Sources/Shuuchuu/Resources/Info.plist`:

```xml
<key>SUFeedURL</key>
<string>https://raw.githubusercontent.com/bluedusk/x-noise/main/appcast.xml</string>
<key>SUPublicEDKey</key>
<string><base64-eddsa-public-key></string>
<key>SUEnableAutomaticChecks</key>
<true/>
<key>SUAutomaticallyUpdate</key>
<false/>
<key>SUScheduledCheckInterval</key>
<integer>86400</integer>
```

The public key string is filled in once `generate_keys` runs (see Release pipeline). The current linker-embedded plist (used by `swift run`) and the packaged `Contents/Info.plist` (emitted by the new packaging script) both source from this single file — no drift.

### Package.swift addition

```swift
.package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.0"),
```

```swift
.executableTarget(
    name: "Shuuchuu",
    dependencies: [
        .product(name: "Sparkle", package: "Sparkle"),
    ],
    ...
)
```

The existing `-sectcreate __TEXT __info_plist` linker flag continues to work — Sparkle reads from `Bundle.main.infoDictionary` regardless of how the plist got there.

### Entitlements

New file: `config/packaging/Shuuchuu.entitlements`.

```xml
<plist version="1.0">
<dict>
    <key>com.apple.security.network.client</key>
    <true/>
</dict>
</plist>
```

Required because hardened runtime + notarisation expect an entitlements file even when sandbox is off. Sparkle 2's xpc helpers handle their own sandboxing internally.

## UI surfaces

### 1. Settings → "Updates" section

New section in `Sources/Shuuchuu/UI/Pages/SettingsPage.swift`, between `appSection` and `licenseSection`:

```
Updates
─────────────────────────────────────────
  Current version          0.18.0 (1305)        ← 5 taps reveals beta toggle
  Last checked             5 minutes ago
  [ Check for updates ]                  ← .glassProminent button
  Automatically check      [✓]
  Auto-install in background [ ]
  What's new                ↗ release notes
  ─── (revealed) ──────────────────────────
  Beta updates             [ ]
```

State binding:
- `version`/`build` from `Bundle.main.infoDictionary["CFBundleShortVersionString"]`/`CFBundleVersion`.
- "Last checked" from `updates.lastCheckDate` (KVO-bridged from `controller.updater.lastUpdateCheckDate`).
- "Check for updates" calls `model.triggerUpdateCheck()`. Disabled when `!updates.canCheckForUpdates` or while a check is in flight.
- Auto-check toggle bound to `controller.updater.automaticallyChecksForUpdates` (Sparkle persists).
- Auto-install toggle bound to `controller.updater.automaticallyDownloadsUpdates`.
- "What's new" opens `UpdateChecker.releasesURL` via `NSWorkspace`.
- 5-tap reveal pattern (matches iOS's developer-mode-on-version): `@State var betaTaps = 0; .onTapGesture { betaTaps += 1 }`. After 5 taps within 3 s, set `@State var betaRevealed = true` (session-scoped — closing Settings re-hides it next open).
- Beta toggle bound to `UserDefaults["app.betaUpdates"]`.

The section uses the existing `SettingRow` / `GlassToggle` / `IconButton` primitives from the Settings page — no new design tokens.

### 2. Settings header banner (when an update is queued)

When `updates.hasUpdate == true`, the Settings page header shows a small `.glass` pill: "Version `<latestVersion>` available · Install". Tapping calls `model.triggerUpdateCheck()` to reopen Sparkle's dialog. This mirrors x-island's `UpdateBanner` in `SettingsView.swift:187`.

### 3. Menubar logo dot

`MenubarLabel` already renders the 集中 glyph. Add a 6 pt `Circle().fill(design.accent)` overlay at top-trailing when `model.updates.hasUpdate == true`. The same overlay slot is used by the planned paywall lock-glyph; precedence (when both apply) is **lock > update**, since locked-out users can't install anyway.

`MenubarLabel` reads `updates.hasUpdate` via `@EnvironmentObject UpdateChecker` (per CLAUDE.md macOS-26 rule: pass observed objects through the environment, not init params). Inject from `ShuuchuuApp` alongside `AppModel`/`DesignSettings`/`FocusSettings`.

### 4. Sparkle's own UI

We do not customise Sparkle's update / progress / install windows. They appear as standard NSWindows with the system look — fine for v1.

## Release pipeline

Two new shell scripts, ported from x-island and renamed/retargeted:

### `scripts/release.sh`

```
./scripts/release.sh <version> [changelog message]
./scripts/release.sh 0.2.0 "Fix soundtrack tag autocomplete"
./scripts/release.sh 0.2.0           # auto-generate from git log since previous tag

Flags:
  -y / --yes      skip confirmations
  --beta          beta channel + GitHub pre-release; appcast item gets sparkle:channel=beta
```

Steps:

1. Verify clean git tree, current branch is `main`.
2. Bump `CFBundleShortVersionString` and `CFBundleVersion` in `Sources/Shuuchuu/Resources/Info.plist`.
3. Update `CHANGELOG.md` (insert entry; auto-generate from `git log v<prev>..HEAD --oneline` if no message provided).
4. `swift build -c release`.
5. Wrap binary in `.app` bundle: copy `.build/release/Shuuchuu` to `output/Shuuchuu.app/Contents/MacOS/Shuuchuu`, copy `Info.plist` to `Contents/Info.plist`, copy `config/packaging/Shuuchuu.entitlements`, embed `Sparkle.framework`.
6. `codesign --deep --force --options runtime --entitlements config/packaging/Shuuchuu.entitlements --sign "$X_NOISE_SIGN_IDENTITY" output/Shuuchuu.app`.
7. Zip: `ditto -c -k --keepParent output/Shuuchuu.app output/Shuuchuu.zip`.
8. Notarise: `xcrun notarytool submit output/Shuuchuu.zip --keychain-profile "$X_NOISE_NOTARY_PROFILE" --wait`. Staple: `xcrun stapler staple output/Shuuchuu.app`. Re-zip the stapled bundle.
9. `git commit -am "release: v<version>"`, `git tag v<version>`, `git push --follow-tags`.
10. `gh release create v<version> output/Shuuchuu.zip --notes-file <changelog-snippet>` (`--prerelease` if `--beta`).
11. Call `scripts/update-appcast.sh` to append the new item, sign it, and push.

Required env (in a `.env` file, not committed):

```
SPARKLE_EDDSA_KEY=<base64 private key>
X_NOISE_SIGN_IDENTITY=Developer ID Application: <name> (<team>)
X_NOISE_NOTARY_PROFILE=<keychain profile created by `notarytool store-credentials`>
```

### `scripts/update-appcast.sh`

Direct port of x-island's `scripts/update-appcast.sh`:

1. Verify Sparkle's `sign_update` exists at `.build/artifacts/sparkle/Sparkle/bin/sign_update` (resolve via `swift build` if missing).
2. Compute EdDSA signature: `echo "$SPARKLE_EDDSA_KEY" | sign_update output/Shuuchuu.zip --ed-key-file /dev/stdin`.
3. Build a new `<item>` block and prepend to `appcast.xml`:

```xml
<item>
    <title>Version 0.2.0</title>
    <pubDate>...</pubDate>
    <sparkle:minimumSystemVersion>26.0</sparkle:minimumSystemVersion>
    <sparkle:channel>beta</sparkle:channel>   <!-- only for --beta releases -->
    <description><![CDATA[<ul>...</ul>]]></description>
    <enclosure
        url="https://github.com/bluedusk/x-noise/releases/download/v0.2.0/Shuuchuu.zip"
        sparkle:version="2"
        sparkle:shortVersionString="0.2.0"
        sparkle:edSignature="..."
        length="..."
        type="application/octet-stream"
    />
</item>
```

4. `git add appcast.xml CHANGELOG.md Info.plist && git commit -m "release: appcast v<version>" && git push`.

`raw.githubusercontent.com` serves the new `appcast.xml` immediately after push (max ~5 min CDN lag — acceptable for a 24 h check interval).

### EdDSA key generation

One-time, before first release:

```bash
swift build  # resolves Sparkle artifacts
.build/artifacts/sparkle/Sparkle/bin/generate_keys
```

`generate_keys` writes the private key to the user's Keychain and prints the public key. Public key goes into `Info.plist`'s `SUPublicEDKey`. Private key is exported once with `generate_keys -x` and stored encrypted in the user's password manager (and as `SPARKLE_EDDSA_KEY` in `.env` for the release script).

## Bootstrap & flow diagrams

### App launch
```
AppModel.bootstrap():
  1. license.startTrialIfNeeded()        ← existing
  2. updates.startIfNeeded()             ← new
       Sparkle reads SUFeedURL + SUPublicEDKey from Info.plist
       schedules a check on a 24 h timer (or runs ~10s after launch on first run)
  3. Catalog + audio bootstrap continue
```

### Update available (background scheduled check)
```
Sparkle timer fires
  → fetches https://raw.githubusercontent.com/bluedusk/x-noise/main/appcast.xml
  → finds an item with sparkle:version > current CFBundleVersion
  → checks channel (allowedChannels delegate)
  → updater(_:didFindValidUpdate:) → @MainActor:
       updates.hasUpdate = true
       updates.latestVersion = item.displayVersionString
  → MenubarLabel re-renders with dot overlay
  → SettingsPage header re-renders with banner
  → Sparkle shows its built-in update dialog (with release notes)
       (the popover dismisses; Sparkle window becomes key)
  → user clicks Install:
       Sparkle downloads the .zip
       verifies EdDSA signature against SUPublicEDKey
       quits app, replaces bundle, relaunches
```

### Manual check
```
Settings → "Check for updates"
  → AppModel.triggerUpdateCheck()
  → updates.checkForUpdates()
  → controller.checkForUpdates(nil)
  → Sparkle shows "checking…" then either the update dialog or "you're up to date"
```

## Beta-channel mechanics

- Beta toggle: 5 taps on the version row reveals it; bound to `UserDefaults["app.betaUpdates"]`.
- When ON: `allowedChannels(for:)` returns `["beta"]`. Sparkle filters appcast items by `<sparkle:channel>` and considers items where channel is `"beta"` **or** unset (stable items always show).
- When OFF: returns `[]`. Sparkle considers only items with no `<sparkle:channel>` element.
- `release.sh --beta` writes `<sparkle:channel>beta</sparkle:channel>` into the new item and creates a GitHub pre-release.

## Error handling

Sparkle owns user-facing error UX (download failed, signature invalid, no internet, no update available). We don't intercept. The only first-party error path is:

- **`updaterDidNotFindUpdate`** is also called when the appcast can't be fetched (e.g. offline). We treat this as `hasUpdate = false` and silently move on. Same posture as the license controller's soft-revalidate rule: a network glitch never harasses the user.

Logging: `os.Logger(subsystem: "com.bluedusk.shuuchuu", category: "update")`. Failures from `try updater.start()` go to the existing log subsystem.

## Testing

UI is preview-only (project convention). Unit tests are limited because Sparkle needs a real `SPUStandardUpdaterController`, but we cover the seams we own:

- **`UpdateCheckerTests.swift`**
  - Beta-toggle UserDefaults flag → `allowedChannels(for:)` returns `["beta"]`. (Cast `UpdateChecker` as `SPUUpdaterDelegate` and call directly with a stub `SPUUpdater`.)
  - `didFindValidUpdate` sets `hasUpdate = true` and copies `displayVersionString`. (Construct a fake `SUAppcastItem` from a minimal XML literal — Sparkle exposes `SUAppcastItem(dictionary:error:)` for tests.)
  - `updaterDidNotFindUpdate` clears flags.

- **Manual smoke (documented in spec, not automated):**
  1. Build and sign locally with `release.sh 0.0.1-test`.
  2. Push a fake appcast item with `sparkle:version=99999` to a test branch; point `SUFeedURL` at that branch's raw URL.
  3. Run `.build/release/Shuuchuu`; trigger "Check for updates" from Settings.
  4. Verify dialog appears, install proceeds, app relaunches at the new version.
  5. Verify the menubar dot disappears after install.

`appcast.xml` itself is hand-edited by the release script — round-trip XML correctness is the script's responsibility, validated by Sparkle parsing it at runtime during the smoke step.

## Implementation file list

New files:
- `Sources/Shuuchuu/Update/UpdateChecker.swift`
- `Tests/ShuuchuuTests/UpdateCheckerTests.swift`
- `config/packaging/Shuuchuu.entitlements`
- `scripts/release.sh`
- `scripts/update-appcast.sh`
- `appcast.xml` (initial empty channel + placeholder, committed at repo root)
- `CHANGELOG.md` (created if missing)

Modified files:
- `Package.swift` — add Sparkle SPM dep + product dependency on the executable target.
- `Sources/Shuuchuu/Resources/Info.plist` — add `SUFeedURL`, `SUPublicEDKey`, `SUEnableAutomaticChecks`, `SUAutomaticallyUpdate`, `SUScheduledCheckInterval`, `SUEnableInstallerLauncherService`.
- `Sources/Shuuchuu/AppModel.swift` — add `let updates = UpdateChecker()`, call `updates.startIfNeeded()` from `bootstrap()`, add `triggerUpdateCheck()` shim.
- `Sources/Shuuchuu/UI/Pages/SettingsPage.swift` — new `updatesSection`; insert above `licenseSection`. Add 5-tap-to-reveal beta toggle.
- `Sources/Shuuchuu/UI/MenubarLabel.swift` — environment-object `UpdateChecker`; render accent dot when `hasUpdate`.
- `Sources/Shuuchuu/ShuuchuuApp.swift` — inject `UpdateChecker` into the SwiftUI environment alongside the other env objects.
- `.gitignore` — add `.env`, `output/`, `*.zip`.
- `CLAUDE.md` — add a brief "Releases" section pointing at `scripts/release.sh`.

## Out of scope (deliberately deferred)

- Homebrew cask + `update-homebrew-tap.sh` — easy follow-up once we have one stable release out the door.
- Mac App Store distribution (uses StoreKit-driven updates; incompatible with Sparkle).
- Sparkle delta updates (smaller patch downloads). Not worth the complexity until binary size is a real complaint.
- In-app changelog viewer. "What's new" links out to the GitHub Releases page for v1.
- Background-only auto-install (`SUAutomaticallyUpdate=true`) is exposed in Settings but defaults off — no flip without explicit user opt-in.
- Forced/critical updates. We don't have a security model that needs them yet.
- Custom Sparkle UI / themed update dialogs.
- Rollback flow if a release is broken — current playbook is "publish v+1 with the fix and bump the appcast".
