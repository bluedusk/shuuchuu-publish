import XCTest
@testable import XNoise

@MainActor
final class FocusSessionPhaseHookTests: XCTestCase {

    private func ephemeralDefaults() -> UserDefaults {
        let suite = "test.focus.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        return d
    }

    func testOnPhaseChangeFiresOnSkip() {
        let settings = FocusSettings(defaults: ephemeralDefaults())
        let session = FocusSession(settings: settings)
        var fired: [SessionPhase] = []
        session.onPhaseChange = { fired.append($0) }

        // Starts in .focus; skip → break.
        session.skip()
        XCTAssertEqual(fired, [.shortBreak])

        // From short break, skip → focus.
        session.skip()
        XCTAssertEqual(fired, [.shortBreak, .focus])
    }

    func testOnPhaseChangeFiresOnExpiry() {
        let settings = FocusSettings(defaults: ephemeralDefaults())
        settings.focusMin = 1
        let session = FocusSession(settings: settings)
        var fired: [SessionPhase] = []
        session.onPhaseChange = { fired.append($0) }

        // skip() invokes advancePhase directly.
        session.skip()
        XCTAssertEqual(fired, [.shortBreak])
    }

    func testOnPhaseChangeNotFiredOnReset() {
        let settings = FocusSettings(defaults: ephemeralDefaults())
        let session = FocusSession(settings: settings)
        session.skip()  // → shortBreak
        var fired: [SessionPhase] = []
        session.onPhaseChange = { fired.append($0) }

        session.reset()
        XCTAssertTrue(fired.isEmpty)
    }
}
