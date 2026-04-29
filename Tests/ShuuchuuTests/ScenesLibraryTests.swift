import XCTest
@testable import Shuuchuu

@MainActor
final class ScenesLibraryTests: XCTestCase {
    func testDecodesInjectedData() {
        let url = Bundle.module.url(forResource: "scenes-fixture",
                                    withExtension: "json")!
        let data = try! Data(contentsOf: url)
        let lib = ScenesLibrary(jsonData: data)
        XCTAssertEqual(lib.scenes.count, 2)
        XCTAssertEqual(lib.scenes.map(\.id), ["plasma", "aurora"])
    }

    func testEntryByIdHit() {
        let url = Bundle.module.url(forResource: "scenes-fixture",
                                    withExtension: "json")!
        let lib = ScenesLibrary(jsonData: try! Data(contentsOf: url))
        XCTAssertEqual(lib.entry(id: "aurora")?.title, "Aurora")
    }

    func testEntryByIdMiss() {
        let url = Bundle.module.url(forResource: "scenes-fixture",
                                    withExtension: "json")!
        let lib = ScenesLibrary(jsonData: try! Data(contentsOf: url))
        XCTAssertNil(lib.entry(id: "nope"))
    }

    func testEmptyOnInvalidJSON() {
        let lib = ScenesLibrary(jsonData: Data("not json".utf8))
        XCTAssertTrue(lib.scenes.isEmpty)
    }
}
