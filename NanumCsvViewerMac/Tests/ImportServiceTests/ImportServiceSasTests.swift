import Foundation
import XCTest
@testable import ImportService
import ImportServiceProtocol

final class ImportServiceSasTests: XCTestCase {
    func testServiceRoutesSasKindToReadStatReader() throws {
        let fixture = try XCTUnwrap(Bundle.module.url(forResource: "nanum-fixture", withExtension: "sas7bdat"))
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
            kind: .sas7bdat,
            limits: ImportLimits(maxBytes: 256 * 1024, maxRows: 10, maxColumns: 10, maxCells: 100, timeoutSeconds: 5),
            outputFile: ImportFileReference(fileHandle: output),
            metadataFile: nil,
            outputURL: outputURL
        ) { result, error in
            XCTAssertNil(error)
            XCTAssertEqual(result?.rowCount, 2)
            XCTAssertEqual(result?.columnCount, 5)
            XCTAssertEqual(result?.warnings.map(\.code), ["sas-best-effort"])
            XCTAssertNotNil(result?.metadataURL)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1)
    }

    func testServiceReportsTypedErrorForOversizedSas() throws {
        let fixture = try XCTUnwrap(Bundle.module.url(forResource: "nanum-fixture", withExtension: "sas7bdat"))
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
            kind: .sas7bdat,
            limits: ImportLimits(maxBytes: 8, maxRows: 10, maxColumns: 10, maxCells: 100, timeoutSeconds: 5),
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
            .appendingPathComponent("import-service-sas-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
