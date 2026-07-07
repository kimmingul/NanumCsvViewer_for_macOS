import Foundation
import XCTest
@testable import ImportService
import ImportServiceProtocol

final class XlsBiffReaderTests: XCTestCase {
    func testDetectsLegacyXlsByExtensionAndOleMagic() throws {
        let fixture = try fixtureURL("iris-excel-xls", ext: "xls")

        XCTAssertTrue(XlsBiffReader.hasXlsExtension(fixture.path))
        XCTAssertTrue(XlsBiffReader.isXlsFile(path: fixture.path))
        XCTAssertFalse(XlsBiffReader.hasXlsExtension("/tmp/workbook.xlsx"))
    }

    func testExportsFirstSheetToCsv() throws {
        let fixture = try fixtureURL("iris-excel-xls", ext: "xls")
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let source = try FileHandle(forReadingFrom: fixture)
        defer { try? source.close() }
        let outputURL = directory.appendingPathComponent("iris.csv")
        FileManager.default.createFile(atPath: outputURL.path, contents: nil)
        let output = try FileHandle(forWritingTo: outputURL)
        defer { try? output.close() }

        let result = try XlsBiffReader.exportFirstSheetToCsv(
            source: source,
            output: output,
            outputURL: outputURL,
            limits: ImportLimits(maxBytes: 64 * 1024, maxRows: 200, maxColumns: 8, maxCells: 2_000, timeoutSeconds: 5)
        )

        XCTAssertEqual(result.rowCount, 151)
        XCTAssertEqual(result.columnCount, 5)
        XCTAssertTrue(result.warnings.isEmpty)

        let rows = try String(contentsOf: outputURL, encoding: .utf8).split(separator: "\n", omittingEmptySubsequences: false)
        XCTAssertEqual(rows.count, 151)
        XCTAssertEqual(rows[0], "Sepal.Length,Sepal.Width,Petal.Length,Petal.Width,Species")
        XCTAssertEqual(rows[1], "5.1,3.5,1.4,0.2,setosa")
        XCTAssertEqual(rows[150], "5.9,3,5.1,1.8,virginica")
    }

    func testListsUtf8SheetNames() throws {
        let fixture = try fixtureURL("utf8-sheet-names", ext: "xls")
        let source = try FileHandle(forReadingFrom: fixture)
        defer { try? source.close() }

        let names = try XlsBiffReader.sheetNames(
            source: source,
            limits: ImportLimits(maxBytes: 64 * 1024, maxRows: 200, maxColumns: 8, maxCells: 2_000, timeoutSeconds: 5)
        )

        XCTAssertEqual(names, ["µ", "∂"])
    }

    func testExportsNamedSheetToCsv() throws {
        let fixture = try fixtureURL("utf8-sheet-names", ext: "xls")
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let source = try FileHandle(forReadingFrom: fixture)
        defer { try? source.close() }
        let outputURL = directory.appendingPathComponent("sheet.csv")
        FileManager.default.createFile(atPath: outputURL.path, contents: nil)
        let output = try FileHandle(forWritingTo: outputURL)
        defer { try? output.close() }

        let result = try XlsBiffReader.exportSheetToCsv(
            source: source,
            sheetName: "∂",
            output: output,
            outputURL: outputURL,
            limits: ImportLimits(maxBytes: 64 * 1024, maxRows: 200, maxColumns: 8, maxCells: 2_000, timeoutSeconds: 5)
        )

        XCTAssertEqual(result.rowCount, 2)
        XCTAssertEqual(result.columnCount, 1)
        XCTAssertEqual(try String(contentsOf: outputURL, encoding: .utf8), "x\n1")
    }

    func testRejectsWorkbookOverByteLimitBeforeParsing() throws {
        let fixture = try fixtureURL("iris-excel-xls", ext: "xls")
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let source = try FileHandle(forReadingFrom: fixture)
        defer { try? source.close() }
        let outputURL = directory.appendingPathComponent("limited.csv")
        FileManager.default.createFile(atPath: outputURL.path, contents: nil)
        let output = try FileHandle(forWritingTo: outputURL)
        defer { try? output.close() }

        XCTAssertThrowsError(try XlsBiffReader.exportFirstSheetToCsv(
            source: source,
            output: output,
            outputURL: outputURL,
            limits: ImportLimits(maxBytes: 1024, maxRows: 200, maxColumns: 8, maxCells: 2_000, timeoutSeconds: 5)
        )) { error in
            XCTAssertEqual(error as? XlsBiffReader.Error, .maxBytesExceeded)
        }
        XCTAssertEqual(try Data(contentsOf: outputURL).count, 0)
    }

    func testMalformedWorkbookFailsClosedWithoutCsvOutput() throws {
        let fixture = try fixtureURL("malformed-ole", ext: "xls")
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let source = try FileHandle(forReadingFrom: fixture)
        defer { try? source.close() }
        let outputURL = directory.appendingPathComponent("malformed.csv")
        FileManager.default.createFile(atPath: outputURL.path, contents: nil)
        let output = try FileHandle(forWritingTo: outputURL)
        defer { try? output.close() }

        XCTAssertThrowsError(try XlsBiffReader.exportFirstSheetToCsv(
            source: source,
            output: output,
            outputURL: outputURL,
            limits: ImportLimits(maxBytes: 64 * 1024, maxRows: 200, maxColumns: 8, maxCells: 2_000, timeoutSeconds: 5)
        )) { error in
            guard case XlsBiffReader.Error.parseFailed = error else {
                return XCTFail("Expected parseFailed, got \(error)")
            }
        }
        XCTAssertEqual(try Data(contentsOf: outputURL).count, 0)
    }

    private func fixtureURL(_ name: String, ext: String) throws -> URL {
        try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: ext))
    }

    private func temporaryDirectory() throws -> URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("xls-biff-reader-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
