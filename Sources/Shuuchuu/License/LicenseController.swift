import Foundation
import Combine

/// Single source of truth for entitlement. Mirrors the controller pattern used by
/// `Catalog`, `MixingController`, etc. — exposes `@Published var state` and
/// derived `isUnlocked`.
@MainActor
final class LicenseController: ObservableObject {
    @Published private(set) var state: LicenseState = .uninitialized
    /// Cleared by the activation sheet on retry; set by `activate(...)` failures.
    @Published var lastActivationError: LSError?

    let api: LemonSqueezyAPI
    let storage: LicenseStorage
    let trialDuration: TimeInterval
    let activationLimit: Int
    private let now: @Sendable () -> Date
    private let instanceName: @Sendable () -> String

    private var trialTimer: AnyCancellable?
    private var didStartTrial = false

    init(
        api: LemonSqueezyAPI,
        storage: LicenseStorage,
        trialDuration: TimeInterval,
        activationLimit: Int,
        now: @escaping @Sendable () -> Date = { Date() },
        instanceName: @escaping @Sendable () -> String = {
            Host.current().localizedName ?? "Mac"
        }
    ) {
        self.api = api
        self.storage = storage
        self.trialDuration = trialDuration
        self.activationLimit = activationLimit
        self.now = now
        self.instanceName = instanceName
    }

    var isUnlocked: Bool { state.isUnlocked }

    /// Days remaining in trial (rounded up). Returns 0 if not in trial.
    var trialDaysRemaining: Int {
        guard case .trial(let startedAt) = state else { return 0 }
        let remaining = trialDuration - effectiveNow().timeIntervalSince(startedAt)
        if remaining <= 0 { return 0 }
        let oneDay: TimeInterval = 24 * 60 * 60
        return max(1, Int((remaining / oneDay).rounded(.up)))
    }

    // MARK: - Bootstrap

    /// Reads Keychain synchronously, sets initial state, starts the trial timer.
    /// Idempotent — safe to call multiple times. Subsequent calls re-read storage.
    func startTrialIfNeeded() {
        didStartTrial = true
        let key = storage.licenseKey
        let instance = storage.instanceId
        let trialStart = storage.trialStartedAt

        // Update the wall-clock floor now so a clock-rollback is detected immediately.
        bumpWallclock()

        if let key, let instance {
            let lastValidated = storage.lastValidated ?? .distantPast
            state = .licensed(key: key, instanceId: instance, lastValidated: lastValidated)
            // Don't auto-revalidate from here — call sites do that as an explicit Task.
            return
        }

        if let trialStart {
            if effectiveNow().timeIntervalSince(trialStart) >= trialDuration {
                state = .trialExpired
            } else {
                state = .trial(startedAt: trialStart)
                scheduleTrialTimer()
            }
            return
        }

        // First ever launch: stamp the trial start.
        let stamp = effectiveNow()
        storage.trialStartedAt = stamp
        state = .trial(startedAt: stamp)
        scheduleTrialTimer()
    }

    // MARK: - Activate

    @discardableResult
    func activate(key rawKey: String) async -> Bool {
        let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isPlausibleKey(key) else {
            lastActivationError = .licenseNotFound
            return false
        }
        switch await api.activate(licenseKey: key, instanceName: instanceName()) {
        case .success(let activation):
            storage.licenseKey = key
            storage.instanceId = activation.instanceId
            let validated = effectiveNow()
            storage.lastValidated = validated
            state = .licensed(key: key, instanceId: activation.instanceId, lastValidated: validated)
            lastActivationError = nil
            trialTimer?.cancel()
            trialTimer = nil
            return true
        case .failure(let err):
            lastActivationError = err
            return false
        }
    }

    // MARK: - Revalidate

    /// Soft revalidation: only an explicit `valid:false` from LS revokes; network
    /// errors are logged and ignored.
    func revalidate() async {
        guard case .licensed(let key, let instance, _) = state else { return }
        switch await api.validate(licenseKey: key, instanceId: instance) {
        case .success(let v):
            if v.valid {
                let stamped = effectiveNow()
                storage.lastValidated = stamped
                state = .licensed(key: key, instanceId: instance, lastValidated: stamped)
                return
            }
            switch v.status {
            case .disabled:
                state = .revoked(reason: .disabled)
                storage.clearLicenseFields()
            case .expired:
                state = .revoked(reason: .expired)
                storage.clearLicenseFields()
            case .inactive, .unknown, .active:
                // Ambiguous — server says invalid but no clear reason. Keep license
                // locally; user will see the next clear signal on the next launch.
                break
            }
        case .failure:
            // Soft fail: ignore.
            break
        }
    }

    // MARK: - Deactivate (sign out of this Mac)

    func deactivateThisDevice() async {
        guard case .licensed(let key, let instance, _) = state else { return }
        // Best-effort server call. We honor the user's local sign-out either way.
        _ = await api.deactivate(licenseKey: key, instanceId: instance)
        storage.clearLicenseFields()
        state = .trialExpired
    }

    // MARK: - Helpers

    private func isPlausibleKey(_ s: String) -> Bool {
        guard s.count >= 8, s.count <= 200 else { return false }
        let allowed = CharacterSet(charactersIn:
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
        return s.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    /// Clamp `now()` to the largest wall-clock we've ever seen, so setting the
    /// system clock backwards can't extend the trial.
    private func effectiveNow() -> Date {
        let n = now()
        if let floor = storage.lastSeenWallclock, floor > n { return floor }
        return n
    }

    /// Advance the wall-clock floor. The storage setter persists on first set
    /// and after a fixed threshold (see `LicenseStorage.lastSeenWallclock`);
    /// callers don't need to flush separately on the hot trial-tick path.
    private func bumpWallclock() {
        let n = now()
        if let floor = storage.lastSeenWallclock, floor > n { return }
        storage.lastSeenWallclock = n
    }

    /// Persist the in-memory wall-clock floor. Call from `AppModel.handleSleep`
    /// (and any other "we might exit soon" boundary).
    func flushPersist() {
        storage.persistWallclock()
    }

    /// Re-evaluates trial expiry once a minute. Cancelled when state leaves `.trial`.
    private func scheduleTrialTimer() {
        trialTimer?.cancel()
        trialTimer = Timer.publish(every: 60, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                guard case .trial(let startedAt) = self.state else {
                    self.trialTimer?.cancel()
                    self.trialTimer = nil
                    return
                }
                self.bumpWallclock()
                if self.effectiveNow().timeIntervalSince(startedAt) >= self.trialDuration {
                    self.state = .trialExpired
                    self.trialTimer?.cancel()
                    self.trialTimer = nil
                }
            }
    }
}
