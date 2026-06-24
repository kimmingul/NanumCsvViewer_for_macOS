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

    func testFutureRowReadBeforeIndexingDoesNotPoisonCache() throws {
        let path = try temporaryPath()
        let rows = (0..<2_000).map { "r\($0),v\($0)" }.joined(separator: "\n")
        try ("name,value\n" + rows + "\n").data(using: .utf8)!.write(to: URL(fileURLWithPath: path))
        defer { try? FileManager.default.removeItem(atPath: path) }

        let doc = try VirtualCsvDocument.open(path: path)

        XCTAssertEqual(try doc.getDisplayRow(1_234), [""])
        XCTAssertEqual(try doc.getDataRow(1_234), [""])

        try doc.runIndexing(progress: { _ in }, cancellation: CancellationFlag())

        XCTAssertEqual(try doc.getDisplayRow(1_234), ["r1234", "v1234"])
        XCTAssertEqual(try doc.getDataRowUncached(1_234), ["r1234", "v1234"])
    }

    func testSimpleIndexingDoesNotCreateBlankRowWhenCrLfSplitsAtReadUnitBoundary() throws {
        let prefix = "col\n"
        let paddingCount = MemoryFileBuffer.chunkSize - prefix.utf8.count - 1
        let paddedRow = String(repeating: "a", count: paddingCount)
        let content = prefix + paddedRow + "\r\nsecond\n"
        let (doc, path) = try openIndexed(content)
        defer { try? FileManager.default.removeItem(atPath: path) }

        XCTAssertEqual(doc.dataRowsAvailable, 2)
        XCTAssertEqual(doc.displayRowCount, 2)
        XCTAssertEqual(try doc.getDisplayRow(0), [paddedRow])
        XCTAssertEqual(try doc.getDisplayRow(1), ["second"])
    }

    func testHeaderWithUnclosedQuoteDoesNotSwallowPhysicalRows() throws {
        let swallowedRows = (1...19).map { "r\($0),v\($0)" }.joined(separator: "\n")
        let content = "\"name,value\n" + swallowedRows + "\n\"r20\",v20\nr21,v21\n"
        let (doc, path) = try openIndexed(content)
        defer { try? FileManager.default.removeItem(atPath: path) }

        XCTAssertEqual(doc.header, ["name", "value"])
        XCTAssertEqual(doc.dataRowsAvailable, 21)
        XCTAssertEqual(try doc.getDisplayRow(0), ["r1", "v1"])
        XCTAssertEqual(try doc.getDisplayRow(19), ["r20", "v20"])
        XCTAssertEqual(try doc.getDisplayRow(20), ["r21", "v21"])
    }

    func testValidQuotedNewlineDataRecordRemainsSingleRow() throws {
        let (doc, path) = try openIndexed("name,note\nAlice,\"hello\nworld\"\nBob,plain\n")
        defer { try? FileManager.default.removeItem(atPath: path) }

        XCTAssertEqual(doc.dataRowsAvailable, 2)
        XCTAssertEqual(try doc.getDisplayRow(0), ["Alice", "hello\nworld"])
        XCTAssertEqual(try doc.getDisplayRow(1), ["Bob", "plain"])
    }

    func testMalformedHeaderRecoveryKeepsLaterQuotedNewlineRecordTogether() throws {
        let swallowedRows = (1...5).map { "r\($0),plain" }.joined(separator: "\n")
        let content = "\"name,note\n" + swallowedRows + "\n\"r6\",plain\nAlice,\"hello\nworld\"\nBob,plain\n"
        let (doc, path) = try openIndexed(content)
        defer { try? FileManager.default.removeItem(atPath: path) }

        XCTAssertEqual(doc.dataRowsAvailable, 8)
        XCTAssertEqual(try doc.getDisplayRow(0), ["r1", "plain"])
        XCTAssertEqual(try doc.getDisplayRow(5), ["r6", "plain"])
        XCTAssertEqual(try doc.getDisplayRow(6), ["Alice", "hello\nworld"])
        XCTAssertEqual(try doc.getDisplayRow(7), ["Bob", "plain"])
    }

    func testRepeatedSmallFileGridReadsNeverReturnBlankRows() throws {
        let path = try temporaryPath()
        let rows = (0..<300).map { index in
            let payload = String(format: "payload-%03d-abcdefghijklmnopqrstuvwxyz", index)
            return String(format: "r%03d,%@,%03d", index, payload, index)
        }
        try ("id,payload,n\n" + rows.joined(separator: "\n") + "\n").data(using: .utf8)!.write(to: URL(fileURLWithPath: path))
        defer { try? FileManager.default.removeItem(atPath: path) }

        for iteration in 0..<80 {
            let doc = try VirtualCsvDocument.open(path: path)
            try doc.runIndexing(progress: { _ in }, cancellation: CancellationFlag())

            XCTAssertEqual(doc.displayRowCount, rows.count, "iteration \(iteration)")
            for row in 0..<doc.displayRowCount {
                let fields = try doc.getDisplayRow(row)
                XCTAssertEqual(fields.first, String(format: "r%03d", row), "iteration \(iteration), row \(row), fields \(fields)")
                XCTAssertNotEqual(fields, [""], "iteration \(iteration), row \(row)")
            }
        }
    }

    func testColumnStatisticsInfersTypesAndSummariesFromSample() throws {
        let (doc, path) = try openIndexed("""
        id,age,score,enrolled,visit_date,site
        1,42,10.5,true,2026-01-02,A
        2,,11.5,false,2026-01-03,A
        3,65,9.0,true,2026-01-04,B
        4,65,12.0,true,,B

        """)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let stats = try doc.analyzeColumns(sampleLimit: 5, cancellation: CancellationFlag())

        XCTAssertEqual(stats.rowSampleCount, 4)
        XCTAssertEqual(stats.columns[1].inferredType, .integer)
        XCTAssertEqual(stats.columns[1].nullCount, 1)
        XCTAssertEqual(stats.columns[1].nonNullCount, 3)
        XCTAssertEqual(stats.columns[1].uniqueCount, 2)
        XCTAssertEqual(stats.columns[1].numeric?.min, 42)
        XCTAssertEqual(stats.columns[1].numeric?.max, 65)
        XCTAssertEqual(stats.columns[1].numeric?.median, 65)
        XCTAssertEqual(stats.columns[2].inferredType, .float)
        XCTAssertEqual(stats.columns[3].inferredType, .boolean)
        XCTAssertEqual(stats.columns[4].inferredType, .date)
        XCTAssertEqual(stats.columns[5].inferredType, .categorical)
        XCTAssertEqual(stats.columns[5].topValues.first?.value, "A")
        XCTAssertEqual(stats.columns[5].topValues.first?.count, 2)
    }

    func testExpressionFilterSupportsComparisonContainsAndBooleanLogic() throws {
        let (doc, path) = try openIndexed("""
        name,age,sex,note
        Alice,70,F,positive response
        Bob,55,M,negative
        Chris,72,M,positive response
        Dana,40,F,pending

        """)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let filter = try AdvancedFilterExpression.compile(#"age > 65 AND sex == "M" AND note contains "positive""#, headers: doc.header)
        try doc.applyFilter(filter.predicate, progress: nil, cancellation: CancellationFlag())

        XCTAssertEqual(doc.displayRowCount, 1)
        XCTAssertEqual(try doc.getDisplayRow(0)[0], "Chris")
        XCTAssertEqual(doc.getSourceRowNumber(0), 3)
    }

    func testDisplayIndexForSourceRowFindsRowsAfterFiltering() throws {
        let (doc, path) = try openIndexed("name,city\nAlice,NY\nBob,LA\nCarol,NY\n")
        defer { try? FileManager.default.removeItem(atPath: path) }

        try doc.applyFilter({ $0.count > 1 && $0[1] == "NY" }, progress: nil, cancellation: CancellationFlag())

        XCTAssertEqual(doc.displayIndexForSourceRowNumber(3), 1)
        XCTAssertNil(doc.displayIndexForSourceRowNumber(2))
        XCTAssertNil(doc.displayIndexForSourceRowNumber(0))
    }

    func testExportsCurrentFilteredSortedViewAsCsv() throws {
        let (doc, path) = try openIndexed("name,city,note\nAlice,NY,\"hello, world\"\nBob,LA,plain\nCarol,NY,\"quoted \"\"value\"\"\"\n")
        let exportPath = try temporaryPath()
        defer {
            try? FileManager.default.removeItem(atPath: path)
            try? FileManager.default.removeItem(atPath: exportPath)
        }

        try doc.filterColumnContains(column: 1, term: "NY", withinCurrentView: false, progress: nil, cancellation: CancellationFlag())
        try doc.sort(column: 0, ascending: false, progress: nil, cancellation: CancellationFlag())
        try doc.exportCurrentView(to: exportPath, selectedColumns: [0, 2], cancellation: CancellationFlag())

        let exported = try String(contentsOfFile: exportPath, encoding: .utf8)
        XCTAssertEqual(exported, "name,note\nCarol,\"quoted \"\"value\"\"\"\nAlice,\"hello, world\"\n")
    }

    func testPersistentIndexSidecarLoadsReopenedFile() throws {
        let path = try temporaryPath()
        try "name,city\nAlice,NY\nBob,LA\n".data(using: .utf8)!.write(to: URL(fileURLWithPath: path))
        defer {
            try? FileManager.default.removeItem(atPath: path)
            try? FileManager.default.removeItem(atPath: path + ".ncvidx")
        }

        let first = try VirtualCsvDocument.open(path: path)
        XCTAssertFalse(first.indexingComplete)
        try first.runIndexing(progress: { _ in }, cancellation: CancellationFlag())
        try waitForFile(atPath: path + ".ncvidx")
        let sidecarPrefix = try Data(contentsOf: URL(fileURLWithPath: path + ".ncvidx")).prefix(13)
        XCTAssertEqual(String(data: sidecarPrefix, encoding: .utf8), "NanumCsvIdx2\n")

        let second = try VirtualCsvDocument.open(path: path)
        XCTAssertTrue(second.indexingComplete)
        XCTAssertEqual(second.dataRowsAvailable, 2)
        XCTAssertEqual(try second.getDisplayRow(1), ["Bob", "LA"])
    }

    func testIndexProgressCanOverrideDisplayedPercent() {
        let progress = IndexProgress(bytesProcessed: 10, fileLength: 100, rowsSoFar: 0, percentOverride: 75)
        XCTAssertEqual(progress.percent, 75)
    }
}

func temporaryPath() throws -> String {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
    return directory.appendingPathComponent("nanumcsv_swift_\(UUID().uuidString).csv").path
}

func waitForFile(atPath path: String, timeout: TimeInterval = 2.0) throws {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if FileManager.default.fileExists(atPath: path) {
            return
        }
        Thread.sleep(forTimeInterval: 0.01)
    }
    XCTFail("Timed out waiting for file at \(path)")
}
