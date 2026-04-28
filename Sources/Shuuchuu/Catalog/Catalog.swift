import Foundation
import SwiftUI

protocol CatalogFetcher: Sendable {
    func fetch() async throws -> Data
}

struct URLSessionFetcher: CatalogFetcher {
    let url: URL
    let session: URLSession
    init(url: URL, session: URLSession = .shared) {
        self.url = url
        self.session = session
    }
    func fetch() async throws -> Data {
        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        return data
    }
}

/// Reads the catalog from the app bundle (learning / offline-first mode).
struct BundleCatalogFetcher: CatalogFetcher {
    let resource: String
    let ext: String

    init(resource: String = "catalog", ext: String = "json") {
        self.resource = resource
        self.ext = ext
    }

    func fetch() async throws -> Data {
        guard let url = Bundle.module.url(forResource: resource, withExtension: ext) else {
            throw URLError(.fileDoesNotExist)
        }
        return try Data(contentsOf: url)
    }
}

@MainActor
final class Catalog: ObservableObject {
    enum State: Equatable {
        case loading
        case ready([Category])
        case offline(stale: [Category]?)
        case error(String)
    }

    @Published private(set) var state: State = .loading

    private let fetcher: CatalogFetcher
    private let cacheFile: URL

    init(fetcher: CatalogFetcher, cacheFile: URL) {
        self.fetcher = fetcher
        self.cacheFile = cacheFile
    }

    func refresh() async {
        let cached = loadCache()
        if let cached {
            state = .ready(cached.categories)
        }

        do {
            let data = try await fetcher.fetch()
            let fresh = try JSONDecoder().decode(CatalogDocument.self, from: data)
            try? data.write(to: cacheFile, options: .atomic)
            state = .ready(fresh.categories)
        } catch {
            if cached != nil {
                return
            }
            state = .offline(stale: nil)
        }
    }

    private func loadCache() -> CatalogDocument? {
        guard let data = try? Data(contentsOf: cacheFile) else { return nil }
        return try? JSONDecoder().decode(CatalogDocument.self, from: data)
    }
}
