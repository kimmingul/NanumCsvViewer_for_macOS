import XCTest
@testable import CsvCore
@testable import NanumCsvViewerMac

final class SearchFieldParserTests: XCTestCase {
    func testParsesRegexAndSlashRegexSearchTerms() throws {
        let prefixed = try SearchFieldParser.parse("regex:^A\\d+$", column: nil)
        XCTAssertEqual(prefixed, try CsvSearchQuery(text: "^A\\d+$", mode: .regex, column: nil))

        let slash = try SearchFieldParser.parse("/positive|negative/", column: 2)
        XCTAssertEqual(slash, try CsvSearchQuery(text: "positive|negative", mode: .regex, column: 2))
    }

    func testParsesFuzzyAndPlainContainsSearchTerms() throws {
        let fuzzy = try SearchFieldParser.parse("fuzzy:bsln", column: nil)
        XCTAssertEqual(fuzzy, try CsvSearchQuery(text: "bsln", mode: .fuzzy, column: nil))

        let plain = try SearchFieldParser.parse("baseline", column: 1)
        XCTAssertEqual(plain, try CsvSearchQuery(text: "baseline", mode: .contains, column: 1))
    }
}
