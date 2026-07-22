import Foundation
import XCTest
@testable import CsvCore

final class CsvFormulaSanitizerTests: XCTestCase {
    func testNeutralizesFormulaLeadingCharacters() {
        XCTAssertEqual(CsvFormulaSanitizer.sanitize("=SUM(A1:A9)"), "'=SUM(A1:A9)")
        XCTAssertEqual(CsvFormulaSanitizer.sanitize("+1"), "'+1")
        XCTAssertEqual(CsvFormulaSanitizer.sanitize("-1"), "'-1")
        XCTAssertEqual(CsvFormulaSanitizer.sanitize("@cmd"), "'@cmd")
        XCTAssertEqual(CsvFormulaSanitizer.sanitize("\t=x"), "'\t=x")
    }

    func testLeavesOrdinaryValuesUnchanged() {
        XCTAssertEqual(CsvFormulaSanitizer.sanitize("hello"), "hello")
        XCTAssertEqual(CsvFormulaSanitizer.sanitize("123"), "123")
        XCTAssertEqual(CsvFormulaSanitizer.sanitize(""), "")
        XCTAssertEqual(CsvFormulaSanitizer.sanitize("a=b"), "a=b")
    }

    func testExportSanitizesFormulaCellsWhenEnabled() throws {
        let (doc, path) = try openIndexed("name,note\nAlice,=SUM(A1:A9)\nBob,+2\n")
        let out = try temporaryPath()
        defer {
            try? FileManager.default.removeItem(atPath: path)
            try? FileManager.default.removeItem(atPath: out)
        }

        try doc.exportCurrentView(to: out, format: .csv, sanitizeFormulas: true, cancellation: CancellationFlag())
        let csv = try String(contentsOfFile: out, encoding: .utf8)
        XCTAssertTrue(csv.contains("'=SUM(A1:A9)"), csv)
        XCTAssertTrue(csv.contains("'+2"), csv)
    }

    func testExportLeavesFormulaCellsWhenDisabled() throws {
        let (doc, path) = try openIndexed("name,note\nAlice,=SUM(A1:A9)\n")
        let out = try temporaryPath()
        defer {
            try? FileManager.default.removeItem(atPath: path)
            try? FileManager.default.removeItem(atPath: out)
        }

        try doc.exportCurrentView(to: out, format: .csv, cancellation: CancellationFlag())
        let csv = try String(contentsOfFile: out, encoding: .utf8)
        XCTAssertTrue(csv.contains("=SUM(A1:A9)"), csv)
        XCTAssertFalse(csv.contains("'=SUM(A1:A9)"), "sanitization is off by default")
    }

    private func openIndexed(_ content: String) throws -> (VirtualCsvDocument, String) {
        let path = try temporaryPath()
        try content.data(using: .utf8)!.write(to: URL(fileURLWithPath: path))
        let doc = try VirtualCsvDocument.open(path: path)
        try doc.runIndexing(progress: { _ in }, cancellation: CancellationFlag())
        return (doc, path)
    }
}
