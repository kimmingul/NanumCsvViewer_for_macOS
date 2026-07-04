import Foundation
import XCTest
@testable import CsvCore

final class FacetSummaryTests: XCTestCase {
    private func openIndexed(_ content: String) throws -> (VirtualCsvDocument, String) {
        let directory = NSTemporaryDirectory()
        let path = (directory as NSString).appendingPathComponent("facet-\(UUID().uuidString).csv")
        try content.data(using: .utf8)!.write(to: URL(fileURLWithPath: path))
        let doc = try VirtualCsvDocument.open(path: path)
        try doc.runIndexing(progress: { _ in }, cancellation: CancellationFlag())
        return (doc, path)
    }

    func testTopValuesFacetCountsSortsAndAggregatesOverflow() throws {
        let (doc, path) = try openIndexed("""
        status,amount
        open,1
        open,2
        closed,3
        open,4
        pending,5
        closed,6
        review,7
        hold,8

        """)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let report = try doc.facetSummaries(
            columns: [FacetColumnRequest(column: 0, wantsHistogram: false)],
            topValueLimit: 3,
            cancellation: CancellationFlag()
        )

        XCTAssertEqual(report.totalRowCount, 8)
        XCTAssertEqual(report.scannedRowCount, 8)
        XCTAssertFalse(report.isRowCapped)
        XCTAssertEqual(report.summaries.count, 1)

        guard case .topValues(let bins, let otherCount, let distinctTruncated) = report.summaries[0].content else {
            return XCTFail("expected topValues facet")
        }
        XCTAssertEqual(bins, [
            FacetValueBin(value: "open", count: 3),
            FacetValueBin(value: "closed", count: 2),
            FacetValueBin(value: "hold", count: 1)
        ])
        XCTAssertEqual(otherCount, 2)
        XCTAssertFalse(distinctTruncated)
    }

    func testTopValuesFacetCountsBlanksAsEmptyValue() throws {
        let (doc, path) = try openIndexed("site\nA\n\nA\n\nB\n")
        defer { try? FileManager.default.removeItem(atPath: path) }

        let report = try doc.facetSummaries(
            columns: [FacetColumnRequest(column: 0, wantsHistogram: false)],
            topValueLimit: 6,
            cancellation: CancellationFlag()
        )

        guard case .topValues(let bins, _, _) = report.summaries[0].content else {
            return XCTFail("expected topValues facet")
        }
        XCTAssertEqual(bins, [
            FacetValueBin(value: "", count: 2),
            FacetValueBin(value: "A", count: 2),
            FacetValueBin(value: "B", count: 1)
        ])
    }

    func testHistogramFacetBinsNumericValues() throws {
        let (doc, path) = try openIndexed("""
        value
        0
        1
        2
        3
        4
        5
        6
        7
        8
        9
        10
        11
        12
        oops

        """)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let report = try doc.facetSummaries(
            columns: [FacetColumnRequest(column: 0, wantsHistogram: true)],
            histogramBinCount: 6,
            cancellation: CancellationFlag()
        )

        guard case .histogram(let bins, let numericCount, let nonNumericCount) = report.summaries[0].content else {
            return XCTFail("expected histogram facet")
        }
        XCTAssertEqual(numericCount, 13)
        XCTAssertEqual(nonNumericCount, 1)
        XCTAssertEqual(bins.count, 6)
        XCTAssertEqual(bins.first?.lowerBound, 0)
        XCTAssertEqual(bins.last?.upperBound, 12)
        // Width 2: [0,2) [2,4) [4,6) [6,8) [8,10) [10,12]
        XCTAssertEqual(bins.map(\.count), [2, 2, 2, 2, 2, 3])
        XCTAssertEqual(bins.map(\.count).reduce(0, +), numericCount)
    }

    func testHistogramFacetFallsBackToValueBarsForLowCardinality() throws {
        let (doc, path) = try openIndexed("rating\n5\n3\n5\n1\n3\n5\n")
        defer { try? FileManager.default.removeItem(atPath: path) }

        let report = try doc.facetSummaries(
            columns: [FacetColumnRequest(column: 0, wantsHistogram: true)],
            histogramBinCount: 6,
            topValueLimit: 6,
            cancellation: CancellationFlag()
        )

        guard case .topValues(let bins, let otherCount, _) = report.summaries[0].content else {
            return XCTFail("low-cardinality numeric column should fall back to value bars")
        }
        XCTAssertEqual(bins, [
            FacetValueBin(value: "5", count: 3),
            FacetValueBin(value: "3", count: 2),
            FacetValueBin(value: "1", count: 1)
        ])
        XCTAssertEqual(otherCount, 0)
    }

    func testFacetsCrossFilterButExcludeOwnColumnFilter() throws {
        let (doc, path) = try openIndexed("""
        city,status
        NY,open
        LA,open
        NY,closed
        SF,open

        """)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let report = try doc.facetSummaries(
            columns: [
                FacetColumnRequest(column: 0, wantsHistogram: false),
                FacetColumnRequest(column: 1, wantsHistogram: false)
            ],
            columnPredicates: [0: { row in row.count > 0 && row[0] == "NY" }],
            topValueLimit: 6,
            cancellation: CancellationFlag()
        )

        // The city facet ignores its own filter so the other choices stay visible.
        guard case .topValues(let cityBins, _, _) = report.summaries[0].content else {
            return XCTFail("expected topValues facet for city")
        }
        XCTAssertEqual(cityBins, [
            FacetValueBin(value: "NY", count: 2),
            FacetValueBin(value: "LA", count: 1),
            FacetValueBin(value: "SF", count: 1)
        ])

        // The status facet is narrowed by the city filter.
        guard case .topValues(let statusBins, _, _) = report.summaries[1].content else {
            return XCTFail("expected topValues facet for status")
        }
        XCTAssertEqual(statusBins, [
            FacetValueBin(value: "closed", count: 1),
            FacetValueBin(value: "open", count: 1)
        ])
    }

