import Foundation
import XCTest
@testable import CsvCore

/// Reference values generated with scipy 1.x (stats.skew/kurtosis bias=False,
/// stats.f_oneway, stats.shapiro, numpy percentile method='linear').
final class CsvExtendedStatisticsTests: XCTestCase {
    private let sampleA = [23.1, 25.4, 21.9, 28.0, 24.5, 26.2, 22.8, 27.3, 25.0, 23.7]
    private let sampleB = [30.2, 28.9, 31.5, 29.7, 32.0, 30.8, 28.4, 31.1]
    private let sampleC = [26.5, 27.2, 25.8, 28.1, 26.9, 27.6]

    func testDescriptiveStatisticsMatchesScipy() {
        let result = CsvStatistics.descriptive(values: sampleA, missingCount: 2)

        XCTAssertEqual(result.count, 10)
        XCTAssertEqual(result.missingCount, 2)
        XCTAssertEqual(result.mean, 24.79, accuracy: 1e-9)
        XCTAssertEqual(result.standardDeviation, 1.984635426917946, accuracy: 1e-9)
        XCTAssertEqual(result.standardError, 0.6275968274121354, accuracy: 1e-9)
        XCTAssertEqual(result.confidenceIntervalLow, 23.370277341520207, accuracy: 1e-6)
        XCTAssertEqual(result.confidenceIntervalHigh, 26.20972265847979, accuracy: 1e-6)
        XCTAssertEqual(result.minimum, 21.9, accuracy: 1e-9)
        XCTAssertEqual(result.quartile1, 23.25, accuracy: 1e-9)
        XCTAssertEqual(result.median, 24.75, accuracy: 1e-9)
        XCTAssertEqual(result.quartile3, 26.0, accuracy: 1e-9)
        XCTAssertEqual(result.maximum, 28.0, accuracy: 1e-9)
        XCTAssertEqual(result.range, 6.1, accuracy: 1e-9)
        XCTAssertEqual(result.interquartileRange, 2.75, accuracy: 1e-9)
        XCTAssertEqual(result.skewness, 0.24455981328804458, accuracy: 1e-9)
        XCTAssertEqual(result.excessKurtosis, -0.8929286973831441, accuracy: 1e-9)
        XCTAssertEqual(result.coefficientOfVariation, 0.08005790346583082, accuracy: 1e-9)
        XCTAssertTrue(result.modes.isEmpty, "all values unique: no mode")
    }

    func testDescriptiveStatisticsFindsModes() {
        let result = CsvStatistics.descriptive(values: [1, 2, 2, 3, 3, 4], missingCount: 0)
        XCTAssertEqual(result.modes, [2, 3])
    }

    func testFrequencyAnalysisCountsPercentAndCumulative() {
        let values = ["a", "b", "a", "c", "a", "b", "", "a"]
        let result = CsvStatistics.frequencyAnalysis(values: values, blankLabel: "(Blank)")

        XCTAssertEqual(result.total, 8)
        XCTAssertEqual(result.entries.first?.value, "a")
        XCTAssertEqual(result.entries.first?.count, 4)
        XCTAssertEqual(result.entries.first?.percent ?? 0, 50.0, accuracy: 1e-9)
        XCTAssertEqual(result.entries.first?.cumulativePercent ?? 0, 50.0, accuracy: 1e-9)
        XCTAssertEqual(result.entries[1].value, "b")
        XCTAssertEqual(result.entries[1].cumulativePercent, 75.0, accuracy: 1e-9)
        XCTAssertEqual(result.entries.last?.value, "(Blank)")
        XCTAssertEqual(result.entries.last?.cumulativePercent ?? 0, 100.0, accuracy: 1e-9)
    }

    func testOneWayAnovaMatchesScipy() {
        let result = CsvStatistics.oneWayAnova(groups: [
            ("A", sampleA), ("B", sampleB), ("C", sampleC)
        ])

        XCTAssertEqual(result.fStatistic, 28.69557290449255, accuracy: 1e-8)
        XCTAssertEqual(result.degreesOfFreedomBetween, 2)
        XCTAssertEqual(result.degreesOfFreedomWithin, 21)
        XCTAssertEqual(result.pValue, 9.85142294264528e-07, accuracy: 1e-11)
        XCTAssertEqual(result.etaSquared, 0.732112602982351, accuracy: 1e-9)
    }

