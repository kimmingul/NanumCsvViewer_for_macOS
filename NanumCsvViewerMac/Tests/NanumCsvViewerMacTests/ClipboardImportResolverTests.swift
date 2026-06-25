import Foundation
import XCTest
@testable import NanumCsvViewerMac

final class ClipboardImportResolverTests: XCTestCase {
    func testResolvesExistingFilePathBeforeInlineCsvText() throws {
        let path = NSTemporaryDirectory() + "nanumcsv_clipboard_\(UUID().uuidString).csv"
        try "a,b\n1,2\n".data(using: .utf8)!.write(to: URL(fileURLWithPath: path))
        defer { try? FileManager.default.removeItem(atPath: path) }

        let result = try ClipboardImportResolver.resolve(text: "  \(path)\n")

        XCTAssertEqual(result, .existingFile(URL(fileURLWithPath: path)))
    }

    func testResolvesFileUrlBeforeInlineCsvText() throws {
        let path = NSTemporaryDirectory() + "nanumcsv_clipboard_url_\(UUID().uuidString).csv"
        try "a,b\n1,2\n".data(using: .utf8)!.write(to: URL(fileURLWithPath: path))
        defer { try? FileManager.default.removeItem(atPath: path) }

        let result = try ClipboardImportResolver.resolve(text: URL(fileURLWithPath: path).absoluteString)

        XCTAssertEqual(result, .existingFile(URL(fileURLWithPath: path)))
    }

    func testWritesInlineClipboardTextToTemporaryCsvFile() throws {
        let result = try ClipboardImportResolver.resolve(text: "name,city\nAlice,Seoul\n")
        guard case let .createdFile(url) = result else {
            return XCTFail("Expected a created clipboard CSV file")
        }
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertEqual(url.pathExtension, "csv")
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "name,city\nAlice,Seoul\n")
    }

    func testRejectsBlankClipboardText() {
        XCTAssertThrowsError(try ClipboardImportResolver.resolve(text: " \n\t ")) { error in
            XCTAssertEqual(error as? ClipboardImportResolver.ImportError, .emptyClipboardText)
        }
    }
}
