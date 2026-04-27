import XCTest
import Combine
@testable import XNoise

@MainActor
final class AppModelSoundtrackTests: XCTestCase {

    private static func ephemeralDefaults() -> UserDefaults {
        let suite = "test.appmodel.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        return d
    }

    private func makeModel(defaults: UserDefaults? = nil) -> (AppModel, MockSoundtrackController) {
        let d = defaults ?? Self.ephemeralDefaults()
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
        let mock = MockSoundtrackController()
        let model = AppModel(
            catalog: catalog, state: state, mixer: mixer, cache: cache,
            focusSettings: focusSettings, session: session, design: design,
            favorites: favorites, prefs: prefs, savedMixes: savedMixes,
            soundtracksLibrary: library, soundtrackController: mock,
            defaults: d
        )
        resolverBox.resolve = { [weak model] id in model?.findTrack(id: id) }
        return (model, mock)
    }

    private func parsedURL(_ raw: String) -> SoundtrackURL {
        switch SoundtrackURL.parse(raw) {
        case .success(let p): return p
        case .failure(let e): fatalError("parse failed: \(e)")
        }
    }

    // MARK: - addSoundtrack

    func testAddSoundtrackFromIdleAutoActivates() {
        let (model, mock) = makeModel()
        XCTAssertEqual(model.mode, .idle)

        let r = model.addSoundtrack(rawURL: "https://youtu.be/abc123")
        guard case .success(let entry) = r else { XCTFail("expected success"); return }

        XCTAssertEqual(model.mode, .soundtrack(entry.id))
        XCTAssertEqual(mock.calls, [.load(id: entry.id, autoplay: true)])
    }

    func testAddSoundtrackFromMixDoesNotStealMode() {
        let (model, mock) = makeModel()
        model.mode = .mix       // pretend the user has a mix going

        let r = model.addSoundtrack(rawURL: "https://youtu.be/abc123")
        guard case .success = r else { XCTFail("expected success"); return }

        XCTAssertEqual(model.mode, .mix)
        XCTAssertTrue(mock.calls.isEmpty)
    }

    func testAddSoundtrackInvalidURLReturnsError() {
        let (model, _) = makeModel()
        let r = model.addSoundtrack(rawURL: "not a url")
        XCTAssertEqual(r, .failure(.invalidURL))
        XCTAssertEqual(model.mode, .idle)
    }

    func testAddSoundtrackUnsupportedHostReturnsError() {
        let (model, _) = makeModel()
        let r = model.addSoundtrack(rawURL: "https://soundcloud.com/foo")
        XCTAssertEqual(r, .failure(.unsupportedHost))
    }

    // MARK: - activateSoundtrack

    func testActivateInactiveSoundtrack() {
        let (model, mock) = makeModel()
        let entry = model.soundtracksLibrary.add(parsed: parsedURL("https://youtu.be/x"))

        model.activateSoundtrack(id: entry.id)

        XCTAssertEqual(model.mode, .soundtrack(entry.id))
        XCTAssertEqual(mock.calls, [.load(id: entry.id, autoplay: true)])
    }

    func testActivateSameSoundtrackIsIdempotent() {
        let (model, mock) = makeModel()
        let entry = model.soundtracksLibrary.add(parsed: parsedURL("https://youtu.be/x"))
        model.activateSoundtrack(id: entry.id)
        mock.calls.removeAll()

        model.activateSoundtrack(id: entry.id)

        XCTAssertEqual(model.mode, .soundtrack(entry.id))
        XCTAssertTrue(mock.calls.isEmpty)
    }

    func testActivateDifferentSoundtrackSwaps() {
        let (model, mock) = makeModel()
        let a = model.soundtracksLibrary.add(parsed: parsedURL("https://youtu.be/a"))
        let b = model.soundtracksLibrary.add(parsed: parsedURL("https://youtu.be/b"))
        model.activateSoundtrack(id: a.id)
        mock.calls.removeAll()

        model.activateSoundtrack(id: b.id)

        XCTAssertEqual(model.mode, .soundtrack(b.id))
        XCTAssertEqual(mock.calls, [.load(id: b.id, autoplay: true)])
    }

    func testActivateUnknownIdIsNoOp() {
        let (model, mock) = makeModel()
        let unknown = UUID()
        model.activateSoundtrack(id: unknown)
        XCTAssertEqual(model.mode, .idle)
        XCTAssertTrue(mock.calls.isEmpty)
    }

    // MARK: - deactivateSoundtrack

