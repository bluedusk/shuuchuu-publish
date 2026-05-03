# Sparkle In-App Update — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wire Sparkle 2.9 into Shuuchuu so shipped builds can self-update from a GitHub-Releases zip with EdDSA-signed appcast verification, plus the release scripts to publish a new version.

**Architecture:** `UpdateChecker` (`@MainActor`, `ObservableObject`) wraps `SPUStandardUpdaterController`, sits next to `LicenseController` inside `AppModel`, and exposes `hasUpdate`/`latestVersion`/`canCheckForUpdates`/`lastCheckDate` as `@Published` for SwiftUI. Beta channel gated on `UserDefaults["app.betaUpdates"]`. Settings UI gets an "Updates" section; `MenubarLabel` gets an accent dot overlay when an update is queued. Release pipeline = ported `release.sh` + `update-appcast.sh` from x-island.

**Tech Stack:** Swift 6 / SwiftUI / Sparkle 2.9 / SPM. Shell scripts (zsh) for release. EdDSA signing via Sparkle's `sign_update` tool.

**Spec:** `docs/superpowers/specs/2026-05-03-app-update-design.md`

---

## File map

New:
- `Sources/Shuuchuu/Update/UpdateChecker.swift`
- `Tests/ShuuchuuTests/UpdateCheckerTests.swift`
- `config/packaging/Shuuchuu.entitlements`
- `scripts/release.sh`
- `scripts/update-appcast.sh`
- `appcast.xml` (repo root)
- `CHANGELOG.md` (repo root)

Modified:
- `Package.swift`
- `Sources/Shuuchuu/Resources/Info.plist`
- `Sources/Shuuchuu/AppModel.swift`
- `Sources/Shuuchuu/ShuuchuuApp.swift`
- `Sources/Shuuchuu/UI/MenubarLabel.swift`
- `Sources/Shuuchuu/UI/Pages/SettingsPage.swift`
- `.gitignore`
- `CLAUDE.md`

---

## Task 1: Add Sparkle SPM dependency

**Files:**
- Modify: `Package.swift`

- [ ] **Step 1: Add Sparkle as a package dependency and product**

Replace the contents of `Package.swift` with:

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Shuuchuu",
    platforms: [.macOS("26.0")],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.0"),
    ],
    targets: [
        .executableTarget(
            name: "Shuuchuu",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Sources/Shuuchuu",
            exclude: ["Resources/Info.plist"],
            resources: [.process("Resources")],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency"),
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Sources/Shuuchuu/Resources/Info.plist",
                ]),
            ]
        ),
        .testTarget(
            name: "ShuuchuuTests",
            dependencies: ["Shuuchuu"],
            path: "Tests/ShuuchuuTests",
            resources: [.process("Fixtures")]
        ),
    ]
)
```

- [ ] **Step 2: Resolve and verify it builds**

Run: `swift build 2>&1 | tail -30`
Expected: completes successfully (Sparkle clones into `.build/checkouts/Sparkle/`, the executable links).

- [ ] **Step 3: Commit**

```bash
git add Package.swift Package.resolved
git commit -m "build: add Sparkle 2.9 SPM dependency"
```

---

## Task 2: Add entitlements file

**Files:**
- Create: `config/packaging/Shuuchuu.entitlements`

- [ ] **Step 1: Create the directory and file**

Run: `mkdir -p config/packaging`

Write `config/packaging/Shuuchuu.entitlements`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.network.client</key>
    <true/>
</dict>
</plist>
```

- [ ] **Step 2: Validate the plist parses**

Run: `plutil config/packaging/Shuuchuu.entitlements`
Expected: `config/packaging/Shuuchuu.entitlements: OK`

- [ ] **Step 3: Commit**

```bash
git add config/packaging/Shuuchuu.entitlements
git commit -m "build: add hardened-runtime entitlements file"
```

---

## Task 3: Add Sparkle keys to Info.plist (with placeholder pubkey)

**Files:**
- Modify: `Sources/Shuuchuu/Resources/Info.plist`

> The real EdDSA public key gets generated separately (Task 14, manual step) and committed as a follow-up. Use the all-zero placeholder for now so the build succeeds. The placeholder is harmless for `swift run` since Sparkle skips signature checks until it actually downloads an update.

- [ ] **Step 1: Replace Info.plist contents**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>app.shuuchuu</string>
    <key>CFBundleName</key>
    <string>Shuuchuu</string>
    <key>CFBundleDisplayName</key>
    <string>Shuuchuu</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>26.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>SUFeedURL</key>
    <string>https://raw.githubusercontent.com/bluedusk/x-noise/main/appcast.xml</string>
    <key>SUPublicEDKey</key>
    <string>AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=</string>
    <key>SUEnableAutomaticChecks</key>
    <true/>
    <key>SUAutomaticallyUpdate</key>
    <false/>
    <key>SUScheduledCheckInterval</key>
    <integer>86400</integer>
