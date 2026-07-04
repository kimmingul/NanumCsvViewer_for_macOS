import Foundation

public struct DescriptiveStatisticsResult: Equatable, Sendable {
    public let count: Int
    public let missingCount: Int
    public let mean: Double
    public let standardDeviation: Double
    public let standardError: Double
    public let confidenceIntervalLow: Double
    public let confidenceIntervalHigh: Double
    public let minimum: Double
    public let quartile1: Double
    public let median: Double
    public let quartile3: Double
    public let maximum: Double
    public let range: Double
    public let interquartileRange: Double
    public let modes: [Double]
    public let skewness: Double
    public let excessKurtosis: Double
    public let coefficientOfVariation: Double
}

public struct FrequencyEntry: Equatable, Sendable {
    public let value: String
    public let count: Int
    public let percent: Double
    public let cumulativePercent: Double
}

public struct FrequencyAnalysisResult: Equatable, Sendable {
    public let entries: [FrequencyEntry]
    public let total: Int
    public let distinctCount: Int
}

public struct AnovaGroupSummary: Equatable, Sendable {
    public let name: String
    public let count: Int
    public let mean: Double
    public let standardDeviation: Double
}

public struct OneWayAnovaResult: Equatable, Sendable {
    public let fStatistic: Double
    public let degreesOfFreedomBetween: Int
    public let degreesOfFreedomWithin: Int
    public let pValue: Double
    public let etaSquared: Double
    public let groups: [AnovaGroupSummary]
    public let interpretation: String
}

public struct ShapiroWilkResult: Equatable, Sendable {
    public let wStatistic: Double
    public let pValue: Double
    public let sampleSize: Int
    public let interpretation: String
}

extension CsvStatistics {
    // MARK: - Descriptive statistics

    static func descriptive(values: [Double], missingCount: Int) -> DescriptiveStatisticsResult {
        let clean = values.filter(\.isFinite)
        let n = clean.count
        guard n > 0 else {
            return DescriptiveStatisticsResult(
                count: 0, missingCount: missingCount, mean: 0, standardDeviation: 0,
                standardError: 0, confidenceIntervalLow: 0, confidenceIntervalHigh: 0,
                minimum: 0, quartile1: 0, median: 0, quartile3: 0, maximum: 0,
                range: 0, interquartileRange: 0, modes: [], skewness: 0,
                excessKurtosis: 0, coefficientOfVariation: 0
            )
        }

        let sorted = clean.sorted()
        let m = mean(clean)
        let variance = n > 1 ? clean.reduce(0) { $0 + pow($1 - m, 2) } / Double(n - 1) : 0
        let sd = sqrt(variance)
        let se = n > 0 ? sd / sqrt(Double(n)) : 0
        let critical = n > 1 ? studentTCriticalTwoSided(alpha: 0.05, degreesOfFreedom: Double(n - 1)) : 0
        let q1 = percentileLinear(sorted, 0.25)
        let q2 = percentileLinear(sorted, 0.5)
        let q3 = percentileLinear(sorted, 0.75)

        return DescriptiveStatisticsResult(
            count: n,
            missingCount: missingCount,
            mean: m,
            standardDeviation: sd,
            standardError: se,
            confidenceIntervalLow: m - critical * se,
            confidenceIntervalHigh: m + critical * se,
            minimum: sorted[0],
            quartile1: q1,
            median: q2,
            quartile3: q3,
            maximum: sorted[n - 1],
            range: sorted[n - 1] - sorted[0],
            interquartileRange: q3 - q1,
            modes: modes(sorted),
            skewness: sampleSkewness(clean, mean: m),
            excessKurtosis: sampleExcessKurtosis(clean, mean: m),
            coefficientOfVariation: m == 0 ? 0 : sd / m
        )
    }

