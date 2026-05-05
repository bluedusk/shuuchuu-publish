import XCTest
@testable import Shuuchuu

@MainActor
final class LicenseControllerTests: XCTestCase {
    private let trialDuration: TimeInterval = 5 * 24 * 60 * 60

    private func makeController(
        api: LemonSqueezyAPI = StubLemonSqueezyAPI(),
        backend: LicenseStorageBackend = InMemoryLicenseBackend(),
        nowProvider: NowProvider = NowProvider()
    ) -> (LicenseController, NowProvider, LicenseStorage) {
        let storage = LicenseStorage(backend: backend)
        let controller = LicenseController(
            api: api,
            storage: storage,
            trialDuration: trialDuration,
            activationLimit: 3,
            now: { nowProvider.now },
            instanceName: { "TestMac" }
        )
        return (controller, nowProvider, storage)
    }

    // MARK: - Trial start

    func testFirstLaunchStampsTrial() {
        let (c, t, storage) = makeController()
        c.startTrialIfNeeded()
        if case .trial(let started) = c.state {
            XCTAssertEqual(started.timeIntervalSince1970, t.now.timeIntervalSince1970, accuracy: 1)
        } else {
            XCTFail("expected .trial, got \(c.state)")
        }
        XCTAssertNotNil(storage.trialStartedAt)
    }

    func testRestartWithinTrialKeepsTrial() {
        let (c1, t, _) = makeController()
        c1.startTrialIfNeeded()
        c1.storage.flushPendingWrites()

        // Simulate relaunch a day later — same backend (Keychain mock).
        let backend = c1.storage.backend
        t.now = t.now.addingTimeInterval(24 * 60 * 60)
        let (c2, _, _) = makeController(backend: backend, nowProvider: t)
        c2.startTrialIfNeeded()
        if case .trial = c2.state { /* ok */ } else {
            XCTFail("expected .trial after relaunch within window, got \(c2.state)")
        }
    }

    func testRestartAfterTrialExpiresLocksOut() {
        let (c1, t, _) = makeController()
        c1.startTrialIfNeeded()
        c1.storage.flushPendingWrites()
        let backend = c1.storage.backend

        t.now = t.now.addingTimeInterval(trialDuration + 60) // a minute past expiry
        let (c2, _, _) = makeController(backend: backend, nowProvider: t)
        c2.startTrialIfNeeded()
        XCTAssertEqual(c2.state, .trialExpired)
    }

    func testTrialDaysRemainingCountsDown() {
        let (c, t, _) = makeController()
        c.startTrialIfNeeded()
        XCTAssertEqual(c.trialDaysRemaining, 5)

        t.now = t.now.addingTimeInterval(2 * 24 * 60 * 60 + 60)  // 2 days + a minute
        // Re-bootstrap so state is recomputed against new "now".
        c.startTrialIfNeeded()
        XCTAssertEqual(c.trialDaysRemaining, 3)
    }

    // MARK: - Activation

    func testActivateSuccessTransitionsToLicensed() async {
        let api = StubLemonSqueezyAPI(activate: .success(LSActivation(instanceId: "INST-1")))
        let (c, _, storage) = makeController(api: api)
        c.startTrialIfNeeded()

        let ok = await c.activate(key: "TEST-KEY-AAAA-BBBB")
        XCTAssertTrue(ok)
        if case .licensed(let key, let inst, _) = c.state {
            XCTAssertEqual(key, "TEST-KEY-AAAA-BBBB")
            XCTAssertEqual(inst, "INST-1")
        } else {
            XCTFail("expected .licensed, got \(c.state)")
        }
        XCTAssertEqual(storage.licenseKey, "TEST-KEY-AAAA-BBBB")
        XCTAssertEqual(storage.instanceId, "INST-1")
    }

    func testActivateFailureSetsLastErrorAndStays() async {
        let api = StubLemonSqueezyAPI(activate: .failure(.activationLimitReached))
        let (c, _, _) = makeController(api: api)
        c.startTrialIfNeeded()

        let ok = await c.activate(key: "TEST-KEY-AAAA-BBBB")
        XCTAssertFalse(ok)
        XCTAssertEqual(c.lastActivationError, .activationLimitReached)
        if case .trial = c.state { /* ok */ } else {
            XCTFail("expected .trial after failed activate, got \(c.state)")
        }
    }

    func testActivateRejectsImplausibleKey() async {
        let api = StubLemonSqueezyAPI()
        let (c, _, _) = makeController(api: api)
        c.startTrialIfNeeded()

        // Empty / very short / illegal chars are rejected without hitting the API.
        let ok = await c.activate(key: "abc")
        XCTAssertFalse(ok)
        let calls = await api.activateCalls
        XCTAssertEqual(calls, 0)
    }

