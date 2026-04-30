import Foundation

public enum SceneKind: String, Codable, Sendable, Equatable {
    case shader
}

public struct Scene: Identifiable, Codable, Sendable, Equatable {
    public let id: String
    public let title: String
    public let thumbnail: String
    public let kind: SceneKind

    public init(id: String, title: String, thumbnail: String, kind: SceneKind) {
        self.id = id
        self.title = title
        self.thumbnail = thumbnail
        self.kind = kind
    }
}
