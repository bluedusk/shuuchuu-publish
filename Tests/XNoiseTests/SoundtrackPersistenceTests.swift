import XCTest
@testable import XNoise

final class SoundtrackPersistenceTests: XCTestCase {

    func testWebSoundtrackRoundTrip() throws {
        let original = WebSoundtrack(
            id: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            kind: .youtube,
            url: "https://www.youtube.com/embed/abc?enablejsapi=1",
            title: "lofi beats",
            volume: 0.7,
            addedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(WebSoundtrack.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testWebSoundtrackRoundTripWithNilTitle() throws {
        let original = WebSoundtrack(
            id: UUID(),
            kind: .spotify,
            url: "https://open.spotify.com/embed/playlist/abc",
            title: nil,
            volume: 0.5,
            addedAt: Date()
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(WebSoundtrack.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testAudioModeIdleRoundTrip() throws {
        let original: AudioMode = .idle
        let data = try JSONEncoder().encode(original)
        XCTAssertEqual(try JSONDecoder().decode(AudioMode.self, from: data), original)
    }

    func testAudioModeMixRoundTrip() throws {
        let original: AudioMode = .mix
        let data = try JSONEncoder().encode(original)
        XCTAssertEqual(try JSONDecoder().decode(AudioMode.self, from: data), original)
    }

    func testAudioModeSoundtrackRoundTrip() throws {
        let id = UUID()
        let original: AudioMode = .soundtrack(id)
        let data = try JSONEncoder().encode(original)
        XCTAssertEqual(try JSONDecoder().decode(AudioMode.self, from: data), original)
    }
}
