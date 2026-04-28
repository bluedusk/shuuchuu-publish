import Foundation
import Combine

/// Persistent set of favorited track ids.
final class Favorites: ObservableObject {
    @Published private(set) var ids: Set<String>

    private let defaults: UserDefaults
    private let key = "shuuchuu.favorites"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let arr = defaults.array(forKey: key) as? [String] {
            self.ids = Set(arr)
        } else {
            self.ids = ["rain", "fire", "ocean"]
        }
    }

    func contains(_ id: String) -> Bool { ids.contains(id) }

    func toggle(_ id: String) {
        if ids.contains(id) { ids.remove(id) } else { ids.insert(id) }
        persist()
    }

    private func persist() {
        defaults.set(Array(ids), forKey: key)
    }
}
