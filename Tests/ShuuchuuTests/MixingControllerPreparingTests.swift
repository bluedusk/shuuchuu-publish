import XCTest
import AVFoundation
import CryptoKit
@testable import Shuuchuu

/// Verifies the streaming-UX hooks: `MixingController` should publish
/// `preparing` while a track's `prepare()` is in flight, clear it when
/// prepare resolves, and route hard failures into `failed`.
@MainActor
final class MixingControllerPreparingTests: XCTestCase {
    private var tempDir: URL!

    override func setUp() async throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("shuuchuu-mixctl-\(UUID())")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func fixturePayload() throws -> Data {
        let url = Bundle.module.url(forResource: "loop-1s", withExtension: "caf")!
        return try Data(contentsOf: url)
    }

    private func makeTrack(payload: Data) -> Track {
        Track(
            id: "loop",
            name: "Loop",
            kind: .streamed(StreamedInfo(
                url: URL(string: "https://example/loop.caf")!,
                sha256: sha256Hex(payload),
                bytes: Int64(payload.count),
                durationSec: 1
            )),
            artworkUrl: nil
        )
    }

    func testPreparingClearsAfterSuccessfulPrepare() async throws {
        let payload = try fixturePayload()
        let track = makeTrack(payload: payload)
        let cache = AudioCache(baseDir: tempDir, downloader: GatedDownloader(payload: payload))
        let state = MixState(defaults: ephemeralDefaults())
        let mixer = MixingController(state: state, cache: cache, resolveTrack: { _ in track })

        state.append(id: "loop", volume: 0.5)
        mixer.reconcileNow()

        // attachSource is async — the `preparing` flag is set synchronously inside
        // reconcile via the spawned Task before any awaits, so it should be observable
        // immediately. Wait for the prepare to finish, then confirm the flag clears.
        await Task.yield()
        await waitFor { mixer.preparing.contains("loop") == false }
        XCTAssertFalse(mixer.preparing.contains("loop"))
        XCTAssertFalse(mixer.failed.contains("loop"))
    }

    func testFailedSetPopulatedOnDownloadError() async throws {
        let payload = try fixturePayload()
        let track = makeTrack(payload: payload)
        // Wrong-payload downloader produces a sha mismatch → AudioCache.integrityFailed.
        let cache = AudioCache(baseDir: tempDir, downloader: GatedDownloader(payload: Data([0xDE, 0xAD])))
        let state = MixState(defaults: ephemeralDefaults())
        let mixer = MixingController(state: state, cache: cache, resolveTrack: { _ in track })

        state.append(id: "loop", volume: 0.5)
        mixer.reconcileNow()

        await waitFor { mixer.failed.contains("loop") }
        XCTAssertTrue(mixer.failed.contains("loop"))
        XCTAssertFalse(mixer.preparing.contains("loop"))
    }

    func testNoSpinnerForAlreadyCachedTrack() async throws {
        let payload = try fixturePayload()
        let track = makeTrack(payload: payload)
        let cache = AudioCache(baseDir: tempDir, downloader: GatedDownloader(payload: payload))
        let state = MixState(defaults: ephemeralDefaults())
        let mixer = MixingController(state: state, cache: cache, resolveTrack: { _ in track })

        // Warm the cache: first attach pulls bytes.
        state.append(id: "loop", volume: 0.5)
        mixer.reconcileNow()
        await waitFor { mixer.preparing.contains("loop") == false }

        // Filesystem listing lags `replaceItemAt` by a few ms in tests even when
        // the file is reachable through `AVAudioFile.read`. Wait until `isCached`
        // confirms the file is visible before proceeding.
        guard case .streamed(let info) = track.kind else { return XCTFail("unreachable") }
        await waitFor { cache.isCached(info) }
        XCTAssertTrue(cache.isCached(info))

        // Toggle off, then back on — file is now on disk.
        state.remove(id: "loop")
        mixer.reconcileNow()
        state.append(id: "loop", volume: 0.5)
        mixer.reconcileNow()

        // Cache hit path: the spinner should never flip on. Polling for the
        // negative case is racy, so we wait a tick and check the flag never
        // activated. Yields once for the attach Task to start, twice for the
        // local prepare path inside it.
        for _ in 0..<5 { await Task.yield() }
        XCTAssertFalse(mixer.preparing.contains("loop"))
    }

    func testRetryClearsFailedAndReprepares() async throws {
        let payload = try fixturePayload()
        let track = makeTrack(payload: payload)
        let downloader = SwitchableDownloader(payload: Data([0xDE, 0xAD]))
        let cache = AudioCache(baseDir: tempDir, downloader: downloader)
        let state = MixState(defaults: ephemeralDefaults())
        let mixer = MixingController(state: state, cache: cache, resolveTrack: { _ in track })

        state.append(id: "loop", volume: 0.5)
        mixer.reconcileNow()
        await waitFor { mixer.failed.contains("loop") }

        // Heal the network and retry.
        downloader.payload = payload
        mixer.retry(id: "loop")
        await waitFor { mixer.failed.contains("loop") == false && mixer.preparing.contains("loop") == false }
        XCTAssertFalse(mixer.failed.contains("loop"))
    }

    /// Polls `condition` on the main actor every 20ms, up to 2s. XCTest's
    /// `expectation(for:)` is awkward to combine with @Published reads, so this
    /// is the simpler primitive.
    private func waitFor(_ condition: () -> Bool, timeout: TimeInterval = 2) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    private func ephemeralDefaults() -> UserDefaults {
        UserDefaults(suiteName: "test.mixctl.\(UUID())")!
    }
}

private final class GatedDownloader: AudioDownloader, @unchecked Sendable {
    let payload: Data
    init(payload: Data) { self.payload = payload }
    func download(from url: URL) async throws -> Data { payload }
}

private final class SwitchableDownloader: AudioDownloader, @unchecked Sendable {
    var payload: Data
    init(payload: Data) { self.payload = payload }
    func download(from url: URL) async throws -> Data { payload }
}
