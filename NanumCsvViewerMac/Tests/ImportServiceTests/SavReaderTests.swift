import CsvCore
import Foundation
import XCTest
@testable import ImportService
import ImportServiceProtocol

final class SavReaderTests: XCTestCase {
    func testExportsSavToCsvAndMetadataSidecar() throws {
        let fixture = try fixtureURL("nanum-fixture", ext: "sav")
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let outputURL = directory.appendingPathComponent("fixture.csv")
        FileManager.default.createFile(atPath: outputURL.path, contents: nil)

        let source = try FileHandle(forReadingFrom: fixture)
        defer { try? source.close() }
        let output = try FileHandle(forWritingTo: outputURL)
        defer { try? output.close() }

        let result = try SavReader.exportToCsv(
            source: source,
            output: output,
            outputURL: outputURL,
            limits: ImportLimits(maxBytes: 256 * 1024, maxRows: 10, maxColumns: 10, maxCells: 100, timeoutSeconds: 5)
        )

        XCTAssertEqual(result.rowCount, 2)
        XCTAssertEqual(result.columnCount, 5)
        XCTAssertNotNil(result.metadataURL)
        XCTAssertEqual(
            try String(contentsOf: outputURL, encoding: .utf8),
            "status,income,ratio,score,name\n1,1234.5,0.25,120000,Alice\n2,,0.5,250000,Bob"
        )

        let metadataURL = try XCTUnwrap(result.metadataURL)
        let metadata = try JSONDecoder().decode(ImportMetadata.self, from: Data(contentsOf: metadataURL))
        XCTAssertEqual(metadata.rowCount, 2)
        XCTAssertEqual(metadata.encoding, "UTF-8")
        XCTAssertEqual(metadata.columns.map(\.name), ["status", "income", "ratio", "score", "name"])
        XCTAssertEqual(metadata.columns[0].label, "Employment status")
        XCTAssertEqual(metadata.columns[0].declaredType, .ordinal)
        XCTAssertEqual(metadata.columns[0].valueLabels["2"], "Part time")
        XCTAssertEqual(metadata.columns[1].declaredType, .currency)
        XCTAssertEqual(metadata.columns[2].declaredType, .percent)
        XCTAssertEqual(metadata.columns[3].declaredType, .scientific)
        XCTAssertEqual(metadata.columns[4].declaredType, .categorical)
        XCTAssertEqual(metadata.columnTypeOverrides()[0], .categorical)
        XCTAssertEqual(metadata.columnTypeOverrides()[1], .float)
    }

    func testExportsCompressedZSavFixture() throws {
        let fixture = try fixtureURL("nanum-fixture", ext: "zsav")
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let outputURL = directory.appendingPathComponent("fixture.csv")
        FileManager.default.createFile(atPath: outputURL.path, contents: nil)
        let source = try FileHandle(forReadingFrom: fixture)
        defer { try? source.close() }
        let output = try FileHandle(forWritingTo: outputURL)
        defer { try? output.close() }

        let result = try SavReader.exportToCsv(
            source: source,
            output: output,
            outputURL: outputURL,
            limits: ImportLimits(maxBytes: 256 * 1024, maxRows: 10, maxColumns: 10, maxCells: 100, timeoutSeconds: 5)
        )

        XCTAssertEqual(result.rowCount, 2)
        XCTAssertEqual(try String(contentsOf: outputURL, encoding: .utf8).split(separator: "\n").count, 3)
    }

    func testRejectsSavOverByteLimitBeforeParsingAndTruncatesOutput() throws {
        let fixture = try fixtureURL("nanum-fixture", ext: "sav")
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let outputURL = directory.appendingPathComponent("limited.csv")
        try Data("stale".utf8).write(to: outputURL)
        let source = try FileHandle(forReadingFrom: fixture)
        defer { try? source.close() }
        let output = try FileHandle(forWritingTo: outputURL)
        defer { try? output.close() }

        XCTAssertThrowsError(try SavReader.exportToCsv(
            source: source,
            output: output,
            outputURL: outputURL,
            limits: ImportLimits(maxBytes: 8, maxRows: 10, maxColumns: 10, maxCells: 100, timeoutSeconds: 5)
        )) { error in
            XCTAssertEqual(error as? SavReader.Error, .maxBytesExceeded)
        }
        XCTAssertEqual(try Data(contentsOf: outputURL).count, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: outputURL.appendingPathExtension("metadata.json").path))
    }

    func testMalformedSavFailsClosedWithoutCsvOrMetadata() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let fixture = directory.appendingPathComponent("malformed.sav")
        try Data("$FL2not-a-real-sav".utf8).write(to: fixture)
        let outputURL = directory.appendingPathComponent("malformed.csv")
        try Data("stale".utf8).write(to: outputURL)
        let source = try FileHandle(forReadingFrom: fixture)
        defer { try? source.close() }
        let output = try FileHandle(forWritingTo: outputURL)
        defer { try? output.close() }

        XCTAssertThrowsError(try SavReader.exportToCsv(
            source: source,
            output: output,
            outputURL: outputURL,
            limits: ImportLimits(maxBytes: 256 * 1024, maxRows: 10, maxColumns: 10, maxCells: 100, timeoutSeconds: 5)
        )) { error in
            guard case SavReader.Error.parseFailed = error else {
                return XCTFail("Expected parseFailed, got \(error)")
            }
        }
        XCTAssertEqual(try Data(contentsOf: outputURL).count, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: outputURL.appendingPathExtension("metadata.json").path))
    }

    private func fixtureURL(_ name: String, ext: String) throws -> URL {
        try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: ext))
    }

    private func temporaryDirectory() throws -> URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("sav-reader-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
