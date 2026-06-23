import XCTest
@testable import CsvCore

final class RecordIndexTests: XCTestCase {
    func testAddIncrementsCountAndPreservesValues() {
        let index = RecordIndex()
        XCTAssertEqual(index.count, 0)
        index.add(10)
        index.add(25)
        index.add(99)
        XCTAssertEqual(index.count, 0)
        index.publish()
        XCTAssertEqual(index.count, 3)
        XCTAssertEqual(index[0], 10)
        XCTAssertEqual(index[1], 25)
        XCTAssertEqual(index[2], 99)
    }

    func testValuesSurviveSegmentBoundaryCrossing() {
        let segmentSize = 1 << 20
        let total = segmentSize + 5
        let index = RecordIndex()
        for i in 0..<total {
            index.add(Int64(i * 2))
        }
        index.publish()

        XCTAssertEqual(index.count, Int64(total))
        XCTAssertEqual(index[0], 0)
        XCTAssertEqual(index[Int64(segmentSize - 1)], Int64((segmentSize - 1) * 2))
        XCTAssertEqual(index[Int64(segmentSize)], Int64(segmentSize * 2))
        XCTAssertEqual(index[Int64(total - 1)], Int64((total - 1) * 2))
    }
}
