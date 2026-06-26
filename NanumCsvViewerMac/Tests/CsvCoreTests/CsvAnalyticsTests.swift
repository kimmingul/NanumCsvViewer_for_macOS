import Foundation
import XCTest
@testable import CsvCore

final class CsvAnalyticsTests: XCTestCase {
    private func openIndexed(_ content: String) throws -> (VirtualCsvDocument, String) {
        let path = try temporaryPath()
        try content.data(using: .utf8)!.write(to: URL(fileURLWithPath: path))
        let doc = try VirtualCsvDocument.open(path: path)
        try doc.runIndexing(progress: { _ in }, cancellation: CancellationFlag())
        return (doc, path)
    }

    func testFindDuplicatesUsesSelectedColumnsAndReportsSourceRows() throws {
        let (doc, path) = try openIndexed("""
        patient,visit,value
        P1,2026-01-01,10
        P1,2026-01-01,11
        P2,2026-01-02,20
        P2,2026-01-03,21

        """)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let duplicates = try doc.findDuplicates(columns: [0, 1], cancellation: CancellationFlag())

        XCTAssertEqual(duplicates.count, 1)
        XCTAssertEqual(duplicates[0].key, ["P1", "2026-01-01"])
        XCTAssertEqual(duplicates[0].sourceRows, [1, 2])
    }

    func testGroupByAggregatesFilteredRows() throws {
        let (doc, path) = try openIndexed("""
        site,arm,value
        A,T,10
        A,T,20
        A,C,30
        B,T,5

        """)
        defer { try? FileManager.default.removeItem(atPath: path) }

        try doc.filterColumnContains(column: 1, term: "T", withinCurrentView: false, progress: nil, cancellation: CancellationFlag())
        let result = try doc.groupBy(
            groupColumns: [0],
            valueColumn: 2,
            functions: [.count, .sum, .mean, .median, .min, .max, .uniqueCount, .standardDeviation],
            cancellation: CancellationFlag()
        )

        XCTAssertEqual(result.rows.count, 2)
        XCTAssertEqual(result.rows[0].key, ["A"])
        XCTAssertEqual(result.rows[0].values[.count], 2)
        XCTAssertEqual(result.rows[0].values[.sum], 30)
        XCTAssertEqual(result.rows[0].values[.mean], 15)
        XCTAssertEqual(result.rows[0].values[.median], 15)
        XCTAssertEqual(result.rows[0].values[.min], 10)
        XCTAssertEqual(result.rows[0].values[.max], 20)
        XCTAssertEqual(result.rows[0].values[.uniqueCount], 2)
        XCTAssertEqual(result.rows[1].key, ["B"])
        XCTAssertEqual(result.rows[1].values[.count], 1)
    }

    func testNumericDistributionBuildsHistogramAndBoxPlot() throws {
        let (doc, path) = try openIndexed("value\n1\n2\n3\n4\n5\n")
        defer { try? FileManager.default.removeItem(atPath: path) }

        let distribution = try doc.numericDistribution(column: 0, binCount: 2, cancellation: CancellationFlag())

        XCTAssertEqual(distribution.count, 5)
        XCTAssertEqual(distribution.min, 1)
        XCTAssertEqual(distribution.max, 5)
        XCTAssertEqual(distribution.median, 3)
        XCTAssertEqual(distribution.q1, 2)
        XCTAssertEqual(distribution.q3, 4)
        XCTAssertEqual(distribution.bins.map(\.count), [2, 3])
    }

    func testDateHistogramBinsByMonth() throws {
        let (doc, path) = try openIndexed("""
        visit_date,value
        2026-01-01,10
        2026-01-15,20
        2026-02-01,5

        """)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let histogram = try doc.dateHistogram(dateColumn: 0, valueColumn: 1, period: .month, cancellation: CancellationFlag())

        XCTAssertEqual(histogram.bins.count, 2)
        XCTAssertEqual(histogram.bins[0].label, "2026-01")
        XCTAssertEqual(histogram.bins[0].count, 2)
        XCTAssertEqual(histogram.bins[0].sum, 30)
        XCTAssertEqual(histogram.bins[0].average, 15)
        XCTAssertEqual(histogram.bins[1].label, "2026-02")
        XCTAssertEqual(histogram.bins[1].count, 1)
    }

