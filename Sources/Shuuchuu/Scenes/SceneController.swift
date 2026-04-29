import Foundation
import Combine
import QuartzCore

@MainActor
public final class SceneController: ObservableObject {
    public struct Active: Equatable, Sendable {
        public let id: String
        public let startTime: CFTimeInterval
    }

    @Published public private(set) var active: Active?

    public var activeSceneId: String? { active?.id }

    private let library: ScenesLibrary
    private let renderer: ShaderRendering
    private let defaults: UserDefaults

    private static let defaultsKey = "shuuchuu.activeScene"

    public init(library: ScenesLibrary,
                renderer: ShaderRendering,
                defaults: UserDefaults = .standard) {
        self.library = library
        self.renderer = renderer
        self.defaults = defaults
        if let id = defaults.string(forKey: Self.defaultsKey) {
            setScene(id)
        }
    }

    public func setScene(_ id: String?) {
        guard let id, library.entry(id: id) != nil else {
            clearActive()
            return
        }
        do {
            try renderer.warm(id)
            active = Active(id: id, startTime: CACurrentMediaTime())
            defaults.set(id, forKey: Self.defaultsKey)
        } catch {
            print("[SceneController] warm failed for \(id): \(error)")
            clearActive()
        }
    }

    private func clearActive() {
        active = nil
        defaults.removeObject(forKey: Self.defaultsKey)
    }
}
