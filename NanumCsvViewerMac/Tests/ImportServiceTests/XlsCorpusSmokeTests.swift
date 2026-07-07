import Foundation
import XCTest
@testable import ImportService
import ImportServiceProtocol

final class XlsCorpusSmokeTests: XCTestCase {
    func testUpstreamCorpusDoesNotCrashAndFailuresLeaveNoCsv() throws {
        let fixtures = try XCTUnwrap(Bundle.module.urls(forResourcesWithExtension: "xls", subdirectory: nil))
        XCTAssertGreaterThanOrEqual(fixtures.count, 30)

        for fixture in fixtures.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let directory = try temporaryDirectory()
            defer { try? FileManager.default.removeItem(at: directory) }

            let source = try FileHandle(forReadingFrom: fixture)
            defer { try? source.close() }
            let outputURL = directory.appendingPathComponent("corpus.csv")
            FileManager.default.createFile(atPath: outputURL.path, contents: nil)
            let output = try FileHandle(forWritingTo: outputURL)
            defer { try? output.close() }

            do {
                _ = try XlsBiffReader.exportFirstSheetToCsv(
                    source: source,
                    output: output,
                    outputURL: outputURL,
                    limits: ImportLimits(maxBytes: 256 * 1024, maxRows: 1_000, maxColumns: 512, maxCells: 50_000, timeoutSeconds: 5)
                )
            } catch {
                XCTAssertEqual(
                    try Data(contentsOf: outputURL).count,
                    0,
                    "Failed import left partial CSV for \(fixture.lastPathComponent): \(error)"
                )
            }
        }
    }

    private func temporaryDirectory() throws -> URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("xls-corpus-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
