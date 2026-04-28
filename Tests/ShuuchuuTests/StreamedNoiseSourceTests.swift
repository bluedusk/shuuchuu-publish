import XCTest
import AVFoundation
import CryptoKit
@testable import Shuuchuu

final class StreamedNoiseSourceTests: XCTestCase {
    private var tempDir: URL!
    private var cache: AudioCache!

    override func setUp() async throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("shuuchuu-streamed-\(UUID())")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func fixtureTrack() throws -> (Track, Data) {
        let url = Bundle.module.url(forResource: "loop-1s", withExtension: "caf")!
        let data = try Data(contentsOf: url)
        let hash = sha256Hex(data)
        let track = Track(
            id: "loop",
            name: "Loop",
            kind: .streamed(StreamedInfo(
                url: URL(string: "https://example/loop.caf")!,
                sha256: hash,
                bytes: Int64(data.count),
                durationSec: 1
            )),
            artworkUrl: nil
        )
        return (track, data)
    }

    func testPrepareDownloadsAndLoads() async throws {
        let (track, payload) = try fixtureTrack()
        cache = AudioCache(baseDir: tempDir, downloader: FixedDownloader(payload: payload))

        let source = StreamedNoiseSource(track: track, cache: cache)
        XCTAssertFalse(source.isReady)
        try await source.prepare()
        XCTAssertTrue(source.isReady)
        XCTAssertTrue(source.node is AVAudioPlayerNode)
    }

    func testIDAndName() async throws {
        let (track, payload) = try fixtureTrack()
        cache = AudioCache(baseDir: tempDir, downloader: FixedDownloader(payload: payload))
        let source = StreamedNoiseSource(track: track, cache: cache)
        XCTAssertEqual(source.id, "loop")
        XCTAssertEqual(source.displayName, "Loop")
    }
}

private final class FixedDownloader: AudioDownloader, @unchecked Sendable {
    let payload: Data
    init(payload: Data) { self.payload = payload }
    func download(from url: URL) async throws -> Data { payload }
}
