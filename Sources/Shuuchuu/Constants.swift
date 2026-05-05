import Foundation

enum Constants {
    // MARK: - Catalog
    static let catalogCacheFilename = "catalog.json"

    // MARK: - Audio cache
    static let audioCacheDirName = "shuuchuu"
    static let audioCacheLimitBytes: Int64 = 500 * 1024 * 1024

    // MARK: - Fades (milliseconds)
    static let fadeInMs: Double = 150
    static let fadeOutMs: Double = 300
    static let crossfadeMs: Double = 300

    // MARK: - UserDefaults keys
    enum PrefKey {
        static let lastTrackId = "shuuchuu.lastTrackId"
        static let volume = "shuuchuu.volume"
        static let lastCategoryId = "shuuchuu.lastCategoryId"
        static let resumeOnWake = "shuuchuu.resumeOnWake"
        static let resumeOnLaunch = "shuuchuu.resumeOnLaunch"
    }

    static let defaultVolume: Float = 0.7

    // MARK: - License (LemonSqueezy)
    enum License {
        /// Storefront URL where users buy a license. Replace `<variant-id>` once the
        /// LemonSqueezy product is created.
        static let storeURL = URL(string: "https://shuuchuu.lemonsqueezy.com/buy/<variant-id>")!
        /// Base URL for license API endpoints (`/activate`, `/validate`, `/deactivate`).
        static let apiBase = URL(string: "https://api.lemonsqueezy.com/v1/licenses")!
        /// Trial length — 5 days.
        static let trialDuration: TimeInterval = 5 * 24 * 60 * 60
        /// Devices per license (LS `activation_limit`).
        static let activationLimit = 3
        /// Keychain service identifier.
        static let keychainService = "com.bluedusk.shuuchuu.license"
    }
}
