import Foundation

enum Constants {
    // MARK: - Catalog
    static let catalogCacheFilename = "catalog.json"

    // MARK: - Audio cache
    static let audioCacheDirName = "x-noise"
    static let audioCacheLimitBytes: Int64 = 500 * 1024 * 1024

    // MARK: - Fades (milliseconds)
    static let fadeInMs: Double = 150
    static let fadeOutMs: Double = 300
    static let crossfadeMs: Double = 300

    // MARK: - UserDefaults keys
    enum PrefKey {
        static let lastTrackId = "x-noise.lastTrackId"
        static let volume = "x-noise.volume"
        static let lastCategoryId = "x-noise.lastCategoryId"
        static let resumeOnWake = "x-noise.resumeOnWake"
        static let resumeOnLaunch = "x-noise.resumeOnLaunch"
    }

    static let defaultVolume: Float = 0.7
}
