import Foundation
import XCTest
@testable import CsvCore

final class CsvChartDataTests: XCTestCase {
    private func openIndexed(_ content: String) throws -> (VirtualCsvDocument, String) {
        let directory = NSTemporaryDirectory()
        let path = (directory as NSString).appendingPathComponent("chart-\(UUID().uuidString).csv")
        try content.data(using: .utf8)!.write(to: URL(fileURLWithPath: path))
        let doc = try VirtualCsvDocument.open(path: path)
        try doc.runIndexing(progress: { _ in }, cancellation: CancellationFlag())
        return (doc, path)
    }

    // MARK: - Kernel density

    func testKernelDensityIntegratesToApproximatelyOne() {
        let values = (0..<200).map { _ in Double.random(in: 0...10) }
        let points = CsvChartMath.kernelDensity(values: values, gridCount: 256)

        XCTAssertEqual(points.count, 256)
        var integral = 0.0
        for index in 1..<points.count {
            let dx = points[index].x - points[index - 1].x
            integral += dx * (points[index].density + points[index - 1].density) / 2
        }
        XCTAssertEqual(integral, 1.0, accuracy: 0.08, "trapezoid integral of the KDE should be close to 1")
    }

    func testKernelDensityOfConstantValuesIsEmpty() {
        XCTAssertTrue(CsvChartMath.kernelDensity(values: [5, 5, 5], gridCount: 64).isEmpty)
        XCTAssertTrue(CsvChartMath.kernelDensity(values: [], gridCount: 64).isEmpty)
    }

    // MARK: - Linear regression

    func testLinearRegressionRecoversExactLine() throws {
        let pairs = (0..<50).map { i in (Double(i), 2.5 * Double(i) - 4) }
        let fit = try XCTUnwrap(CsvChartMath.linearRegression(pairs: pairs))

        XCTAssertEqual(fit.slope, 2.5, accuracy: 1e-9)
        XCTAssertEqual(fit.intercept, -4, accuracy: 1e-9)
        XCTAssertEqual(fit.rSquared, 1.0, accuracy: 1e-9)
    }

    func testLinearRegressionKnownValues() throws {
        // scipy.stats.linregress([1,2,3,4,5], [2,1,4,3,5]) -> slope=0.8, intercept=0.6, r=0.8
        let fit = try XCTUnwrap(CsvChartMath.linearRegression(pairs: [(1, 2), (2, 1), (3, 4), (4, 3), (5, 5)]))
        XCTAssertEqual(fit.slope, 0.8, accuracy: 1e-9)
        XCTAssertEqual(fit.intercept, 0.6, accuracy: 1e-9)
        XCTAssertEqual(fit.rSquared, 0.64, accuracy: 1e-9)
    }

    func testLinearRegressionNeedsVariance() {
        XCTAssertNil(CsvChartMath.linearRegression(pairs: [(1, 1), (1, 2)]))
        XCTAssertNil(CsvChartMath.linearRegression(pairs: [(1, 1)]))
    }

    // MARK: - Boxplot

    func testBoxplotSummaryQuartilesWhiskersAndOutliers() throws {
        let values: [Double] = [1, 2, 3, 4, 5, 6, 7, 8, 9, 100]
        let summary = try XCTUnwrap(CsvChartMath.boxplotSummary(values: values))

        XCTAssertEqual(summary.median, 5.5, accuracy: 1e-9)
        XCTAssertEqual(summary.quartile1, 3.25, accuracy: 1e-9)
        XCTAssertEqual(summary.quartile3, 7.75, accuracy: 1e-9)
        XCTAssertEqual(summary.outliers, [100])
        XCTAssertEqual(summary.whiskerLow, 1, accuracy: 1e-9, "low whisker = min non-outlier")
        XCTAssertEqual(summary.whiskerHigh, 9, accuracy: 1e-9, "high whisker = max non-outlier")
    }

    // MARK: - Q-Q

    func testNormalQQPointsAreMonotonicAndCentered() {
        let values = (1...99).map(Double.init)
        let points = CsvChartMath.normalQQPoints(values: values)

        XCTAssertEqual(points.count, 99)
        XCTAssertEqual(points[49].theoretical, 0, accuracy: 1e-6, "middle quantile of a symmetric sample is z=0")
        XCTAssertEqual(points[49].sample, 50, accuracy: 1e-9)
        let theoreticalSorted = points.map(\.theoretical)
        XCTAssertEqual(theoreticalSorted, theoreticalSorted.sorted())
    }

    // MARK: - Density grid

