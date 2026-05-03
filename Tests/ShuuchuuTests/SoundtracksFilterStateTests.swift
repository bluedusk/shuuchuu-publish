import XCTest
@testable import Shuuchuu

@MainActor
final class SoundtracksFilterStateTests: XCTestCase {

    func testEmptyByDefault() {
        let f = SoundtracksFilterState()
        XCTAssertTrue(f.selected.isEmpty)
        XCTAssertFalse(f.isActive)
    }

    func testToggleAddsAndRemoves() {
        let f = SoundtracksFilterState()
        f.toggle("lo-fi")
        XCTAssertEqual(f.selected, ["lo-fi"])
        f.toggle("study")
        XCTAssertEqual(f.selected, ["lo-fi", "study"])
        f.toggle("lo-fi")
        XCTAssertEqual(f.selected, ["study"])
    }

    func testIsActiveTrueWhenAnyTagSelected() {
        let f = SoundtracksFilterState()
        f.toggle("lo-fi")
        XCTAssertTrue(f.isActive)
    }

    func testMatchesIntersection() {
        let f = SoundtracksFilterState()
        f.toggle("lo-fi")
        f.toggle("study")
        XCTAssertTrue(f.matches(tags: ["lo-fi", "study", "rain"]))
        XCTAssertFalse(f.matches(tags: ["lo-fi"]))
        XCTAssertFalse(f.matches(tags: []))
    }

    func testMatchesEverythingWhenInactive() {
        let f = SoundtracksFilterState()
        XCTAssertTrue(f.matches(tags: []))
        XCTAssertTrue(f.matches(tags: ["anything"]))
    }

    func testReconcileDropsOrphanedSelections() {
        let f = SoundtracksFilterState()
        f.toggle("lo-fi")
        f.toggle("study")
        f.reconcile(against: ["lo-fi", "rain"])
        XCTAssertEqual(f.selected, ["lo-fi"])
    }

    func testClear() {
        let f = SoundtracksFilterState()
        f.toggle("lo-fi")
        f.toggle("study")
        f.clear()
        XCTAssertTrue(f.selected.isEmpty)
    }
}
