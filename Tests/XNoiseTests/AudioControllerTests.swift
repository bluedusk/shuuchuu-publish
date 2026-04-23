import XCTest
@testable import XNoise

@MainActor
final class AudioControllerTests: XCTestCase {
    func testInitialStateIsIdle() {
        let c = AudioController()
        XCTAssertEqual(c.state, .idle)
    }

    func testPlayProceduralTransitionsToPlaying() async {
        let c = AudioController()
        let src = ProceduralNoiseSource(variant: .white, id: "w", displayName: "W")
        await c.play(src)
        XCTAssertEqual(c.state, .playing("w"))
    }

    func testStopTransitionsToIdle() async {
        let c = AudioController()
        let src = ProceduralNoiseSource(variant: .white, id: "w", displayName: "W")
        await c.play(src)
        await c.stop()
        XCTAssertEqual(c.state, .idle)
    }

    func testVolumeUpdatesMixer() async {
        let c = AudioController()
        c.volume = 0.42
        XCTAssertEqual(c.volume, 0.42, accuracy: 0.001)
    }
}