</dict>
</plist>
```

- [ ] **Step 2: Validate plist parses**

Run: `plutil Sources/Shuuchuu/Resources/Info.plist`
Expected: `Sources/Shuuchuu/Resources/Info.plist: OK`

- [ ] **Step 3: Build to confirm linker still embeds it correctly**

Run: `swift build 2>&1 | tail -10`
Expected: build succeeds, no plist warnings.

- [ ] **Step 4: Commit**

```bash
git add Sources/Shuuchuu/Resources/Info.plist
git commit -m "build: add Sparkle SUFeedURL and update keys to Info.plist (placeholder pubkey)"
```

---

## Task 4: Write failing UpdateChecker tests

**Files:**
- Create: `Tests/ShuuchuuTests/UpdateCheckerTests.swift`

- [ ] **Step 1: Write the test file**

```swift
import XCTest
import Sparkle
@testable import Shuuchuu

@MainActor
final class UpdateCheckerTests: XCTestCase {

    // Use a private suite so we don't pollute the user's defaults during tests.
    private var defaults: UserDefaults!
    private let suiteName = "shuuchuu.UpdateCheckerTests"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func testAllowedChannelsEmptyByDefault() {
        let checker = UpdateChecker(defaults: defaults)
        let channels = checker.allowedChannels(for: checker.updaterForTesting)
        XCTAssertEqual(channels, [])
    }

    func testAllowedChannelsBetaWhenFlagOn() {
        defaults.set(true, forKey: "app.betaUpdates")
        let checker = UpdateChecker(defaults: defaults)
        let channels = checker.allowedChannels(for: checker.updaterForTesting)
        XCTAssertEqual(channels, ["beta"])
    }

    func testDidFindValidUpdateSetsHasUpdateAndVersion() async {
        let checker = UpdateChecker(defaults: defaults)
        let item = try! SUAppcastItem(dictionary: [
            "url": "https://example.com/Shuuchuu.zip",
            "sparkle:version": "42",
            "sparkle:shortVersionString": "9.9.9",
        ])

        checker.updater(checker.updaterForTesting, didFindValidUpdate: item)

        // Delegate hops back onto the main actor via Task — yield once so it lands.
        await Task.yield()

        XCTAssertTrue(checker.hasUpdate)
        XCTAssertEqual(checker.latestVersion, "9.9.9")
    }

    func testUpdaterDidNotFindUpdateClearsFlags() async {
        let checker = UpdateChecker(defaults: defaults)

        // Pre-set state that should be cleared.
        let item = try! SUAppcastItem(dictionary: [
            "url": "https://example.com/Shuuchuu.zip",
            "sparkle:version": "42",
            "sparkle:shortVersionString": "9.9.9",
        ])
        checker.updater(checker.updaterForTesting, didFindValidUpdate: item)
        await Task.yield()

        let dummyError = NSError(domain: "test", code: 0)
        checker.updaterDidNotFindUpdate(checker.updaterForTesting, error: dummyError)
        await Task.yield()

        XCTAssertFalse(checker.hasUpdate)
        XCTAssertNil(checker.latestVersion)
    }
}
```

- [ ] **Step 2: Run the tests to confirm they fail**

Run: `swift test --filter UpdateCheckerTests 2>&1 | tail -10`
Expected: FAIL — `UpdateChecker` is not yet defined.

---

## Task 5: Implement UpdateChecker

**Files:**
- Create: `Sources/Shuuchuu/Update/UpdateChecker.swift`

- [ ] **Step 1: Create the directory**

Run: `mkdir -p Sources/Shuuchuu/Update`

- [ ] **Step 2: Write UpdateChecker**

```swift
import AppKit
import Combine
import Foundation
import Sparkle
import os

/// Wraps Sparkle's `SPUStandardUpdaterController` so SwiftUI can observe the
/// update state. The controller itself owns the timer; we just republish a few
/// flags as `@Published` so views re-render correctly.
///
/// Mirrors `Sources/xIslandApp/UpdateChecker.swift` from the x-island project.
@MainActor
final class UpdateChecker: NSObject, ObservableObject {
    static let releasesURL = URL(string: "https://github.com/bluedusk/x-noise/releases")!

    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var hasUpdate = false
    @Published private(set) var latestVersion: String?
    @Published private(set) var lastCheckDate: Date?

    private let defaults: UserDefaults
    private let logger = Logger(subsystem: "app.shuuchuu", category: "update")
    private var controller: SPUStandardUpdaterController!
    private var cancellables: Set<AnyCancellable> = []

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        super.init()
        controller = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
    }

    /// Exposed for delegate-method unit tests. Production code never reads this.
    var updaterForTesting: SPUUpdater { controller.updater }

    /// True if `automaticallyChecksForUpdates` is currently enabled.
    var automaticallyChecksForUpdates: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }

    /// True if Sparkle should silently download updates and install on next quit.
    var automaticallyDownloadsUpdates: Bool {
        get { controller.updater.automaticallyDownloadsUpdates }
        set { controller.updater.automaticallyDownloadsUpdates = newValue }
    }

    /// Start Sparkle's scheduled update timer. Idempotent: safe to call once
    /// after `AppModel.bootstrap`. Auto-check / auto-install / interval are
    /// sourced from Info.plist so first launch never prompts the user.
    func startIfNeeded() {
        let updater = controller.updater
        do {
            try updater.start()
        } catch {
            logger.error("Sparkle updater failed to start: \(error.localizedDescription)")
        }

        updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .sink { [weak self] value in self?.canCheckForUpdates = value }
            .store(in: &cancellables)

        updater.publisher(for: \.lastUpdateCheckDate)
            .receive(on: RunLoop.main)
            .sink { [weak self] value in self?.lastCheckDate = value }
            .store(in: &cancellables)
    }

    /// User-initiated "Check for updates". Shows Sparkle's standard dialogs.
    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}

