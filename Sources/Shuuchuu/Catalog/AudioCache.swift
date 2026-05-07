import Foundation
import CryptoKit

protocol AudioDownloader: AnyObject, Sendable {
    func download(from url: URL) async throws -> Data
}

final class URLSessionDownloader: AudioDownloader, @unchecked Sendable {
    let session: URLSession
    init(session: URLSession = .shared) { self.session = session }
    func download(from url: URL) async throws -> Data {
        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        return data
    }
}

/// Persistent on-disk cache for streamed audio. SHA-256 keyed (the catalog hash
/// IS the cache filename), LRU-evicting when over the byte cap.
///
/// Concurrency: actor-isolated so two parallel fetches for the same track share
/// a single download Task instead of racing each other on the network and the
/// rename. Without dedup the second fetch's atomic rename can clobber an
/// in-flight write and leave a corrupt file behind.
actor AudioCache {
    enum CacheError: Error {
        case integrityFailed
        case invalidHash
    }

    let baseDir: URL
    let downloader: AudioDownloader
    let limitBytes: Int64

    /// In-flight fetches keyed on sha256 — second caller awaits the same Task.
    private var inFlight: [String: Task<URL, Error>] = [:]

    init(baseDir: URL, downloader: AudioDownloader, limitBytes: Int64 = Constants.audioCacheLimitBytes) {
        self.baseDir = baseDir
        self.downloader = downloader
        self.limitBytes = limitBytes
        try? FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)
    }

    /// Sync, nonisolated — used by `MixingController` to decide whether attaching
    /// a streamed track will hit the network. Lets the UI suppress the spinner
    /// for cache hits, where prepare resolves locally in <100 ms.
    nonisolated func isCached(_ info: StreamedInfo) -> Bool {
        let ext = Self.safeExtension(for: info.url)
        let fileURL = baseDir.appendingPathComponent("\(info.sha256).\(ext)")
        return FileManager.default.fileExists(atPath: fileURL.path)
    }

    func localURL(for info: StreamedInfo) async throws -> URL {
        try Self.validateHash(info.sha256)

        if let existing = inFlight[info.sha256] {
            return try await existing.value
        }

        let task = Task<URL, Error> { [info] in
            try await self.fetchAndCache(info: info)
        }
        inFlight[info.sha256] = task
        defer { inFlight[info.sha256] = nil }
        return try await task.value
    }

    private func fetchAndCache(info: StreamedInfo) async throws -> URL {
        let ext = Self.safeExtension(for: info.url)
        let fileURL = baseDir.appendingPathComponent("\(info.sha256).\(ext)")

        if FileManager.default.fileExists(atPath: fileURL.path) {
            try? FileManager.default.setAttributes(
                [.modificationDate: Date()], ofItemAtPath: fileURL.path
            )
            return fileURL
        }

        let data = try await downloader.download(from: info.url)
        let got = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard got == info.sha256 else { throw CacheError.integrityFailed }

        let tmpURL = fileURL.appendingPathExtension("tmp")
        try data.write(to: tmpURL, options: .atomic)
        _ = try FileManager.default.replaceItemAt(fileURL, withItemAt: tmpURL)

        evictIfOverLimit(keeping: fileURL)
        return fileURL
    }

    /// Reject any sha256 that isn't 64 hex chars before using it as a path
    /// component. Without this, a malicious catalog could embed `..` segments
    /// and write outside `baseDir`.
    private static func validateHash(_ s: String) throws {
        guard s.count == 64, s.allSatisfy({ $0.isHexDigit }) else {
            throw CacheError.invalidHash
        }
    }

    /// Pin the file extension to a known audio format. Defaults to `caf`.
    /// Without this, an attacker-controlled catalog URL could push a path-
    /// extension that alters how the file is interpreted by downstream loaders.
    private static func safeExtension(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        let allowed: Set<String> = ["caf", "mp3", "m4a", "aac", "wav", "flac", "ogg"]
        return allowed.contains(ext) ? ext : "caf"
    }

    func evictIfOverLimit(keeping exempt: URL? = nil) {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(
            at: baseDir,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]
        ) else { return }

        var entries: [(url: URL, size: Int64, mtime: Date)] = []
        for item in items {
            let values = try? item.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            let size = Int64(values?.fileSize ?? 0)
            let mtime = values?.contentModificationDate ?? .distantPast
            entries.append((item, size, mtime))
        }

        var total = entries.reduce(Int64(0)) { $0 + $1.size }
        guard total > limitBytes else { return }

        entries.sort { $0.mtime < $1.mtime }
        for entry in entries {
            if total <= limitBytes { break }
            if entry.url == exempt { continue }
            try? fm.removeItem(at: entry.url)
            total -= entry.size
        }
    }

    func clear() {
        try? FileManager.default.removeItem(at: baseDir)
        try? FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)
    }
}