    func testPivotTableAggregatesRowsAndColumns() throws {
        let (doc, path) = try openIndexed("""
        site,arm,event,value
        A,T,AE,2
        A,T,SAE,1
        A,C,AE,3
        B,T,AE,4

        """)
        let exportPath = try temporaryPath()
        defer {
            try? FileManager.default.removeItem(atPath: path)
            try? FileManager.default.removeItem(atPath: exportPath)
        }

        let pivot = try doc.pivotTable(rowColumns: [0], columnColumns: [1, 2], valueColumn: 3, function: .sum, cancellation: CancellationFlag())

        XCTAssertEqual(pivot.rowKeys, [["A"], ["B"]])
        XCTAssertEqual(pivot.columnKeys, [["C", "AE"], ["T", "AE"], ["T", "SAE"]])
        XCTAssertEqual(pivot.value(row: ["A"], column: ["C", "AE"]), 3)
        XCTAssertEqual(pivot.value(row: ["A"], column: ["T", "AE"]), 2)
        XCTAssertEqual(pivot.value(row: ["A"], column: ["T", "SAE"]), 1)
        XCTAssertEqual(pivot.value(row: ["B"], column: ["T", "AE"]), 4)

        try pivot.exportCsv(to: exportPath)
        let exported = try String(contentsOfFile: exportPath, encoding: .utf8)
        XCTAssertEqual(exported, "site,C | AE,T | AE,T | SAE\nA,3,2,1\nB,0,4,0\n")
    }

    func testPivotTableSupportsValueOnlyAndSingleAxisLayouts() throws {
        let (doc, path) = try openIndexed("""
        site,arm,value
        A,Control,3
        A,Treatment,7
        B,Control,2
        B,Treatment,5

        """)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let valueOnly = try doc.pivotTable(
            rowColumns: [],
            columnColumns: [],
            valueColumn: 2,
            function: .sum,
            cancellation: CancellationFlag()
        )
        XCTAssertEqual(valueOnly.rowKeys, [[]])
        XCTAssertEqual(valueOnly.columnKeys, [[]])
        XCTAssertEqual(valueOnly.value(row: [], column: []), 17)

        let rowsOnly = try doc.pivotTable(
            rowColumns: [0],
            columnColumns: [],
            valueColumn: 2,
            function: .sum,
            cancellation: CancellationFlag()
        )
        XCTAssertEqual(rowsOnly.rowKeys, [["A"], ["B"]])
        XCTAssertEqual(rowsOnly.columnKeys, [[]])
        XCTAssertEqual(rowsOnly.value(row: ["A"], column: []), 10)
        XCTAssertEqual(rowsOnly.value(row: ["B"], column: []), 7)

        let columnsOnly = try doc.pivotTable(
            rowColumns: [],
            columnColumns: [1],
            valueColumn: 2,
            function: .sum,
            cancellation: CancellationFlag()
        )
        XCTAssertEqual(columnsOnly.rowKeys, [[]])
        XCTAssertEqual(columnsOnly.columnKeys, [["Control"], ["Treatment"]])
        XCTAssertEqual(columnsOnly.value(row: [], column: ["Control"]), 5)
        XCTAssertEqual(columnsOnly.value(row: [], column: ["Treatment"]), 12)
    }

    func testPivotTableHonorsCancellationDuringAggregation() {
        let rows = (0..<20_000).map { index in
            ["A", "\(index)"]
        }
        let cancellation = CancellationFlag()
        cancellation.cancel()

        XCTAssertThrowsError(try CsvAnalytics.pivotTable(
            rows: rows,
            rowColumns: [0],
            columnColumns: [],
            valueColumn: 1,
            function: .sum,
            cancellation: cancellation
        )) { error in
            guard case CsvError.cancelled = error else {
                XCTFail("Expected CsvError.cancelled, got \(error)")
                return
            }
        }
    }
}
