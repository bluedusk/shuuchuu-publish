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
        let state = MixState()
        let focusSettings = FocusSettings()
        let session = FocusSession(settings: focusSettings)
        let favorites = Favorites()
        let savedMixes = SavedMixes()
        // resolveTrack is captured weakly via a closure so MixingController doesn't
        // pin AppModel — but the closure must be set after AppModel is built. So we
        // build the model first with a temporary controller, then thread the resolver.
        // Simpler: build a small mutable resolver box that we wire in after init.
        let resolverBox = TrackResolverBox()
        let mixer = MixingController(state: state, cache: cache, resolveTrack: { id in
            resolverBox.resolve?(id)
        })
        let model = AppModel(
            catalog: catalog,
            state: state,
            mixer: mixer,
            cache: cache,
            focusSettings: focusSettings,
            session: session,
            design: design,
            favorites: favorites,
            prefs: prefs,
            savedMixes: savedMixes
        )
        resolverBox.resolve = { [weak model] id in model?.findTrack(id: id) }
        return model
    }
}

/// Captures the track-resolver closure so MixingController can be constructed before
/// AppModel exists. Avoids a retain cycle by letting the resolver be weakly bound.
@MainActor
final class TrackResolverBox {
    var resolve: ((String) -> Track?)?
}