    func testDeactivateActiveSoundtrack() {
        let (model, mock) = makeModel()
        let entry = model.soundtracksLibrary.add(parsed: parsedURL("https://youtu.be/x"))
        model.activateSoundtrack(id: entry.id)
        mock.calls.removeAll()

        model.deactivateSoundtrack()

        XCTAssertEqual(model.mode, .idle)
        XCTAssertEqual(mock.calls, [.setPaused(true)])
    }

    func testDeactivateWhenNotInSoundtrackModeIsNoOp() {
        let (model, mock) = makeModel()
        model.deactivateSoundtrack()
        XCTAssertEqual(model.mode, .idle)
        XCTAssertTrue(mock.calls.isEmpty)
    }

    // MARK: - removeSoundtrack

    func testRemoveActiveSoundtrackFallsBackToIdle() {
        let (model, mock) = makeModel()
        let entry = model.soundtracksLibrary.add(parsed: parsedURL("https://youtu.be/x"))
        model.activateSoundtrack(id: entry.id)
        mock.calls.removeAll()

        model.removeSoundtrack(id: entry.id)

        XCTAssertEqual(model.mode, .idle)
        XCTAssertEqual(mock.calls, [.unload])
        XCTAssertNil(model.soundtracksLibrary.entry(id: entry.id))
    }

    func testRemoveInactiveSoundtrackPreservesMode() {
        let (model, mock) = makeModel()
        let active = model.soundtracksLibrary.add(parsed: parsedURL("https://youtu.be/a"))
        let other  = model.soundtracksLibrary.add(parsed: parsedURL("https://youtu.be/b"))
        model.activateSoundtrack(id: active.id)
        mock.calls.removeAll()

        model.removeSoundtrack(id: other.id)

        XCTAssertEqual(model.mode, .soundtrack(active.id))
        XCTAssertTrue(mock.calls.isEmpty)
    }

    // MARK: - Mix mutations flip mode

    func testToggleTrackFromIdleEntersMix() {
        let (model, _) = makeModel()
        let track = Track(id: "rain", name: "Rain", kind: .procedural(.white), artworkUrl: nil)
        model.toggleTrack(track)
        XCTAssertEqual(model.mode, .mix)
    }

    func testToggleTrackFromSoundtrackPausesAndSwitchesToMix() {
        let (model, mock) = makeModel()
        let entry = model.soundtracksLibrary.add(parsed: parsedURL("https://youtu.be/x"))
        model.activateSoundtrack(id: entry.id)
        mock.calls.removeAll()

        let track = Track(id: "rain", name: "Rain", kind: .procedural(.white), artworkUrl: nil)
        model.toggleTrack(track)

        XCTAssertEqual(model.mode, .mix)
        // Soundtrack is paused but NOT unloaded — per spec §2.4 the WKWebView is
        // retained so the user can flip back fast.
        XCTAssertEqual(mock.calls, [.setPaused(true)])
    }

    func testActivateSoundtrackFromMixPausesMix() {
        let (model, _) = makeModel()
        let rain = Track(id: "rain", name: "Rain", kind: .procedural(.white), artworkUrl: nil)
        model.toggleTrack(rain)
        XCTAssertEqual(model.mode, .mix)
        XCTAssertTrue(model.state.anyPlaying)

        let entry = model.soundtracksLibrary.add(parsed: parsedURL("https://youtu.be/x"))
        model.activateSoundtrack(id: entry.id)

        XCTAssertEqual(model.mode, .soundtrack(entry.id))
        XCTAssertFalse(model.state.anyPlaying)   // mix paused
        XCTAssertTrue(model.state.contains("rain"))   // mix preserved
    }

    func testApplyPresetFromSoundtrackSwitchesToMix() {
        let (model, mock) = makeModel()
        let entry = model.soundtracksLibrary.add(parsed: parsedURL("https://youtu.be/x"))
        model.activateSoundtrack(id: entry.id)
        mock.calls.removeAll()

        let preset = Preset(id: "deep", name: "Deep", mix: ["rain": 0.5])
        model.applyPreset(preset)

        XCTAssertEqual(model.mode, .mix)
        XCTAssertEqual(mock.calls, [.setPaused(true)])
    }

    // MARK: - setSoundtrackVolume