    /// numpy percentile with method='linear' on an ascending-sorted array.
    private static func percentileLinear(_ sorted: [Double], _ q: Double) -> Double {
        guard !sorted.isEmpty else { return 0 }
        guard sorted.count > 1 else { return sorted[0] }
        let position = q * Double(sorted.count - 1)
        let lower = Int(position.rounded(.down))
        let upper = min(lower + 1, sorted.count - 1)
        let fraction = position - Double(lower)
        return sorted[lower] + (sorted[upper] - sorted[lower]) * fraction
    }

    private static func modes(_ sorted: [Double]) -> [Double] {
        var runs: [(value: Double, length: Int)] = []
        for value in sorted {
            if let last = runs.last, last.value == value {
                runs[runs.count - 1].length += 1
            } else {
                runs.append((value, 1))
            }
        }
        let maxRun = runs.map(\.length).max() ?? 1
        guard maxRun > 1 else { return [] }
        return runs.filter { $0.length == maxRun }.map(\.value)
    }

    /// Bias-corrected sample skewness (scipy stats.skew with bias=False).
    private static func sampleSkewness(_ values: [Double], mean m: Double) -> Double {
        let n = Double(values.count)
        guard n > 2 else { return 0 }
        let m2 = values.reduce(0) { $0 + pow($1 - m, 2) } / n
        let m3 = values.reduce(0) { $0 + pow($1 - m, 3) } / n
        guard m2 > 0 else { return 0 }
        let g1 = m3 / pow(m2, 1.5)
        return g1 * sqrt(n * (n - 1)) / (n - 2)
    }

    /// Bias-corrected excess kurtosis (scipy stats.kurtosis with bias=False).
    private static func sampleExcessKurtosis(_ values: [Double], mean m: Double) -> Double {
        let n = Double(values.count)
        guard n > 3 else { return 0 }
        let m2 = values.reduce(0) { $0 + pow($1 - m, 2) } / n
        let m4 = values.reduce(0) { $0 + pow($1 - m, 4) } / n
        guard m2 > 0 else { return 0 }
        let g2 = m4 / (m2 * m2) - 3
        return ((n + 1) * g2 + 6) * (n - 1) / ((n - 2) * (n - 3))
    }

    // MARK: - Frequency analysis

    static func frequencyAnalysis(values: [String], blankLabel: String, limit: Int? = nil) -> FrequencyAnalysisResult {
        var counts: [String: Int] = [:]
        for value in values {
            counts[value, default: 0] += 1
        }
        let total = values.count
        var ordered = counts.sorted { lhs, rhs in
            if lhs.value != rhs.value { return lhs.value > rhs.value }
            return lhs.key.localizedCaseInsensitiveCompare(rhs.key) == .orderedAscending
        }
        // Blank values sort to the end regardless of count so the label reads naturally.
        if let blankIndex = ordered.firstIndex(where: { $0.key.isEmpty }) {
            let blank = ordered.remove(at: blankIndex)
            ordered.append(blank)
        }
        if let limit, ordered.count > limit {
            ordered = Array(ordered.prefix(limit))
        }

        var cumulative = 0.0
        let entries = ordered.map { key, count -> FrequencyEntry in
            let percent = total > 0 ? Double(count) * 100 / Double(total) : 0
            cumulative += percent
            return FrequencyEntry(
                value: key.isEmpty ? blankLabel : key,
                count: count,
                percent: percent,
                cumulativePercent: cumulative
            )
        }
        return FrequencyAnalysisResult(entries: entries, total: total, distinctCount: counts.count)
    }

    // MARK: - One-way ANOVA

