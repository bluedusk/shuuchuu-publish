import Foundation

final class Preferences {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var lastTrackId: String? {
        get { defaults.string(forKey: Constants.PrefKey.lastTrackId) }
        set { defaults.set(newValue, forKey: Constants.PrefKey.lastTrackId) }
    }

    var volume: Float {
        get {
            if defaults.object(forKey: Constants.PrefKey.volume) == nil {
                return Constants.defaultVolume
            }
            return defaults.float(forKey: Constants.PrefKey.volume)
        }
        set {
            let clamped = max(0, min(1, newValue))
            defaults.set(clamped, forKey: Constants.PrefKey.volume)
        }
    }

    var lastCategoryId: String? {
        get { defaults.string(forKey: Constants.PrefKey.lastCategoryId) }
        set { defaults.set(newValue, forKey: Constants.PrefKey.lastCategoryId) }
    }

    var resumeOnWake: Bool {
        get { defaults.bool(forKey: Constants.PrefKey.resumeOnWake) }
        set { defaults.set(newValue, forKey: Constants.PrefKey.resumeOnWake) }
    }

    var resumeOnLaunch: Bool {
        get { defaults.bool(forKey: Constants.PrefKey.resumeOnLaunch) }
        set { defaults.set(newValue, forKey: Constants.PrefKey.resumeOnLaunch) }
    }
}
