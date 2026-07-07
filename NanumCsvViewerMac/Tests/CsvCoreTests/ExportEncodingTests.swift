import Foundation
import XCTest
@testable import CsvCore

final class ExportEncodingTests: XCTestCase {
    private func openIndexed(_ content: String) throws -> (VirtualCsvDocument, String) {
        let path = (NSTemporaryDirectory() as NSString).appendingPathComponent("exportenc-\(UUID().uuidString).csv")
        try content.data(using: .utf8)!.write(to: URL(fileURLWithPath: path))
        let doc = try VirtualCsvDocument.open(path: path)
        try doc.runIndexing(progress: { _ in }, cancellation: CancellationFlag())
        return (doc, path)
    }

    private func exportOut() -> String {
        (NSTemporaryDirectory() as NSString).appendingPathComponent("exportout-\(UUID().uuidString).csv")
    }

    func testExportEncodingResolution() {
        XCTAssertEqual(EncodingDetector.exportEncoding(named: CsvEncodingName.utf8).byteOrderMark, false)
        XCTAssertEqual(EncodingDetector.exportEncoding(named: CsvEncodingName.utf8Bom).byteOrderMark, true)
        XCTAssertEqual(EncodingDetector.exportEncoding(named: CsvEncodingName.cp949).encoding, EncodingDetector.cp949Encoding)
    }

    func testExportsUtf8ByDefaultWithoutBom() throws {
        let (doc, path) = try openIndexed("name,city\n김민걸,서울\n")
        defer { try? FileManager.default.removeItem(atPath: path) }
        let out = exportOut()
        defer { try? FileManager.default.removeItem(atPath: out) }

        try doc.exportCurrentView(to: out, format: .csv, cancellation: CancellationFlag())
        let bytes = try Data(contentsOf: URL(fileURLWithPath: out))
        XCTAssertFalse(bytes.starts(with: [0xEF, 0xBB, 0xBF]), "plain UTF-8 has no BOM")
        XCTAssertEqual(String(data: bytes, encoding: .utf8), "name,city\n김민걸,서울\n")
    }

    func testExportsUtf8WithBomPrefix() throws {
        let (doc, path) = try openIndexed("a\n1\n")
        defer { try? FileManager.default.removeItem(atPath: path) }
        let out = exportOut()
        defer { try? FileManager.default.removeItem(atPath: out) }

        try doc.exportCurrentView(to: out, format: .csv, encodingName: CsvEncodingName.utf8Bom, cancellation: CancellationFlag())
        let bytes = try Data(contentsOf: URL(fileURLWithPath: out))
        XCTAssertTrue(bytes.starts(with: [0xEF, 0xBB, 0xBF]), "BOM written once at the start")
        XCTAssertEqual(String(data: bytes.dropFirst(3), encoding: .utf8), "a\n1\n")
    }

    func testExportsCp949RoundTrips() throws {
        let (doc, path) = try openIndexed("도시\n서울\n부산\n")
        defer { try? FileManager.default.removeItem(atPath: path) }
        let out = exportOut()
        defer { try? FileManager.default.removeItem(atPath: out) }

        try doc.exportCurrentView(to: out, format: .csv, encodingName: CsvEncodingName.cp949, cancellation: CancellationFlag())
        let bytes = try Data(contentsOf: URL(fileURLWithPath: out))
        // Decoding the bytes back as CP949 must recover the Korean text.
        let decoded = String(data: bytes, encoding: EncodingDetector.cp949Encoding)
        XCTAssertEqual(decoded, "도시\n서울\n부산\n")
        // And it must NOT be valid UTF-8 with the same content (proves it was re-encoded).
        XCTAssertNotEqual(String(data: bytes, encoding: .utf8), "도시\n서울\n부산\n")
    }

    func testBomNotWrittenForJsonEvenWhenBomEncodingChosen() throws {
        let (doc, path) = try openIndexed("a\n1\n")
        defer { try? FileManager.default.removeItem(atPath: path) }
        let out = exportOut()
        defer { try? FileManager.default.removeItem(atPath: out) }

        // JSON is conventionally UTF-8; a BOM corrupts it for many parsers.
        try doc.exportCurrentView(to: out, format: .json, encodingName: CsvEncodingName.utf8Bom, cancellation: CancellationFlag())
        let bytes = try Data(contentsOf: URL(fileURLWithPath: out))
        XCTAssertFalse(bytes.starts(with: [0xEF, 0xBB, 0xBF]), "no BOM on JSON")
        XCTAssertEqual(bytes.first, UInt8(ascii: "["), "JSON starts with the array bracket, not a BOM")
    }

    func testCp949ExportIsAlwaysUtf8ForNonCsvFormats() throws {
        let (doc, path) = try openIndexed("도시\n서울\n")
        defer { try? FileManager.default.removeItem(atPath: path) }
        let out = exportOut()
        defer { try? FileManager.default.removeItem(atPath: out) }

        try doc.exportCurrentView(to: out, format: .json, encodingName: CsvEncodingName.cp949, cancellation: CancellationFlag())
        let bytes = try Data(contentsOf: URL(fileURLWithPath: out))
        XCTAssertNotNil(String(data: bytes, encoding: .utf8), "non-CSV export stays valid UTF-8 regardless of encoding choice")
    }

    func testLossyFlagFalseWhenAllRepresentable() throws {
        let (doc, path) = try openIndexed("도시\n서울\n")
        defer { try? FileManager.default.removeItem(atPath: path) }
        let out = exportOut()
        defer { try? FileManager.default.removeItem(atPath: out) }
        let lossy = try doc.exportCurrentView(to: out, format: .csv, encodingName: CsvEncodingName.cp949, cancellation: CancellationFlag())
        XCTAssertFalse(lossy, "hangul is representable in CP949")
    }

    func testLossyFlagTrueWhenCharacterUnrepresentable() throws {
        // An emoji has no CP949 representation.
        let (doc, path) = try openIndexed("v\n🎉\n")
        defer { try? FileManager.default.removeItem(atPath: path) }
        let out = exportOut()
        defer { try? FileManager.default.removeItem(atPath: out) }
        let lossy = try doc.exportCurrentView(to: out, format: .csv, encodingName: CsvEncodingName.cp949, cancellation: CancellationFlag())
        XCTAssertTrue(lossy, "emoji cannot be encoded in CP949 and is flagged lossy")
    }

    func testExportReportsProgressToCompletion() throws {
        let rows = (0..<500).map { "\($0)" }.joined(separator: "\n")
        let (doc, path) = try openIndexed("v\n\(rows)\n")
        defer { try? FileManager.default.removeItem(atPath: path) }
        let out = exportOut()
        defer { try? FileManager.default.removeItem(atPath: out) }

        var lastProgress = -1
        try doc.exportCurrentView(to: out, format: .csv, progress: { lastProgress = $0 }, cancellation: CancellationFlag())
        XCTAssertEqual(lastProgress, 100, "progress ends at 100%")
    }
}
