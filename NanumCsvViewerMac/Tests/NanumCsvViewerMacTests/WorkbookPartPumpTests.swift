import XCTest
@testable import NanumCsvViewerMac

final class WorkbookPartPumpTests: XCTestCase {
    func testInitialBatchIsBoundedByConcurrency() {
        let pump = WorkbookPartPump(total: 10, concurrency: 4)
        XCTAssertEqual(pump.initialBatch(), [0, 1, 2, 3])
    }

    func testInitialBatchClampsToTotal() {
        let pump = WorkbookPartPump(total: 2, concurrency: 4)
        XCTAssertEqual(pump.initialBatch(), [0, 1])
    }

    func testPipelineStaysFullAndDrainsExactlyOnce() {
        let pump = WorkbookPartPump(total: 6, concurrency: 2)
        var started = pump.initialBatch() // [0,1]
        XCTAssertEqual(started, [0, 1])

        var drainedCount = 0
        var launched = Set(started)
        // Simulate completions in order until fully drained.
        var pending = started
        while let _ = pending.first {
            pending.removeFirst()
            let (next, drained) = pump.partFinished()
            if let next {
                XCTAssertFalse(launched.contains(next), "each index launched once")
                launched.insert(next)
                pending.append(next)
            }
            if drained { drainedCount += 1 }
        }

        XCTAssertEqual(launched, Set(0..<6), "every part launched exactly once")
        XCTAssertEqual(drainedCount, 1, "drained fires exactly once")
        _ = started
    }

    func testStopPreventsFurtherLaunches() {
        let pump = WorkbookPartPump(total: 10, concurrency: 2)
        _ = pump.initialBatch() // starts 0,1 (inFlight = 2)
        let drainedOnStop = pump.stop()
        XCTAssertFalse(drainedOnStop, "still 2 in flight")

        // Remaining in-flight complete; no new launches after stop.
        let (next1, drained1) = pump.partFinished()
        XCTAssertNil(next1, "stopped: no replacement launched")
        XCTAssertFalse(drained1, "one still in flight")
        let (next2, drained2) = pump.partFinished()
        XCTAssertNil(next2)
        XCTAssertTrue(drained2, "drained once the last in-flight finishes")
    }
}
