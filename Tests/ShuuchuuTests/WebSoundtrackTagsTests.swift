import XCTest
@testable import Shuuchuu

final class WebSoundtrackTagsTests: XCTestCase {

    func testNormalizeLowercases() {
        XCTAssertEqual(TagNormalize.normalize("Lo-Fi"), "lo-fi")
    }

    func testNormalizeTrimsWhitespace() {
        XCTAssertEqual(TagNormalize.normalize("  study  "), "study")
    }

    func testNormalizeReturnsNilForEmpty() {
        XCTAssertNil(TagNormalize.normalize(""))
        XCTAssertNil(TagNormalize.normalize("   "))
    }

    func testNormalizeListDeduplicatesPreservingOrder() {
        XCTAssertEqual(
            TagNormalize.normalize(list: ["Study", "lo-fi", "STUDY", "rain"]),
            ["study", "lo-fi", "rain"]
        )
    }

    func testNormalizeListClampsToThree() {
        XCTAssertEqual(
            TagNormalize.normalize(list: ["a", "b", "c", "d", "e"]),
            ["a", "b", "c"]
        )
    }

    func testNormalizeListDropsEmpties() {
        XCTAssertEqual(
            TagNormalize.normalize(list: ["", "study", "  "]),
            ["study"]
        )
    }
}
