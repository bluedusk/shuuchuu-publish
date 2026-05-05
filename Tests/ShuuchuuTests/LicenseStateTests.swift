import XCTest
@testable import Shuuchuu

final class LicenseStateTests: XCTestCase {

    func testIsUnlockedTrueForTrialAndLicensed() {
        XCTAssertTrue(LicenseState.trial(startedAt: Date()).isUnlocked)
        XCTAssertTrue(LicenseState.licensed(key: "k", instanceId: "i", lastValidated: Date()).isUnlocked)
    }

    func testIsUnlockedFalseForOtherStates() {
        XCTAssertFalse(LicenseState.uninitialized.isUnlocked)
        XCTAssertFalse(LicenseState.trialExpired.isUnlocked)
        XCTAssertFalse(LicenseState.revoked(reason: .disabled).isUnlocked)
        XCTAssertFalse(LicenseState.revoked(reason: .expired).isUnlocked)
        XCTAssertFalse(LicenseState.revoked(reason: .refunded).isUnlocked)
    }
}
