import Foundation
import XCTest
@testable import CsvCore

final class AnalysisRowCapTests: XCTestCase {
    private var originalLimit = 0

    override func setUp() {
        super.setUp()
        originalLimit = VirtualCsvDocument.analysisRowLimit
    }

    override func tearDown() {
        VirtualCsvDocument.analysisRowLimit = originalLimit
        super.tearDown()
    }

    private func openIndexed(_ content: String) throws -> (VirtualCsvDocument, String) {
        let directory = NSTemporaryDirectory()
        let path = (directory as NSString).appendingPathComponent("rowcap-\(UUID().uuidString).csv")
        try content.data(using: .utf8)!.write(to: URL(fileURLWithPath: path))
        let doc = try VirtualCsvDocument.open(path: path)
        try doc.runIndexing(progress: { _ in }, cancellation: CancellationFlag())
        return (doc, path)
    }

    func testDefaultAnalysisRowLimitMatchesWindowsTwin() {
        XCTAssertEqual(VirtualCsvDocument.analysisRowLimit, 2_000_000)
    }

    func testAnalysisScansOnlyFirstRowsWhenLimitIsLower() throws {
        let (doc, path) = try openIndexed("""
        group,value
        a,1
        a,2
        b,3
        b,4
        b,5

        """)
        defer { try? FileManager.default.removeItem(atPath: path) }

        VirtualCsvDocument.analysisRowLimit = 3
        XCTAssertTrue(doc.analysisRowsTruncated)

        let grouped = try doc.groupBy(
            groupColumns: [0],
            valueColumn: 1,
            functions: [.count],
            cancellation: CancellationFlag()
        )
        let counts = Dictionary(uniqueKeysWithValues: grouped.rows.map { ($0.key, $0.values[.count]) })
        XCTAssertEqual(counts[["a"]], 2)
        XCTAssertEqual(counts[["b"]], 1, "rows past the analysis cap must not be scanned")

        let stats = try doc.descriptiveStatistics(column: 1, cancellation: CancellationFlag())
        XCTAssertEqual(stats.count, 3, "extended statistics must honor the same cap")

        let duplicates = try doc.findDuplicates(columns: [0], cancellation: CancellationFlag())
        XCTAssertEqual(duplicates.map(\.sourceRows.count), [2], "only the capped rows participate in duplicate scan")
    }

    func testAnalysisNotTruncatedWhenViewFitsLimit() throws {
        let (doc, path) = try openIndexed("group,value\na,1\nb,2\n")
        defer { try? FileManager.default.removeItem(atPath: path) }

        VirtualCsvDocument.analysisRowLimit = 10
        XCTAssertFalse(doc.analysisRowsTruncated)
    }

    func testExportIgnoresAnalysisRowLimit() throws {
        let (doc, path) = try openIndexed("v\n1\n2\n3\n4\n")
        defer { try? FileManager.default.removeItem(atPath: path) }

        VirtualCsvDocument.analysisRowLimit = 2
        let exportPath = (NSTemporaryDirectory() as NSString).appendingPathComponent("rowcap-export-\(UUID().uuidString).csv")
        defer { try? FileManager.default.removeItem(atPath: exportPath) }
        try doc.exportCurrentView(to: exportPath, cancellation: CancellationFlag())

        let exported = try String(contentsOfFile: exportPath, encoding: .utf8)
        XCTAssertEqual(exported.split(separator: "\n").count, 5, "export must always write the full view")
    }
}
