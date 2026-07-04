import Foundation

public struct KernelDensityPoint: Equatable, Sendable {
    public let x: Double
    public let density: Double
}

public struct LinearRegressionResult: Equatable, Sendable {
    public let slope: Double
    public let intercept: Double
    public let rSquared: Double
    public let sampleSize: Int
}

public struct BoxplotSummary: Equatable, Sendable {
    public let count: Int
    public let quartile1: Double
    public let median: Double
    public let quartile3: Double
    public let whiskerLow: Double
    public let whiskerHigh: Double
    public let outliers: [Double]
}

public struct QQPoint: Equatable, Sendable {
    public let theoretical: Double
    public let sample: Double

    public init(theoretical: Double, sample: Double) {
        self.theoretical = theoretical
        self.sample = sample
    }
}

public struct DensityGrid: Equatable, Sendable {
    public let columns: Int
    public let rows: Int
    public let xRange: ClosedRange<Double>
    public let yRange: ClosedRange<Double>
    public let counts: [Int]
    public let maxCount: Int

    public func count(atColumn column: Int, row: Int) -> Int {
        guard column >= 0, column < columns, row >= 0, row < rows else { return 0 }
        return counts[row * columns + column]
    }
}

public enum CsvChartMath {
    /// Gaussian KDE with Silverman's rule-of-thumb bandwidth, evaluated on an
    /// evenly spaced grid over the sample range. Large inputs are
    /// stride-sampled: the naive evaluation is O(values x grid) and a full
    /// 2M-row column would otherwise stall for minutes.
    public static func kernelDensity(values: [Double], gridCount: Int = 128, sampleCap: Int = 20_000) -> [KernelDensityPoint] {
        var sample = values.filter(\.isFinite)
        if sample.count > sampleCap, sampleCap >= 2 {
            let stride = Double(sample.count - 1) / Double(sampleCap - 1)
            sample = (0..<sampleCap).map { sample[Int((Double($0) * stride).rounded())] }
        }
        guard sample.count >= 2, gridCount >= 2 else { return [] }
        guard let minValue = sample.min(), let maxValue = sample.max(), minValue < maxValue else { return [] }

        let n = Double(sample.count)
        let mean = sample.reduce(0, +) / n
        let variance = sample.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / (n - 1)
        let standardDeviation = variance.squareRoot()
        let sorted = sample.sorted()
        let iqr = percentileLinear(sorted, 0.75) - percentileLinear(sorted, 0.25)
        var spread = Swift.min(standardDeviation, iqr / 1.34)
        if spread <= 0 { spread = standardDeviation }
        guard spread > 0 else { return [] }
        let bandwidth = 0.9 * spread * pow(n, -0.2)
        guard bandwidth > 0 else { return [] }

        let step = (maxValue - minValue) / Double(gridCount - 1)
        let normalization = 1.0 / (n * bandwidth * (2 * Double.pi).squareRoot())
        return (0..<gridCount).map { index in
            let x = minValue + Double(index) * step
            var sum = 0.0
            for value in sample {
                let z = (x - value) / bandwidth
                sum += exp(-0.5 * z * z)
            }
            return KernelDensityPoint(x: x, density: sum * normalization)
        }
    }

    public static func linearRegression(pairs: [(Double, Double)]) -> LinearRegressionResult? {
        let sample = pairs.filter { $0.0.isFinite && $0.1.isFinite }
        let n = Double(sample.count)
        guard sample.count >= 2 else { return nil }
        let meanX = sample.reduce(0) { $0 + $1.0 } / n
        let meanY = sample.reduce(0) { $0 + $1.1 } / n
        var sxx = 0.0
        var sxy = 0.0
        var syy = 0.0
        for (x, y) in sample {
            sxx += (x - meanX) * (x - meanX)
            sxy += (x - meanX) * (y - meanY)
            syy += (y - meanY) * (y - meanY)
        }
        guard sxx > 0 else { return nil }
        let slope = sxy / sxx
        let intercept = meanY - slope * meanX
        let rSquared = syy > 0 ? (sxy * sxy) / (sxx * syy) : 1
        return LinearRegressionResult(slope: slope, intercept: intercept, rSquared: rSquared, sampleSize: sample.count)
    }

