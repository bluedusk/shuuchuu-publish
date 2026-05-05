import XCTest
@testable import Shuuchuu

@MainActor
final class AppModelSaveMixTests: XCTestCase {
    private func makeModel() -> (AppModel, SavedMixes) {
        let suite = "test.appmodel.savemix.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)

        let saved = SavedMixes(defaults: d)
        let state = MixState(defaults: d)
        let prefs = Preferences(defaults: d)
        let design = DesignSettings(defaults: d)
        let favorites = Favorites(defaults: d)
        let focusSettings = FocusSettings(defaults: d)
        let session = FocusSession(settings: focusSettings)
        let cache = AudioCache(baseDir: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),
                               downloader: URLSessionDownloader())
        let resolverBox = TrackResolverBox()
        let mixer = MixingController(state: state, cache: cache, resolveTrack: { id in resolverBox.resolve?(id) })
        let catalog = Catalog(fetcher: BundleCatalogFetcher(),
                              cacheFile: FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).json"))
        let scenesLibrary = ScenesLibrary()
        let stubRenderer = StubShaderRenderer()
        let model = AppModel(
            catalog: catalog, state: state, mixer: mixer, cache: cache,
            focusSettings: focusSettings, session: session, design: design,
            favorites: favorites, prefs: prefs, savedMixes: saved,
            soundtracksLibrary: SoundtracksLibrary(defaults: d),
            soundtrackController: MockSoundtrackController(),
            scenes: scenesLibrary,
            shaderRenderer: nil,
            scene: SceneController(library: scenesLibrary, renderer: stubRenderer),
            license: makeTestLicense(),
            updates: UpdateChecker()
        )
        resolverBox.resolve = { [weak model] id in model?.findTrack(id: id) }
        return (model, saved)
    }

    func testBeginSaveMixEntersNamingMode() {
        let (model, _) = makeModel()
        model.state.append(id: "rain", volume: 0.5)
        model.beginSaveMix()
        if case .naming(let text) = model.saveMode {
            XCTAssertEqual(text, "")
        } else {
            XCTFail("expected .naming, got \(model.saveMode)")
        }
    }

    func testCancelSaveMixReturnsInactive() {
        let (model, _) = makeModel()
        model.state.append(id: "rain", volume: 0.5)
        model.beginSaveMix()
        model.cancelSaveMix()
        XCTAssertEqual(model.saveMode, .inactive)
    }

    func testCommitSaveMixPersistsAndExits() {
        let (model, store) = makeModel()
        model.state.append(id: "rain", volume: 0.5)
        model.beginSaveMix()
        model.updateSaveName("Rainy")
        model.commitSaveMix()
        XCTAssertEqual(model.saveMode, .inactive)
        XCTAssertEqual(store.mixes.first?.name, "Rainy")
        XCTAssertEqual(store.mixes.first?.tracks.first?.id, "rain")
    }

    func testCommitSaveMixDuplicateEntersConflictMode() {
        let (model, store) = makeModel()
        _ = store.save(name: "Existing", tracks: [MixTrack(id: "rain", volume: 0.5)])
        model.state.append(id: "thunder", volume: 0.5)
        model.beginSaveMix()
        model.updateSaveName("Existing")
        model.commitSaveMix()
        if case .confirmingOverwrite(let text, let existing) = model.saveMode {
            XCTAssertEqual(text, "Existing")
            XCTAssertEqual(existing.tracks.first?.id, "rain")
        } else {
            XCTFail("expected .confirmingOverwrite, got \(model.saveMode)")
        }
    }

    func testOverwriteExistingReplacesTracksAndExits() {
        let (model, store) = makeModel()
        guard case .saved(let original) = store.save(name: "Existing",
                                                     tracks: [MixTrack(id: "rain", volume: 0.5)]) else {
            XCTFail(); return
        }
        model.state.append(id: "thunder", volume: 0.5)
        model.beginSaveMix()
        model.updateSaveName("Existing")
        model.commitSaveMix()
        model.overwriteExisting()
        XCTAssertEqual(model.saveMode, .inactive)
        XCTAssertEqual(store.mixes.count, 1)
        XCTAssertEqual(store.mixes.first?.id, original.id)
        XCTAssertEqual(store.mixes.first?.tracks.first?.id, "thunder")
    }

    func testSaveAsNewWithSuffixCreatesNewMix() {
        let (model, store) = makeModel()
        _ = store.save(name: "Existing", tracks: [MixTrack(id: "rain", volume: 0.5)])
        model.state.append(id: "thunder", volume: 0.5)
        model.beginSaveMix()
        model.updateSaveName("Existing")
        model.commitSaveMix()
        model.saveAsNewWithSuffix()
        XCTAssertEqual(model.saveMode, .inactive)
        XCTAssertEqual(store.mixes.count, 2)
        XCTAssertTrue(store.mixes.contains(where: { $0.name == "Existing (2)" }))
    }

    func testCurrentlyLoadedMixIdMatchesByTrackIdSet() async {
        let (model, store) = makeModel()
        guard case .saved(let m) = store.save(name: "Pair",
                                              tracks: [MixTrack(id: "rain", volume: 0.5),
                                                       MixTrack(id: "thunder", volume: 0.5)]) else {
            XCTFail(); return
        }
        model.state.append(id: "thunder", volume: 0.9)  // different volume
        model.state.append(id: "rain",    volume: 0.1)  // different order

        // Allow the Combine subscription to fire on the main runloop.
        await Task.yield()
        try? await Task.sleep(nanoseconds: 50_000_000)  // 50ms is generous

        XCTAssertEqual(model.currentlyLoadedMixId, AnyHashable(m.id))
    }

    func testBeginSaveMixIsNoOpWhenStateIsEmpty() {
        let (model, _) = makeModel()
        XCTAssertTrue(model.state.isEmpty)
        model.beginSaveMix()
        XCTAssertEqual(model.saveMode, .inactive)
    }

    func testCommitSaveMixIsNoOpOnWhitespaceOnlyName() {
        let (model, store) = makeModel()
        model.state.append(id: "rain", volume: 0.5)
        model.beginSaveMix()
        model.updateSaveName("   ")
        model.commitSaveMix()
        // Save was rejected — still in naming mode, store still empty.
        if case .naming = model.saveMode {} else {
            XCTFail("expected to remain in .naming, got \(model.saveMode)")
        }
        XCTAssertTrue(store.mixes.isEmpty)
    }
}
