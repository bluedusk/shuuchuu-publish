import XCTest
import Sparkle
@testable import Shuuchuu

@MainActor
final class UpdateCheckerTests: XCTestCase {

    // Use a private suite so we don't pollute the user's defaults during tests.
    private var defaults: UserDefaults!
    private let suiteName = "shuuchuu.UpdateCheckerTests"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func testAllowedChannelsEmptyByDefault() {
        let checker = UpdateChecker(defaults: defaults)
        let channels = checker.allowedChannels(for: checker.updaterForTesting)
        XCTAssertEqual(channels, [])
    }

    func testAllowedChannelsBetaWhenFlagOn() {
        defaults.set(true, forKey: "app.betaUpdates")
        let checker = UpdateChecker(defaults: defaults)
        let channels = checker.allowedChannels(for: checker.updaterForTesting)
        XCTAssertEqual(channels, ["beta"])
    }

    func testDidFindValidUpdateSetsHasUpdateAndVersion() async {
        let checker = UpdateChecker(defaults: defaults)
        let item = SUAppcastItem(dictionary: [
            "enclosure": [
                "url": "https://example.com/Shuuchuu.zip",
                "sparkle:version": "42",
                "sparkle:shortVersionString": "9.9.9",
            ],
        ])!

        checker.updater(checker.updaterForTesting, didFindValidUpdate: item)

        // Delegate hops back onto the main actor via Task — yield once so it lands.
        await Task.yield()

        XCTAssertTrue(checker.hasUpdate)
        XCTAssertEqual(checker.latestVersion, "9.9.9")
    }

    func testUpdaterDidNotFindUpdateClearsFlags() async {
        let checker = UpdateChecker(defaults: defaults)

        // Pre-set state that should be cleared.
        let item = SUAppcastItem(dictionary: [
            "enclosure": [
                "url": "https://example.com/Shuuchuu.zip",
                "sparkle:version": "42",
                "sparkle:shortVersionString": "9.9.9",
            ],
        ])!
        checker.updater(checker.updaterForTesting, didFindValidUpdate: item)
        await Task.yield()

        let dummyError = NSError(domain: "test", code: 0)
        checker.updaterDidNotFindUpdate(checker.updaterForTesting, error: dummyError)
        await Task.yield()

        XCTAssertFalse(checker.hasUpdate)
        XCTAssertNil(checker.latestVersion)
    }
}
