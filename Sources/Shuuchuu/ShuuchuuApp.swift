import SwiftUI
import AppKit

@main
struct ShuuchuuApp: App {
    @StateObject private var model: AppModel
    @StateObject private var design: DesignSettings

    init() {
        let d = DesignSettings()
        _design = StateObject(wrappedValue: d)
        _model  = StateObject(wrappedValue: AppModel.live(design: d))
    }

    var body: some SwiftUI.Scene {
        MenuBarExtra {
            PopoverView()
                .environmentObject(model)
                .environmentObject(design)
                .environmentObject(model.updates)
                .environmentObject(model.license)
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
                .environmentObject(model.session)
                .environmentObject(model.focusSettings)
                .environmentObject(model.license)
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
            .appendingPathComponent("shuuchuu")
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
        let soundtracksLibrary = SoundtracksLibrary()
        let soundtrackController = WebSoundtrackController()
        // resolveTrack is captured weakly via a closure so MixingController doesn't
        // pin AppModel — but the closure must be set after AppModel is built. So we
        // build the model first with a temporary controller, then thread the resolver.
        // Simpler: build a small mutable resolver box that we wire in after init.
        let resolverBox = TrackResolverBox()
        let mixer = MixingController(state: state, cache: cache, resolveTrack: { id in
            resolverBox.resolve?(id)
        })
        let scenesLibrary = ScenesLibrary()
        guard let shaderRenderer = ShaderRenderer() else {
            fatalError("ShaderRenderer init failed — no Metal device on this Mac")
        }
        let scene = SceneController(library: scenesLibrary,
                                    renderer: shaderRenderer)
        // Keychain via /usr/bin/security CLI. Shells out so the access is made
        // by Apple's stable-signed binary, sidestepping the prompt-every-launch
        // problem that hits unsigned dev builds using SecItem* directly.
        // Mirrors x-island's LicenseManager pattern.
        let licenseStorage = LicenseStorage(
            backend: SecurityCLILicenseBackend(service: Constants.License.keychainService)
        )
        let licenseClient = LemonSqueezyClient(apiBase: Constants.License.apiBase)
        let license = LicenseController(
            api: licenseClient,
            storage: licenseStorage,
            trialDuration: Constants.License.trialDuration,
            activationLimit: Constants.License.activationLimit
        )
        let updates = UpdateChecker()
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
            savedMixes: savedMixes,
            soundtracksLibrary: soundtracksLibrary,
            soundtrackController: soundtrackController,
            scenes: scenesLibrary,
            shaderRenderer: shaderRenderer,
            scene: scene,
            license: license,
            updates: updates
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
