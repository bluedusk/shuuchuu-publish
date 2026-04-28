import XCTest
import CryptoKit
@testable import XNoise

final class AudioCacheTests: XCTestCase {
    private var tempDir: URL!

    override func setUp() async throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("xnoise-cache-\(UUID())")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func makeTrack(url: URL, hash: String, bytes: Int64 = 100) -> Track {
        Track(id: "t",
              name: "T",
              kind: .streamed(StreamedInfo(url: url, sha256: hash, bytes: bytes, durationSec: 10)),
              artworkUrl: nil)
    }

    func testDownloadAndVerify() async throws {
        let payload = Data("hello".utf8)
        let hash = sha256(payload)
        let remoteURL = URL(string: "https://example/audio.caf")!
        let track = makeTrack(url: remoteURL, hash: hash)

        let cache = AudioCache(
            baseDir: tempDir,
            downloader: StubDownloader(payload: payload)
        )
        let localURL = try await cache.localURL(for: track)

        let onDisk = try Data(contentsOf: localURL)
        XCTAssertEqual(onDisk, payload)
    }

    func testReusesCachedFileOnSecondCall() async throws {
        let payload = Data("hello".utf8)
        let hash = sha256(payload)
        let track = makeTrack(url: URL(string: "https://example/a.caf")!, hash: hash)
        let downloader = StubDownloader(payload: payload)
        let cache = AudioCache(baseDir: tempDir, downloader: downloader)

        _ = try await cache.localURL(for: track)
        _ = try await cache.localURL(for: track)

        XCTAssertEqual(downloader.callCount, 1)
    }

    func testIntegrityFailureThrows() async throws {
        let track = makeTrack(
            url: URL(string: "https://example/a.caf")!,
            hash: String(repeating: "0", count: 64)
        )
        let cache = AudioCache(
            baseDir: tempDir,
            downloader: StubDownloader(payload: Data("hello".utf8))
        )
        do {
            _ = try await cache.localURL(for: track)
            XCTFail("expected integrity error")
        } catch AudioCache.CacheError.integrityFailed {
            // pass
        }
    }

    func testLRUEviction() async throws {
        let dynamic = DynamicPayloadDownloader()
        let cache = AudioCache(
            baseDir: tempDir,
            downloader: dynamic,
            limitBytes: 100  // tight cap: fits 2 of 3 50-byte files
        )

        for i in 0..<3 {
            let payload = Data(repeating: UInt8(i), count: 50)
            let hash = sha256(payload)
            let url = URL(string: "https://example/\(i).caf")!
            let track = makeTrack(url: url, hash: hash)
            dynamic.next = payload
            _ = try await cache.localURL(for: track)
            try await Task.sleep(nanoseconds: 10_000_000) // 10 ms
        }

        await cache.evictIfOverLimit()

        let files = try FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)
        XCTAssertLessThanOrEqual(files.count, 2)
    }
}

private final class StubDownloader: AudioDownloader {
    let payload: Data
    var callCount = 0
    init(payload: Data) { self.payload = payload }
    func download(from url: URL) async throws -> Data {
        callCount += 1
        return payload
    }
}

private final class DynamicPayloadDownloader: AudioDownloader {
    var next: Data = Data()
    func download(from url: URL) async throws -> Data { next }
}