    public static func boxplotSummary(values: [Double], outlierCap: Int = 200) -> BoxplotSummary? {
        let sorted = values.filter(\.isFinite).sorted()
        guard !sorted.isEmpty else { return nil }
        let q1 = percentileLinear(sorted, 0.25)
        let median = percentileLinear(sorted, 0.5)
        let q3 = percentileLinear(sorted, 0.75)
        let iqr = q3 - q1
        let lowFence = q1 - 1.5 * iqr
        let highFence = q3 + 1.5 * iqr
        let inliers = sorted.filter { $0 >= lowFence && $0 <= highFence }
        let outliers = sorted.filter { $0 < lowFence || $0 > highFence }
        return BoxplotSummary(
            count: sorted.count,
            quartile1: q1,
            median: median,
            quartile3: q3,
            whiskerLow: inliers.first ?? q1,
            whiskerHigh: inliers.last ?? q3,
            outliers: Array(outliers.prefix(outlierCap))
        )
    }

    /// Blom plotting positions against the standard normal, matching the
    /// convention used by the Shapiro-Wilk implementation.
    public static func normalQQPoints(values: [Double], cap: Int = 2_000) -> [QQPoint] {
        var sorted = values.filter(\.isFinite).sorted()
        guard sorted.count >= 3 else { return [] }
        if sorted.count > cap {
            let stride = Double(sorted.count - 1) / Double(cap - 1)
            sorted = (0..<cap).map { sorted[Int((Double($0) * stride).rounded())] }
        }
        let n = Double(sorted.count)
        return sorted.enumerated().map { index, value in
            let p = (Double(index) + 1 - 0.375) / (n + 0.25)
            return QQPoint(theoretical: CsvStatistics.normalQuantile(p), sample: value)
        }
    }

    public static func densityGrid(pairs: [(Double, Double)], columns: Int, rows: Int) -> DensityGrid? {
        let sample = pairs.filter { $0.0.isFinite && $0.1.isFinite }
        guard !sample.isEmpty, columns > 0, rows > 0 else { return nil }
        let xs = sample.map(\.0)
        let ys = sample.map(\.1)
        guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else { return nil }
        let xSpan = maxX > minX ? maxX - minX : 1
        let ySpan = maxY > minY ? maxY - minY : 1
        var counts = [Int](repeating: 0, count: columns * rows)
        for (x, y) in sample {
            let column = Swift.min(columns - 1, Int((x - minX) / xSpan * Double(columns)))
            let row = Swift.min(rows - 1, Int((y - minY) / ySpan * Double(rows)))
            counts[row * columns + column] += 1
        }
        return DensityGrid(
            columns: columns,
            rows: rows,
            xRange: minX...maxX,
            yRange: minY...maxY,
            counts: counts,
            maxCount: counts.max() ?? 0
        )
    }

    static func percentileLinear(_ sorted: [Double], _ q: Double) -> Double {
        guard !sorted.isEmpty else { return 0 }
        guard sorted.count > 1 else { return sorted[0] }
        let position = q * Double(sorted.count - 1)
        let lower = Int(position.rounded(.down))
        let upper = Swift.min(lower + 1, sorted.count - 1)
        let fraction = position - Double(lower)
        return sorted[lower] + fraction * (sorted[upper] - sorted[lower])
    }
}

// MARK: - Document-level chart datasets

public struct HistogramChartData: Equatable, Sendable {
    public let distribution: NumericDistribution
    public let density: [KernelDensityPoint]
    public let normality: ShapiroWilkResult?
}

public struct BoxplotChartGroup: Equatable, Sendable {
    public let label: String
    public let summary: BoxplotSummary
}