    static func oneWayAnova(groups: [(String, [Double])]) -> OneWayAnovaResult {
        let cleanGroups = groups.map { ($0.0, $0.1.filter(\.isFinite)) }.filter { !$0.1.isEmpty }
        let summaries = cleanGroups.map { name, values -> AnovaGroupSummary in
            let m = mean(values)
            let variance = values.count > 1
                ? values.reduce(0) { $0 + pow($1 - m, 2) } / Double(values.count - 1)
                : 0
            return AnovaGroupSummary(name: name, count: values.count, mean: m, standardDeviation: sqrt(variance))
        }

        let k = cleanGroups.count
        let all = cleanGroups.flatMap(\.1)
        let totalCount = all.count
        guard k > 1, totalCount > k else {
            return OneWayAnovaResult(
                fStatistic: 0, degreesOfFreedomBetween: max(0, k - 1),
                degreesOfFreedomWithin: max(0, totalCount - k), pValue: 1,
                etaSquared: 0, groups: summaries,
                interpretation: "not statistically significant (p >= 0.05)"
            )
        }

        let grandMean = mean(all)
        let ssBetween = cleanGroups.reduce(0.0) { total, group in
            total + Double(group.1.count) * pow(mean(group.1) - grandMean, 2)
        }
        let ssWithin = cleanGroups.reduce(0.0) { total, group in
            let m = mean(group.1)
            return total + group.1.reduce(0) { $0 + pow($1 - m, 2) }
        }
        let dfBetween = k - 1
        let dfWithin = totalCount - k
        let msBetween = ssBetween / Double(dfBetween)
        let msWithin = ssWithin / Double(dfWithin)
        let f = msWithin > 0 ? msBetween / msWithin : (msBetween > 0 ? .infinity : 0)
        let p = fSurvival(f, degreesOfFreedom1: Double(dfBetween), degreesOfFreedom2: Double(dfWithin))
        let ssTotal = ssBetween + ssWithin
        return OneWayAnovaResult(
            fStatistic: f,
            degreesOfFreedomBetween: dfBetween,
            degreesOfFreedomWithin: dfWithin,
            pValue: p,
            etaSquared: ssTotal > 0 ? ssBetween / ssTotal : 0,
            groups: summaries,
            interpretation: p < 0.05
                ? "statistically significant (p < 0.05)"
                : "not statistically significant (p >= 0.05)"
        )
    }

    private static func fSurvival(_ f: Double, degreesOfFreedom1 d1: Double, degreesOfFreedom2 d2: Double) -> Double {
        guard f.isFinite else { return f > 0 ? 0 : 1 }
        guard f > 0, d1 > 0, d2 > 0 else { return 1 }
        let x = d2 / (d2 + d1 * f)
        return clampedProbability(regularizedIncompleteBeta(a: d2 / 2, b: d1 / 2, x: x))
    }

    // MARK: - Shapiro-Wilk (Royston 1995, AS R94)

