import Foundation
import XCTest
@testable import NanumCsvViewerMac

final class BenchmarkTests: XCTestCase {
    func testRowsPerSecondComputation() {
        let result = BenchmarkResult(name: "Scan", milliseconds: 500, rowsProcessed: 1000)
        XCTAssertEqual(result.rowsPerSecond, 2000, "1000 rows in 0.5 s is 2000 rows/s")
    }

    func testRowsPerSecondZeroWhenNoTime() {
        XCTAssertEqual(BenchmarkResult(name: "x", milliseconds: 0, rowsProcessed: 100).rowsPerSecond, 0)
    }

    func testDurationToMilliseconds() {
        XCTAssertEqual(Duration.seconds(2).milliseconds, 2000, accuracy: 0.0001)
        XCTAssertEqual(Duration.milliseconds(250).milliseconds, 250, accuracy: 0.0001)
        XCTAssertEqual(Duration.microseconds(500).milliseconds, 0.5, accuracy: 0.0001)
    }

}
