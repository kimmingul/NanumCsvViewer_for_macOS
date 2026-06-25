import Foundation
import XCTest
@testable import CsvCore

final class CsvExportFormatTests: XCTestCase {
    func testExportsCurrentViewAsMarkdownJsonAndHtml() throws {
        let (doc, path) = try openIndexed("""
        name,city,note
        Alice,NY,hello
        Bob,LA,plain
        Carol,NY,quoted value

        """)
        let markdownPath = try temporaryPath()
        let jsonPath = try temporaryPath()
        let htmlPath = try temporaryPath()
        defer {
            try? FileManager.default.removeItem(atPath: path)
            try? FileManager.default.removeItem(atPath: markdownPath)
            try? FileManager.default.removeItem(atPath: jsonPath)
            try? FileManager.default.removeItem(atPath: htmlPath)
        }

        try doc.filterColumnContains(column: 1, term: "NY", withinCurrentView: false, progress: nil, cancellation: CancellationFlag())
        try doc.exportCurrentView(to: markdownPath, format: .markdown, selectedColumns: [0, 2], cancellation: CancellationFlag())
        try doc.exportCurrentView(to: jsonPath, format: .json, selectedColumns: [0, 2], cancellation: CancellationFlag())
        try doc.exportCurrentView(to: htmlPath, format: .html, selectedColumns: [0, 2], cancellation: CancellationFlag())

        XCTAssertEqual(try String(contentsOfFile: markdownPath, encoding: .utf8), """
        | name | note |
        | --- | --- |
        | Alice | hello |
        | Carol | quoted value |

        """)

        XCTAssertEqual(try String(contentsOfFile: jsonPath, encoding: .utf8), """
        [
          {
            "name" : "Alice",
            "note" : "hello"
          },
          {
            "name" : "Carol",
            "note" : "quoted value"
          }
        ]
        """)

        XCTAssertEqual(try String(contentsOfFile: htmlPath, encoding: .utf8), """
        <!doctype html>
        <html>
        <head><meta charset="utf-8"><title>Nanum CSV Viewer Export</title></head>
        <body>
        <table>
        <thead><tr><th>name</th><th>note</th></tr></thead>
        <tbody>
        <tr><td>Alice</td><td>hello</td></tr>
        <tr><td>Carol</td><td>quoted value</td></tr>
        </tbody>
        </table>
        </body>
        </html>
        """)
    }

    private func openIndexed(_ content: String) throws -> (VirtualCsvDocument, String) {
        let path = try temporaryPath()
        try content.data(using: .utf8)!.write(to: URL(fileURLWithPath: path))
        let doc = try VirtualCsvDocument.open(path: path)
        try doc.runIndexing(progress: { _ in }, cancellation: CancellationFlag())
        return (doc, path)
    }
}
