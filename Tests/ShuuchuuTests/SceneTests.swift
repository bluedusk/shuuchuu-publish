import XCTest
@testable import Shuuchuu

final class SceneTests: XCTestCase {
    func testDecodeShaderEntry() throws {
        let json = #"""
        [{"id":"plasma","title":"Plasma","thumbnail":"plasma.jpg","kind":"shader"}]
        """#
        let scenes = try JSONDecoder().decode([Scene].self, from: Data(json.utf8))
        XCTAssertEqual(scenes.count, 1)
        XCTAssertEqual(scenes[0].id, "plasma")
        XCTAssertEqual(scenes[0].title, "Plasma")
        XCTAssertEqual(scenes[0].thumbnail, "plasma.jpg")
        XCTAssertEqual(scenes[0].kind, .shader)
    }

    func testRoundTripEncoding() throws {
        let original = Scene(id: "aurora", title: "Aurora",
                             thumbnail: "aurora.jpg", kind: .shader)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Scene.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testRejectsUnknownKind() {
        let json = #"""
        [{"id":"x","title":"X","thumbnail":"x.jpg","kind":"video"}]
        """#
        XCTAssertThrowsError(try JSONDecoder().decode([Scene].self,
                                                      from: Data(json.utf8)))
    }
}
