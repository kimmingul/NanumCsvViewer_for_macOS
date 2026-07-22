import Foundation
import XCTest
@testable import CsvCore

final class CsvNumberTests: XCTestCase {
    func testUsFormatParsesGroupingAndDecimal() {
        XCTAssertEqual(CsvNumber.parse("1,234.56", format: .us), 1234.56)
        XCTAssertEqual(CsvNumber.parse("1,234", format: .us), 1234)
        XCTAssertEqual(CsvNumber.parse("1.5", format: .us), 1.5)
        XCTAssertEqual(CsvNumber.parse("-42", format: .us), -42)
        XCTAssertEqual(CsvNumber.parse("  7  ", format: .us), 7)
        XCTAssertNil(CsvNumber.parse("abc", format: .us))
    }

    func testEuropeanFormatParsesGroupingAndDecimal() {
        XCTAssertEqual(CsvNumber.parse("1.234,56", format: .european), 1234.56)
        XCTAssertEqual(CsvNumber.parse("1,5", format: .european), 1.5)
        XCTAssertEqual(CsvNumber.parse("1.234", format: .european), 1234)
        XCTAssertEqual(CsvNumber.parse("42", format: .european), 42)
        XCTAssertNil(CsvNumber.parse("1,2,3", format: .european)) // "1.2.3" is not a number
    }

    func testPlainFormatMatchesDouble() {
        XCTAssertEqual(CsvNumber.parse("1234.56", format: .plain), 1234.56)
        XCTAssertNil(CsvNumber.parse("1,234", format: .plain))
    }

    func testInferenceRecognizesGroupedNumbers() {
        let previous = CsvNumber.format
        CsvNumber.format = .us
        defer { CsvNumber.format = previous }

        let report = ColumnStatisticsBuilder.summarize(
            headers: ["amount"],
            rows: [["1,234"], ["5,678"], ["9,012"]]
        )
        XCTAssertEqual(report.columns[0].inferredType, .integer)
        XCTAssertNotNil(report.columns[0].numeric, "grouped numbers are summarized instead of silently dropped")
    }
}
