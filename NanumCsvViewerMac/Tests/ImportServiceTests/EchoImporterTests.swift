import Foundation
import XCTest
@testable import ImportService
import ImportServiceProtocol

final class EchoImporterTests: XCTestCase {
    func testEchoCopiesInputBytesToDestinationCsv() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("echo-importer-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let sourceURL = directory.appendingPathComponent("source.txt")
        try Data("a,b\n1,2\n".utf8).write(to: sourceURL)

        let handle = try FileHandle(forReadingFrom: sourceURL)
        defer { try? handle.close() }
        let outputURL = directory.appendingPathComponent("echo.csv")
        FileManager.default.createFile(atPath: outputURL.path, contents: nil)
        let output = try FileHandle(forWritingTo: outputURL)
        defer { try? output.close() }

        let result = try EchoImporter.copy(
            source: handle,
            output: output,
            outputURL: outputURL,
            limits: ImportLimits(maxBytes: 64, maxRows: 10, maxColumns: 10, maxCells: 100, timeoutSeconds: 5),
        )

        XCTAssertEqual(result.csvURL.lastPathComponent, "echo.csv")
        XCTAssertEqual(try String(contentsOf: result.csvURL, encoding: .utf8), "a,b\n1,2\n")
        XCTAssertEqual(result.rowCount, 0)
        XCTAssertEqual(result.columnCount, 0)
        XCTAssertTrue(result.warnings.isEmpty)
    }

    func testEchoRejectsInputLargerThanLimit() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("echo-importer-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let sourceURL = directory.appendingPathComponent("source.txt")
        try Data("abcdef".utf8).write(to: sourceURL)

        let handle = try FileHandle(forReadingFrom: sourceURL)
        defer { try? handle.close() }
        let outputURL = directory.appendingPathComponent("echo.csv")
        FileManager.default.createFile(atPath: outputURL.path, contents: nil)
        let output = try FileHandle(forWritingTo: outputURL)
        defer { try? output.close() }

        XCTAssertThrowsError(try EchoImporter.copy(
            source: handle,
            output: output,
            outputURL: outputURL,
            limits: ImportLimits(maxBytes: 5, maxRows: 10, maxColumns: 10, maxCells: 100, timeoutSeconds: 5),
        )) { error in
            XCTAssertEqual((error as? EchoImporter.Error), .maxBytesExceeded)
        }
    }
}