    static func shapiroWilk(values: [Double]) -> ShapiroWilkResult {
        let x = values.filter(\.isFinite).sorted()
        let n = x.count
        guard n >= 3 else {
            return ShapiroWilkResult(wStatistic: 1, pValue: 1, sampleSize: n, interpretation: "sample too small")
        }
        guard x[0] != x[n - 1] else {
            return ShapiroWilkResult(wStatistic: 1, pValue: 1, sampleSize: n, interpretation: "constant data")
        }

        // Expected normal order statistics.
        var m = (0..<n).map { i in
            normalQuantile((Double(i) + 1 - 0.375) / (Double(n) + 0.25))
        }
        let ssq = m.reduce(0) { $0 + $1 * $1 }
        let rsn = 1 / sqrt(Double(n))
        var weights = Array(repeating: 0.0, count: n)

        if n == 3 {
            weights[0] = -sqrt(0.5)
            weights[2] = sqrt(0.5)
        } else {
            let c = m.map { $0 / sqrt(ssq) }
            let an = polynomial([-2.706056, 4.434685, -2.071190, -0.147981, 0.221157, c[n - 1]], rsn)
            weights[n - 1] = an
            weights[0] = -an
            var phi: Double
            if n > 5 {
                let an1 = polynomial([-3.582633, 5.682633, -1.752461, -0.293762, 0.042981, c[n - 2]], rsn)
                weights[n - 2] = an1
                weights[1] = -an1
                phi = (ssq - 2 * m[n - 1] * m[n - 1] - 2 * m[n - 2] * m[n - 2])
                    / (1 - 2 * an * an - 2 * an1 * an1)
            } else {
                phi = (ssq - 2 * m[n - 1] * m[n - 1]) / (1 - 2 * an * an)
            }
            let bound = n > 5 ? 2 : 1
            for i in bound..<(n - bound) {
                weights[i] = m[i] / sqrt(phi)
            }
        }
        m = []

        let meanX = x.reduce(0, +) / Double(n)
        let ssx = x.reduce(0) { $0 + pow($1 - meanX, 2) }
        let b = zip(weights, x).reduce(0) { $0 + $1.0 * $1.1 }
        let w = min(1, ssx > 0 ? (b * b) / ssx : 1)

        let p: Double
        let nd = Double(n)
        if n == 3 {
            p = max(0, min(1, 6 / Double.pi * (asin(sqrt(w)) - asin(sqrt(0.75)))))
        } else if n <= 11 {
            let gamma = -2.273 + 0.459 * nd
            let transformed = -log(max(1e-12, gamma - log1p(-w)))
            let mu = 0.5440 - 0.39978 * nd + 0.025054 * nd * nd - 0.0006714 * nd * nd * nd
            let sigma = exp(1.3822 - 0.77857 * nd + 0.062767 * nd * nd - 0.0020322 * nd * nd * nd)
            p = upperTailNormal((transformed - mu) / sigma)
        } else {
            let transformed = log1p(-w)
            let u = log(nd)
            let mu = -1.5861 - 0.31082 * u - 0.083751 * u * u + 0.0038915 * u * u * u
            let sigma = exp(-0.4803 - 0.082676 * u + 0.0030302 * u * u)
            p = upperTailNormal((transformed - mu) / sigma)
        }

        return ShapiroWilkResult(
            wStatistic: w,
            pValue: p,
            sampleSize: n,
            interpretation: p < 0.05
                ? "deviates from normality (p < 0.05)"
                : "consistent with normality (p >= 0.05)"
        )
    }

    /// Evaluates c[0]*x^(k-1) + c[1]*x^(k-2) + ... + c[k-1] (Royston's poly with
    /// the constant term supplied last).
    private static func polynomial(_ coefficients: [Double], _ x: Double) -> Double {
        coefficients.reduce(0) { $0 * x + $1 }
    }

    private static func upperTailNormal(_ z: Double) -> Double {
        0.5 * erfc(z / 2.0.squareRoot())
    }

    /// Acklam's inverse normal CDF approximation (|relative error| < 1.15e-9).
    static func normalQuantile(_ p: Double) -> Double {
        guard p > 0 else { return -.infinity }
        guard p < 1 else { return .infinity }

        let a: [Double] = [
            -3.969683028665376e+01, 2.209460984245205e+02, -2.759285104469687e+02,
            1.383577518672690e+02, -3.066479806614716e+01, 2.506628277459239e+00
        ]
        let b: [Double] = [
            -5.447609879822406e+01, 1.615858368580409e+02, -1.556989798598866e+02,
            6.680131188771972e+01, -1.328068155288572e+01
        ]
        let c: [Double] = [
            -7.784894002430293e-03, -3.223964580411365e-01, -2.400758277161838e+00,
            -2.549732539343734e+00, 4.374664141464968e+00, 2.938163982698783e+00
        ]
        let d: [Double] = [
            7.784695709041462e-03, 3.224671290700398e-01, 2.445134137142996e+00,
            3.754408661907416e+00
        ]
        let low = 0.02425
        let high = 1 - low

        func tailValue(_ q: Double) -> Double {
            let r = sqrt(-2 * log(q))
            return (((((c[0] * r + c[1]) * r + c[2]) * r + c[3]) * r + c[4]) * r + c[5])
                / ((((d[0] * r + d[1]) * r + d[2]) * r + d[3]) * r + 1)
        }

        if p < low {
            return tailValue(p)
        }
        if p > high {
            return -tailValue(1 - p)
        }
        let q = p - 0.5
        let r = q * q
        return (((((a[0] * r + a[1]) * r + a[2]) * r + a[3]) * r + a[4]) * r + a[5]) * q
            / (((((b[0] * r + b[1]) * r + b[2]) * r + b[3]) * r + b[4]) * r + 1)
    }
}

