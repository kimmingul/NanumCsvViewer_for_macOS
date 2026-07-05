import Foundation
import XCTest
@testable import CsvCore

final class StreamingAnalyticsTests: XCTestCase {
    private func openIndexed(_ content: String) throws -> (VirtualCsvDocument, String) {
        let path = (NSTemporaryDirectory() as NSString).appendingPathComponent("stream-\(UUID().uuidString).csv")
        try content.data(using: .utf8)!.write(to: URL(fileURLWithPath: path))
        let doc = try VirtualCsvDocument.open(path: path)
        try doc.runIndexing(progress: { _ in }, cancellation: CancellationFlag())
        return (doc, path)
    }

    func testForEachDisplayRowStreamsCurrentViewInOrder() throws {
        let (doc, path) = try openIndexed("a,b\n1,x\n2,y\n3,z\n")
        defer { try? FileManager.default.removeItem(atPath: path) }
        try doc.applyFilter({ $0.count > 1 && $0[1] != "y" }, progress: nil, cancellation: CancellationFlag())

        var seen: [[String]] = []
        try doc.forEachDisplayRow(cancellation: CancellationFlag()) { seen.append($0) }
        XCTAssertEqual(seen, [["1", "x"], ["3", "z"]], "streams the filtered view in display order")
    }

    func testProjectedDisplayRowsKeepsOnlyRequestedColumns() throws {
        let (doc, path) = try openIndexed("a,b,c,d\n1,2,3,4\n5,6,7,8\n")
        defer { try? FileManager.default.removeItem(atPath: path) }

        let projected = try doc.projectedDisplayRows(columns: [3, 1], cancellation: CancellationFlag())
        XCTAssertEqual(projected.rows, [["4", "2"], ["8", "6"]])
        XCTAssertEqual(projected.indexMap[3], 0)
        XCTAssertEqual(projected.indexMap[1], 1)
    }

    // The projection/remap must NOT leak projected column positions into the
    // result metadata — reports look up column names by these indices.
    func testGroupByResultCarriesOriginalColumnIndices() throws {
        let (doc, path) = try openIndexed("region,segment,amount\nA,x,10\nA,y,20\nB,x,30\n")
        defer { try? FileManager.default.removeItem(atPath: path) }

        let result = try doc.groupBy(groupColumns: [0], valueColumn: 2, functions: [.sum], cancellation: CancellationFlag())
        XCTAssertEqual(result.groupColumns, [0], "original group column index preserved")
        XCTAssertEqual(result.valueColumn, 2, "original value column index preserved")
        let byKey = Dictionary(uniqueKeysWithValues: result.rows.map { ($0.key, $0.values[.sum]) })
        XCTAssertEqual(byKey[["A"]], 30)
        XCTAssertEqual(byKey[["B"]], 30)
    }

    func testDateHistogramResultCarriesOriginalColumnIndices() throws {
        let (doc, path) = try openIndexed("label,when,amount\na,2026-01-05,10\nb,2026-01-20,20\nc,2026-02-03,30\n")
        defer { try? FileManager.default.removeItem(atPath: path) }

        let result = try doc.dateHistogram(dateColumn: 1, valueColumn: 2, period: .month, cancellation: CancellationFlag())
        XCTAssertEqual(result.dateColumn, 1, "original date column index preserved (reports name columns by this)")
        XCTAssertEqual(result.valueColumn, 2)
        XCTAssertEqual(result.bins.map(\.count).reduce(0, +), 3)
    }

    func testPivotResultCarriesOriginalColumnIndices() throws {
        let (doc, path) = try openIndexed("region,segment,amount\nA,x,10\nA,y,20\nB,x,30\n")
        defer { try? FileManager.default.removeItem(atPath: path) }

        let result = try doc.pivotTable(
            rowColumns: [0],
            columnColumns: [1],
            valueColumn: 2,
            function: .sum,
            cancellation: CancellationFlag()
        )
        XCTAssertEqual(result.rowColumns, [0])
        XCTAssertEqual(result.columnColumns, [1])
        XCTAssertEqual(result.valueColumn, 2)
        XCTAssertEqual(result.value(row: ["A"], column: ["x"]), 10)
        XCTAssertEqual(result.value(row: ["A"], column: ["y"]), 20)
        XCTAssertEqual(result.value(row: ["B"], column: ["x"]), 30)
    }

    func testStreamingResultsMatchAcrossFilteredView() throws {
        let (doc, path) = try openIndexed("g,v\nA,1\nB,2\nA,3\nB,4\nA,5\n")
        defer { try? FileManager.default.removeItem(atPath: path) }
        try doc.applyFilter({ $0.first == "A" }, progress: nil, cancellation: CancellationFlag())

        let stats = try doc.descriptiveStatistics(column: 1, cancellation: CancellationFlag())
        XCTAssertEqual(stats.count, 3, "analytics run over the filtered view only")
        let corr = try doc.correlation(xColumn: 1, yColumn: 1, method: .pearson, cancellation: CancellationFlag())
        XCTAssertEqual(corr.sampleSize, 3)
    }

    func testForEachDisplayRowThrowsOnCancellation() throws {
        let (doc, path) = try openIndexed("a\n1\n2\n3\n")
        defer { try? FileManager.default.removeItem(atPath: path) }
        let cancellation = CancellationFlag()
        cancellation.cancel()
        XCTAssertThrowsError(try doc.forEachDisplayRow(cancellation: cancellation) { _ in }) { error in
            guard case CsvError.cancelled = error else { return XCTFail("expected cancelled, got \(error)") }
        }
    }
}