    func testOneWayAnovaDegenerateCases() {
        let single = CsvStatistics.oneWayAnova(groups: [("A", sampleA)])
        XCTAssertEqual(single.pValue, 1, accuracy: 1e-12)

        let constant = CsvStatistics.oneWayAnova(groups: [("A", [5, 5, 5]), ("B", [5, 5, 5])])
        XCTAssertEqual(constant.fStatistic, 0, accuracy: 1e-12)
    }

    func testShapiroWilkMatchesScipySmallSample() {
        let result = CsvStatistics.shapiroWilk(values: sampleA)
        XCTAssertEqual(result.wStatistic, 0.9731049564875252, accuracy: 5e-4)
        XCTAssertEqual(result.pValue, 0.9180457935176647, accuracy: 5e-3)
    }

    func testShapiroWilkDetectsNonNormalData() {
        let mixed = [1.2, 1.1, 8.9, 1.3, 1.0, 9.4, 1.2, 1.1, 9.1, 1.25, 1.15, 8.7]
        let result = CsvStatistics.shapiroWilk(values: mixed)
        XCTAssertEqual(result.wStatistic, 0.6420915123172207, accuracy: 5e-4)
        XCTAssertLessThan(result.pValue, 0.001)
    }

    func testShapiroWilkMatchesScipyNormalSample50() {
        let norm50 = [
            10.993428, 9.723471, 11.295377, 13.04606, 9.531693, 9.531726, 13.158426, 11.534869,
            9.061051, 11.08512, 9.073165, 9.06854, 10.483925, 6.17344, 6.550164, 8.875425,
            7.974338, 10.628495, 8.183952, 7.175393, 12.931298, 9.548447, 10.135056, 7.150504,
            8.911235, 10.221845, 7.698013, 10.751396, 8.798723, 9.416613, 8.796587, 13.704556,
            9.973006, 7.884578, 11.64509, 7.558313, 10.417727, 6.08066, 7.343628, 10.393722,
            11.476933, 10.342737, 9.768703, 9.397793, 7.042956, 8.560312, 9.078722, 12.114244,
            10.687237, 6.47392
        ]
        let result = CsvStatistics.shapiroWilk(values: norm50)
        XCTAssertEqual(result.wStatistic, 0.9827494614161075, accuracy: 5e-4)
        XCTAssertEqual(result.pValue, 0.672207564902706, accuracy: 2e-2)
    }

    func testDocumentLevelExtendedStatistics() throws {
        let path = NSTemporaryDirectory() + "/ext-stats-\(UUID().uuidString).csv"
        var lines = ["group,value"]
        for v in sampleA { lines.append("A,\(v)") }
        for v in sampleB { lines.append("B,\(v)") }
        for v in sampleC { lines.append("C,\(v)") }
        try lines.joined(separator: "\n").appending("\n").data(using: .utf8)!.write(to: URL(fileURLWithPath: path))
        defer { try? FileManager.default.removeItem(atPath: path) }

        let doc = try VirtualCsvDocument.open(path: path)
        try doc.runIndexing(progress: { _ in }, cancellation: CancellationFlag())

        let descriptive = try doc.descriptiveStatistics(column: 1, cancellation: CancellationFlag())
        XCTAssertEqual(descriptive.count, 24)

        let frequency = try doc.frequencyAnalysis(column: 0, blankLabel: "(Blank)", cancellation: CancellationFlag())
        XCTAssertEqual(frequency.entries.first?.value, "A")
        XCTAssertEqual(frequency.entries.first?.count, 10)

        let anova = try doc.oneWayAnova(groupColumn: 0, valueColumn: 1, cancellation: CancellationFlag())
        XCTAssertEqual(anova.fStatistic, 28.69557290449255, accuracy: 1e-6)

        let shapiro = try doc.shapiroWilk(column: 1, cancellation: CancellationFlag())
        XCTAssertEqual(shapiro.sampleSize, 24)
    }
}
