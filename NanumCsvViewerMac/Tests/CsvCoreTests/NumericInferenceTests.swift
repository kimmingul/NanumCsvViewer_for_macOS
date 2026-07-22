import Foundation
import XCTest
@testable import CsvCore

final class NumericInferenceTests: XCTestCase {
    func testIdentifierLikeTokensAreNotNumbers() {
        XCTAssertNil(NumericInference.number(from: "00123"))
        XCTAssertNil(NumericInference.number(from: "007"))
        XCTAssertNil(NumericInference.number(from: "-05"))
        XCTAssertNil(NumericInference.number(from: "1234567890123456")) // 16 digits, past Double's exact range
    }

    func testGenuineNumbersStillParse() {
        XCTAssertEqual(NumericInference.number(from: "0"), 0)
        XCTAssertEqual(NumericInference.number(from: "0.5"), 0.5)
        XCTAssertEqual(NumericInference.number(from: "123"), 123)
        XCTAssertEqual(NumericInference.number(from: "-42"), -42)
        XCTAssertEqual(NumericInference.number(from: "1e5"), 100000)
        XCTAssertEqual(NumericInference.number(from: "1.5e3"), 1500)
        XCTAssertEqual(NumericInference.number(from: "123456789012345"), 123456789012345) // 15 digits, still exact
        XCTAssertNil(NumericInference.number(from: "abc"))
    }

    func testLeadingZeroIdColumnInfersAsTextNotInteger() {
        let report = ColumnStatisticsBuilder.summarize(
            headers: ["zip"],
            rows: [["00123"], ["00456"], ["00789"]]
        )
        XCTAssertNotEqual(report.columns[0].inferredType, .integer)
        XCTAssertNil(report.columns[0].numeric, "no numeric summary is computed on identifier data")
    }

    func testCompactYyyyMMddInfersAsDate() {
        // Compact yyyyMMdd is recognized as a date (a deliberate feature for
        // Korean / medical CSVs). ColumnStatistics and CsvDataQuality now use the
        // same allowCompactNumeric setting, so they classify it consistently.
        let stats = ColumnStatisticsBuilder.summarize(
            headers: ["code"],
            rows: [["20180101"], ["20200304"], ["20211231"]]
        )
        XCTAssertEqual(stats.columns[0].inferredType, .date)
    }

    func testExplicitDateStillInfersAsDate() {
        let report = ColumnStatisticsBuilder.summarize(
            headers: ["day"],
            rows: [["2018-01-01"], ["2020-03-04"], ["2021-12-31"]]
        )
        XCTAssertEqual(report.columns[0].inferredType, .date)
    }
}
