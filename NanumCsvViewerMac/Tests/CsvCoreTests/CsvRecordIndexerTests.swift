import Foundation
import XCTest
@testable import CsvCore

final class CsvRecordIndexerTests: XCTestCase {
    private func index(_ text: String, chunk: Int, delimiter: UInt8 = UInt8(ascii: ",")) -> [Int64] {
        let data = Data(text.utf8)
        let idx = RecordIndex()
        let indexer = CsvRecordIndexer(index: idx, fileLength: Int64(data.count), delimiter: delimiter, firstRecordStart: 0)
        var offset = 0
        while offset < data.count {
            let end = min(data.count, offset + chunk)
            indexer.processBuffer(Data(data[offset..<end]), baseOffset: Int64(offset))
            offset = end
        }
        idx.publish()
        return (0..<idx.count).map { idx[$0] }
    }

    func testChunkedProcessingMatchesSingleBuffer() {
        let samples = [
            "a,b\nc,d\ne,f",
            "a,b\r\nc,d\r\ne",
            "a\rb\rc",
            "\"x\ny\",1\nz,2",
            "a,b\n",
            "",
            "single"
        ]
        for sample in samples {
            let whole = index(sample, chunk: max(1, sample.utf8.count))
            for chunk in [1, 2, 3, 5, 7] {
                XCTAssertEqual(index(sample, chunk: chunk), whole, sample)
            }
        }
    }

    func testRecordsStartAfterEachUnquotedNewline() {
        XCTAssertEqual(index("a,b\nc,d\ne,f", chunk: 64), [0, 4, 8])
    }

    func testCrlfCountsAsSingleSeparator() {
        XCTAssertEqual(index("a\r\nb\r\nc", chunk: 64), [0, 3, 6])
    }

    func testNewlineInsideQuotesDoesNotSplit() {
        XCTAssertEqual(index("\"x\ny\",1\nz,2", chunk: 64), [0, 8])
    }

    func testTrailingNewlineDoesNotCreatePhantomRow() {
        XCTAssertEqual(index("a\nb\n", chunk: 64), [0, 2])
    }

    func testCrSplitAcrossChunkBoundaryIsHandled() {
        XCTAssertEqual(index("a\r\nb", chunk: 2), [0, 3])
        XCTAssertEqual(index("a\r\nb", chunk: 2), index("a\r\nb", chunk: 64))
    }
}
