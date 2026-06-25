import Foundation
import XCTest
@testable import CsvCore

final class CsvStatisticsTests: XCTestCase {
    private func openIndexed(_ content: String) throws -> (VirtualCsvDocument, String) {
        let path = try temporaryPath()
        try content.data(using: .utf8)!.write(to: URL(fileURLWithPath: path))
        let doc = try VirtualCsvDocument.open(path: path)
        try doc.runIndexing(progress: { _ in }, cancellation: CancellationFlag())
        return (doc, path)
    }

    func testPearsonAndSpearmanCorrelation() throws {
        let (doc, path) = try openIndexed("x,y\n1,2\n2,4\n3,6\n4,8\n")
        defer { try? FileManager.default.removeItem(atPath: path) }

        let pearson = try doc.correlation(xColumn: 0, yColumn: 1, method: .pearson, cancellation: CancellationFlag())
        let spearman = try doc.correlation(xColumn: 0, yColumn: 1, method: .spearman, cancellation: CancellationFlag())

        XCTAssertEqual(pearson.coefficient, 1, accuracy: 0.0001)
        XCTAssertLessThan(pearson.pValue, 0.001)
        XCTAssertEqual(spearman.coefficient, 1, accuracy: 0.0001)
    }

    func testIndependentTTestReportsEffect() throws {
        let (doc, path) = try openIndexed("""
        group,value
        A,10
        A,12
        A,11
        B,20
        B,22
        B,21

        """)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let result = try doc.independentTTest(groupColumn: 0, valueColumn: 1, groupA: "A", groupB: "B", cancellation: CancellationFlag())

        XCTAssertEqual(result.meanA, 11, accuracy: 0.001)
        XCTAssertEqual(result.meanB, 21, accuracy: 0.001)
        XCTAssertLessThan(result.pValue, 0.01)
        XCTAssertGreaterThan(abs(result.effectSize), 5)
        XCTAssertTrue(result.interpretation.contains("statistically significant"))
    }

    func testIndependentTTestUsesStudentTDistributionForPValueAndConfidenceInterval() throws {
        let (doc, path) = try openIndexed("""
        group,value
        A,14.2
        A,15.1
        A,13.9
        A,14.8
        A,15.4
        B,12.8
        B,13.0
        B,12.5
        B,13.4
        B,12.9

        """)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let result = try doc.independentTTest(groupColumn: 0, valueColumn: 1, groupA: "A", groupB: "B", cancellation: CancellationFlag())

        XCTAssertEqual(result.tStatistic, 5.5993, accuracy: 0.0001)
        XCTAssertEqual(result.degreesOfFreedom, 6.0548, accuracy: 0.0001)
        XCTAssertGreaterThan(result.pValue, 0.001)
        XCTAssertLessThan(result.pValue, 0.002)
        XCTAssertLessThan(result.confidenceIntervalLow, 1.1439)
        XCTAssertGreaterThan(result.confidenceIntervalHigh, 2.3761)
    }

    func testPairedTTest() throws {
        let (doc, path) = try openIndexed("before,after\n10,12\n12,15\n14,17\n")
        defer { try? FileManager.default.removeItem(atPath: path) }

        let result = try doc.pairedTTest(beforeColumn: 0, afterColumn: 1, cancellation: CancellationFlag())

        XCTAssertEqual(result.meanDifference, 2.666, accuracy: 0.01)
        XCTAssertLessThan(result.pValue, 0.05)
    }

    func testPairedTTestUsesStudentTDistributionForPValueAndConfidenceInterval() throws {
        let (doc, path) = try openIndexed("""
        before,after
        10,12
        12,15
        14,17
        13,16
        11,13

        """)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let result = try doc.pairedTTest(beforeColumn: 0, afterColumn: 1, cancellation: CancellationFlag())

        XCTAssertEqual(result.meanDifference, 2.6, accuracy: 0.0001)
        XCTAssertEqual(result.tStatistic, 10.6145, accuracy: 0.0001)
        XCTAssertEqual(result.degreesOfFreedom, 4.0, accuracy: 0.0001)
        XCTAssertGreaterThan(result.pValue, 0.0004)
        XCTAssertLessThan(result.pValue, 0.0005)
        XCTAssertLessThan(result.confidenceIntervalLow, 2.1199)
        XCTAssertGreaterThan(result.confidenceIntervalHigh, 3.0801)
    }

    func testChiSquareTest() throws {
        let (doc, path) = try openIndexed("""
        arm,response
        T,yes
        T,yes
        T,no
        C,no
        C,no
        C,yes

        """)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let result = try doc.chiSquareTest(rowColumn: 0, columnColumn: 1, cancellation: CancellationFlag())

        XCTAssertEqual(result.degreesOfFreedom, 1)
        XCTAssertGreaterThan(result.statistic, 0)
        XCTAssertGreaterThan(result.pValue, 0)
        XCTAssertLessThanOrEqual(result.pValue, 1)
    }

    func testChiSquareUsesGammaSurvivalFunction() throws {
        let (doc, path) = try openIndexed("""
        arm,response
        A,x
        A,y
        A,z
        A,z
        A,z
        A,z
        B,x
        B,x
        B,y
        B,y
        B,y
        B,y
        B,y
        B,y
        B,y
        B,z

        """)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let result = try doc.chiSquareTest(rowColumn: 0, columnColumn: 1, cancellation: CancellationFlag())

        XCTAssertEqual(result.statistic, 6.0089, accuracy: 0.0001)
        XCTAssertEqual(result.degreesOfFreedom, 2)
        XCTAssertEqual(result.pValue, 0.0496, accuracy: 0.0001)
    }
}
