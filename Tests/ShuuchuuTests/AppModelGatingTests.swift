import XCTest
@testable import Shuuchuu

@MainActor
final class AppModelGatingTests: XCTestCase {
    private func makeModel(unlocked: Bool) -> AppModel {
        let suite = "test.gating.\(UUID())"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)

        let prefs = Preferences(defaults: d)
        let state = MixState(defaults: d)
        let cache = AudioCache(baseDir: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),
                               downloader: URLSessionDownloader())
        let catalog = Catalog(fetcher: BundleCatalogFetcher(),
                              cacheFile: FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).json"))
        let resolverBox = TrackResolverBox()
        let mixer = MixingController(state: state, cache: cache, resolveTrack: { resolverBox.resolve?($0) })
        let focusSettings = FocusSettings(defaults: d)
        let session = FocusSession(settings: focusSettings)
        let design = DesignSettings(defaults: d)
        let favorites = Favorites(defaults: d)
        let savedMixes = SavedMixes(defaults: d)
        let library = SoundtracksLibrary(defaults: d)
        let scenesLibrary = ScenesLibrary()
        let stubRenderer = StubShaderRenderer()

        // For "locked" we hand-build a controller seeded with an expired trial.
        let license: LicenseController
        if unlocked {
            license = makeTestLicense()
        } else {
            let backend = InMemoryLicenseBackend()
            let storage = LicenseStorage(backend: backend)
            // Stamp a trial start far in the past so startTrialIfNeeded → .trialExpired
            storage.trialStartedAt = Date(timeIntervalSince1970: 0)
            let c = LicenseController(
                api: StubLemonSqueezyAPI(),
                storage: storage,
                trialDuration: 5 * 24 * 60 * 60,
                activationLimit: 3
            )
            c.startTrialIfNeeded()
            license = c
        }

        let model = AppModel(
            catalog: catalog, state: state, mixer: mixer, cache: cache,
            focusSettings: focusSettings, session: session, design: design,
            favorites: favorites, prefs: prefs, savedMixes: savedMixes,
            soundtracksLibrary: library,
            soundtrackController: MockSoundtrackController(),
            scenes: scenesLibrary,
            shaderRenderer: stubRenderer,
            scene: SceneController(library: scenesLibrary, renderer: stubRenderer),
            license: license,
            updates: UpdateChecker(),
            defaults: d
        )
        resolverBox.resolve = { [weak model] id in model?.findTrack(id: id) }
        return model
    }

    private func track() -> Track {
        Track(id: "rain", name: "Rain", kind: .procedural(.white), artworkUrl: nil)
    }

    func testLockedToggleTrackIsNoop() {
        let model = makeModel(unlocked: false)
        XCTAssertFalse(model.license.isUnlocked)
        model.toggleTrack(track())
        XCTAssertTrue(model.state.tracks.isEmpty, "toggleTrack must no-op while locked")
    }

    func testLockedApplyPresetIsNoop() {
        let model = makeModel(unlocked: false)
        let preset = Preset(id: "p", name: "P", mix: ["rain": 0.5])
        model.applyPreset(preset)
        XCTAssertTrue(model.state.tracks.isEmpty)
    }

    func testLockedAddSoundtrackFails() {
        let model = makeModel(unlocked: false)
        let result = model.addSoundtrack(rawURL: "https://www.youtube.com/watch?v=dQw4w9WgXcQ")
        if case .failure = result { /* ok */ } else {
            XCTFail("expected failure when locked, got \(result)")
        }
    }

    func testLockedTogglePlayAllIsNoop() {
        let model = makeModel(unlocked: false)
        model.togglePlayAll()
        XCTAssertEqual(model.mode, .idle)
    }

    func testUnlockedToggleTrackWorks() {
        let model = makeModel(unlocked: true)
        model.toggleTrack(track())
        XCTAssertEqual(model.state.tracks.count, 1)
    }
}