// MARK: - SPUUpdaterDelegate

extension UpdateChecker: SPUUpdaterDelegate {
    nonisolated func allowedChannels(for updater: SPUUpdater) -> Set<String> {
        // Reading UserDefaults is thread-safe; we don't need MainActor isolation.
        let beta = defaultsSnapshot.bool(forKey: "app.betaUpdates")
        return beta ? ["beta"] : []
    }

    nonisolated func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        let version = item.displayVersionString
        Task { @MainActor in
            self.hasUpdate = true
            self.latestVersion = version
        }
    }

    nonisolated func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: any Error) {
        Task { @MainActor in
            self.hasUpdate = false
            self.latestVersion = nil
        }
    }

    /// `defaults` is mutated only on the main actor at init time; reading it
    /// from a `nonisolated` delegate is safe because UserDefaults itself is
    /// thread-safe and we never reassign the property.
    nonisolated private var defaultsSnapshot: UserDefaults {
        // Force-unwrap is safe: `defaults` is set during `init` before any
        // delegate callback can fire (Sparkle is started later via startIfNeeded).
        MainActor.assumeIsolated { self.defaults }
    }
}
```

- [ ] **Step 3: Run the tests to confirm they pass**

Run: `swift test --filter UpdateCheckerTests 2>&1 | tail -15`
Expected: PASS — all four tests green.

- [ ] **Step 4: Commit**

```bash
git add Sources/Shuuchuu/Update/UpdateChecker.swift Tests/ShuuchuuTests/UpdateCheckerTests.swift
git commit -m "feat(updates): add UpdateChecker wrapping Sparkle's SPUStandardUpdaterController"
```

---

## Task 6: Wire UpdateChecker into AppModel

**Files:**
- Modify: `Sources/Shuuchuu/AppModel.swift`
- Modify: `Sources/Shuuchuu/ShuuchuuApp.swift`

- [ ] **Step 1: Add the property to AppModel**

In `Sources/Shuuchuu/AppModel.swift`, find the existing property declarations near line 47 (`let license: LicenseController`). Add immediately after:

```swift
    let updates: UpdateChecker
```

- [ ] **Step 2: Add the init parameter**

In the `AppModel.init(...)` signature (near line 67), add `updates: UpdateChecker,` after `license: LicenseController,`. In the assignments (near line 101), add:

```swift
        self.updates = updates
```

immediately after `self.license = license`.

- [ ] **Step 3: Add `triggerUpdateCheck()` shim**

In `AppModel.swift`, find `func goTo(_ page: AppPage)` (~line 520). Add this method just above it:

```swift
    // MARK: - Updates

    func triggerUpdateCheck() {
        updates.checkForUpdates()
    }
```

- [ ] **Step 4: Start the updater in handleLaunch**

In `handleLaunch()` (~line 528), after the license-revalidate block, add:

```swift
        updates.startIfNeeded()
```

So the function reads:

```swift
    func handleLaunch() async {
        guard !didLaunch else { return }
        didLaunch = true
        // License state was bootstrapped synchronously in init; revalidate now if licensed.
        if case .licensed = license.state {
            Task { await license.revalidate() }
        }
        updates.startIfNeeded()
        await loadCatalog()
    }
```

- [ ] **Step 5: Construct UpdateChecker in `AppModel.live`**

In `Sources/Shuuchuu/ShuuchuuApp.swift`, in `AppModel.live(design:)`, just before the `let model = AppModel(...)` call (~line 85), add:

```swift
        let updates = UpdateChecker()
```

In the `AppModel(...)` argument list, add `updates: updates,` after `license: license`.

- [ ] **Step 6: Build to verify**

Run: `swift build 2>&1 | tail -10`
Expected: builds successfully.

- [ ] **Step 7: Commit**

```bash
git add Sources/Shuuchuu/AppModel.swift Sources/Shuuchuu/ShuuchuuApp.swift
git commit -m "feat(updates): wire UpdateChecker into AppModel; start on handleLaunch"
```

---

## Task 7: Inject UpdateChecker into SwiftUI environment

**Files:**
- Modify: `Sources/Shuuchuu/ShuuchuuApp.swift`

- [ ] **Step 1: Add environment objects on both PopoverView and MenubarLabel**

Replace the `body` of `ShuuchuuApp` with:

```swift
    var body: some SwiftUI.Scene {
        MenuBarExtra {
            PopoverView()
                .environmentObject(model)
                .environmentObject(design)
                .environmentObject(model.updates)
                .task { await model.handleLaunch() }
                .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.willSleepNotification)) { _ in
                    Task { await model.handleSleep() }
                }
                .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)) { _ in
                    Task { await model.handleWake() }
                }
        } label: {
            MenubarLabel()
                .environmentObject(model)
                .environmentObject(design)
                .environmentObject(model.updates)
        }
        .menuBarExtraStyle(.window)
    }
