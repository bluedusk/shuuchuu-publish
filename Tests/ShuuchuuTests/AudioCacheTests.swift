import XCTest
import CryptoKit
@testable import Shuuchuu

final class AudioCacheTests: XCTestCase {
    private var tempDir: URL!

    override func setUp() async throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("shuuchuu-cache-\(UUID())")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func makeInfo(url: URL, hash: String, bytes: Int64 = 100) -> StreamedInfo {
        StreamedInfo(url: url, sha256: hash, bytes: bytes, durationSec: 10)
    }

    func testDownloadAndVerify() async throws {
        let payload = Data("hello".utf8)
        let hash = sha256(payload)
        let remoteURL = URL(string: "https://example/audio.caf")!
        let info = makeInfo(url: remoteURL, hash: hash)

        let cache = AudioCache(
            baseDir: tempDir,
            downloader: StubDownloader(payload: payload)
        )
        let localURL = try await cache.localURL(for: info)

        let onDisk = try Data(contentsOf: localURL)
        XCTAssertEqual(onDisk, payload)
    }

    func testReusesCachedFileOnSecondCall() async throws {
        let payload = Data("hello".utf8)
        let hash = sha256(payload)
        let info = makeInfo(url: URL(string: "https://example/a.caf")!, hash: hash)
        let downloader = StubDownloader(payload: payload)
        let cache = AudioCache(baseDir: tempDir, downloader: downloader)

        _ = try await cache.localURL(for: info)
        _ = try await cache.localURL(for: info)

        let count = await downloader.callCount
        XCTAssertEqual(count, 1)
    }

    func testIntegrityFailureThrows() async throws {
        let info = makeInfo(
            url: URL(string: "https://example/a.caf")!,
            hash: String(repeating: "0", count: 64)
        )
        let cache = AudioCache(
            baseDir: tempDir,
            downloader: StubDownloader(payload: Data("hello".utf8))
        )
        do {
            _ = try await cache.localURL(for: info)
            XCTFail("expected integrity error")
        } catch AudioCache.CacheError.integrityFailed {
            // pass
        }
    }

    func testInvalidHashRejected() async throws {
        let info = makeInfo(url: URL(string: "https://example/a.caf")!, hash: "../etc/passwd")
        let cache = AudioCache(baseDir: tempDir, downloader: StubDownloader(payload: Data()))
        do {
            _ = try await cache.localURL(for: info)
            XCTFail("expected invalidHash error")
        } catch AudioCache.CacheError.invalidHash {
            // pass — must reject before touching the network
        }
    }

    func testConcurrentFetchesShareSingleDownload() async throws {
        let payload = Data("dedup".utf8)
        let hash = sha256(payload)
        let info = makeInfo(url: URL(string: "https://example/a.caf")!, hash: hash)
        let downloader = StubDownloader(payload: payload)
        let cache = AudioCache(baseDir: tempDir, downloader: downloader)

        // Kick off 5 concurrent fetches for the same key — they should all
        // resolve to the same file, but only ONE network round-trip should happen.
        async let r0 = cache.localURL(for: info)
        async let r1 = cache.localURL(for: info)
        async let r2 = cache.localURL(for: info)
        async let r3 = cache.localURL(for: info)
        async let r4 = cache.localURL(for: info)
        let urls = try await [r0, r1, r2, r3, r4]

        XCTAssertEqual(Set(urls.map(\.path)).count, 1)
        let count = await downloader.callCount
        XCTAssertEqual(count, 1)
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
            let info = makeInfo(url: url, hash: hash)
            await dynamic.setNext(payload)
            _ = try await cache.localURL(for: info)
            try await Task.sleep(nanoseconds: 10_000_000) // 10 ms
        }

        await cache.evictIfOverLimit()

        let files = try FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)
        XCTAssertLessThanOrEqual(files.count, 2)
    }
}

private actor StubDownloader: AudioDownloader {
    let payload: Data
    private(set) var callCount = 0
    init(payload: Data) { self.payload = payload }
    func download(from url: URL) async throws -> Data {
        callCount += 1
        return payload
    }
}

private actor DynamicPayloadDownloader: AudioDownloader {
    private var next: Data = Data()
    func setNext(_ data: Data) { next = data }
    func download(from url: URL) async throws -> Data { next }
}
