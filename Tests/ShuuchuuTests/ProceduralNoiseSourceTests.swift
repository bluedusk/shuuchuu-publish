import XCTest
import AVFoundation
@testable import Shuuchuu

final class ProceduralNoiseSourceTests: XCTestCase {
    func testIsReadyImmediately() async throws {
        let s = ProceduralNoiseSource(variant: .white, id: "white", displayName: "White")
        XCTAssertTrue(s.isReady)
        try await s.prepare()
        XCTAssertTrue(s.isReady)
    }

    func testNodeIsSourceNode() {
        let s = ProceduralNoiseSource(variant: .pink, id: "pink", displayName: "Pink")
        XCTAssertTrue(s.node is AVAudioSourceNode)
    }

    func testIDAndDisplayName() {
        let s = ProceduralNoiseSource(variant: .brown, id: "brown", displayName: "Brown")
        XCTAssertEqual(s.id, "brown")
        XCTAssertEqual(s.displayName, "Brown")
    }
}
