import XCTest
@testable import NanumCsvViewerMac

final class PerformanceSnapshotTests: XCTestCase {

    func testCurrentMemoryFootprintIsPositive() {
        let footprint = MemoryMetrics.currentFootprintBytes()
        XCTAssertNotNil(footprint)
        XCTAssertGreaterThan(footprint ?? 0, 0)
    }

}
