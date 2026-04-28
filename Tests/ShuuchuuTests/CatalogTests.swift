import XCTest
@testable import Shuuchuu

final class CatalogTests: XCTestCase {
    private var tempDir: URL!

    override func setUp() async throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("shuuchuu-catalog-\(UUID())")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func fixtureData() throws -> Data {
        let url = Bundle.module.url(forResource: "catalog-valid", withExtension: "json")!
        return try Data(contentsOf: url)
    }

    @MainActor
    func testFetchSuccess() async throws {
        let data = try fixtureData()
        let catalog = Catalog(
            fetcher: StubFetcher(result: .success(data)),
            cacheFile: tempDir.appendingPathComponent("catalog.json")
        )
        await catalog.refresh()
        guard case .ready(let categories) = catalog.state else {
            return XCTFail("expected ready, got \(catalog.state)")
        }
        XCTAssertEqual(categories.count, 2)
    }

    @MainActor
    func testOfflineWithStaleCache() async throws {
        let cacheFile = tempDir.appendingPathComponent("catalog.json")
        try fixtureData().write(to: cacheFile)

        let catalog = Catalog(
            fetcher: StubFetcher(result: .failure(URLError(.notConnectedToInternet))),
            cacheFile: cacheFile
        )
        await catalog.refresh()
        guard case .ready(let categories) = catalog.state else {
            return XCTFail("expected ready from cache, got \(catalog.state)")
        }
        XCTAssertEqual(categories.count, 2)
    }

    @MainActor
    func testOfflineNoCache() async throws {
        let catalog = Catalog(
            fetcher: StubFetcher(result: .failure(URLError(.notConnectedToInternet))),
            cacheFile: tempDir.appendingPathComponent("catalog.json")
        )
        await catalog.refresh()
        guard case .offline(let stale) = catalog.state else {
            return XCTFail("expected offline, got \(catalog.state)")
        }
        XCTAssertNil(stale)
    }

    @MainActor
    func testCorruptResponseFallsBackToCache() async throws {
        let cacheFile = tempDir.appendingPathComponent("catalog.json")
        try fixtureData().write(to: cacheFile)

        let catalog = Catalog(
            fetcher: StubFetcher(result: .success(Data("not json".utf8))),
            cacheFile: cacheFile
        )
        await catalog.refresh()
        guard case .ready(let categories) = catalog.state else {
            return XCTFail("expected ready, got \(catalog.state)")
        }
        XCTAssertEqual(categories.count, 2)
    }
}

private struct StubFetcher: CatalogFetcher {
    let result: Result<Data, Error>
    func fetch() async throws -> Data {
        try result.get()
    }
}
