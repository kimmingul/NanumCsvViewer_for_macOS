import XCTest
@testable import NanumCsvViewerMac

final class PerformanceSnapshotTests: XCTestCase {
    func testFormatsPerformanceDashboardWithIndexingAndViewMetrics() {
        let snapshot = PerformanceSnapshot(
            fileBytes: 2_097_152,
            totalRows: 120_000,
            visibleRows: 42_000,
            columnCount: 18,
            storageMode: "RAM",
            indexingElapsed: 1.25,
            indexingComplete: true
        )

        XCTAssertEqual(snapshot.formattedLines(), [
            "File: 2.0 MB",
            "Rows: 42,000 / 120,000 visible",
            "Columns: 18",
            "Storage: RAM",
            "Indexing: complete in 1.25 s",
            "Throughput: 96,000 rows/s"
        ])
    }

    func testFormatsInProgressSnapshotWithoutThroughput() {
        let snapshot = PerformanceSnapshot(
            fileBytes: 512,
            totalRows: 80,
            visibleRows: 80,
            columnCount: 3,
            storageMode: "Disk",
            indexingElapsed: nil,
            indexingComplete: false
        )

        XCTAssertEqual(snapshot.formattedLines(), [
            "File: 512 B",
            "Rows: 80",
            "Columns: 3",
            "Storage: Disk",
            "Indexing: in progress"
        ])
    }
}