    func testDensityGridCountsFallIntoExpectedCells() throws {
        let pairs: [(Double, Double)] = [(0, 0), (0.1, 0.1), (9.9, 9.9), (10, 10)]
        let grid = try XCTUnwrap(CsvChartMath.densityGrid(pairs: pairs, columns: 2, rows: 2))

        XCTAssertEqual(grid.columns, 2)
        XCTAssertEqual(grid.rows, 2)
        XCTAssertEqual(grid.count(atColumn: 0, row: 0), 2)
        XCTAssertEqual(grid.count(atColumn: 1, row: 1), 2)
        XCTAssertEqual(grid.count(atColumn: 0, row: 1), 0)
        XCTAssertEqual(grid.maxCount, 2)
    }

    // MARK: - Document-level chart data

    func testScatterChartDataSwitchesToDensityGridForManyPoints() throws {
        var lines = ["x,y"]
        for i in 0..<50 {
            lines.append("\(i),\(i * 2)")
        }
        let (doc, path) = try openIndexed(lines.joined(separator: "\n") + "\n")
        defer { try? FileManager.default.removeItem(atPath: path) }

        let scatter = try doc.scatterChartData(xColumn: 0, yColumn: 1, maxScatterPoints: 10, cancellation: CancellationFlag())
        XCTAssertNotNil(scatter.densityGrid, "over the cap the scatter must aggregate to a density grid")
        XCTAssertTrue(scatter.points.isEmpty)
        XCTAssertEqual(scatter.regression?.slope ?? .nan, 2, accuracy: 1e-9)

        let smallScatter = try doc.scatterChartData(xColumn: 0, yColumn: 1, maxScatterPoints: 1_000, cancellation: CancellationFlag())
        XCTAssertNil(smallScatter.densityGrid)
        XCTAssertEqual(smallScatter.points.count, 50)
    }

    func testCorrelationMatrixIsSymmetricWithUnitDiagonal() throws {
        let (doc, path) = try openIndexed("""
        a,b,c
        1,2,10
        2,4,8
        3,6,6
        4,8,4

        """)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let matrix = try doc.correlationMatrixChartData(columns: [0, 1, 2], cancellation: CancellationFlag())
        XCTAssertEqual(matrix.columns, [0, 1, 2])
        XCTAssertEqual(matrix.value(row: 0, column: 0) ?? .nan, 1, accuracy: 1e-9)
        XCTAssertEqual(matrix.value(row: 0, column: 1) ?? .nan, 1, accuracy: 1e-9, "b = 2a is perfectly correlated")
        XCTAssertEqual(matrix.value(row: 0, column: 2) ?? .nan, -1, accuracy: 1e-9, "c descends as a ascends")
        XCTAssertEqual(
            matrix.value(row: 1, column: 2) ?? .nan,
            matrix.value(row: 2, column: 1) ?? .nan,
            accuracy: 1e-12
        )
    }

    func testParetoChartDataAccumulatesToHundredPercent() throws {
        let (doc, path) = try openIndexed("""
        defect
        scratch
        scratch
        scratch
        dent
        dent
        stain

        """)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let pareto = try doc.paretoChartData(column: 0, limit: 10, cancellation: CancellationFlag())
        XCTAssertEqual(pareto.entries.map(\.label), ["scratch", "dent", "stain"])
        XCTAssertEqual(pareto.entries.map(\.count), [3, 2, 1])
        XCTAssertEqual(pareto.entries.last?.cumulativePercent ?? 0, 100, accuracy: 1e-9)
        XCTAssertEqual(pareto.entries.first?.cumulativePercent ?? 0, 50, accuracy: 1e-9)
    }

    func testHistogramChartDataIncludesKdeAndNormality() throws {
        var lines = ["v"]
        var generator = SystemRandomNumberGenerator()
        for _ in 0..<80 {
            lines.append(String(Double.random(in: 0...100, using: &generator)))
        }
        let (doc, path) = try openIndexed(lines.joined(separator: "\n") + "\n")
        defer { try? FileManager.default.removeItem(atPath: path) }

        let histogram = try doc.histogramChartData(column: 0, binCount: 10, cancellation: CancellationFlag())
        XCTAssertEqual(histogram.distribution.bins.count, 10)
        XCTAssertFalse(histogram.density.isEmpty)
        XCTAssertNotNil(histogram.normality)
    }

    func testBoxplotChartDataGroupsAndRunsAnova() throws {
        let (doc, path) = try openIndexed("""
        group,value
        a,1
        a,2
        a,3
        a,4
        b,11
        b,12
        b,13
        b,14

        """)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let boxplot = try doc.boxplotChartData(groupColumn: 0, valueColumn: 1, cancellation: CancellationFlag())
        XCTAssertEqual(boxplot.groups.map(\.label), ["a", "b"])
        XCTAssertEqual(boxplot.groups[0].summary.median, 2.5, accuracy: 1e-9)
        XCTAssertEqual(boxplot.groups[1].summary.median, 12.5, accuracy: 1e-9)
        XCTAssertNotNil(boxplot.anova)
        XCTAssertLessThan(boxplot.anova?.pValue ?? 1, 0.001, "clearly separated groups")
    }
}
