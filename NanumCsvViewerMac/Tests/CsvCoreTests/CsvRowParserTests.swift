import XCTest
@testable import CsvCore

final class CsvRowParserTests: XCTestCase {
    func testSplitsSimpleFields() {
        XCTAssertEqual(CsvRowParser.parse("a,b,c", delimiter: ","), ["a", "b", "c"])
    }

    func testEmptyFieldsArePreserved() {
        XCTAssertEqual(CsvRowParser.parse(",b,", delimiter: ","), ["", "b", ""])
    }

    func testQuotedFieldKeepsDelimiter() {
        XCTAssertEqual(CsvRowParser.parse("a,\"b,c\",d", delimiter: ","), ["a", "b,c", "d"])
    }

    func testEscapedDoubleQuoteCollapses() {
        XCTAssertEqual(CsvRowParser.parse("\"she said \"\"hi\"\"\"", delimiter: ","), ["she said \"hi\""])
    }

    func testEmbeddedNewlineInQuotesIsNormalizedToLF() {
        XCTAssertEqual(CsvRowParser.parse("\"line1\r\nline2\",x", delimiter: ","), ["line1\nline2", "x"])
        XCTAssertEqual(CsvRowParser.parse("\"line1\rline2\"", delimiter: ","), ["line1\nline2"])
    }

    func testHonorsAlternateDelimiters() {
        XCTAssertEqual(CsvRowParser.parse("a\tb\tc", delimiter: "\t"), ["a", "b", "c"])
        XCTAssertEqual(CsvRowParser.parse("a;b;c", delimiter: ";"), ["a", "b", "c"])
        XCTAssertEqual(CsvRowParser.parse("a|b|c", delimiter: "|"), ["a", "b", "c"])
    }

    func testTrailingGarbageAfterClosingQuoteIsAppended() {
        XCTAssertEqual(CsvRowParser.parse("\"ab\"c,d", delimiter: ","), ["abc", "d"])
    }
}