```

- [ ] **Step 2: Build**

Run: `swift build 2>&1 | tail -10`
Expected: builds successfully.

- [ ] **Step 3: Commit**

```bash
git add Sources/Shuuchuu/ShuuchuuApp.swift
git commit -m "feat(updates): inject UpdateChecker into SwiftUI environment"
```

---

## Task 8: Add update-available dot to MenubarLabel

**Files:**
- Modify: `Sources/Shuuchuu/UI/MenubarLabel.swift`

- [ ] **Step 1: Replace MenubarLabel with the dotted version**

Replace the `MenubarLabel` struct with:

```swift
struct MenubarLabel: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var design: DesignSettings
    @EnvironmentObject var updates: UpdateChecker

    var body: some View {
        HStack(spacing: 4) {
            Text(labelString)
                .font(.system(size: 13, weight: .medium))
                .monospacedDigit()
                .opacity(model.session.isRunning ? 1.0 : 0.6)
            if !model.license.isUnlocked {
                Image(systemName: "lock.fill")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            } else if updates.hasUpdate {
                Circle()
                    .fill(design.accent)
                    .frame(width: 6, height: 6)
                    .accessibilityLabel("Update available")
            }
        }
    }

    private var labelString: String {
        let prefix = (model.session.phase == .focus) ? "集中" : "休憩"
        guard model.focusSettings.menubarTimer else { return prefix }
        return "\(prefix) \(timerString)"
    }

    private var timerString: String {
        let mins = (model.session.remainingSec + 59) / 60
        return "\(mins)m"
    }
}
```

(Lock takes precedence over the dot — locked users can't install anyway.)

- [ ] **Step 2: Build**

Run: `swift build 2>&1 | tail -5`
Expected: builds.

- [ ] **Step 3: Commit**

```bash
git add Sources/Shuuchuu/UI/MenubarLabel.swift
git commit -m "feat(updates): show accent-color dot on menubar logo when update available"
```

---

## Task 9: Add Settings → Updates section (version row + Check now)

**Files:**
- Modify: `Sources/Shuuchuu/UI/Pages/SettingsPage.swift`

- [ ] **Step 1: Add the env object and state**

At the top of `SettingsPage`, after the existing `@EnvironmentObject` lines (~line 6), add:

```swift
    @EnvironmentObject var updates: UpdateChecker

    @State private var betaTaps = 0
    @State private var betaTapStarted: Date?
    @State private var betaRevealed = false
```

- [ ] **Step 2: Insert the section into the page body**

In the `body` (~line 9), find:

```swift
                    appSection
                    licenseSection
```

Replace with:

```swift
                    appSection
                    updatesSection
                    licenseSection
