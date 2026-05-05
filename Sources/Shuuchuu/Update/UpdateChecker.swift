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
    static let releasesURL = URL(string: "https://github.com/bluedusk/shuuchuu-publish/releases")!

    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var hasUpdate = false
    @Published private(set) var latestVersion: String?
    @Published private(set) var lastCheckDate: Date?

    // Marked `nonisolated(unsafe)` so the `nonisolated` delegate methods can
    // read the bool flag without hopping to MainActor. UserDefaults is documented
    // thread-safe and we never reassign this property after init.
    nonisolated(unsafe) private let defaults: UserDefaults
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

    var automaticallyChecksForUpdates: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }

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
        let beta = defaults.bool(forKey: "app.betaUpdates")
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
}
