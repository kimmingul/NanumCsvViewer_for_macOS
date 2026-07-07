import Foundation

enum BinaryImportRouting {
    private static let ole2Magic = Data([0xD0, 0xCF, 0x11, 0xE0])
    private static let spssSavMagic = Data("$FL2".utf8)
    private static let sas7bdatMagic = Data([0xC2, 0xEA, 0x81, 0x60, 0xB3, 0x14, 0x11, 0xCF, 0xBD, 0x92, 0x08, 0x00, 0x09, 0xC7, 0x31, 0x8C, 0x18, 0x1F, 0x10, 0x11])

    static func isLegacyXls(url: URL) -> Bool {
        guard url.pathExtension.lowercased() == "xls",
              let handle = FileHandle(forReadingAtPath: url.path) else {
            return false
        }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: ole2Magic.count), data.count == ole2Magic.count else {
            return false
        }
        return data == ole2Magic
    }

    static func isSpssSav(url: URL) -> Bool {
        guard url.pathExtension.lowercased() == "sav",
              let handle = FileHandle(forReadingAtPath: url.path) else {
            return false
        }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: spssSavMagic.count), data.count == spssSavMagic.count else {
            return false
        }
        return data == spssSavMagic
    }

    static func isSas7bdat(url: URL, enabled: Bool) -> Bool {
        guard enabled,
              url.pathExtension.lowercased() == "sas7bdat",
              let handle = FileHandle(forReadingAtPath: url.path) else {
            return false
        }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 32), data.count >= 32 else {
            return false
        }
        return data[12..<32] == sas7bdatMagic
    }
}
