import Foundation
import Combine

@MainActor
final class SoundtracksFilterState: ObservableObject {
    @Published private(set) var selected: [String] = []

    var isActive: Bool { !selected.isEmpty }

    func toggle(_ tag: String) {
        guard let n = TagNormalize.normalize(tag) else { return }
        if let i = selected.firstIndex(of: n) {
            selected.remove(at: i)
        } else {
            selected.append(n)
        }
    }

    func clear() { selected.removeAll() }

    /// True when the soundtrack's tag set is a superset of every selected tag.
    /// Empty selection matches everything.
    func matches(tags: [String]) -> Bool {
        guard isActive else { return true }
        let set = Set(tags)
        return selected.allSatisfy(set.contains)
    }

    /// Drop selections that no longer appear in `available`. Called by the view
    /// layer when the library's `tagsInUse` shrinks (e.g., last user of a tag
    /// was removed).
    func reconcile(against available: [String]) {
        let valid = Set(available)
        selected.removeAll { !valid.contains($0) }
    }
}
