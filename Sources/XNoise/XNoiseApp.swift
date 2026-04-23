import SwiftUI
import AppKit

@main
struct XNoiseApp: App {
    @StateObject private var model = AppModel.live()

    var body: some Scene {
        MenuBarExtra {
            PopoverView()
                .environmentObject(model)
                .task { await model.handleLaunch() }
                .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.willSleepNotification)) { _ in
                    Task { await model.handleSleep() }
                }
                .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)) { _ in
                    Task { await model.handleWake() }
                }
        } label: {
            MenubarLabel().environmentObject(model)
        }
        .menuBarExtraStyle(.window)
    }
}

extension AppModel {
    @MainActor
    static func live() -> AppModel {
        let prefs = Preferences()
        let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Constants.audioCacheDirName)
        let appSupportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("x-noise")
        try? FileManager.default.createDirectory(at: appSupportDir, withIntermediateDirectories: true)
        let catalog = Catalog(
            fetcher: URLSessionFetcher(url: Constants.catalogURL),
            cacheFile: appSupportDir.appendingPathComponent(Constants.catalogCacheFilename)
        )
        let cache = AudioCache(baseDir: cachesDir, downloader: URLSessionDownloader())
        let audio = AudioController()
        return AppModel(catalog: catalog, audio: audio, cache: cache, prefs: prefs)
    }
}
