import Compression
import Foundation

enum ZipArchiveError: Error, Equatable {
    case notAZipFile
    case corruptArchive(String)
    case unsupportedCompression(UInt16)
    case entryNotFound(String)
}

/// Minimal read-only ZIP support: enough to open .xlsx packages (stored and
/// deflate entries, no ZIP64, no encryption).
struct ZipArchiveReader {
    /// Guards against crafted archives: a workbook part larger than this or
    /// an archive with an absurd entry count is rejected instead of being
    /// inflated into memory.
    static let maxEntryUncompressedSize = 1 << 30
    static let maxEntryCount = 10_000

    struct Entry {
        let name: String
        let compressionMethod: UInt16
        let compressedSize: Int
        let uncompressedSize: Int
        let localHeaderOffset: Int
    }

    private let data: Data
    let entries: [Entry]

    init(path: String) throws {
        self.data = try Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe)
        guard data.count >= 22 else { throw ZipArchiveError.notAZipFile }

        // Locate the end-of-central-directory record by scanning backwards.
        let maxCommentScan = min(data.count, 22 + 65_536)
        var eocdOffset = -1
        var offset = data.count - 22
        let lowerBound = data.count - maxCommentScan
        while offset >= lowerBound {
            if Self.readUInt32(data, at: offset) == 0x06054b50 {
                eocdOffset = offset
                break
            }
            offset -= 1
        }
        guard eocdOffset >= 0 else { throw ZipArchiveError.notAZipFile }

        let entryCount = Int(Self.readUInt16(data, at: eocdOffset + 10))
        guard entryCount <= Self.maxEntryCount else {
            throw ZipArchiveError.corruptArchive("too many entries (\(entryCount))")
        }
        let centralDirectoryOffset = Int(Self.readUInt32(data, at: eocdOffset + 16))
        guard centralDirectoryOffset < data.count else {
            throw ZipArchiveError.corruptArchive("central directory offset out of range")
        }

        var parsed: [Entry] = []
        var cursor = centralDirectoryOffset
        for _ in 0..<entryCount {
            guard cursor + 46 <= data.count, Self.readUInt32(data, at: cursor) == 0x02014b50 else {
                throw ZipArchiveError.corruptArchive("bad central directory entry")
            }
            let method = Self.readUInt16(data, at: cursor + 10)
            let compressedSize = Int(Self.readUInt32(data, at: cursor + 20))
            let uncompressedSize = Int(Self.readUInt32(data, at: cursor + 24))
            let nameLength = Int(Self.readUInt16(data, at: cursor + 28))
            let extraLength = Int(Self.readUInt16(data, at: cursor + 30))
            let commentLength = Int(Self.readUInt16(data, at: cursor + 32))
            let headerOffset = Int(Self.readUInt32(data, at: cursor + 42))
            guard cursor + 46 + nameLength <= data.count else {
                throw ZipArchiveError.corruptArchive("entry name out of range")
            }
            let nameData = data.subdata(in: (cursor + 46)..<(cursor + 46 + nameLength))
            let name = String(data: nameData, encoding: .utf8) ?? ""
            parsed.append(Entry(
                name: name,
                compressionMethod: method,
                compressedSize: compressedSize,
                uncompressedSize: uncompressedSize,
                localHeaderOffset: headerOffset
            ))
            cursor += 46 + nameLength + extraLength + commentLength
        }
        self.entries = parsed
    }

    func contains(_ name: String) -> Bool {
        entries.contains { $0.name == name }
    }

    func read(_ name: String) throws -> Data {
        guard let entry = entries.first(where: { $0.name == name }) else {
            throw ZipArchiveError.entryNotFound(name)
        }
        guard entry.uncompressedSize <= Self.maxEntryUncompressedSize else {
            throw ZipArchiveError.corruptArchive("entry \(name) claims \(entry.uncompressedSize) bytes")
        }
        let headerOffset = entry.localHeaderOffset
        guard headerOffset + 30 <= data.count, Self.readUInt32(data, at: headerOffset) == 0x04034b50 else {
            throw ZipArchiveError.corruptArchive("bad local header for \(name)")
        }
        let nameLength = Int(Self.readUInt16(data, at: headerOffset + 26))
        let extraLength = Int(Self.readUInt16(data, at: headerOffset + 28))
        let payloadStart = headerOffset + 30 + nameLength + extraLength
        let payloadEnd = payloadStart + entry.compressedSize
        guard payloadEnd <= data.count else {
            throw ZipArchiveError.corruptArchive("entry payload out of range for \(name)")
        }
        let payload = data.subdata(in: payloadStart..<payloadEnd)

        switch entry.compressionMethod {
        case 0:
            return payload
        case 8:
            return try Self.inflate(payload, expectedSize: entry.uncompressedSize)
        default:
            throw ZipArchiveError.unsupportedCompression(entry.compressionMethod)
        }
    }

    private static func inflate(_ payload: Data, expectedSize: Int) throws -> Data {
        guard expectedSize > 0 else { return Data() }
        var destination = Data(count: expectedSize)
        let written = destination.withUnsafeMutableBytes { destinationBuffer -> Int in
            payload.withUnsafeBytes { sourceBuffer in
                compression_decode_buffer(
                    destinationBuffer.bindMemory(to: UInt8.self).baseAddress!,
                    expectedSize,
                    sourceBuffer.bindMemory(to: UInt8.self).baseAddress!,
                    payload.count,
                    nil,
                    COMPRESSION_ZLIB
                )
            }
        }
        guard written == expectedSize else {
            throw ZipArchiveError.corruptArchive("inflate produced \(written) of \(expectedSize) bytes")
        }
        return destination
    }

    private static func readUInt16(_ data: Data, at offset: Int) -> UInt16 {
        UInt16(data[data.startIndex + offset]) | (UInt16(data[data.startIndex + offset + 1]) << 8)
    }

    private static func readUInt32(_ data: Data, at offset: Int) -> UInt32 {
        UInt32(data[data.startIndex + offset])
            | (UInt32(data[data.startIndex + offset + 1]) << 8)
            | (UInt32(data[data.startIndex + offset + 2]) << 16)
            | (UInt32(data[data.startIndex + offset + 3]) << 24)
    }
}
