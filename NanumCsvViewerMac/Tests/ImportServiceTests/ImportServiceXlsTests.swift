import Foundation
import XCTest
@testable import ImportService
import ImportServiceProtocol

final class ImportServiceXlsTests: XCTestCase {
    func testServiceRoutesXlsKindToBiffReader() throws {
        let fixture = try XCTUnwrap(Bundle.module.url(forResource: "iris-excel-xls", withExtension: "xls"))
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let source = try FileHandle(forReadingFrom: fixture)
        defer { try? source.close() }
        let outputURL = directory.appendingPathComponent("import.csv")
        FileManager.default.createFile(atPath: outputURL.path, contents: nil)
        let output = try FileHandle(forWritingTo: outputURL)
        defer { try? output.close() }

        let expectation = expectation(description: "reply")
        ImportService().importFile(
            sourceFile: ImportFileReference(fileHandle: source),
            kind: .xls,
            limits: ImportLimits(maxBytes: 64 * 1024, maxRows: 200, maxColumns: 8, maxCells: 2_000, timeoutSeconds: 5),
            outputFile: ImportFileReference(fileHandle: output),
            metadataFile: nil,
            outputURL: outputURL
        ) { result, error in
            XCTAssertNil(error)
            XCTAssertEqual(result?.rowCount, 151)
            XCTAssertEqual(result?.columnCount, 5)
            XCTAssertEqual(try? String(contentsOf: outputURL, encoding: .utf8).split(separator: "\n").first, "Sepal.Length,Sepal.Width,Petal.Length,Petal.Width,Species")
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1)
    }

    func testServiceReportsTypedErrorForOversizedXls() throws {
        let fixture = try XCTUnwrap(Bundle.module.url(forResource: "iris-excel-xls", withExtension: "xls"))
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let source = try FileHandle(forReadingFrom: fixture)
        defer { try? source.close() }
        let outputURL = directory.appendingPathComponent("import.csv")
        FileManager.default.createFile(atPath: outputURL.path, contents: nil)
        let output = try FileHandle(forWritingTo: outputURL)
        defer { try? output.close() }

        let expectation = expectation(description: "reply")
        ImportService().importFile(
            sourceFile: ImportFileReference(fileHandle: source),
            kind: .xls,
            limits: ImportLimits(maxBytes: 1024, maxRows: 200, maxColumns: 8, maxCells: 2_000, timeoutSeconds: 5),
            outputFile: ImportFileReference(fileHandle: output),
            metadataFile: nil,
            outputURL: outputURL
        ) { result, error in
            XCTAssertNil(result)
            XCTAssertEqual(error?.code, "maxBytesExceeded")
            XCTAssertEqual(try? Data(contentsOf: outputURL).count, 0)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1)
    }

    private func temporaryDirectory() throws -> URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("import-service-xls-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
