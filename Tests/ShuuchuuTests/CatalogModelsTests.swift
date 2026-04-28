import XCTest
@testable import Shuuchuu

final class CatalogModelsTests: XCTestCase {
    func testDecodeFixture() throws {
        let url = Bundle.module.url(forResource: "catalog-valid", withExtension: "json")!
        let data = try Data(contentsOf: url)
        let catalog = try JSONDecoder().decode(CatalogDocument.self, from: data)

        XCTAssertEqual(catalog.schemaVersion, 1)
        XCTAssertEqual(catalog.categories.count, 2)

        let noise = catalog.categories[0]
        XCTAssertEqual(noise.id, "noise")
        XCTAssertEqual(noise.tracks.count, 2)

        guard case .procedural(let variant) = noise.tracks[0].kind else {
            return XCTFail("expected procedural white")
        }
        XCTAssertEqual(variant, .white)

        let rain = catalog.categories[1].tracks[0]
        XCTAssertEqual(rain.id, "rain")
        guard case .streamed(let info) = rain.kind else {
            return XCTFail("expected streamed rain")
        }
        XCTAssertEqual(info.url.absoluteString, "https://cdn.example/rain.caf")
        XCTAssertEqual(info.sha256.count, 64)
        XCTAssertEqual(info.bytes, 3456789)
    }

    func testEncodeRoundTrips() throws {
        let doc = CatalogDocument(
            schemaVersion: 1,
            categories: [
                Category(id: "noise", name: "Noise", tracks: [
                    Track(id: "brown", name: "Brown Noise",
                          kind: .procedural(.brown),
                          artworkUrl: nil),
                ])
            ]
        )
        let data = try JSONEncoder().encode(doc)
        let decoded = try JSONDecoder().decode(CatalogDocument.self, from: data)
        XCTAssertEqual(decoded.categories[0].tracks[0].id, "brown")
    }
}