    func testFacetsApplyBasePredicateToEveryColumn() throws {
        let (doc, path) = try openIndexed("""
        city,note
        NY,keep
        LA,keep
        NY,skip

        """)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let report = try doc.facetSummaries(
            columns: [FacetColumnRequest(column: 0, wantsHistogram: false)],
            basePredicate: { row in row.count > 1 && row[1] == "keep" },
            topValueLimit: 6,
            cancellation: CancellationFlag()
        )

        guard case .topValues(let bins, _, _) = report.summaries[0].content else {
            return XCTFail("expected topValues facet")
        }
        XCTAssertEqual(bins, [
            FacetValueBin(value: "LA", count: 1),
            FacetValueBin(value: "NY", count: 1)
        ])
    }

    func testFacetRowCapMarksReportTruncated() throws {
        let (doc, path) = try openIndexed("v\na\nb\nc\nd\ne\n")
        defer { try? FileManager.default.removeItem(atPath: path) }

        let report = try doc.facetSummaries(
            columns: [FacetColumnRequest(column: 0, wantsHistogram: false)],
            rowCap: 3,
            cancellation: CancellationFlag()
        )

        XCTAssertEqual(report.totalRowCount, 5)
        XCTAssertEqual(report.scannedRowCount, 3)
        XCTAssertTrue(report.isRowCapped)
        guard case .topValues(let bins, _, _) = report.summaries[0].content else {
            return XCTFail("expected topValues facet")
        }
        XCTAssertEqual(bins.map(\.count).reduce(0, +), 3)
    }

    func testFacetSummariesThrowsWhenCancelled() throws {
        let (doc, path) = try openIndexed("v\n1\n2\n3\n")
        defer { try? FileManager.default.removeItem(atPath: path) }

        let cancellation = CancellationFlag()
        cancellation.cancel()

        XCTAssertThrowsError(
            try doc.facetSummaries(
                columns: [FacetColumnRequest(column: 0, wantsHistogram: true)],
                cancellation: cancellation
            )
        ) { error in
            guard case CsvError.cancelled = error else {
                return XCTFail("expected CsvError.cancelled, got \(error)")
            }
        }
    }

    func testNumericRangeFilterMatchesHalfOpenAndClosedRanges() {
        var state = ColumnFilterState()
        state.setNumericRange(column: 1, lower: 2, upper: 4, includesUpperBound: false)

        let halfOpen = state.predicate()
        XCTAssertFalse(halfOpen(["x", "1.9"]))
        XCTAssertTrue(halfOpen(["x", "2"]))
        XCTAssertTrue(halfOpen(["x", "3.99"]))
        XCTAssertFalse(halfOpen(["x", "4"]))
        XCTAssertFalse(halfOpen(["x", "abc"]))
        XCTAssertFalse(halfOpen(["x", ""]))
        XCTAssertTrue(halfOpen(["x", " 2.5 "]), "numeric parsing should trim whitespace")

        state.setNumericRange(column: 1, lower: 2, upper: 4, includesUpperBound: true)
        let closed = state.predicate()
        XCTAssertTrue(closed(["x", "4"]))
        XCTAssertFalse(closed(["x", "4.01"]))
    }

    func testNumericRangeFilterReplacesPerColumnAndDescribes() {
        var state = ColumnFilterState()
        state.setNumericRange(column: 0, lower: 0, upper: 10, includesUpperBound: false)
        state.setNumericRange(column: 0, lower: 5, upper: 10, includesUpperBound: true)

        XCTAssertEqual(state.filters.count, 1)
        guard case .numericRange(let column, let lower, let upper, let includesUpperBound)? = state.filter(for: 0) else {
            return XCTFail("expected numericRange filter")
        }
        XCTAssertEqual(column, 0)
        XCTAssertEqual(lower, 5)
        XCTAssertEqual(upper, 10)
        XCTAssertTrue(includesUpperBound)

        let descriptions = state.descriptions(columnNames: ["amount"], blankLabel: "(Blank)")
        XCTAssertEqual(descriptions.count, 1)
        XCTAssertTrue(descriptions[0].contains("amount"), "description should include column name: \(descriptions[0])")
        XCTAssertTrue(descriptions[0].contains("5"), "description should include lower bound: \(descriptions[0])")
        XCTAssertTrue(descriptions[0].contains("10"), "description should include upper bound: \(descriptions[0])")
    }

    func testSavedViewRoundTripsNumericRangeFilter() throws {
        var filters = ColumnFilterState()
        filters.setNumericRange(column: 2, lower: -1.5, upper: 99, includesUpperBound: true)
        let view = SavedCsvView(
            name: "facet",
            filterText: nil,
            filterColumn: nil,
            sortKeys: [],
            hiddenColumnIndexes: [],
            searchQuery: nil,
            currentColumn: 0,
            columnFilters: filters
        )

        let data = try JSONEncoder().encode(view)
        let decoded = try JSONDecoder().decode(SavedCsvView.self, from: data)
        XCTAssertEqual(decoded.columnFilters, filters)
    }
}
