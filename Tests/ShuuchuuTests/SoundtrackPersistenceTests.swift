import XCTest
@testable import Shuuchuu

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

extension SoundtrackPersistenceTests {

    private func ephemeralDefaults() -> UserDefaults {
        let suite = "test.soundtracks.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        return d
    }

    @MainActor
    func testLibraryRoundTrip() {
        let d = ephemeralDefaults()
        let lib = SoundtracksLibrary(defaults: d)
        let parsed: SoundtrackURL
        switch SoundtrackURL.parse("https://youtu.be/abc123") {
        case .success(let p): parsed = p
        case .failure: XCTFail("parse failed"); return
        }
        let added = lib.add(parsed: parsed)

        XCTAssertEqual(lib.entries.count, 1)
        XCTAssertEqual(added.kind, .youtube)
        XCTAssertEqual(added.url, "https://www.youtube.com/embed/abc123?enablejsapi=1")
        XCTAssertEqual(added.volume, 0.5, accuracy: 0.001)
        XCTAssertNil(added.title)

        let reloaded = SoundtracksLibrary(defaults: d)
        XCTAssertEqual(reloaded.entries.count, 1)
        XCTAssertEqual(reloaded.entries.first?.id, added.id)
    }

    @MainActor
    func testLibraryRemove() {
        let d = ephemeralDefaults()
        let lib = SoundtracksLibrary(defaults: d)
        let a = parseAndAdd("https://youtu.be/abc", into: lib)
        _ = parseAndAdd("https://youtu.be/def", into: lib)
        XCTAssertEqual(lib.entries.count, 2)

        lib.remove(id: a.id)
        XCTAssertEqual(lib.entries.count, 1)
        XCTAssertEqual(lib.entries.first?.url.contains("def"), true)

        let reloaded = SoundtracksLibrary(defaults: d)
        XCTAssertEqual(reloaded.entries.count, 1)
    }

    @MainActor
    func testLibrarySetVolume() {
        let d = ephemeralDefaults()
        let lib = SoundtracksLibrary(defaults: d)
        let a = parseAndAdd("https://youtu.be/abc", into: lib)
        lib.setVolume(id: a.id, volume: 0.25)

        XCTAssertEqual(lib.entries.first?.volume ?? 0, 0.25, accuracy: 0.001)
        let reloaded = SoundtracksLibrary(defaults: d)
        XCTAssertEqual(reloaded.entries.first?.volume ?? 0, 0.25, accuracy: 0.001)
    }

    @MainActor
    func testLibrarySetTitle() {
        let d = ephemeralDefaults()
        let lib = SoundtracksLibrary(defaults: d)
        let a = parseAndAdd("https://youtu.be/abc", into: lib)
        lib.setTitle(id: a.id, title: "lofi beats")

        XCTAssertEqual(lib.entries.first?.title, "lofi beats")
    }

    @MainActor
    private func parseAndAdd(_ raw: String, into lib: SoundtracksLibrary) -> WebSoundtrack {
        switch SoundtrackURL.parse(raw) {
        case .success(let p): return lib.add(parsed: p)
        case .failure(let e): fatalError("parse failed: \(e)")
        }
    }
}
