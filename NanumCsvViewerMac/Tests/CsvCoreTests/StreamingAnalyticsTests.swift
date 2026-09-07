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

    func testExactPivotFilterUsesTheSameNullGroupAsPivotKeys() throws {
        let result = try CsvAnalytics.pivotTable(
            rows: [["", "2"], ["NA", "3"], ["A", "5"]],
            rowColumns: [0], columnColumns: [], valueColumn: 1, function: .sum,
            filters: [PivotFilter(column: 0, selectedValue: "")]
        )
        XCTAssertEqual(result.rowKeys, [["null"]])
        XCTAssertEqual(result.value(row: ["null"], column: []), 5)
    }

    func testLargeFilterSelectionHasCompactDescriptionWithoutChangingPredicate() {
        let state = ColumnFilterState(filters: [
            .selectedValues(column: 0, values: Set((0..<100_000).map { "category-\($0)" }), includeBlanks: true)
        ])
        let description = state.descriptions(columnNames: ["category"], blankLabel: "(Blank)").joined()
        XCTAssertLessThan(description.count, 100)
        let predicate = state.predicate()
        XCTAssertTrue(predicate(["category-99999"]))
        XCTAssertTrue(predicate([""]))
        XCTAssertFalse(predicate(["outside-selection"]))
    }

    func testPivotRejectsWideAndSparseDenseResultsBeforeExpansion() throws {
        let wide = (0...PivotResourceLimits.maximumColumns).map { ["r", "c\($0)", "1"] }
        XCTAssertThrowsError(try CsvAnalytics.pivotTable(
            rows: wide, rowColumns: [0], columnColumns: [1], valueColumn: 2, function: .sum
        )) { XCTAssertEqual($0 as? CsvResourceLimitError, .pivotDimensions) }

        // Only 4,000 occupied cells, but more than one million displayed cells.
        let sparse = (0..<4_000).map { ["r\($0)", "c\($0 % 256)", "1"] }
        XCTAssertThrowsError(try CsvAnalytics.pivotTable(
            rows: sparse, rowColumns: [0], columnColumns: [1], valueColumn: 2, function: .count
        )) { XCTAssertEqual($0 as? CsvResourceLimitError, .pivotDimensions) }
    }

    func testPivotRowBoundaryAndFilteringBeforeResourceCheck() throws {
        let rows = (0...PivotResourceLimits.maximumRows).map { ["r\($0)", "1"] }
        let allowed = try CsvAnalytics.pivotTable(
            rows: Array(rows.dropLast()), rowColumns: [0], columnColumns: [],
            valueColumn: 1, function: .sum
        )
        XCTAssertEqual(allowed.value(row: ["r99999"], column: []), 1)
        XCTAssertThrowsError(try CsvAnalytics.pivotTable(
            rows: rows, rowColumns: [0], columnColumns: [], valueColumn: 1, function: .sum
        )) { XCTAssertEqual($0 as? CsvResourceLimitError, .pivotDimensions) }
        let filtered = try CsvAnalytics.pivotTable(
            rows: rows, rowColumns: [0], columnColumns: [], valueColumn: 1, function: .sum,
            filters: [PivotFilter(column: 0, selectedValue: "r100000")]
        )
        XCTAssertEqual(filtered.rowKeys, [["r100000"]])
        XCTAssertEqual(filtered.value(row: ["r100000"], column: []), 1)
    }

    func testStreamingPivotPreservesAllAggregationsAndCurrentView() throws {
        let (doc, path) = try openIndexed("group,value\nA,2\nA,4\nA,4\nA,6\nA,bad\nA,\nB,100\n")
        defer { try? FileManager.default.removeItem(atPath: path) }
        try doc.filterColumnEquals(column: 0, value: "A", withinCurrentView: false, progress: nil, cancellation: CancellationFlag())
        let expected: [AggregationFunction: Double] = [
            .count: 6, .sum: 16, .mean: 4, .median: 4,
            .min: 2, .max: 6, .uniqueCount: 5, .standardDeviation: sqrt(2)
        ]
        for function in AggregationFunction.allCases {
            let result = try doc.pivotTable(
                rowColumns: [0], columnColumns: [], valueColumn: 1,
                function: function, cancellation: CancellationFlag()
            )
            XCTAssertEqual(result.rowKeys, [["A"]])
            XCTAssertEqual(result.value(row: ["A"], column: []), expected[function]!, accuracy: 1e-12)
        }
    }

    func testDistinctBudgetCountsCategoriesNotRowsAndNeverReturnsPartialResult() throws {
        let (doc, path) = try openIndexed("value\nA\nA\nB\n")
        defer { try? FileManager.default.removeItem(atPath: path) }
        let values = try doc.distinctValues(
            column: 0, withinCurrentView: false, limit: nil, progress: nil,
            maximumDistinctValues: 2, cancellation: CancellationFlag()
        )
        XCTAssertEqual(values, [.init(value: "A", count: 2), .init(value: "B", count: 1)])
        XCTAssertThrowsError(try doc.distinctValues(
            column: 0, withinCurrentView: false, limit: 1, progress: nil,
            maximumDistinctValues: 1, cancellation: CancellationFlag()
        )) { XCTAssertEqual($0 as? CsvResourceLimitError, .distinctValues(1)) }
        try doc.filterColumnEquals(column: 0, value: "B", withinCurrentView: false, progress: nil, cancellation: CancellationFlag())
        XCTAssertEqual(try doc.distinctValues(
            column: 0, withinCurrentView: true, limit: nil, progress: nil,
            maximumDistinctValues: 1, cancellation: CancellationFlag()
        ), [.init(value: "B", count: 1)])
    }

    func testBoundedPivotOptionsIncludeLateCategoriesOrThrowInsteadOfSampling() throws {
        let (doc, path) = try openIndexed("value\n" + String(repeating: "A\n", count: 50_001) + "Z\n")
        defer { try? FileManager.default.removeItem(atPath: path) }
        XCTAssertEqual(try doc.pivotFilterValues(
            column: 0, dateGrouping: nil, maximumDistinctValues: 2, cancellation: CancellationFlag()
        ), ["A", "Z"])
        XCTAssertThrowsError(try doc.pivotFilterValues(
            column: 0, dateGrouping: nil, maximumDistinctValues: 1, cancellation: CancellationFlag()
        )) { XCTAssertEqual($0 as? CsvResourceLimitError, .distinctValues(1)) }
        let cancellation = CancellationFlag()
        cancellation.cancel()
        XCTAssertThrowsError(try doc.pivotFilterValues(
            column: 0, dateGrouping: nil, maximumDistinctValues: 2, cancellation: cancellation
        )) { XCTAssertTrue($0 is CsvError) }
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

    func testFrequencyFromCountsMatchesValueBasedResult() {
        let values = ["a", "b", "a", "c", "a", "b", ""]
        let fromValues = CsvStatistics.frequencyAnalysis(values: values, blankLabel: "(Blank)")
        var counts: [String: Int] = [:]
        for value in values { counts[value, default: 0] += 1 }
        let fromCounts = CsvStatistics.frequencyAnalysis(counts: counts, total: values.count, blankLabel: "(Blank)")
        XCTAssertEqual(fromCounts, fromValues, "streaming count path matches the value-list path")
    }

    func testStreamedFrequencyAnalysisCountsColumn() throws {
        let (doc, path) = try openIndexed("city\nNY\nLA\nNY\nNY\nLA\n")
        defer { try? FileManager.default.removeItem(atPath: path) }
        let result = try doc.frequencyAnalysis(column: 0, blankLabel: "(Blank)", cancellation: CancellationFlag())
        XCTAssertEqual(result.entries.first?.value, "NY")
        XCTAssertEqual(result.entries.first?.count, 3)
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
