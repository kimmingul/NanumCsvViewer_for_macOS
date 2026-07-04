import Foundation
import XCTest
@testable import NanumCsvViewerMac

final class AnalysisScopeLabelTests: XCTestCase {
    private func makeProvenance(visibleRows: Int, scannedRows: Int?) -> AnalysisProvenance {
        AnalysisProvenance(
            visibleRows: visibleRows,
            totalRows: visibleRows,
            isFiltered: false,
            filters: [],
            sortDescription: nil,
            columnNames: ["a"],
            parameterLines: [],
            generatedAt: Date(),
            elapsedMilliseconds: nil,
            scannedRows: scannedRows
        )
    }

    func testProvenanceMentionsRowCapWhenScannedFewerThanVisible() {
        let lines = makeProvenance(visibleRows: 3_000_000, scannedRows: 2_000_000).lines
        XCTAssertTrue(
            lines.contains { $0.contains("2,000,000") && ($0.contains("showing first") || $0.contains("처음")) },
            "expected a showing-first-N-rows line, got \(lines)"
        )
    }

    func testProvenanceOmitsRowCapWhenAllRowsScanned() {
        let lines = makeProvenance(visibleRows: 100, scannedRows: 100).lines
        XCTAssertFalse(
            lines.contains { $0.contains("showing first") || $0.contains("처음") },
            "no cap line expected when the scan covered every row, got \(lines)"
        )
    }
}
