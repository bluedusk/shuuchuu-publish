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
}
