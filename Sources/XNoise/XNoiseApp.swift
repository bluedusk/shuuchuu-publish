import SwiftUI
import AppKit

@main
struct XNoiseApp: App {
    @StateObject private var model: AppModel
    @StateObject private var design: DesignSettings

    init() {
        let d = DesignSettings()
        _design = StateObject(wrappedValue: d)
        _model  = StateObject(wrappedValue: AppModel.live(design: d))
    }

    var body: some Scene {
        MenuBarExtra {
            PopoverView()
                .environmentObject(model)
                .environmentObject(design)
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
        }
        .menuBarExtraStyle(.window)
    }
}

extension AppModel {
    @MainActor
    static func live(design: DesignSettings) -> AppModel {
        let prefs = Preferences()
        let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Constants.audioCacheDirName)
        let appSupportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("x-noise")
        try? FileManager.default.createDirectory(at: appSupportDir, withIntermediateDirectories: true)
        let catalog = Catalog(
            fetcher: BundleCatalogFetcher(),
            cacheFile: appSupportDir.appendingPathComponent(Constants.catalogCacheFilename)
        )
        let cache = AudioCache(baseDir: cachesDir, downloader: URLSessionDownloader())
        let mixer = MixingController()
        let focusSettings = FocusSettings()
        let session = FocusSession(settings: focusSettings)
        let favorites = Favorites()
        return AppModel(
            catalog: catalog,
            mixer: mixer,
            cache: cache,
            focusSettings: focusSettings,
            session: session,
            design: design,
            favorites: favorites,
            prefs: prefs
        )
    }
}