```

- [ ] **Step 3: Add the `updatesSection` view**

Right after `appSection` (~line 154, before `licenseSection`), add:

```swift
    private var updatesSection: some View {
        Group {
            sectionLabel("Updates")
            SettingRow(label: "Version") {
                Text(versionString)
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .contentShape(Rectangle())
                    .onTapGesture { handleVersionTap() }
            }
            if let last = updates.lastCheckDate {
                SettingRow(label: "Last checked") {
                    Text(last.formatted(.relative(presentation: .named)))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            SettingRow(label: "Check for updates") {
                Button("Check now") { model.triggerUpdateCheck() }
                    .buttonStyle(.glassProminent)
                    .disabled(!updates.canCheckForUpdates)
            }
            SettingRow(label: "Automatically check") {
                GlassToggle(
                    isOn: Binding(
                        get: { updates.automaticallyChecksForUpdates },
                        set: { updates.automaticallyChecksForUpdates = $0 }
                    ),
                    accent: design.accent
                )
            }
            SettingRow(label: "Auto-install in background") {
                GlassToggle(
                    isOn: Binding(
                        get: { updates.automaticallyDownloadsUpdates },
                        set: { updates.automaticallyDownloadsUpdates = $0 }
                    ),
                    accent: design.accent
                )
            }
            SettingRow(label: "What's new") {
                Button("Release notes") {
                    NSWorkspace.shared.open(UpdateChecker.releasesURL)
                }
                .buttonStyle(.glass)
            }
            if betaRevealed {
                SettingRow(label: "Beta updates") {
                    GlassToggle(
                        isOn: Binding(
                            get: { UserDefaults.standard.bool(forKey: "app.betaUpdates") },
                            set: { UserDefaults.standard.set($0, forKey: "app.betaUpdates") }
                        ),
                        accent: design.accent
                    )
                }
            }
        }
    }

    private var versionString: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    private func handleVersionTap() {
        let now = Date()
        if let started = betaTapStarted, now.timeIntervalSince(started) > 3 {
            betaTaps = 0
        }
        betaTapStarted = now
        betaTaps += 1
        if betaTaps >= 5 {
            betaRevealed = true
        }
    }
```

- [ ] **Step 4: Add `import AppKit` to the file (NSWorkspace)**

At the top of `Sources/Shuuchuu/UI/Pages/SettingsPage.swift`, replace `import SwiftUI` with:

```swift
import AppKit
import SwiftUI
```

- [ ] **Step 5: Build**

Run: `swift build 2>&1 | tail -10`
Expected: builds.

- [ ] **Step 6: Commit**

```bash
git add Sources/Shuuchuu/UI/Pages/SettingsPage.swift
git commit -m "feat(updates): add Settings Updates section with version, check-now, toggles, beta reveal"
```

---

## Task 10: Manual smoke — does it run?

**Files:** None (verification only).

- [ ] **Step 1: Kill any stale app and relaunch**

Run: `pkill -x Shuuchuu; swift run 2>&1 | tail -5 &`

Expected: app launches; 集中 logo visible in the menubar.

- [ ] **Step 2: Open the popover, navigate to Settings**

Click the menubar 集中 → cog/Settings tab. Confirm the new "Updates" section renders with `Version 0.1.0 (1)`, `Check for updates` button, two toggles, and `What's new` link.

- [ ] **Step 3: Tap version 5 times to reveal beta toggle**

Click the version row 5 times within 3 seconds. Confirm the "Beta updates" row appears.

- [ ] **Step 4: Verify "Check now" button does *not* crash**

Click "Check now". Sparkle will fail to verify the placeholder pubkey when an update is found, but with no items in the appcast yet it'll show "You're up to date" — which is the expected pass.

- [ ] **Step 5: Quit the app**

Run: `pkill -x Shuuchuu`

(No commit — this is verification only.)

---

## Task 11: Initial appcast.xml + CHANGELOG.md

**Files:**
- Create: `appcast.xml`
- Create: `CHANGELOG.md`

- [ ] **Step 1: Create empty appcast.xml**

Write `appcast.xml`:

```xml
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
    <channel>
        <title>Shuuchuu Updates</title>
        <link>https://github.com/bluedusk/x-noise/releases</link>
        <description>Most recent changes with links to updates.</description>
        <language>en</language>
    </channel>
</rss>
```

- [ ] **Step 2: Create CHANGELOG.md**

Write `CHANGELOG.md`:

```markdown
# Changelog

All notable changes to Shuuchuu are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow
[SemVer](https://semver.org/).

## [Unreleased]
- Sparkle in-app updates.
```

- [ ] **Step 3: Commit**

```bash
git add appcast.xml CHANGELOG.md
git commit -m "chore: scaffold appcast.xml and CHANGELOG.md"
```

---

## Task 12: Add release.sh

**Files:**
- Create: `scripts/release.sh`

- [ ] **Step 1: Write the script**

```bash
#!/bin/zsh
# release.sh — One-command local release for Shuuchuu.
#
# Usage:
#   ./scripts/release.sh <version> [changelog message]
#   ./scripts/release.sh 0.2.0 "Fix soundtrack autocomplete"
#   ./scripts/release.sh 0.2.0                              # auto-generate from git log
#
# Flags:
#   -y, --yes    Skip confirmation prompts
#   --beta       Beta channel + GitHub pre-release; appcast item gets sparkle:channel=beta
#
# Requires .env with: SPARKLE_EDDSA_KEY, X_NOISE_SIGN_IDENTITY, X_NOISE_NOTARY_PROFILE

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RELEASE_REPO="bluedusk/x-noise"
APP_NAME="Shuuchuu"
BUNDLE_ID="app.shuuchuu"
PLIST="Sources/${APP_NAME}/Resources/Info.plist"

AUTO_YES=false
BETA=false
VERSION=""
CHANGELOG_MSG=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -y|--yes) AUTO_YES=true; shift ;;
        --beta) BETA=true; shift ;;
        -*) echo "Unknown option: $1"; exit 1 ;;
        *)
            if [[ -z "$VERSION" ]]; then VERSION="$1"
            else CHANGELOG_MSG="$1"
            fi
            shift
            ;;
    esac
done

if [[ -z "$VERSION" ]]; then
    echo "Usage: $0 [-y|--yes] [--beta] <version> [changelog message]"
    exit 1
fi

if [[ "$BETA" == true ]]; then
    [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-beta\.[0-9]+)?$ ]] || {
        echo "Error: beta version must be semver or semver-beta.N (got: $VERSION)"; exit 1
    }
else
    [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
        echo "Error: version must be semver (got: $VERSION)"; exit 1
    }
fi

cd "$REPO_ROOT"

# Load env
if [[ ! -f ".env" ]]; then
    echo "Error: .env file required with SPARKLE_EDDSA_KEY, X_NOISE_SIGN_IDENTITY, X_NOISE_NOTARY_PROFILE"
    exit 1
fi
set -a; source .env; set +a

: "${SPARKLE_EDDSA_KEY:?Missing SPARKLE_EDDSA_KEY in .env}"
: "${X_NOISE_SIGN_IDENTITY:?Missing X_NOISE_SIGN_IDENTITY in .env}"
: "${X_NOISE_NOTARY_PROFILE:?Missing X_NOISE_NOTARY_PROFILE in .env}"

# Verify clean tree on main
if [[ -n "$(git status --porcelain)" ]]; then
    echo "Error: working tree has uncommitted changes"; exit 1
fi

BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [[ "$BRANCH" != "main" && "$AUTO_YES" != true ]]; then
    echo -n "Current branch is '$BRANCH', not 'main'. Continue? [y/N] "
    read -r ans
    [[ "$ans" == "y" || "$ans" == "Y" ]] || exit 1
fi

# Compute build number = monotonically-increasing integer
PREV_BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$PLIST")
BUILD_NUMBER=$((PREV_BUILD + 1))
echo "Bumping version: $(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$PLIST") -> $VERSION"
echo "Bumping build:   $PREV_BUILD -> $BUILD_NUMBER"

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$PLIST"

# Generate changelog message if not provided
if [[ -z "$CHANGELOG_MSG" ]]; then
    PREV_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "")
    if [[ -n "$PREV_TAG" ]]; then
        CHANGELOG_MSG=$(git log --oneline "${PREV_TAG}..HEAD" | sed 's/^[0-9a-f]* /- /')
    else
        CHANGELOG_MSG=$(git log --oneline | head -10 | sed 's/^[0-9a-f]* /- /')
    fi
fi

# Prepend to CHANGELOG
DATE=$(date +%Y-%m-%d)
TMP_CHANGELOG=$(mktemp)
{
    echo "## [$VERSION] - $DATE"
    echo ""
    echo "$CHANGELOG_MSG"
    echo ""
    cat CHANGELOG.md
} > "$TMP_CHANGELOG"
mv "$TMP_CHANGELOG" CHANGELOG.md

# Build release binary
echo "Building release binary..."
swift build -c release

# Wrap into .app bundle
OUT_DIR="output"
APP_DIR="$OUT_DIR/${APP_NAME}.app"
rm -rf "$OUT_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources" "$APP_DIR/Contents/Frameworks"

cp ".build/release/${APP_NAME}" "$APP_DIR/Contents/MacOS/${APP_NAME}"
cp "$PLIST" "$APP_DIR/Contents/Info.plist"

# Copy resource bundle (catalog, sounds, etc.)
RESOURCE_BUNDLE=".build/release/${APP_NAME}_${APP_NAME}.bundle"
if [[ -d "$RESOURCE_BUNDLE" ]]; then
    cp -R "$RESOURCE_BUNDLE" "$APP_DIR/Contents/Resources/"
fi

# Embed Sparkle.framework
SPARKLE_FRAMEWORK=$(find .build -name "Sparkle.framework" -type d -path "*/Sparkle/Sparkle.framework" | head -1)
if [[ -z "$SPARKLE_FRAMEWORK" ]]; then
    echo "Error: Sparkle.framework not found in .build/"
    exit 1
fi
cp -R "$SPARKLE_FRAMEWORK" "$APP_DIR/Contents/Frameworks/"

# Sign (deep, hardened, with entitlements)
echo "Signing..."
codesign --deep --force --options runtime \
    --entitlements config/packaging/Shuuchuu.entitlements \
    --sign "$X_NOISE_SIGN_IDENTITY" \
    "$APP_DIR"

# Zip
ZIP_PATH="$OUT_DIR/${APP_NAME}.zip"
ditto -c -k --keepParent "$APP_DIR" "$ZIP_PATH"

# Notarise
echo "Notarising..."
xcrun notarytool submit "$ZIP_PATH" \
    --keychain-profile "$X_NOISE_NOTARY_PROFILE" \
    --wait

# Staple + re-zip
xcrun stapler staple "$APP_DIR"
rm "$ZIP_PATH"
ditto -c -k --keepParent "$APP_DIR" "$ZIP_PATH"

# Commit version bump + changelog
git add "$PLIST" CHANGELOG.md
git commit -m "release: v$VERSION"
git tag "v$VERSION"
git push --follow-tags

# GitHub release
PRERELEASE_FLAG=""
[[ "$BETA" == true ]] && PRERELEASE_FLAG="--prerelease"
gh release create "v$VERSION" "$ZIP_PATH" \
    --repo "$RELEASE_REPO" \
    --title "v$VERSION" \
    --notes "$CHANGELOG_MSG" \
    $PRERELEASE_FLAG

# Update appcast
export X_NOISE_VERSION="$VERSION"
export X_NOISE_BUILD_NUMBER="$BUILD_NUMBER"
export X_NOISE_ZIP_PATH="$REPO_ROOT/$ZIP_PATH"
export X_NOISE_RELEASE_NOTES="$CHANGELOG_MSG"
[[ "$BETA" == true ]] && export X_NOISE_BETA=true
./scripts/update-appcast.sh

echo "Done. v$VERSION published."
```

- [ ] **Step 2: Make executable**

Run: `chmod +x scripts/release.sh`

- [ ] **Step 3: Lint with shellcheck if available**

Run: `command -v shellcheck >/dev/null && shellcheck scripts/release.sh || echo "shellcheck not installed, skipping"`
Expected: no errors (or skipped).

- [ ] **Step 4: Commit**

```bash
git add scripts/release.sh
git commit -m "feat(releases): add scripts/release.sh"
```

---

## Task 13: Add update-appcast.sh

**Files:**
- Create: `scripts/update-appcast.sh`

- [ ] **Step 1: Write the script**

```bash
#!/bin/zsh
# update-appcast.sh — Append a new release to appcast.xml.
#
# Required env:
#   X_NOISE_VERSION        — semantic version
#   X_NOISE_BUILD_NUMBER   — integer build number
#   X_NOISE_ZIP_PATH       — path to the signed/notarised .zip
#   SPARKLE_EDDSA_KEY      — base64 EdDSA private key
#
# Optional:
#   GITHUB_REPO            — owner/repo (default: bluedusk/x-noise)
#   X_NOISE_RELEASE_NOTES  — markdown release notes (rendered as HTML)
#   X_NOISE_BETA           — if "true", marks as beta channel

set -euo pipefail

: "${X_NOISE_VERSION:?Missing X_NOISE_VERSION}"
: "${X_NOISE_BUILD_NUMBER:?Missing X_NOISE_BUILD_NUMBER}"
: "${X_NOISE_ZIP_PATH:?Missing X_NOISE_ZIP_PATH}"
: "${SPARKLE_EDDSA_KEY:?Missing SPARKLE_EDDSA_KEY}"

REPO="${GITHUB_REPO:-bluedusk/x-noise}"
APPCAST="appcast.xml"
SIGN_UPDATE=$(find .build -name "sign_update" -type f | head -1)

if [[ -z "$SIGN_UPDATE" ]]; then
    echo "Error: sign_update not found. Run 'swift build' first to resolve Sparkle."
    exit 1
fi
if [[ ! -f "$X_NOISE_ZIP_PATH" ]]; then
    echo "Error: ZIP not found at $X_NOISE_ZIP_PATH"; exit 1
fi
if [[ ! -f "$APPCAST" ]]; then
    echo "Error: $APPCAST not found in working directory"; exit 1
fi

# Compute EdDSA signature
echo "Signing $X_NOISE_ZIP_PATH..."
SIGNATURE=$(echo "$SPARKLE_EDDSA_KEY" | "$SIGN_UPDATE" "$X_NOISE_ZIP_PATH" --ed-key-file /dev/stdin 2>/dev/null)
ED_SIGNATURE=$(echo "$SIGNATURE" | sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p')
FILE_LENGTH=$(stat -f%z "$X_NOISE_ZIP_PATH")

if [[ -z "$ED_SIGNATURE" ]]; then
    echo "Error: failed to extract EdDSA signature"
    echo "sign_update output: $SIGNATURE"
    exit 1
fi

DOWNLOAD_URL="https://github.com/${REPO}/releases/download/v${X_NOISE_VERSION}/Shuuchuu.zip"
PUB_DATE=$(LC_ALL=C date +"%a, %d %b %Y %H:%M:%S %z")

# Build description block — wrap each line in <li>
DESC_HTML=""
if [[ -n "${X_NOISE_RELEASE_NOTES:-}" ]]; then
    LIS=$(echo "$X_NOISE_RELEASE_NOTES" | sed 's/^- /<li>/; s/$/<\/li>/' | tr -d '\n')
    DESC_HTML="<![CDATA[<ul>${LIS}</ul>]]>"
fi

CHANNEL_TAG=""
if [[ "${X_NOISE_BETA:-false}" == "true" ]]; then
    CHANNEL_TAG="            <sparkle:channel>beta</sparkle:channel>"
fi

# Build new <item>
NEW_ITEM=$(cat <<EOF
        <item>
            <title>Version ${X_NOISE_VERSION}</title>
            <pubDate>${PUB_DATE}</pubDate>
            <sparkle:minimumSystemVersion>26.0</sparkle:minimumSystemVersion>
${CHANNEL_TAG}
            <description>${DESC_HTML}</description>
            <enclosure
                url="${DOWNLOAD_URL}"
                sparkle:version="${X_NOISE_BUILD_NUMBER}"
                sparkle:shortVersionString="${X_NOISE_VERSION}"
                sparkle:edSignature="${ED_SIGNATURE}"
                length="${FILE_LENGTH}"
                type="application/octet-stream"
            />
        </item>
EOF
)

# Insert after <language>en</language>
TMP=$(mktemp)
awk -v item="$NEW_ITEM" '
    /<language>en<\/language>/ { print; print item; next }
    { print }
' "$APPCAST" > "$TMP"
mv "$TMP" "$APPCAST"

git add "$APPCAST"
git commit -m "release: appcast v${X_NOISE_VERSION}"
git push

echo "appcast.xml updated and pushed."
```

- [ ] **Step 2: Make executable**

Run: `chmod +x scripts/update-appcast.sh`

- [ ] **Step 3: Commit**

```bash
git add scripts/update-appcast.sh
git commit -m "feat(releases): add scripts/update-appcast.sh"
```

---

## Task 14: .gitignore additions and CLAUDE.md

**Files:**
- Modify: `.gitignore`
- Modify: `CLAUDE.md`

- [ ] **Step 1: Append to .gitignore**

Append these lines to `.gitignore` (create the file if missing):

```
.env
output/
*.zip
```

- [ ] **Step 2: Verify no duplicate entries**

Run: `sort -u .gitignore -o .gitignore`
Expected: file is now sorted and dedup'd. Inspect briefly to confirm sane.

- [ ] **Step 3: Add a "Releases" section to CLAUDE.md**

Append this block to `CLAUDE.md`:

```markdown

## Releases

In-app updates use Sparkle 2.9 (SPM dep). Appcast lives at `appcast.xml` (repo root) and is served via `https://raw.githubusercontent.com/bluedusk/x-noise/main/appcast.xml`. Binaries ship through GitHub Releases on `bluedusk/x-noise`.

To cut a release:

```bash
./scripts/release.sh 0.2.0 "Brief changelog message"
./scripts/release.sh 0.2.0                # auto-generates from git log since prev tag
./scripts/release.sh --beta 0.3.0-beta.1  # beta channel + GitHub pre-release
```

Required `.env` (gitignored):
- `SPARKLE_EDDSA_KEY` — base64 EdDSA private key (one-time generated via Sparkle's `generate_keys`).
- `X_NOISE_SIGN_IDENTITY` — `Developer ID Application: <name> (<team>)`.
- `X_NOISE_NOTARY_PROFILE` — keychain profile from `xcrun notarytool store-credentials`.

The script bumps `CFBundleShortVersionString` + `CFBundleVersion` in `Sources/Shuuchuu/Resources/Info.plist`, builds, signs with hardened runtime + `config/packaging/Shuuchuu.entitlements`, notarises, staples, tags, pushes to GitHub Releases, EdDSA-signs the zip, and prepends a new item to `appcast.xml`.

**EdDSA keys** (one-time):
- After `swift build` (resolves Sparkle), run `.build/artifacts/sparkle/Sparkle/bin/generate_keys`. Public key goes into `Info.plist`'s `SUPublicEDKey`. Private key gets exported with `generate_keys -x` and stored in `.env` as `SPARKLE_EDDSA_KEY` (also keep an offline backup).
```

- [ ] **Step 4: Commit**

```bash
git add .gitignore CLAUDE.md
git commit -m "docs: add Releases section to CLAUDE.md; ignore .env/output/*.zip"
```

---

## Task 15: Final test pass

**Files:** None (verification only).

- [ ] **Step 1: Run the full test suite**

Run: `swift test 2>&1 | tail -20`
Expected: all green; `UpdateCheckerTests` 4 tests passing.

- [ ] **Step 2: Build release binary to confirm packaging path works**

Run: `swift build -c release 2>&1 | tail -5`
Expected: builds.

- [ ] **Step 3: Final smoke**

Run: `pkill -x Shuuchuu; swift run 2>&1 | tail -3 &`
Open Settings, confirm Updates section renders, click "Check now" — Sparkle reports "You're up to date" (the appcast has no items yet).

Run: `pkill -x Shuuchuu`

(No commit — this is verification only.)

---

## Manual one-time setup (post-merge, not part of any task)

These can't be automated by the plan and need user/keychain interaction. Document them once the implementation lands:

1. **Generate EdDSA keys**: `swift build && .build/artifacts/sparkle/Sparkle/bin/generate_keys`
2. **Replace placeholder** in `Info.plist`'s `SUPublicEDKey` with the generated public key. Commit.
3. **Export private key** to `.env`: `.build/artifacts/sparkle/Sparkle/bin/generate_keys -x | grep -A1 'private key' | tail -1` → `SPARKLE_EDDSA_KEY=...`
4. **Notary credentials**: `xcrun notarytool store-credentials shuuchuu-notary --apple-id "<email>" --team-id "<TEAMID>" --password "<app-specific-password>"`. Set `X_NOISE_NOTARY_PROFILE=shuuchuu-notary` in `.env`.
5. **Sign identity**: `security find-identity -v -p codesigning` to find the Developer ID line. Set `X_NOISE_SIGN_IDENTITY` in `.env` to the full `"Developer ID Application: ..."` string.
6. **First release**: `./scripts/release.sh 0.1.0 "Initial release with in-app updates"`.
