import Foundation

/// Reverse-engineered parser for Safari's `Cookies.binarycookies` file. Format
/// references: https://github.com/interstateone/BinaryCookies and
/// https://github.com/libyal/dtformats/blob/main/documentation/Safari%20Cookies.asciidoc
///
/// Layout:
///     "cook" magic, big-endian page count, page sizes (BE), then pages.
///     Each page: tag 0x100 (LE), cookie count (LE), cookie offsets (LE),
///     terminator 0x0, cookie records.
///     Cookie record: size, flags, four string-offsets (url/name/path/value),
///     8-byte terminator, two float64s (expiry, creation; reference epoch
///     2001-01-01 UTC), then the four NUL-terminated strings packed in.
enum SafariBinaryCookies {

    struct Cookie: Equatable {
        let domain: String
        let path: String
        let name: String
        let value: String
        let expiry: Date
        let isSecure: Bool
        let isHTTPOnly: Bool
    }

    enum ParseError: Error {
        case fileTooSmall
        case badMagic
        case badPageTag
        case readPastEnd
    }

    static var defaultCookiesPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return home + "/Library/Containers/com.apple.Safari/Data/Library/Cookies/Cookies.binarycookies"
    }

    static func read(at path: String) throws -> [Cookie] {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        return try parse(data)
    }

    static func parse(_ data: Data) throws -> [Cookie] {
        guard data.count >= 8 else { throw ParseError.fileTooSmall }

        var cursor = 0
        guard data[0] == 0x63, data[1] == 0x6f, data[2] == 0x6f, data[3] == 0x6b else {
            throw ParseError.badMagic
        }
        cursor = 4

        let numPages = try readUInt32BE(data, at: &cursor)
        var pageSizes: [Int] = []
        pageSizes.reserveCapacity(Int(numPages))
        for _ in 0..<numPages {
            pageSizes.append(Int(try readUInt32BE(data, at: &cursor)))
        }

        var cookies: [Cookie] = []
        for size in pageSizes {
            guard cursor + size <= data.count else { throw ParseError.readPastEnd }
            let pageData = data.subdata(in: cursor..<(cursor + size))
            cookies.append(contentsOf: try parsePage(pageData))
            cursor += size
        }
        return cookies
    }

    private static func parsePage(_ data: Data) throws -> [Cookie] {
        var cursor = 0
        let tag = try readUInt32LE(data, at: &cursor)
        guard tag == 0x00000100 else { throw ParseError.badPageTag }

        let numCookies = try readUInt32LE(data, at: &cursor)
        var offsets: [Int] = []
        offsets.reserveCapacity(Int(numCookies))
        for _ in 0..<numCookies {
            offsets.append(Int(try readUInt32LE(data, at: &cursor)))
        }
        // 4-byte terminator after offsets — skip; we don't validate it.

        var cookies: [Cookie] = []
        cookies.reserveCapacity(Int(numCookies))
        for offset in offsets {
            cookies.append(try parseCookie(data, at: offset))
        }
        return cookies
    }

    private static func parseCookie(_ data: Data, at recordStart: Int) throws -> Cookie {
        var cursor = recordStart
        let cookieSize = Int(try readUInt32LE(data, at: &cursor))
        guard recordStart + cookieSize <= data.count else { throw ParseError.readPastEnd }

        _ = try readUInt32LE(data, at: &cursor)                // unknown
        let flags = try readUInt32LE(data, at: &cursor)
        _ = try readUInt32LE(data, at: &cursor)                // unknown

        let urlOffset = Int(try readUInt32LE(data, at: &cursor))
        let nameOffset = Int(try readUInt32LE(data, at: &cursor))
        let pathOffset = Int(try readUInt32LE(data, at: &cursor))
        let valueOffset = Int(try readUInt32LE(data, at: &cursor))

        _ = try readUInt64LE(data, at: &cursor)                // end-of-cookie marker
        let expirySec = try readFloat64LE(data, at: &cursor)
        _ = try readFloat64LE(data, at: &cursor)               // creation

        let url = readNULString(data, recordStart: recordStart, recordSize: cookieSize, fieldOffset: urlOffset)
        let name = readNULString(data, recordStart: recordStart, recordSize: cookieSize, fieldOffset: nameOffset)
        let path = readNULString(data, recordStart: recordStart, recordSize: cookieSize, fieldOffset: pathOffset)
        let value = readNULString(data, recordStart: recordStart, recordSize: cookieSize, fieldOffset: valueOffset)

        return Cookie(
            domain: url,
            path: path,
            name: name,
            value: value,
            expiry: Date(timeIntervalSinceReferenceDate: expirySec),
            isSecure: (flags & 0x1) != 0,
            isHTTPOnly: (flags & 0x4) != 0
        )
    }

    private static func readNULString(_ data: Data, recordStart: Int, recordSize: Int, fieldOffset: Int) -> String {
        let absStart = recordStart + fieldOffset
        let absLimit = recordStart + recordSize
        guard absStart < absLimit else { return "" }
        var end = absStart
        while end < absLimit, data[end] != 0 {
            end += 1
        }
        return String(data: data.subdata(in: absStart..<end), encoding: .utf8) ?? ""
    }

    private static func readUInt32BE(_ data: Data, at cursor: inout Int) throws -> UInt32 {
        guard cursor + 4 <= data.count else { throw ParseError.readPastEnd }
        var v: UInt32 = 0
        for i in 0..<4 { v = (v << 8) | UInt32(data[cursor + i]) }
        cursor += 4
        return v
    }

    private static func readUInt32LE(_ data: Data, at cursor: inout Int) throws -> UInt32 {
        guard cursor + 4 <= data.count else { throw ParseError.readPastEnd }
        var v: UInt32 = 0
        for i in 0..<4 { v |= UInt32(data[cursor + i]) << (8 * i) }
        cursor += 4
        return v
    }

    private static func readUInt64LE(_ data: Data, at cursor: inout Int) throws -> UInt64 {
        guard cursor + 8 <= data.count else { throw ParseError.readPastEnd }
        var v: UInt64 = 0
        for i in 0..<8 { v |= UInt64(data[cursor + i]) << (8 * i) }
        cursor += 8
        return v
    }

    private static func readFloat64LE(_ data: Data, at cursor: inout Int) throws -> Double {
        Double(bitPattern: try readUInt64LE(data, at: &cursor))
    }
}
