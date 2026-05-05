import Foundation
@testable import Shuuchuu

/// Stub LemonSqueezy API used by every test that needs a `LicenseController`.
/// Each method returns a configurable canned result; defaults to a successful path.
actor StubLemonSqueezyAPI: LemonSqueezyAPI {
    private var _activate: Result<LSActivation, LSError>
    private var _validate: Result<LSValidation, LSError>
    private var _deactivate: Result<Void, LSError>
    private(set) var activateCalls: Int = 0
    private(set) var validateCalls: Int = 0
    private(set) var deactivateCalls: Int = 0

    init(
        activate: Result<LSActivation, LSError> = .success(LSActivation(instanceId: "stub-instance")),
        validate: Result<LSValidation, LSError> = .success(LSValidation(valid: true, status: .active)),
        deactivate: Result<Void, LSError> = .success(())
    ) {
        self._activate = activate
        self._validate = validate
        self._deactivate = deactivate
    }

    func setActivate(_ r: Result<LSActivation, LSError>) { _activate = r }
    func setValidate(_ r: Result<LSValidation, LSError>) { _validate = r }

    func activate(licenseKey: String, instanceName: String) async -> Result<LSActivation, LSError> {
        activateCalls += 1
        return _activate
    }
    func validate(licenseKey: String, instanceId: String) async -> Result<LSValidation, LSError> {
        validateCalls += 1
        return _validate
    }
    func deactivate(licenseKey: String, instanceId: String) async -> Result<Void, LSError> {
        deactivateCalls += 1
        return _deactivate
    }
}

/// Build a `LicenseController` pre-seeded into a desired state, for tests that
/// don't care about license behaviour but still need to construct an `AppModel`.
@MainActor
func makeTestLicense(
    unlocked: Bool = true,
    api: LemonSqueezyAPI? = nil,
    backend: LicenseStorageBackend? = nil,
    trialDuration: TimeInterval = 5 * 24 * 60 * 60,
    now: @escaping @Sendable () -> Date = { Date() }
) -> LicenseController {
    let resolvedBackend = backend ?? InMemoryLicenseBackend()
    let storage = LicenseStorage(backend: resolvedBackend)
    if unlocked {
        // Seed Keychain so startTrialIfNeeded boots into .licensed.
        storage.licenseKey = "TEST-LICENSE-KEY-AAAA"
        storage.instanceId = "TEST-INSTANCE"
        storage.lastValidated = now()
    }
    let controller = LicenseController(
        api: api ?? StubLemonSqueezyAPI(),
        storage: storage,
        trialDuration: trialDuration,
        activationLimit: 3,
        now: now,
        instanceName: { "TestMac" }
    )
    controller.startTrialIfNeeded()
    return controller
}
