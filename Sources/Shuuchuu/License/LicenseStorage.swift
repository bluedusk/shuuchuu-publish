import Foundation
import Security

/// Pluggable backend for license-related secrets. Production = Keychain. Tests = in-memory.
protocol LicenseStorageBackend: Sendable {
    func read(account: String) -> String?
    func write(_ value: String, account: String) -> Bool
    func delete(account: String)
}

/// One-stop license persistence. Stores license key, activation instance id,
/// trial-start date, last-validated date, and a clock-rollback floor.
///
/// **All fields are cached in memory.** Backends like `SecurityCLILicenseBackend`
/// spawn a subprocess on every read/write; calling them from the main thread
/// stalls the UI. The cache is loaded once at init, then reads are a dict
/// lookup and writes are enqueued to a background serial queue (fire-and-forget).
final class LicenseStorage: @unchecked Sendable {
    let backend: LicenseStorageBackend

    private enum Key {
        static let licenseKey = "licenseKey"
        static let instanceId = "instanceId"
        static let trialStartedAt = "trialStartedAt"
        static let lastValidated = "lastValidated"
        static let lastSeenWallclock = "lastSeenWallclock"
    }

    private let lock = NSLock()
    private var _licenseKey: String?
    private var _instanceId: String?
    private var _trialStartedAt: Date?
    private var _lastValidated: Date?
    private var _lastSeenWallclock: Date?
    /// Last value we actually wrote to the backend. Used by the wallclock setter
    /// to bound persist frequency without losing the rollback floor across a
    /// force-quit (which never reaches `flushPersist`).
    private var _lastPersistedWallclock: Date?

    /// Persist the wallclock floor at most once per this interval. Trial timer
    /// ticks at 60s; this gives us 10 ticks of memory-only churn between writes,
    /// while still guaranteeing a force-quit-before-sleep loses at most 10 min
    /// of rollback protection.
    private static let wallclockPersistThreshold: TimeInterval = 600

    /// Serial queue: keychain writes happen here, never on main. Order is preserved.
    private let writeQueue = DispatchQueue(label: "shuuchuu.license.persist", qos: .utility)

    init(backend: LicenseStorageBackend) {
        self.backend = backend
        // Pull every field once. Subsequent reads hit the cache only.
        self._licenseKey = backend.read(account: Key.licenseKey)
        self._instanceId = backend.read(account: Key.instanceId)
        self._trialStartedAt = Self.parseDate(backend.read(account: Key.trialStartedAt))
        self._lastValidated = Self.parseDate(backend.read(account: Key.lastValidated))
        self._lastSeenWallclock = Self.parseDate(backend.read(account: Key.lastSeenWallclock))
        self._lastPersistedWallclock = self._lastSeenWallclock
    }

    var licenseKey: String? {
        get { lock.lock(); defer { lock.unlock() }; return _licenseKey }
        set {
            lock.lock(); _licenseKey = newValue; lock.unlock()
            enqueuePersist(newValue, account: Key.licenseKey)
        }
    }

    var instanceId: String? {
        get { lock.lock(); defer { lock.unlock() }; return _instanceId }
        set {
            lock.lock(); _instanceId = newValue; lock.unlock()
            enqueuePersist(newValue, account: Key.instanceId)
        }
    }

    var trialStartedAt: Date? {
        get { lock.lock(); defer { lock.unlock() }; return _trialStartedAt }
        set {
            lock.lock(); _trialStartedAt = newValue; lock.unlock()
            enqueuePersistDate(newValue, account: Key.trialStartedAt)
        }
    }

    var lastValidated: Date? {
        get { lock.lock(); defer { lock.unlock() }; return _lastValidated }
        set {
            lock.lock(); _lastValidated = newValue; lock.unlock()
            enqueuePersistDate(newValue, account: Key.lastValidated)
        }
    }

    /// Memory always updates. Persists to the backend on first set after launch
    /// and after each `wallclockPersistThreshold` advance — so a force-quit
    /// before any sleep still leaves a recent floor on disk to defeat clock
    /// rollback. Frequency is bounded so 60s trial-timer ticks don't hammer
    /// the keychain subprocess.
    var lastSeenWallclock: Date? {
        get { lock.lock(); defer { lock.unlock() }; return _lastSeenWallclock }
        set {
            lock.lock()
            _lastSeenWallclock = newValue
            let shouldPersist: Bool
            if let newValue {
                if let last = _lastPersistedWallclock {
                    shouldPersist = newValue.timeIntervalSince(last) >= Self.wallclockPersistThreshold
                } else {
                    shouldPersist = true
                }
                if shouldPersist { _lastPersistedWallclock = newValue }
            } else {
                shouldPersist = (_lastPersistedWallclock != nil)
                _lastPersistedWallclock = nil
            }
            lock.unlock()
            if shouldPersist {
                enqueuePersistDate(newValue, account: Key.lastSeenWallclock)
            }
        }
    }

    /// Force a persist regardless of threshold. Called at sleep boundaries —
    /// the threshold-based path above already covers most cases, but sleep is
    /// our last reliable opportunity before a possible cold relaunch.
    func persistWallclock() {
        let snapshot: Date?
        lock.lock()
        snapshot = _lastSeenWallclock
        _lastPersistedWallclock = snapshot
        lock.unlock()
        enqueuePersistDate(snapshot, account: Key.lastSeenWallclock)
    }