extension VirtualCsvDocument {
    /// Streams display rows and extracts single-column values without
    /// materializing the full row set (rows x columns) in memory.
    private func forEachDisplayRow(cancellation: CancellationFlag, _ body: ([String]) -> Void) throws {
        let total = analysisRowScanBound
        for viewRow in 0..<total {
            if viewRow & 0xFFF == 0 { try cancellation.check() }
            body(try getDisplayRow(viewRow))
        }
    }

    public func descriptiveStatistics(column: Int, cancellation: CancellationFlag) throws -> DescriptiveStatisticsResult {
        let results = try descriptiveStatisticsBatch(columns: [column], cancellation: cancellation)
        return results[column] ?? CsvStatistics.descriptive(values: [], missingCount: 0)
    }

    /// Single streaming pass that aggregates several columns at once, so
    /// "all numeric columns" descriptive statistics reads the view only once.
    public func descriptiveStatisticsBatch(columns: [Int], cancellation: CancellationFlag) throws -> [Int: DescriptiveStatisticsResult] {
        let targets = columns.filter { $0 >= 0 }
        guard !targets.isEmpty else { return [:] }
        var values: [Int: [Double]] = Dictionary(uniqueKeysWithValues: targets.map { ($0, []) })
        var missing: [Int: Int] = Dictionary(uniqueKeysWithValues: targets.map { ($0, 0) })
        try forEachDisplayRow(cancellation: cancellation) { row in
            for column in targets {
                guard column < row.count,
                      let value = Double(row[column].trimmingCharacters(in: .whitespacesAndNewlines)),
                      value.isFinite else {
                    missing[column, default: 0] += 1
                    continue
                }
                values[column, default: []].append(value)
            }
        }
        var results: [Int: DescriptiveStatisticsResult] = [:]
        for column in targets {
            results[column] = CsvStatistics.descriptive(values: values[column] ?? [], missingCount: missing[column] ?? 0)
        }
        return results
    }

    public func frequencyAnalysis(column: Int, blankLabel: String, limit: Int? = nil, cancellation: CancellationFlag) throws -> FrequencyAnalysisResult {
        var values: [String] = []
        try forEachDisplayRow(cancellation: cancellation) { row in
            values.append(column >= 0 && column < row.count ? row[column] : "")
        }
        return CsvStatistics.frequencyAnalysis(values: values, blankLabel: blankLabel, limit: limit)
    }

    public func oneWayAnova(groupColumn: Int, valueColumn: Int, cancellation: CancellationFlag) throws -> OneWayAnovaResult {
        var grouped: [String: [Double]] = [:]
        var order: [String] = []
        try forEachDisplayRow(cancellation: cancellation) { row in
            guard groupColumn >= 0, groupColumn < row.count,
                  valueColumn >= 0, valueColumn < row.count,
                  let value = Double(row[valueColumn].trimmingCharacters(in: .whitespacesAndNewlines)) else {
                return
            }
            let key = row[groupColumn]
            if grouped[key] == nil { order.append(key) }
            grouped[key, default: []].append(value)
        }
        return CsvStatistics.oneWayAnova(groups: order.map { ($0, grouped[$0] ?? []) })
    }

    public func shapiroWilk(column: Int, cancellation: CancellationFlag) throws -> ShapiroWilkResult {
        var values: [Double] = []
        try forEachDisplayRow(cancellation: cancellation) { row in
            guard column >= 0, column < row.count else { return }
            if let value = Double(row[column].trimmingCharacters(in: .whitespacesAndNewlines)) {
                values.append(value)
            }
        }
        return CsvStatistics.shapiroWilk(values: values)
    }
}
