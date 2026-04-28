import XCTest
@testable import Shuuchuu

final class PreferencesTests: XCTestCase {
    private var defaults: UserDefaults!
    private var prefs: Preferences!

    override func setUp() {
        super.setUp()
        let suite = "test.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        prefs = Preferences(defaults: defaults)
    }

    func testDefaultValues() {
        XCTAssertNil(prefs.lastTrackId)
        XCTAssertEqual(prefs.volume, 0.7, accuracy: 0.001)
        XCTAssertNil(prefs.lastCategoryId)
        XCTAssertFalse(prefs.resumeOnWake)
        XCTAssertFalse(prefs.resumeOnLaunch)
    }

    func testPersistEachField() {
        prefs.lastTrackId = "rain"
        prefs.volume = 0.42
        prefs.lastCategoryId = "soundscapes"
        prefs.resumeOnWake = true
        prefs.resumeOnLaunch = true

        let reloaded = Preferences(defaults: defaults)
        XCTAssertEqual(reloaded.lastTrackId, "rain")
        XCTAssertEqual(reloaded.volume, 0.42, accuracy: 0.001)
        XCTAssertEqual(reloaded.lastCategoryId, "soundscapes")
        XCTAssertTrue(reloaded.resumeOnWake)
        XCTAssertTrue(reloaded.resumeOnLaunch)
    }

    func testVolumeClampedToValidRange() {
        prefs.volume = 2.0
        XCTAssertEqual(prefs.volume, 1.0, accuracy: 0.001)
        prefs.volume = -0.5
        XCTAssertEqual(prefs.volume, 0.0, accuracy: 0.001)
    }
}
