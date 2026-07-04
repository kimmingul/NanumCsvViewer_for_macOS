import Foundation
import XCTest
@testable import CsvCore

final class ColumnTypeOverrideTests: XCTestCase {
    func testConversionClassificationMatrix() {
        XCTAssertEqual(ColumnTypeConversion.classify(from: .integer, to: .string), .allow)
        XCTAssertEqual(ColumnTypeConversion.classify(from: .date, to: .categorical), .allow)
        XCTAssertEqual(ColumnTypeConversion.classify(from: .integer, to: .float), .allow)
        XCTAssertEqual(ColumnTypeConversion.classify(from: .boolean, to: .float), .validateSample, "yes/no booleans are not parseable numbers; must validate")
        XCTAssertEqual(ColumnTypeConversion.classify(from: .float, to: .integer), .block)
        XCTAssertEqual(ColumnTypeConversion.classify(from: .string, to: .date), .validateSample)
        XCTAssertEqual(ColumnTypeConversion.classify(from: .categorical, to: .integer), .validateSample)
        XCTAssertEqual(ColumnTypeConversion.classify(from: .string, to: .boolean), .validateSample)
        XCTAssertEqual(ColumnTypeConversion.classify(from: .integer, to: .empty), .block)
        XCTAssertEqual(ColumnTypeConversion.classify(from: .integer, to: .integer), .allow)
    }

    func testSampleValidationReportsFailures() {
        let good = ColumnTypeConversion.validateSample(values: ["2026-01-01", "2026-02-03"], to: .date)
        XCTAssertTrue(good.passed)
        XCTAssertTrue(good.failures.isEmpty)

        let bad = ColumnTypeConversion.validateSample(values: ["2026-01-01", "not a date", "also bad"], to: .date)
        XCTAssertFalse(bad.passed)
        XCTAssertEqual(bad.failures, ["not a date", "also bad"])

        let numeric = ColumnTypeConversion.validateSample(values: ["1", "2.5", "abc"], to: .float)
        XCTAssertFalse(numeric.passed)
        XCTAssertEqual(numeric.failures, ["abc"])

        let integer = ColumnTypeConversion.validateSample(values: ["1", "2.5"], to: .integer)
        XCTAssertFalse(integer.passed)
        XCTAssertEqual(integer.failures, ["2.5"])

        let blanksIgnored = ColumnTypeConversion.validateSample(values: ["", "na", "1"], to: .integer)
        XCTAssertTrue(blanksIgnored.passed)
    }

    func testReportApplyingOverridesSubstitutesTypeAndReverts() {
        let report = ColumnStatisticsBuilder.summarize(
            headers: ["id", "name"],
            rows: [["1", "Alice"], ["2", "Bob"], ["3", "Cara"]]
        )
        XCTAssertEqual(report.columns[0].inferredType, .integer)

        let overridden = report.applyingOverrides([0: .string])
        XCTAssertEqual(overridden.columns[0].inferredType, .string)
        XCTAssertEqual(overridden.columns[1].inferredType, report.columns[1].inferredType)
        XCTAssertEqual(overridden.columns[0].uniqueCount, report.columns[0].uniqueCount)

        let reverted = report.applyingOverrides([:])
        XCTAssertEqual(reverted.columns[0].inferredType, .integer)
    }
}
