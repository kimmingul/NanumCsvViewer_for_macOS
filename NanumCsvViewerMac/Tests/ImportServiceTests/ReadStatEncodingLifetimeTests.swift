import Foundation
import XCTest
@testable import ImportService
import ImportServiceProtocol

/// `readstat_set_handler_character_encoding` stores the pointer it is given without
/// copying, so a Swift string literal — whose bridged C buffer only lives for the
/// duration of the call — left `parser->output_encoding` dangling. The parse then
/// failed inside `iconv_open` with READSTAT_ERROR_UNSUPPORTED_CHARSET whenever the
/// bytes at that address no longer spelled a charset name.
///
/// The failure is all-or-nothing per process: whether the freed buffer still holds
/// "UTF-8" depends on the process's allocation pattern, so a run either failed every
/// import or none of them. Detection is therefore probabilistic, not guaranteed —
/// reverting the fix makes these tests fail in roughly 2 runs out of 12, so treat a
/// single green run as weak evidence. The stronger check is the rate across many
/// runs: before the fix `swift test --filter ImportServiceTests` failed 5 times in
/// 20, after it 0 times in 20.
final class ReadStatEncodingLifetimeTests: XCTestCase {
    private func fixture(_ ext: String) throws -> URL {
        try XCTUnwrap(Bundle.module.url(forResource: "nanum-fixture", withExtension: ext))
    }

    private func temporaryDirectory() throws -> URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("readstat-encoding-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// Churn the allocator so a dangling encoding pointer is likely to be overwritten.
    private func churnHeap() {
        var scratch: [String] = []
        for i in 0..<512 {
            scratch.append("charset-scratch-\(i)-\(UUID().uuidString)")
        }
        scratch.removeAll()
    }

    private func assertRepeatedImportsSucceed(
        extension ext: String,
        importer: (FileHandle, FileHandle, URL, ImportLimits) throws -> ImportResult
    ) throws {
        let source = try fixture(ext)
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        for attempt in 1...12 {
            churnHeap()
            let handle = try FileHandle(forReadingFrom: source)
            defer { try? handle.close() }
            let outputURL = directory.appendingPathComponent("import-\(attempt).csv")
            FileManager.default.createFile(atPath: outputURL.path, contents: nil)
            let output = try FileHandle(forWritingTo: outputURL)
            defer { try? output.close() }

            let limits = ImportLimits(maxBytes: 256 * 1024, maxRows: 10, maxColumns: 10,
                                      maxCells: 100, timeoutSeconds: 5)
            let result = try importer(handle, output, outputURL, limits)
            XCTAssertEqual(result.rowCount, 2, "attempt \(attempt) read the wrong row count")
            XCTAssertEqual(result.columnCount, 5, "attempt \(attempt) read the wrong column count")
        }
    }

    func testRepeatedSavImportsAllSucceed() throws {
        try assertRepeatedImportsSucceed(extension: "sav") { handle, output, url, limits in
            try SavReader.exportToCsv(
                source: handle, output: output, metadataOutput: nil, outputURL: url, limits: limits
            )
        }
    }

    func testRepeatedSas7bdatImportsAllSucceed() throws {
        try assertRepeatedImportsSucceed(extension: "sas7bdat") { handle, output, url, limits in
            try Sas7bdatReader.exportToCsv(
                source: handle, output: output, metadataOutput: nil, outputURL: url, limits: limits
            )
        }
    }
}