    /// Block until all pending writes have landed in the backend. Tests use
    /// this between successive controller instances; production rarely needs it.
    func flushPendingWrites() {
        writeQueue.sync {}
    }

    /// Wipe license fields but preserve trial timing — used on sign-out so the
    /// user can't re-enter trial after they've already used it.
    func clearLicenseFields() {
        lock.lock()
        _licenseKey = nil
        _instanceId = nil
        _lastValidated = nil
        lock.unlock()
        writeQueue.async { [backend] in
            backend.delete(account: Key.licenseKey)
            backend.delete(account: Key.instanceId)
            backend.delete(account: Key.lastValidated)
        }
    }

    private static func parseDate(_ raw: String?) -> Date? {
        guard let raw, let t = TimeInterval(raw) else { return nil }
        return Date(timeIntervalSince1970: t)
    }

    private func enqueuePersist(_ value: String?, account: String) {
        writeQueue.async { [backend] in
            if let value { _ = backend.write(value, account: account) }
            else { backend.delete(account: account) }
        }
    }

    private func enqueuePersistDate(_ value: Date?, account: String) {
        writeQueue.async { [backend] in
            if let value {
                _ = backend.write(String(value.timeIntervalSince1970), account: account)
            } else {
                backend.delete(account: account)
            }
        }
    }
}

// MARK: - Keychain backend

/// Stores items as `kSecClassGenericPassword` under a single service.
final class KeychainLicenseBackend: LicenseStorageBackend, @unchecked Sendable {
    let service: String

    init(service: String) {
        self.service = service
    }

    func read(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let str = String(data: data, encoding: .utf8) else { return nil }
        return str
    }

    func write(_ value: String, account: String) -> Bool {
        let data = Data(value.utf8)
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let updateStatus = SecItemUpdate(baseQuery as CFDictionary,
                                         [kSecValueData as String: data] as CFDictionary)
        if updateStatus == errSecSuccess { return true }
        if updateStatus == errSecItemNotFound {
            var addQuery = baseQuery
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            return SecItemAdd(addQuery as CFDictionary, nil) == errSecSuccess
        }
        return false
    }

    func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - File backend (production for unsigned dev builds)

/// JSON-file backed storage. Used because the unsigned `swift run` binary's
/// code identity changes on every rebuild, which causes Keychain to prompt
/// "Always Allow" on every launch (the ACL is bound to the previous build's
/// signature). Once the app is properly code-signed for distribution, switch
/// back to `KeychainLicenseBackend`.
final class FileLicenseBackend: LicenseStorageBackend, @unchecked Sendable {
    private let fileURL: URL
    private let lock = NSLock()
    private var cache: [String: String]
    private var loaded = false

    init(fileURL: URL) {
        self.fileURL = fileURL
        self.cache = [:]
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
    }

    func read(account: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        loadIfNeeded()
        return cache[account]
    }

    func write(_ value: String, account: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        loadIfNeeded()
        cache[account] = value
        return persist()
    }

    func delete(account: String) {
        lock.lock(); defer { lock.unlock() }
        loadIfNeeded()
        cache.removeValue(forKey: account)
        _ = persist()
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        guard let data = try? Data(contentsOf: fileURL),
              let dict = try? JSONDecoder().decode([String: String].self, from: data) else { return }
        cache = dict
    }

    private func persist() -> Bool {
        guard let data = try? JSONEncoder().encode(cache) else { return false }
        do {
            try data.write(to: fileURL, options: [.atomic])
            return true
        } catch { return false }
    }
}

// MARK: - Keychain via /usr/bin/security CLI

/// Reads/writes the login keychain by spawning `/usr/bin/security`. We use this
/// instead of `SecItemCopyMatching` because the unsigned `swift run` binary's
/// code identity changes on every rebuild, which makes Keychain prompt
/// "Always Allow" on every launch even after granting it. `/usr/bin/security`
/// has Apple's stable signature, so the ACL it gets sticks across rebuilds.
/// Same trick x-island uses (see `Sources/xIslandCore/LicenseManager.swift`).
final class SecurityCLILicenseBackend: LicenseStorageBackend, @unchecked Sendable {
    let service: String

    init(service: String) {
        self.service = service
    }

    func read(account: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", service, "-a", account, "-w"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do { try process.run() } catch { return nil }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .newlines)
    }

    func write(_ value: String, account: String) -> Bool {
        // `add-generic-password` errors if the item exists, so delete first.
        delete(account: account)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = [
            "add-generic-password",
            "-s", service,
            "-a", account,
            "-w", value,
            "-U"  // update if exists
        ]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do { try process.run() } catch { return false }
        process.waitUntilExit()
        return process.terminationStatus == 0
    }

    func delete(account: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["delete-generic-password", "-s", service, "-a", account]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try? process.run()
        process.waitUntilExit()
    }
}

// MARK: - In-memory backend (tests)

/// Locked dictionary — fine for tests, single-process, no contention.
final class InMemoryLicenseBackend: LicenseStorageBackend, @unchecked Sendable {
    private var store: [String: String] = [:]
    private let lock = NSLock()

    func read(account: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        return store[account]
    }

    func write(_ value: String, account: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        store[account] = value
        return true
    }

    func delete(account: String) {
        lock.lock(); defer { lock.unlock() }
        store.removeValue(forKey: account)
    }
}