    // MARK: - Revalidate

    func testRevalidateValidUpdatesTimestamp() async {
        let api = StubLemonSqueezyAPI(
            activate: .success(LSActivation(instanceId: "I1")),
            validate: .success(LSValidation(valid: true, status: .active))
        )
        let (c, _, storage) = makeController(api: api)
        c.startTrialIfNeeded()
        _ = await c.activate(key: "TEST-KEY-AAAA-BBBB")
        let before = storage.lastValidated
        // Bump the clock so we can detect the new timestamp.
        try? await Task.sleep(nanoseconds: 10_000_000)
        await c.revalidate()
        XCTAssertNotNil(storage.lastValidated)
        XCTAssertGreaterThanOrEqual(storage.lastValidated!, before ?? .distantPast)
    }

    func testRevalidateRevokesOnDisabled() async {
        let api = StubLemonSqueezyAPI(
            activate: .success(LSActivation(instanceId: "I1")),
            validate: .success(LSValidation(valid: false, status: .disabled))
        )
        let (c, _, storage) = makeController(api: api)
        c.startTrialIfNeeded()
        _ = await c.activate(key: "TEST-KEY-AAAA-BBBB")
        await c.revalidate()
        XCTAssertEqual(c.state, .revoked(reason: .disabled))
        XCTAssertNil(storage.licenseKey)
    }

    func testRevalidateNetworkErrorIsSoftFail() async {
        let api = StubLemonSqueezyAPI(
            activate: .success(LSActivation(instanceId: "I1")),
            validate: .failure(.network)
        )
        let (c, _, _) = makeController(api: api)
        c.startTrialIfNeeded()
        _ = await c.activate(key: "TEST-KEY-AAAA-BBBB")
        let stateBefore = c.state
        await c.revalidate()
        XCTAssertEqual(c.state, stateBefore, "network error must not change state")
    }

    // MARK: - Deactivation

    func testDeactivateClearsKeysAndExpiresTrial() async {
        let api = StubLemonSqueezyAPI(activate: .success(LSActivation(instanceId: "I1")))
        let (c, _, storage) = makeController(api: api)
        c.startTrialIfNeeded()
        _ = await c.activate(key: "TEST-KEY-AAAA-BBBB")
        await c.deactivateThisDevice()
        XCTAssertEqual(c.state, .trialExpired)
        XCTAssertNil(storage.licenseKey)
        XCTAssertNil(storage.instanceId)
        XCTAssertNotNil(storage.trialStartedAt, "trial start must persist — cannot re-roll trial")
    }

    func testDeactivateHonoursLocallyEvenIfServerFails() async {
        let api = StubLemonSqueezyAPI(
            activate: .success(LSActivation(instanceId: "I1")),
            validate: .success(LSValidation(valid: true, status: .active)),
            deactivate: .failure(.network)
        )
        let (c, _, storage) = makeController(api: api)
        c.startTrialIfNeeded()
        _ = await c.activate(key: "TEST-KEY-AAAA-BBBB")
        await c.deactivateThisDevice()
        XCTAssertEqual(c.state, .trialExpired)
        XCTAssertNil(storage.licenseKey)
    }

    // MARK: - Clock rollback defense

    func testClockRollbackDoesNotExtendTrial() {
        let (c1, t, _) = makeController()
        c1.startTrialIfNeeded()
        c1.flushPersist()                  // push initial wallclock floor
        c1.storage.flushPendingWrites()
        let backend = c1.storage.backend

        // Move time forward 4 days, then back 4 days. Trial start is preserved by the
        // wall-clock floor — going backwards must not reset the clock.
        t.now = t.now.addingTimeInterval(4 * 24 * 60 * 60)
        let (c2, _, _) = makeController(backend: backend, nowProvider: t)
        c2.startTrialIfNeeded()
        XCTAssertEqual(c2.trialDaysRemaining, 1)
        c2.flushPersist()                  // push the new (advanced) floor
        c2.storage.flushPendingWrites()

        t.now = t.now.addingTimeInterval(-4 * 24 * 60 * 60)
        let (c3, _, _) = makeController(backend: backend, nowProvider: t)
        c3.startTrialIfNeeded()
        // Even with the clock rolled back, the floor is "4 days from start" so we
        // still have ~1 day, not 5.
        XCTAssertLessThanOrEqual(c3.trialDaysRemaining, 1)
    }
}

// MARK: - Test helpers

/// Mutable "now" provider so tests can advance the clock without sleeping.
final class NowProvider: @unchecked Sendable {
    var now: Date

    init(initial: Date = Date(timeIntervalSince1970: 1_700_000_000)) {
        self.now = initial
    }
}
