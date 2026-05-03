import XCTest
@testable import Shuuchuu

@MainActor
final class SoundtracksLibraryTagsTests: XCTestCase {

    private func ephemeralLib() -> SoundtracksLibrary {
        let suite = "test.tags.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        return SoundtracksLibrary(defaults: d)
    }

    private func add(_ lib: SoundtracksLibrary, _ raw: String) -> WebSoundtrack {
        switch SoundtrackURL.parse(raw) {
        case .success(let p): return lib.add(parsed: p)
        case .failure(let e): fatalError("\(e)")
        }
    }

    func testSetTagsNormalizesAndPersists() {
        let lib = ephemeralLib()
        let a = add(lib, "https://youtu.be/abc")
        lib.setTags(id: a.id, tags: ["Study", "lo-fi", "study"])
        XCTAssertEqual(lib.entry(id: a.id)?.tags, ["study", "lo-fi"])
    }

    func testSetTagsClampsToThree() {
        let lib = ephemeralLib()
        let a = add(lib, "https://youtu.be/abc")
        lib.setTags(id: a.id, tags: ["a", "b", "c", "d"])
        XCTAssertEqual(lib.entry(id: a.id)?.tags, ["a", "b", "c"])
    }

    func testTagsInUseEmptyByDefault() {
        let lib = ephemeralLib()
        _ = add(lib, "https://youtu.be/abc")
        XCTAssertEqual(lib.tagsInUse, [])
    }

    func testTagsInUseSortsByUsageThenAlpha() {
        let lib = ephemeralLib()
        let a = add(lib, "https://youtu.be/aaa")
        let b = add(lib, "https://youtu.be/bbb")
        let c = add(lib, "https://youtu.be/ccc")
        lib.setTags(id: a.id, tags: ["lo-fi", "study"])
        lib.setTags(id: b.id, tags: ["lo-fi", "rain"])
        lib.setTags(id: c.id, tags: ["lo-fi"])
        // lo-fi: 3, study: 1, rain: 1 — ties alpha → rain, study
        XCTAssertEqual(lib.tagsInUse, ["lo-fi", "rain", "study"])
    }

    func testTagsInUseDropsOrphans() {
        let lib = ephemeralLib()
        let a = add(lib, "https://youtu.be/abc")
        lib.setTags(id: a.id, tags: ["rain"])
        XCTAssertEqual(lib.tagsInUse, ["rain"])
        lib.setTags(id: a.id, tags: [])
        XCTAssertEqual(lib.tagsInUse, [])
    }
}
