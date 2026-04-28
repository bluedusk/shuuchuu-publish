import Foundation
import CryptoKit

protocol AudioDownloader: AnyObject {
    func download(from url: URL) async throws -> Data
}

final class URLSessionDownloader: AudioDownloader {
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

final class AudioCache {
    enum CacheError: Error {
        case integrityFailed
    }

    let baseDir: URL
    let downloader: AudioDownloader
    let limitBytes: Int64

    init(baseDir: URL, downloader: AudioDownloader, limitBytes: Int64 = Constants.audioCacheLimitBytes) {
        self.baseDir = baseDir
        self.downloader = downloader
        self.limitBytes = limitBytes
        try? FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)
    }

    func localURL(for track: Track) async throws -> URL {
        guard case .streamed(let info) = track.kind else {
            fatalError("AudioCache only handles streamed tracks")
        }
        let ext = info.url.pathExtension.isEmpty ? "caf" : info.url.pathExtension
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

        await evictIfOverLimit(keeping: fileURL)
        return fileURL
    }

    func evictIfOverLimit(keeping exempt: URL? = nil) async {
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
