import Foundation
import Combine

@MainActor
public final class ScenesLibrary: ObservableObject {
    @Published public private(set) var scenes: [Scene] = []

    public init(jsonData: Data? = nil) {
        if let data = jsonData {
            decodeAndPublish(data)
        } else {
            loadFromBundle()
        }
    }

    public func entry(id: String) -> Scene? {
        scenes.first { $0.id == id }
    }

    private func loadFromBundle() {
        guard let url = Bundle.module.url(forResource: "scenes",
                                          withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            scenes = []
            return
        }
        decodeAndPublish(data)
    }

    private func decodeAndPublish(_ data: Data) {
        if let decoded = try? JSONDecoder().decode([Scene].self, from: data) {
            scenes = decoded
        } else {
            scenes = []
        }
    }
}
