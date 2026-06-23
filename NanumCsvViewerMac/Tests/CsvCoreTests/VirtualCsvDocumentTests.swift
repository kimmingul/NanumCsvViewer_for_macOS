import Foundation
import XCTest
@testable import CsvCore

final class VirtualCsvDocumentTests: XCTestCase {
    private func openIndexed(_ content: String) throws -> (VirtualCsvDocument, String) {
        let path = try temporaryPath()
        try content.data(using: .utf8)!.write(to: URL(fileURLWithPath: path))
        let doc = try VirtualCsvDocument.open(path: path)
        try doc.runIndexing(progress: { _ in }, cancellation: CancellationFlag())
        return (doc, path)
    }

    func testReadsHeaderAndRows() throws {
        let (doc, path) = try openIndexed("name,age,city\nAlice,30,NY\nBob,25,LA\n")
        defer { try? FileManager.default.removeItem(atPath: path) }

        XCTAssertEqual(doc.header, ["name", "age", "city"])
        XCTAssertEqual(doc.columnCount, 3)
        XCTAssertEqual(doc.dataRowsAvailable, 2)
        XCTAssertEqual(try doc.getDisplayRow(0), ["Alice", "30", "NY"])
        XCTAssertEqual(try doc.getDisplayRow(1), ["Bob", "25", "LA"])
        XCTAssertEqual(doc.getSourceRowNumber(0), 1)
    }

    func testFilterNarrowsVisibleRowsAndPreservesSourceNumbers() throws {
        let (doc, path) = try openIndexed("name,city\nAlice,NY\nBob,LA\nCarol,NY\n")
        defer { try? FileManager.default.removeItem(atPath: path) }

        try doc.applyFilter({ $0.count > 1 && $0[1] == "NY" }, progress: nil, cancellation: CancellationFlag())
        XCTAssertTrue(doc.isFiltered)
        XCTAssertEqual(doc.displayRowCount, 2)
        XCTAssertEqual(try doc.getDisplayRow(0)[0], "Alice")
        XCTAssertEqual(try doc.getDisplayRow(1)[0], "Carol")
        XCTAssertEqual(doc.getSourceRowNumber(1), 3)

        doc.clearView()
        XCTAssertFalse(doc.isFiltered)
        XCTAssertEqual(doc.displayRowCount, 3)
    }

    func testColumnEqualsFilterHandlesQuotedEscapedValues() throws {
        let (doc, path) = try openIndexed("name,note\nAlice,\"hello, world\"\nBob,\"a \"\"quoted\"\" value\"\nCarol,plain\n")
        defer { try? FileManager.default.removeItem(atPath: path) }

        try doc.filterColumnEquals(column: 1, value: "a \"quoted\" value", withinCurrentView: false, progress: nil, cancellation: CancellationFlag())

        XCTAssertEqual(doc.displayRowCount, 1)
        XCTAssertEqual(try doc.getDisplayRow(0)[0], "Bob")
        XCTAssertEqual(doc.getSourceRowNumber(0), 2)
    }

    func testColumnContainsFilterUsesSelectedColumnOnly() throws {
        let (doc, path) = try openIndexed("name,note\nAlice,\"hello, world\"\nBob,\"a \"\"quoted\"\" value\"\nCarol,plain\n")
        defer { try? FileManager.default.removeItem(atPath: path) }

        try doc.filterColumnContains(column: 1, term: "quoted", withinCurrentView: false, progress: nil, cancellation: CancellationFlag())

        XCTAssertEqual(doc.displayRowCount, 1)
        XCTAssertEqual(try doc.getDisplayRow(0)[0], "Bob")
    }

    func testNumericSortUsesValueOrderNotLexicographic() throws {
        let (doc, path) = try openIndexed("n\n2\n10\n1\n")
        defer { try? FileManager.default.removeItem(atPath: path) }

        try doc.sort(column: 0, ascending: true, progress: nil, cancellation: CancellationFlag())
        XCTAssertEqual(try doc.getDisplayRow(0)[0], "1")
        XCTAssertEqual(try doc.getDisplayRow(1)[0], "2")
        XCTAssertEqual(try doc.getDisplayRow(2)[0], "10")
    }

    func testDescendingSortReversesOrder() throws {
        let (doc, path) = try openIndexed("n\napple\ncherry\nbanana\n")
        defer { try? FileManager.default.removeItem(atPath: path) }

        try doc.sort(column: 0, ascending: false, progress: nil, cancellation: CancellationFlag())
        XCTAssertEqual([try doc.getDisplayRow(0)[0], try doc.getDisplayRow(1)[0], try doc.getDisplayRow(2)[0]], ["cherry", "banana", "apple"])
    }

    func testSortIsStableForEqualKeys() throws {
        let (doc, path) = try openIndexed("key,id\nx,1\nx,2\nx,3\n")
        defer { try? FileManager.default.removeItem(atPath: path) }

        try doc.sort(column: 0, ascending: true, progress: nil, cancellation: CancellationFlag())
        XCTAssertEqual([try doc.getDisplayRow(0)[1], try doc.getDisplayRow(1)[1], try doc.getDisplayRow(2)[1]], ["1", "2", "3"])
    }

    func testMultiColumnSortOrdersByPriority() throws {
        let (doc, path) = try openIndexed("dept,age\nB,30\nA,40\nB,20\nA,25\n")
        defer { try? FileManager.default.removeItem(atPath: path) }

        try doc.sort(keys: [SortKey(column: 0, ascending: true), SortKey(column: 1, ascending: false)], progress: nil, cancellation: CancellationFlag())
        XCTAssertEqual([try doc.getDisplayRow(0)[0], try doc.getDisplayRow(1)[0], try doc.getDisplayRow(2)[0], try doc.getDisplayRow(3)[0]], ["A", "A", "B", "B"])
        XCTAssertEqual([try doc.getDisplayRow(0)[1], try doc.getDisplayRow(1)[1], try doc.getDisplayRow(2)[1], try doc.getDisplayRow(3)[1]], ["40", "25", "30", "20"])
    }

    func testResetViewOrderRestoresFileOrderAfterSort() throws {
        let (doc, path) = try openIndexed("n\n3\n1\n2\n")
        defer { try? FileManager.default.removeItem(atPath: path) }

        try doc.sort(column: 0, ascending: true, progress: nil, cancellation: CancellationFlag())
        doc.resetViewOrder()
        XCTAssertEqual([try doc.getDisplayRow(0)[0], try doc.getDisplayRow(1)[0], try doc.getDisplayRow(2)[0]], ["3", "1", "2"])
    }
}

func temporaryPath() throws -> String {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
    return directory.appendingPathComponent("nanumcsv_swift_\(UUID().uuidString).csv").path
}
