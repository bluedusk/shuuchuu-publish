import Foundation

struct CatalogDocument: Codable, Equatable {
    let schemaVersion: Int
    let categories: [Category]
}

struct Category: Codable, Equatable, Identifiable {
    let id: String
    let name: String
    let tracks: [Track]
}

struct Track: Codable, Equatable, Identifiable {
    let id: String
    let name: String
    let kind: Kind
    let artworkUrl: URL?

    enum Kind: Equatable {
        case procedural(ProceduralVariant)
        case streamed(StreamedInfo)
        case bundled(filename: String)
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, kind, variant, url, sha256, bytes, durationSec, filename, artworkUrl
    }

    init(id: String, name: String, kind: Kind, artworkUrl: URL?) {
        self.id = id
        self.name = name
        self.kind = kind
        self.artworkUrl = artworkUrl
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        artworkUrl = try c.decodeIfPresent(URL.self, forKey: .artworkUrl)

        let kindStr = try c.decode(String.self, forKey: .kind)
        switch kindStr {
        case "procedural":
            let variant = try c.decode(ProceduralVariant.self, forKey: .variant)
            kind = .procedural(variant)
        case "streamed":
            let info = StreamedInfo(
                url: try c.decode(URL.self, forKey: .url),
                sha256: try c.decode(String.self, forKey: .sha256),
                bytes: try c.decode(Int64.self, forKey: .bytes),
                durationSec: try c.decodeIfPresent(Double.self, forKey: .durationSec)
            )
            kind = .streamed(info)
        case "bundled":
            let filename = try c.decode(String.self, forKey: .filename)
            kind = .bundled(filename: filename)
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .kind, in: c,
                debugDescription: "Unknown track kind: \(kindStr)"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encodeIfPresent(artworkUrl, forKey: .artworkUrl)
        switch kind {
        case .procedural(let variant):
            try c.encode("procedural", forKey: .kind)
            try c.encode(variant, forKey: .variant)
        case .streamed(let info):
            try c.encode("streamed", forKey: .kind)
            try c.encode(info.url, forKey: .url)
            try c.encode(info.sha256, forKey: .sha256)
            try c.encode(info.bytes, forKey: .bytes)
            try c.encodeIfPresent(info.durationSec, forKey: .durationSec)
        case .bundled(let filename):
            try c.encode("bundled", forKey: .kind)
            try c.encode(filename, forKey: .filename)
        }
    }
}

struct StreamedInfo: Equatable {
    let url: URL
    let sha256: String
    let bytes: Int64
    let durationSec: Double?
}

enum ProceduralVariant: String, Codable, Equatable {
    case white, pink, brown, green, fluorescent
}