    func testSetVolumeOnActivePushesToController() {
        let (model, mock) = makeModel()
        let entry = model.soundtracksLibrary.add(parsed: parsedURL("https://youtu.be/x"))
        model.activateSoundtrack(id: entry.id)
        mock.calls.removeAll()

        model.setSoundtrackVolume(id: entry.id, volume: 0.3)

        XCTAssertEqual(model.soundtracksLibrary.entry(id: entry.id)?.volume ?? 0, 0.3, accuracy: 0.001)
        XCTAssertEqual(mock.calls, [.setVolume(0.3)])
    }

    func testSetVolumeOnInactivePersistsButDoesNotPush() {
        let (model, mock) = makeModel()
        let active = model.soundtracksLibrary.add(parsed: parsedURL("https://youtu.be/a"))
        let other  = model.soundtracksLibrary.add(parsed: parsedURL("https://youtu.be/b"))
        model.activateSoundtrack(id: active.id)
        mock.calls.removeAll()

        model.setSoundtrackVolume(id: other.id, volume: 0.7)

        XCTAssertEqual(model.soundtracksLibrary.entry(id: other.id)?.volume ?? 0, 0.7, accuracy: 0.001)
        XCTAssertTrue(mock.calls.isEmpty)
    }

    // MARK: - togglePlayAll + pauseActiveSource

    func testTogglePlayAllInSoundtrackModePauses() {
        let (model, mock) = makeModel()
        let entry = model.soundtracksLibrary.add(parsed: parsedURL("https://youtu.be/x"))
        model.activateSoundtrack(id: entry.id)
        XCTAssertFalse(model.activeSourcePaused)
        mock.calls.removeAll()

        model.togglePlayAll()

        XCTAssertTrue(model.activeSourcePaused)
        XCTAssertEqual(mock.calls, [.setPaused(true)])
    }

    func testTogglePlayAllInSoundtrackModeResumes() {
        let (model, mock) = makeModel()
        let entry = model.soundtracksLibrary.add(parsed: parsedURL("https://youtu.be/x"))
        model.activateSoundtrack(id: entry.id)
        model.togglePlayAll()                  // pause
        mock.calls.removeAll()

        model.togglePlayAll()                  // resume

        XCTAssertFalse(model.activeSourcePaused)
        XCTAssertEqual(mock.calls, [.setPaused(false)])
    }

    func testTogglePlayAllInIdleIsNoOp() {
        let (model, mock) = makeModel()
        model.togglePlayAll()
        XCTAssertEqual(model.mode, .idle)
        XCTAssertTrue(mock.calls.isEmpty)
    }

    func testPauseActiveSourceInMixMutesAllTracks() {
        let (model, _) = makeModel()
        let rain = Track(id: "rain", name: "Rain", kind: .procedural(.white), artworkUrl: nil)
        model.toggleTrack(rain)
        XCTAssertTrue(model.state.anyPlaying)

        model.pauseActiveSource(true)
        XCTAssertFalse(model.state.anyPlaying)

        model.pauseActiveSource(false)
        XCTAssertTrue(model.state.anyPlaying)
    }

    // MARK: - FocusSession mirror

    func testFocusPhaseTransitionMirrorsToSoundtrack() {
        let (model, mock) = makeModel()
        let entry = model.soundtracksLibrary.add(parsed: parsedURL("https://youtu.be/x"))
        model.activateSoundtrack(id: entry.id)
        mock.calls.removeAll()

        // Skip from .focus → .shortBreak. Soundtrack should pause.
        model.session.skip()
        XCTAssertEqual(mock.calls, [.setPaused(true)])
        XCTAssertTrue(model.activeSourcePaused)

        mock.calls.removeAll()
        // Skip from .shortBreak → .focus. Soundtrack should resume.
        model.session.skip()
        XCTAssertEqual(mock.calls, [.setPaused(false)])
        XCTAssertFalse(model.activeSourcePaused)
    }

    func testFocusPhaseTransitionMirrorsToMix() {
        let (model, _) = makeModel()
        let rain = Track(id: "rain", name: "Rain", kind: .procedural(.white), artworkUrl: nil)
        model.toggleTrack(rain)
        XCTAssertTrue(model.state.anyPlaying)

        model.session.skip()                     // → break, mix should pause
        XCTAssertFalse(model.state.anyPlaying)

        model.session.skip()                     // → focus, mix should resume
        XCTAssertTrue(model.state.anyPlaying)
    }

    func testFocusPhaseTransitionInIdleIsNoOp() {
        let (model, mock) = makeModel()
        model.session.skip()
        XCTAssertEqual(model.mode, .idle)
        XCTAssertTrue(mock.calls.isEmpty)
    }
}
