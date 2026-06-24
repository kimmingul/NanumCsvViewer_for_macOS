import Darwin
import Foundation

public enum CorrelationMethod: String, Sendable {
    case pearson = "Pearson"
    case spearman = "Spearman"
}

public struct CorrelationResult: Equatable, Sendable {
    public let method: CorrelationMethod
    public let coefficient: Double
    public let pValue: Double
    public let sampleSize: Int
    public let interpretation: String
}

public struct IndependentTTestResult: Equatable, Sendable {
    public let groupA: String
    public let groupB: String
    public let meanA: Double
    public let meanB: Double
    public let tStatistic: Double
    public let degreesOfFreedom: Double
    public let pValue: Double
    public let confidenceIntervalLow: Double
    public let confidenceIntervalHigh: Double
    public let effectSize: Double
    public let interpretation: String
}

public struct PairedTTestResult: Equatable, Sendable {
    public let meanDifference: Double
    public let tStatistic: Double
    public let degreesOfFreedom: Double
    public let pValue: Double
    public let confidenceIntervalLow: Double
    public let confidenceIntervalHigh: Double
    public let effectSize: Double
    public let interpretation: String
}

public struct ChiSquareResult: Equatable, Sendable {
    public let statistic: Double
    public let degreesOfFreedom: Int
    public let pValue: Double
    public let rowLabels: [String]
    public let columnLabels: [String]
    public let observed: [[Double]]
    public let interpretation: String
}

enum CsvStatistics {
    static func correlation(pairs: [(Double, Double)], method: CorrelationMethod) -> CorrelationResult {
        let clean = pairs.filter { $0.0.isFinite && $0.1.isFinite }
        let transformed: [(Double, Double)]
        if method == .spearman {
            transformed = zip(ranks(clean.map(\.0)), ranks(clean.map(\.1))).map { ($0, $1) }
        } else {
            transformed = clean
        }
        let r = pearson(transformed)
        let n = transformed.count
        let t = n > 2 && abs(r) < 1 ? abs(r) * sqrt(Double(n - 2) / max(1e-12, 1 - r * r)) : Double.infinity
        let p = n > 2 ? twoSidedNormalPValue(t) : 1
        return CorrelationResult(
            method: method,
            coefficient: r,
            pValue: p,
            sampleSize: n,
            interpretation: interpretation(pValue: p)
        )
    }

    static func independentTTest(groupA: String, a: [Double], groupB: String, b: [Double]) -> IndependentTTestResult {
        let meanA = mean(a)
        let meanB = mean(b)
        let varianceA = sampleVariance(a)
        let varianceB = sampleVariance(b)
        let nA = Double(a.count)
        let nB = Double(b.count)
        let standardError = sqrt(varianceA / max(1, nA) + varianceB / max(1, nB))
        let diff = meanA - meanB
        let t = standardError == 0 ? 0 : diff / standardError
        let numerator = pow(varianceA / max(1, nA) + varianceB / max(1, nB), 2)
        let denominator = pow(varianceA / max(1, nA), 2) / max(1, nA - 1) + pow(varianceB / max(1, nB), 2) / max(1, nB - 1)
        let df = denominator == 0 ? max(1, nA + nB - 2) : numerator / denominator
        let p = twoSidedNormalPValue(abs(t))
        let ciLow = diff - 1.96 * standardError
        let ciHigh = diff + 1.96 * standardError
        let pooled = sqrt(((nA - 1) * varianceA + (nB - 1) * varianceB) / max(1, nA + nB - 2))
        let effect = pooled == 0 ? 0 : diff / pooled
        return IndependentTTestResult(
            groupA: groupA,
            groupB: groupB,
            meanA: meanA,
            meanB: meanB,
            tStatistic: t,
            degreesOfFreedom: df,
            pValue: p,
            confidenceIntervalLow: ciLow,
            confidenceIntervalHigh: ciHigh,
            effectSize: effect,
            interpretation: interpretation(pValue: p)
        )
    }

    static func pairedTTest(before: [Double], after: [Double]) -> PairedTTestResult {
        let differences = zip(after, before).map { $0 - $1 }
        let meanDiff = mean(differences)
        let variance = sampleVariance(differences)
        let n = Double(differences.count)
        let standardError = sqrt(variance / max(1, n))
        let t = standardError == 0 ? 0 : meanDiff / standardError
        let p = twoSidedNormalPValue(abs(t))
        let ciLow = meanDiff - 1.96 * standardError
        let ciHigh = meanDiff + 1.96 * standardError
        let sd = sqrt(variance)
        return PairedTTestResult(
            meanDifference: meanDiff,
            tStatistic: t,
            degreesOfFreedom: max(0, n - 1),
            pValue: p,
            confidenceIntervalLow: ciLow,
            confidenceIntervalHigh: ciHigh,
            effectSize: sd == 0 ? 0 : meanDiff / sd,
            interpretation: interpretation(pValue: p)
        )
    }