public struct BoxplotChartData: Equatable, Sendable {
    public let groups: [BoxplotChartGroup]
    public let anova: OneWayAnovaResult?
}

public struct ScatterChartData: Equatable, Sendable {
    public struct Point: Equatable, Sendable {
        public let x: Double
        public let y: Double
    }

    public let points: [Point]
    public let densityGrid: DensityGrid?
    public let regression: LinearRegressionResult?
    public let totalPairCount: Int
}

public struct CorrelationMatrixChartData: Equatable, Sendable {
    public let columns: [Int]
    public let values: [Double?]

    public func value(row: Int, column: Int) -> Double? {
        guard row >= 0, row < columns.count, column >= 0, column < columns.count else { return nil }
        return values[row * columns.count + column]
    }
}

public struct ParetoChartEntry: Equatable, Sendable {
    public let label: String
    public let count: Int
    public let cumulativePercent: Double
}

public struct ParetoChartData: Equatable, Sendable {
    public let entries: [ParetoChartEntry]
    public let totalCount: Int
}

extension VirtualCsvDocument {
    public func histogramChartData(column: Int, binCount: Int = 20, cancellation: CancellationFlag) throws -> HistogramChartData {
        let distribution = try numericDistribution(column: column, binCount: binCount, cancellation: cancellation)
        let values = try numericColumnValues(column: column, cancellation: cancellation)
        // Royston's Shapiro-Wilk is only calibrated up to n = 5000, so larger
        // columns are tested on a deterministic stride sample.
        let normalityInput: [Double]
        if values.count > 5_000 {
            let stride = Double(values.count - 1) / Double(4_999)
            normalityInput = (0..<5_000).map { values[Int((Double($0) * stride).rounded())] }
        } else {
            normalityInput = values
        }
        let normality = normalityInput.count >= 3 ? CsvStatistics.shapiroWilk(values: normalityInput) : nil
        return HistogramChartData(
            distribution: distribution,
            density: CsvChartMath.kernelDensity(values: values),
            normality: normality
        )
    }

