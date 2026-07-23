import Foundation
import XCTest
@testable import CsvCore

final class EncodingDetectorTests: XCTestCase {
    private func valid(_ bytes: [UInt8], allowIncomplete: Bool = false) -> Bool {
        EncodingDetector.isValidUtf8(bytes, allowIncompleteAtEnd: allowIncomplete)
    }

    func testAsciiIsValid() {
        XCTAssertTrue(valid([0x41, 0x42, 0x43]))
    }

    func testValidMultibyteSequences() {
        XCTAssertTrue(valid([0xC3, 0xA9]))
        XCTAssertTrue(valid([0xEA, 0xB0, 0x80]))
        XCTAssertTrue(valid([0xF0, 0x9F, 0x98, 0x80]))
    }

    func testRejectsLoneContinuationByte() {
        XCTAssertFalse(valid([0x80]))
    }

    func testRejectsOverlongEncoding() {
        XCTAssertFalse(valid([0xC0, 0x80]))
    }

    func testRejectsUtf16SurrogateRange() {
        XCTAssertFalse(valid([0xED, 0xA0, 0x80]))
    }

    func testRejectsInvalidLeadBytes() {
        XCTAssertFalse(valid([0xF5]))
        XCTAssertFalse(valid([0xFF]))
    }

    func testIncompleteSequenceAtEndRespectsFlag() {
        let truncated: [UInt8] = [0x41, 0xC3]
        XCTAssertTrue(valid(truncated, allowIncomplete: true))
        XCTAssertFalse(valid(truncated, allowIncomplete: false))
    }

    func testCp949DecodesKorean() throws {
        let encoding = EncodingDetector.encoding(named: CsvEncodingName.cp949)
        let data = "name\n가\n".data(using: encoding)
        XCTAssertNotNil(data)
        let path = try temporaryPath()
        try data!.write(to: URL(fileURLWithPath: path))
        defer { try? FileManager.default.removeItem(atPath: path) }

        let doc = try VirtualCsvDocument.open(path: path)
        try doc.runIndexing(progress: { _ in }, cancellation: CancellationFlag())
        XCTAssertEqual(doc.encodingName, CsvEncodingName.cp949)
        XCTAssertEqual(try doc.getDisplayRow(0), ["가"])
    }

    // MARK: - BOM-less UTF-16 detection

    private func utf16LE(_ text: String) -> [UInt8] {
        text.unicodeScalars.flatMap { [UInt8($0.value & 0xFF), UInt8(($0.value >> 8) & 0xFF)] }
    }

    private func utf16BE(_ text: String) -> [UInt8] {
        text.unicodeScalars.flatMap { [UInt8(($0.value >> 8) & 0xFF), UInt8($0.value & 0xFF)] }
    }

    func testDetectsBomlessUtf16LEByParity() {
        XCTAssertEqual(EncodingDetector.detectBomlessUtf16(utf16LE("name,value\n1,2\n"))?.encoding, .utf16LittleEndian)
    }

    func testDetectsBomlessUtf16BEByParity() {
        XCTAssertEqual(EncodingDetector.detectBomlessUtf16(utf16BE("name,value\n1,2\n"))?.encoding, .utf16BigEndian)
    }

    func testDoesNotMisclassifyUtf8AsUtf16() {
        XCTAssertNil(EncodingDetector.detectBomlessUtf16([UInt8]("name,value\n1,2\nAlice,3\n".utf8)))
    }

    func testDoesNotMisclassifyKoreanUtf8AsUtf16() {
        XCTAssertNil(EncodingDetector.detectBomlessUtf16([UInt8]("이름,값\n민걸,3\n".utf8)))
    }

    func testDoesNotMisclassifyUtf32AsUtf16() {
        let utf32LE = "abcdefgh".unicodeScalars.flatMap { scalar -> [UInt8] in
            [UInt8(scalar.value & 0xFF), 0, 0, 0]
        }
        XCTAssertNil(EncodingDetector.detectBomlessUtf16(utf32LE))
    }

    func testDetectResolvesBomlessUtf16File() throws {
        let path = try temporaryPath()
        try Data(utf16LE("header,value\nrow1,10\nrow2,20\n")).write(to: URL(fileURLWithPath: path))
        defer { try? FileManager.default.removeItem(atPath: path) }

        let result = try EncodingDetector.detect(path: path)
        XCTAssertEqual(result.encoding, .utf16LittleEndian)
        XCTAssertFalse(result.isByteIndexable)
    }
}
