import XCTest
@testable import XNoise

final class SavedMixesTests: XCTestCase {
    private func ephemeralDefaults() -> UserDefaults {
        let suite = "test.savedmixes.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        return d
    }

    @MainActor
    func testSaveAndReload() {
        let d = ephemeralDefaults()
        let store = SavedMixes(defaults: d)
        let result = store.save(name: "Rainy night",
                                tracks: [MixTrack(id: "rain", volume: 0.6),
                                         MixTrack(id: "thunder", volume: 0.3)])
        guard case .saved(let mix) = result else {
            XCTFail("expected .saved, got \(result)"); return
        }
        XCTAssertEqual(mix.name, "Rainy night")
        XCTAssertEqual(mix.tracks.count, 2)

        let reloaded = SavedMixes(defaults: d)
        XCTAssertEqual(reloaded.mixes.count, 1)
        XCTAssertEqual(reloaded.mixes.first?.name, "Rainy night")
        XCTAssertEqual(reloaded.mixes.first?.tracks.map(\.id), ["rain", "thunder"])
    }

    @MainActor
    func testDuplicateReturnsExisting() {
        let store = SavedMixes(defaults: ephemeralDefaults())
        _ = store.save(name: "Rainy night",
                       tracks: [MixTrack(id: "rain", volume: 0.5)])
        let result = store.save(name: "Rainy night",
                                tracks: [MixTrack(id: "thunder", volume: 0.5)])
        guard case .duplicate(let existing) = result else {
            XCTFail("expected .duplicate, got \(result)"); return
        }
        XCTAssertEqual(existing.tracks.first?.id, "rain")  // unchanged
        XCTAssertEqual(store.mixes.count, 1)               // not added
    }

    @MainActor
    func testOverwriteReplacesTracks() {
        let store = SavedMixes(defaults: ephemeralDefaults())
        guard case .saved(let original) = store.save(name: "Mix",
                                                     tracks: [MixTrack(id: "rain", volume: 0.5)]) else {
            XCTFail(); return
        }
        store.overwrite(id: original.id,
                        tracks: [MixTrack(id: "thunder", volume: 0.7)])
        XCTAssertEqual(store.mixes.count, 1)
        XCTAssertEqual(store.mixes.first?.id, original.id)  // same identity
        XCTAssertEqual(store.mixes.first?.name, "Mix")
        XCTAssertEqual(store.mixes.first?.tracks.first?.id, "thunder")
    }

    @MainActor
    func testOverwritePersists() {
        let d = ephemeralDefaults()
        let store = SavedMixes(defaults: d)
        guard case .saved(let original) = store.save(name: "Mix",
                                                     tracks: [MixTrack(id: "rain", volume: 0.5)]) else {
            XCTFail(); return
        }
        store.overwrite(id: original.id,
                        tracks: [MixTrack(id: "thunder", volume: 0.7)])

        let reloaded = SavedMixes(defaults: d)
        XCTAssertEqual(reloaded.mixes.count, 1)
        XCTAssertEqual(reloaded.mixes.first?.id, original.id)
        XCTAssertEqual(reloaded.mixes.first?.tracks.first?.id, "thunder")
        XCTAssertEqual(reloaded.mixes.first?.tracks.first?.volume, 0.7)
    }

    @MainActor
    func testSaveWithUniqueSuffixPicksSmallestFree() {
        let store = SavedMixes(defaults: ephemeralDefaults())
        _ = store.save(name: "Mix", tracks: [MixTrack(id: "a", volume: 0.5)])
        _ = store.save(name: "Mix (2)", tracks: [MixTrack(id: "b", volume: 0.5)])
        let m = store.saveWithUniqueSuffix(baseName: "Mix",
                                           tracks: [MixTrack(id: "c", volume: 0.5)])
        XCTAssertEqual(m.name, "Mix (3)")
    }

    @MainActor
    func testWhitespaceTrimmedOnSave() {
        let store = SavedMixes(defaults: ephemeralDefaults())
        guard case .saved(let m) = store.save(name: "  spaced  ",
                                              tracks: [MixTrack(id: "x", volume: 0.5)]) else {
            XCTFail(); return
        }
        XCTAssertEqual(m.name, "spaced")
    }

    @MainActor
    func testDeleteRemoves() {
        let store = SavedMixes(defaults: ephemeralDefaults())
        guard case .saved(let m) = store.save(name: "Mix",
                                              tracks: [MixTrack(id: "a", volume: 0.5)]) else {
            XCTFail(); return
        }
        store.delete(id: m.id)
        XCTAssertTrue(store.mixes.isEmpty)
    }
}