    static func chiSquare(rows: [(String, String)]) -> ChiSquareResult {
        let rowLabels = Array(Set(rows.map(\.0))).sorted()
        let columnLabels = Array(Set(rows.map(\.1))).sorted()
        var observed = Array(repeating: Array(repeating: 0.0, count: columnLabels.count), count: rowLabels.count)
        for pair in rows {
            guard let r = rowLabels.firstIndex(of: pair.0), let c = columnLabels.firstIndex(of: pair.1) else { continue }
            observed[r][c] += 1
        }

        let rowTotals = observed.map { $0.reduce(0, +) }
        let columnTotals = columnLabels.indices.map { column in observed.reduce(0) { $0 + $1[column] } }
        let total = rowTotals.reduce(0, +)
        var statistic = 0.0
        if total > 0 {
            for r in rowLabels.indices {
                for c in columnLabels.indices {
                    let expected = rowTotals[r] * columnTotals[c] / total
                    if expected > 0 {
                        statistic += pow(observed[r][c] - expected, 2) / expected
                    }
                }
            }
        }
        let df = max(0, (rowLabels.count - 1) * (columnLabels.count - 1))
        let p = chiSquareSurvival(statistic: statistic, degreesOfFreedom: df)
        return ChiSquareResult(
            statistic: statistic,
            degreesOfFreedom: df,
            pValue: p,
            rowLabels: rowLabels,
            columnLabels: columnLabels,
            observed: observed,
            interpretation: interpretation(pValue: p)
        )
    }

    private static func pearson(_ pairs: [(Double, Double)]) -> Double {
        guard pairs.count > 1 else { return 0 }
        let xs = pairs.map(\.0)
        let ys = pairs.map(\.1)
        let mx = mean(xs)
        let my = mean(ys)
        let numerator = zip(xs, ys).reduce(0) { $0 + ($1.0 - mx) * ($1.1 - my) }
        let dx = xs.reduce(0) { $0 + pow($1 - mx, 2) }
        let dy = ys.reduce(0) { $0 + pow($1 - my, 2) }
        let denominator = sqrt(dx * dy)
        return denominator == 0 ? 0 : numerator / denominator
    }

    private static func ranks(_ values: [Double]) -> [Double] {
        let sorted = values.enumerated().sorted { $0.element < $1.element }
        var output = Array(repeating: 0.0, count: values.count)
        var i = 0
        while i < sorted.count {
            var j = i
            while j + 1 < sorted.count, sorted[j + 1].element == sorted[i].element {
                j += 1
            }
            let rank = (Double(i + 1) + Double(j + 1)) / 2
            for k in i...j {
                output[sorted[k].offset] = rank
            }
            i = j + 1
        }
        return output
    }

    static func mean(_ values: [Double]) -> Double {
        values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
    }

    private static func sampleVariance(_ values: [Double]) -> Double {
        guard values.count > 1 else { return 0 }
        let m = mean(values)
        return values.reduce(0) { $0 + pow($1 - m, 2) } / Double(values.count - 1)
    }

    private static func twoSidedNormalPValue(_ z: Double) -> Double {
        guard z.isFinite else { return 0 }
        return max(0, min(1, erfc(abs(z) / sqrt(2))))
    }

    private static func chiSquareSurvival(statistic: Double, degreesOfFreedom: Int) -> Double {
        guard degreesOfFreedom > 0 else { return 1 }
        if degreesOfFreedom == 1 {
            return max(0, min(1, erfc(sqrt(max(0, statistic) / 2))))
        }
        let z = (pow(statistic / Double(degreesOfFreedom), 1.0 / 3.0) - (1 - 2.0 / (9 * Double(degreesOfFreedom)))) / sqrt(2.0 / (9 * Double(degreesOfFreedom)))
        return max(0, min(1, 0.5 * erfc(z / sqrt(2))))
    }

    private static func interpretation(pValue: Double) -> String {
        pValue < 0.05 ? "statistically significant (p < 0.05)" : "not statistically significant (p >= 0.05)"
    }
}