    public func boxplotChartData(groupColumn: Int?, valueColumn: Int, cancellation: CancellationFlag) throws -> BoxplotChartData {
        var grouped: [String: [Double]] = [:]
        var order: [String] = []
        for row in try currentDisplayRows(cancellation: cancellation) {
            guard valueColumn < row.count,
                  let value = Double(row[valueColumn].trimmingCharacters(in: .whitespacesAndNewlines)),
                  value.isFinite else { continue }
            let key: String
            if let groupColumn {
                key = groupColumn < row.count ? row[groupColumn] : ""
            } else {
                key = ""
            }
            if grouped[key] == nil { order.append(key) }
            grouped[key, default: []].append(value)
        }
        order.sort { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        let groups = order.compactMap { key -> BoxplotChartGroup? in
            guard let summary = CsvChartMath.boxplotSummary(values: grouped[key] ?? []) else { return nil }
            return BoxplotChartGroup(label: key, summary: summary)
        }
        let anova: OneWayAnovaResult?
        if groupColumn != nil, groups.count >= 2 {
            anova = CsvStatistics.oneWayAnova(groups: order.map { ($0, grouped[$0] ?? []) })
        } else {
            anova = nil
        }
        return BoxplotChartData(groups: groups, anova: anova)
    }

    public func scatterChartData(
        xColumn: Int,
        yColumn: Int,
        maxScatterPoints: Int = 20_000,
        cancellation: CancellationFlag
    ) throws -> ScatterChartData {
        var pairs: [(Double, Double)] = []
        for row in try currentDisplayRows(cancellation: cancellation) {
            guard xColumn < row.count, yColumn < row.count,
                  let x = Double(row[xColumn].trimmingCharacters(in: .whitespacesAndNewlines)),
                  let y = Double(row[yColumn].trimmingCharacters(in: .whitespacesAndNewlines)),
                  x.isFinite, y.isFinite else { continue }
            pairs.append((x, y))
        }
        let regression = CsvChartMath.linearRegression(pairs: pairs)
        if pairs.count > maxScatterPoints {
            return ScatterChartData(
                points: [],
                densityGrid: CsvChartMath.densityGrid(pairs: pairs, columns: 64, rows: 48),
                regression: regression,
                totalPairCount: pairs.count
            )
        }
        return ScatterChartData(
            points: pairs.map { ScatterChartData.Point(x: $0.0, y: $0.1) },
            densityGrid: nil,
            regression: regression,
            totalPairCount: pairs.count
        )
    }

    public func correlationMatrixChartData(columns: [Int], cancellation: CancellationFlag) throws -> CorrelationMatrixChartData {
        let targets = columns.filter { $0 >= 0 && $0 < columnCount }
        var series: [Int: [Double?]] = [:]
        let rows = try currentDisplayRows(cancellation: cancellation)
        for column in targets {
            series[column] = rows.map { row in
                guard column < row.count,
                      let value = Double(row[column].trimmingCharacters(in: .whitespacesAndNewlines)),
                      value.isFinite else { return nil }
                return value
            }
        }
        var values = [Double?](repeating: nil, count: targets.count * targets.count)
        for (i, a) in targets.enumerated() {
            for (j, b) in targets.enumerated() where j >= i {
                var pairs: [(Double, Double)] = []
                let seriesA = series[a] ?? []
                let seriesB = series[b] ?? []
                for index in 0..<Swift.min(seriesA.count, seriesB.count) {
                    if let x = seriesA[index], let y = seriesB[index] {
                        pairs.append((x, y))
                    }
                }
                let coefficient: Double?
                if i == j {
                    coefficient = pairs.count >= 2 ? 1 : nil
                } else if pairs.count >= 3 {
                    let result = CsvStatistics.correlation(pairs: pairs, method: .pearson)
                    coefficient = result.coefficient.isFinite ? result.coefficient : nil
                } else {
                    coefficient = nil
                }
                values[i * targets.count + j] = coefficient
                values[j * targets.count + i] = coefficient
            }
        }
        return CorrelationMatrixChartData(columns: targets, values: values)
    }

    public func qqChartData(column: Int, cancellation: CancellationFlag) throws -> [QQPoint] {
        CsvChartMath.normalQQPoints(values: try numericColumnValues(column: column, cancellation: cancellation))
    }

    public func paretoChartData(column: Int, limit: Int = 20, cancellation: CancellationFlag) throws -> ParetoChartData {
        var counts: [String: Int] = [:]
        for row in try currentDisplayRows(cancellation: cancellation) {
            let value = column >= 0 && column < row.count ? row[column] : ""
            guard !value.isEmpty else { continue }
            counts[value, default: 0] += 1
        }
        let sorted = counts.sorted { lhs, rhs in
            if lhs.value != rhs.value { return lhs.value > rhs.value }
            return lhs.key.localizedCaseInsensitiveCompare(rhs.key) == .orderedAscending
        }
        let total = sorted.reduce(0) { $0 + $1.value }
        guard total > 0 else { return ParetoChartData(entries: [], totalCount: 0) }
        var cumulative = 0
        let entries = sorted.prefix(max(0, limit)).map { key, count -> ParetoChartEntry in
            cumulative += count
            return ParetoChartEntry(
                label: key,
                count: count,
                cumulativePercent: Double(cumulative) * 100 / Double(total)
            )
        }
        return ParetoChartData(entries: Array(entries), totalCount: total)
    }

    private func numericColumnValues(column: Int, cancellation: CancellationFlag) throws -> [Double] {
        guard column >= 0, column < columnCount else { return [] }
        return try currentDisplayRows(cancellation: cancellation).compactMap { row in
            guard column < row.count,
                  let value = Double(row[column].trimmingCharacters(in: .whitespacesAndNewlines)),
                  value.isFinite else { return nil }
            return value
        }
    }
}
