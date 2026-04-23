import XCTest
@testable import XNoise

@MainActor
final class AppModelTests: XCTestCase {
    private var tempDir: URL!

    override func setUp() async throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("xnoise-model-\(UUID())")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func fixtureData() throws -> Data {
        let url = Bundle.module.url(forResource: "catalog-valid", withExtension: "json")!
        return try Data(contentsOf: url)
    }

    private func makeModel(prefs: Preferences? = nil) throws -> AppModel {
        let data = try fixtureData()
        let defaults = UserDefaults(suiteName: "t.\(UUID())")!
        return AppModel(
            catalog: Catalog(
                fetcher: StubFetcher(data: data),
                cacheFile: tempDir.appendingPathComponent("c.json")
            ),
            audio: AudioController(),
            cache: AudioCache(baseDir: tempDir, downloader: NullDownloader()),
            prefs: prefs ?? Preferences(defaults: defaults)
        )
    }

    func testPlayProceduralTrack() async throws {
        let model = try makeModel()
        await model.loadCatalog()
        let whiteTrack = model.categories.first!.tracks.first!
        await model.play(whiteTrack)
        XCTAssertEqual(model.audio.state, .playing("white"))
    }

    func testSelectCategoryPersists() async throws {
        let defaults = UserDefaults(suiteName: "t.\(UUID())")!
        let prefs = Preferences(defaults: defaults)
        let model = try makeModel(prefs: prefs)
        await model.loadCatalog()
        model.selectCategory("soundscapes")
        XCTAssertEqual(prefs.lastCategoryId, "soundscapes")
    }

    func testHandleSleepStops() async throws {
        let model = try makeModel()
        await model.loadCatalog()
        let whiteTrack = model.categories.first!.tracks.first!
        await model.play(whiteTrack)
        XCTAssertEqual(model.audio.state, .playing("white"))
        await model.handleSleep()
        XCTAssertEqual(model.audio.state, .idle)
        XCTAssertEqual(model.pendingResumeTrackId, "white")
    }

    func testHandleWakeResumesWhenEnabled() async throws {
        let defaults = UserDefaults(suiteName: "t.\(UUID())")!
        let prefs = Preferences(defaults: defaults)
        prefs.resumeOnWake = true
        let model = try makeModel(prefs: prefs)
        await model.loadCatalog()
        let whiteTrack = model.categories.first!.tracks.first!
        await model.play(whiteTrack)
        await model.handleSleep()
        await model.handleWake()
        XCTAssertEqual(model.audio.state, .playing("white"))
    }
}

private struct StubFetcher: CatalogFetcher {
    let data: Data
    func fetch() async throws -> Data { data }
}

private final class NullDownloader: AudioDownloader {
    func download(from url: URL) async throws -> Data { Data() }
}
