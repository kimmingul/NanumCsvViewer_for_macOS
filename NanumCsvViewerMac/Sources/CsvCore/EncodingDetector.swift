import CoreFoundation
import Foundation

public enum CsvEncodingName {
    public static let utf8 = "UTF-8"
    public static let utf8Bom = "UTF-8 (BOM)"
    public static let cp949 = "CP949 / EUC-KR"
    public static let selectable = [utf8, utf8Bom, cp949]
}

public struct EncodingDetectionResult {
    public let encoding: String.Encoding
    public let preambleLength: Int
    public let displayName: String
    public let isByteIndexable: Bool
}

public enum EncodingDetector {
    public static func encoding(named name: String) -> String.Encoding {
        if name == CsvEncodingName.cp949 {
            return cp949Encoding
        }
        return .utf8
    }

    /// Resolves an export encoding name to the text encoding and whether a byte
    /// order mark should be written.
    public static func exportEncoding(named name: String) -> (encoding: String.Encoding, byteOrderMark: Bool) {
        switch name {
        case CsvEncodingName.utf8Bom:
            return (.utf8, true)
        case CsvEncodingName.cp949:
            return (cp949Encoding, false)
        default:
            return (.utf8, false)
        }
    }

    public static func detect(path: String) throws -> EncodingDetectionResult {
        let source = try FileByteSource(path: path)
        defer { source.close() }

        let length = source.length
        let bomLength = Int(min(4, length))
        let bom = try source.readData(offset: 0, length: bomLength)
        let bytes = [UInt8](bom)

        if bytes.count >= 3, bytes[0] == 0xEF, bytes[1] == 0xBB, bytes[2] == 0xBF {
            return EncodingDetectionResult(encoding: .utf8, preambleLength: 3, displayName: CsvEncodingName.utf8Bom, isByteIndexable: true)
        }
        if bytes.count >= 2, bytes[0] == 0xFF, bytes[1] == 0xFE {
            if bytes.count >= 4, bytes[2] == 0x00, bytes[3] == 0x00 {
                return EncodingDetectionResult(encoding: .utf32LittleEndian, preambleLength: 4, displayName: "UTF-32 LE", isByteIndexable: false)
            }
            return EncodingDetectionResult(encoding: .utf16LittleEndian, preambleLength: 2, displayName: "UTF-16 LE", isByteIndexable: false)
        }
        if bytes.count >= 2, bytes[0] == 0xFE, bytes[1] == 0xFF {
            return EncodingDetectionResult(encoding: .utf16BigEndian, preambleLength: 2, displayName: "UTF-16 BE", isByteIndexable: false)
        }
        if bytes.count >= 4, bytes[0] == 0x00, bytes[1] == 0x00, bytes[2] == 0xFE, bytes[3] == 0xFF {
            return EncodingDetectionResult(encoding: .utf32BigEndian, preambleLength: 4, displayName: "UTF-32 BE", isByteIndexable: false)
        }

        // A BOM-less UTF-16 file (common from Windows exports) is valid UTF-8 by
        // the check below (its NUL bytes are legal UTF-8), so it would be opened
        // as UTF-8 and show embedded NULs. Detect the ASCII/Latin case by the
        // NUL-parity signature before falling through.
        let parityLength = Int(min(Int64(sampleSize), length)) & ~1
        if parityLength >= 16 {
            let sample = [UInt8](try source.readData(offset: 0, length: parityLength))
            if let utf16 = detectBomlessUtf16(sample) {
                return EncodingDetectionResult(encoding: utf16.encoding, preambleLength: 0, displayName: utf16.displayName, isByteIndexable: false)
            }
        }

        let looksUtf8 = try sampleIsValidUtf8(source: source, start: 0, length: length)
            && sampleIsValidUtf8(source: source, start: length / 2, length: length)
            && sampleIsValidUtf8(source: source, start: max(0, length - Int64(sampleSize)), length: length)

        if looksUtf8 {
            return EncodingDetectionResult(encoding: .utf8, preambleLength: 0, displayName: CsvEncodingName.utf8, isByteIndexable: true)
        }
        return EncodingDetectionResult(encoding: cp949Encoding, preambleLength: 0, displayName: CsvEncodingName.cp949, isByteIndexable: true)
    }

    /// Detects a BOM-less, ASCII/Latin-heavy UTF-16 stream by its NUL-byte
    /// parity: UTF-16LE puts NUL at odd byte offsets, UTF-16BE at even offsets.
    /// Requires a strong asymmetry so real UTF-8/CP949 text (≈0% NUL on both
    /// sides) never matches, and guards against UTF-32 (≈3 NUL per 4 bytes),
    /// which also has a parity signal. Detects only the common ASCII/Latin case;
    /// BOM-less CJK UTF-16 (few NUL bytes) is intentionally left to fall through.
    static func detectBomlessUtf16(_ bytes: [UInt8]) -> (encoding: String.Encoding, displayName: String)? {
        guard bytes.count >= 16 else { return nil }

        // UTF-32 guard: BOM-less UTF-32 ASCII is e.g. `61 00 00 00`, ~3 NUL / 4.
        var utf32LikeQuads = 0
        var quads = 0
        var q = 0
        while q + 4 <= bytes.count {
            let nuls = (bytes[q] == 0 ? 1 : 0) + (bytes[q + 1] == 0 ? 1 : 0)
                + (bytes[q + 2] == 0 ? 1 : 0) + (bytes[q + 3] == 0 ? 1 : 0)
            if nuls >= 3 { utf32LikeQuads += 1 }
            quads += 1
            q += 4
        }
        if quads > 0, Double(utf32LikeQuads) / Double(quads) >= 0.5 { return nil }

        var evenNul = 0, oddNul = 0, evenCount = 0, oddCount = 0
        for (index, byte) in bytes.enumerated() {
            if index & 1 == 0 {
                evenCount += 1
                if byte == 0 { evenNul += 1 }
            } else {
                oddCount += 1
                if byte == 0 { oddNul += 1 }
            }
        }
        let evenRatio = evenCount > 0 ? Double(evenNul) / Double(evenCount) : 0
        let oddRatio = oddCount > 0 ? Double(oddNul) / Double(oddCount) : 0
        let strong = 0.30
        let quiet = 0.05
        if oddRatio >= strong, evenRatio < quiet {
            return (.utf16LittleEndian, "UTF-16 LE")
        }
        if evenRatio >= strong, oddRatio < quiet {
            return (.utf16BigEndian, "UTF-16 BE")
        }
        return nil
    }

    public static func isValidUtf8(_ bytes: [UInt8], allowIncompleteAtEnd: Bool) -> Bool {
        isValidUtf8(bytes[...], allowIncompleteAtEnd: allowIncompleteAtEnd)
    }

    static let cp949Encoding: String.Encoding = {
        let cfEncoding = CFStringConvertIANACharSetNameToEncoding("windows-949" as CFString)
        let nsEncoding = CFStringConvertEncodingToNSStringEncoding(cfEncoding)
        return String.Encoding(rawValue: nsEncoding)
    }()

    private static let sampleSize = 1 << 20

    private static func sampleIsValidUtf8(source: FileByteSource, start: Int64, length: Int64) throws -> Bool {
        guard length > 0 else { return true }
        let toRead = Int(min(Int64(sampleSize), length - start))
        guard toRead > 0 else { return true }

        let data = try source.readData(offset: start, length: toRead)
        var bytes = [UInt8](data)
        if start > 0 {
            while !bytes.isEmpty, (bytes[0] & 0xC0) == 0x80 {
                bytes.removeFirst()
            }
        }
        let reachedEOF = start + Int64(data.count) >= length
        return isValidUtf8(bytes[...], allowIncompleteAtEnd: !reachedEOF)
    }

    private static func isValidUtf8(_ bytes: ArraySlice<UInt8>, allowIncompleteAtEnd: Bool) -> Bool {
        let a = Array(bytes)
        var i = 0
        while i < a.count {
            let b = a[i]
            if b <= 0x7F {
                i += 1
                continue
            }

            var need: Int
            var min2: UInt8 = 0x80
            var max2: UInt8 = 0xBF

            if b >= 0xC2 && b <= 0xDF {
                need = 1
            } else if b == 0xE0 {
                need = 2
                min2 = 0xA0
            } else if b >= 0xE1 && b <= 0xEC {
                need = 2
            } else if b == 0xED {
                need = 2
                max2 = 0x9F
            } else if b >= 0xEE && b <= 0xEF {
                need = 2
            } else if b == 0xF0 {
                need = 3
                min2 = 0x90
            } else if b >= 0xF1 && b <= 0xF3 {
                need = 3
            } else if b == 0xF4 {
                need = 3
                max2 = 0x8F
            } else {
                return false
            }

            if i + need >= a.count {
                return allowIncompleteAtEnd
            }

            let b1 = a[i + 1]
            if b1 < min2 || b1 > max2 { return false }
            if need >= 2 {
                for k in 2...need {
                    let bk = a[i + k]
                    if bk < 0x80 || bk > 0xBF { return false }
                }
            }
            i += need + 1
        }
        return true
    }
}
