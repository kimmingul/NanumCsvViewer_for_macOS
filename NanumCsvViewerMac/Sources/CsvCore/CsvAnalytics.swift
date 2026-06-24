import Foundation

public enum AggregationFunction: String, CaseIterable, Codable, Sendable {
    case count = "Count"
    case sum = "Sum"
    case mean = "Mean"
    case median = "Median"
    case min = "Min"
    case max = "Max"
    case uniqueCount = "Unique Count"
    case standardDeviation = "Std"
}

public struct DuplicateGroup: Equatable, Sendable {
    public let key: [String]
    public let sourceRows: [Int64]
}

public struct GroupByRow: Equatable, Sendable {
    public let key: [String]
    public let values: [AggregationFunction: Double]
}

public struct GroupByResult: Equatable, Sendable {
    public let groupColumns: [Int]
    public let valueColumn: Int
    public let functions: [AggregationFunction]
    public let rows: [GroupByRow]
}

public struct HistogramBin: Equatable, Sendable {
    public let lowerBound: Double
    public let upperBound: Double
    public let count: Int
}

public struct NumericDistribution: Equatable, Sendable {
    public let column: Int
    public let count: Int
    public let min: Double
    public let max: Double
    public let mean: Double
    public let median: Double
    public let q1: Double
    public let q3: Double
    public let standardDeviation: Double
    public let bins: [HistogramBin]
}

public enum DateBinPeriod: String, CaseIterable, Sendable {
    case day = "Day"
    case week = "Week"
    case month = "Month"
    case year = "Year"
}

public struct DateHistogramBin: Equatable, Sendable {
    public let label: String
    public let count: Int
    public let sum: Double?
    public let average: Double?
}

public struct DateHistogram: Equatable, Sendable {
    public let dateColumn: Int
    public let valueColumn: Int?
    public let period: DateBinPeriod
    public let bins: [DateHistogramBin]
}

enum CsvAnalytics {
    static func findDuplicates(rows: [(fields: [String], sourceRow: Int64)], columns: [Int]) -> [DuplicateGroup] {
        var groups: [[String]: [Int64]] = [:]
        for row in rows {
            let key = columns.map { column in column < row.fields.count ? row.fields[column] : "" }
            groups[key, default: []].append(row.sourceRow)
        }
        return groups
            .filter { $0.value.count > 1 }
            .map { DuplicateGroup(key: $0.key, sourceRows: $0.value.sorted()) }
            .sorted { lhs, rhs in
                if lhs.sourceRows.first != rhs.sourceRows.first {
                    return (lhs.sourceRows.first ?? 0) < (rhs.sourceRows.first ?? 0)
                }
                return lhs.key.joined(separator: "\u{1F}") < rhs.key.joined(separator: "\u{1F}")
            }
    }

    static func groupBy(rows: [[String]], groupColumns: [Int], valueColumn: Int, functions: [AggregationFunction]) -> GroupByResult {
        var groups: [[String]: [String]] = [:]
        for row in rows {
            let key = groupColumns.map { column in column < row.count ? row[column] : "" }
            let value = valueColumn < row.count ? row[valueColumn] : ""
            groups[key, default: []].append(value)
        }

        let resultRows: [GroupByRow] = groups.map { key, values in
            let numbers = values.compactMap { Double($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            var output: [AggregationFunction: Double] = [:]
            for function in functions {
                output[function] = aggregate(function, rawValues: values, numbers: numbers)
            }
            return GroupByRow(key: key, values: output)
        }.sorted { (lhs: GroupByRow, rhs: GroupByRow) in
            lhs.key.joined(separator: "\u{1F}").localizedCaseInsensitiveCompare(rhs.key.joined(separator: "\u{1F}")) == .orderedAscending
        }

        return GroupByResult(groupColumns: groupColumns, valueColumn: valueColumn, functions: functions, rows: resultRows)
    }

    static func numericDistribution(values: [Double], column: Int, binCount: Int) -> NumericDistribution {
        let sorted = values.sorted()
        let count = sorted.count
        let minValue = sorted.first ?? 0
        let maxValue = sorted.last ?? 0
        let mean = count == 0 ? 0 : sorted.reduce(0, +) / Double(count)
        let std = count == 0 ? 0 : sqrt(sorted.reduce(0) { $0 + pow($1 - mean, 2) } / Double(count))
        let bins = histogram(values: sorted, minValue: minValue, maxValue: maxValue, binCount: max(1, binCount))

        return NumericDistribution(
            column: column,
            count: count,
            min: minValue,
            max: maxValue,
            mean: mean,
            median: percentile(sorted, 0.5),
            q1: percentile(sorted, 0.25),
            q3: percentile(sorted, 0.75),
            standardDeviation: std,
            bins: bins
        )
    }

    static func dateHistogram(rows: [[String]], dateColumn: Int, valueColumn: Int?, period: DateBinPeriod) -> DateHistogram {
        var buckets: [String: (count: Int, sum: Double)] = [:]
        for row in rows {
            guard dateColumn < row.count, let date = parseDate(row[dateColumn]) else { continue }
            let label = dateLabel(date, period: period)
            let value = valueColumn.flatMap { column -> Double? in
                guard column < row.count else { return nil }
                return Double(row[column].trimmingCharacters(in: .whitespacesAndNewlines))
            } ?? 0
            let current = buckets[label] ?? (0, 0)
            buckets[label] = (current.count + 1, current.sum + value)
        }

        let bins = buckets.keys.sorted().map { label in
            let bucket = buckets[label] ?? (0, 0)
            let hasValue = valueColumn != nil
            return DateHistogramBin(
                label: label,
                count: bucket.count,
                sum: hasValue ? bucket.sum : nil,
                average: hasValue && bucket.count > 0 ? bucket.sum / Double(bucket.count) : nil
            )
        }
        return DateHistogram(dateColumn: dateColumn, valueColumn: valueColumn, period: period, bins: bins)
    }

    static func parseDate(_ value: String) -> Date? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if let date = ISO8601DateFormatter().date(from: trimmed) {
            return date
        }
        for format in ["yyyy-MM-dd", "yyyy/MM/dd", "MM/dd/yyyy", "yyyy-MM-dd HH:mm:ss", "yyyy/MM/dd HH:mm:ss"] {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = format
            if let date = formatter.date(from: trimmed) {
                return date
            }
        }
        return nil
    }

    private static func aggregate(_ function: AggregationFunction, rawValues: [String], numbers: [Double]) -> Double {
        switch function {
        case .count:
            return Double(rawValues.count)
        case .sum:
            return numbers.reduce(0, +)
        case .mean:
            return numbers.isEmpty ? 0 : numbers.reduce(0, +) / Double(numbers.count)
        case .median:
            return percentile(numbers.sorted(), 0.5)
        case .min:
            return numbers.min() ?? 0
        case .max:
            return numbers.max() ?? 0
        case .uniqueCount:
            return Double(Set(rawValues).count)
        case .standardDeviation:
            guard !numbers.isEmpty else { return 0 }
            let mean = numbers.reduce(0, +) / Double(numbers.count)
            return sqrt(numbers.reduce(0) { $0 + pow($1 - mean, 2) } / Double(numbers.count))
        }
    }

    static func percentile(_ sorted: [Double], _ p: Double) -> Double {
        guard !sorted.isEmpty else { return 0 }
        guard sorted.count > 1 else { return sorted[0] }
        let position = p * Double(sorted.count - 1)
        let lower = Int(floor(position))
        let upper = Int(ceil(position))
        if lower == upper { return sorted[lower] }
        let fraction = position - Double(lower)
        return sorted[lower] + (sorted[upper] - sorted[lower]) * fraction
    }

    private static func histogram(values: [Double], minValue: Double, maxValue: Double, binCount: Int) -> [HistogramBin] {
        guard !values.isEmpty else { return [] }
        guard minValue != maxValue else {
            return [HistogramBin(lowerBound: minValue, upperBound: maxValue, count: values.count)]
        }
        let width = (maxValue - minValue) / Double(binCount)
        var counts = Array(repeating: 0, count: binCount)
        for value in values {
            let index = min(binCount - 1, max(0, Int((value - minValue) / width)))
            counts[index] += 1
        }
        return counts.indices.map { index in
            let lower = minValue + Double(index) * width
            return HistogramBin(lowerBound: lower, upperBound: index == binCount - 1 ? maxValue : lower + width, count: counts[index])
        }
    }

    private static func dateLabel(_ date: Date, period: DateBinPeriod) -> String {
        let calendar = Calendar(identifier: .gregorian)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        switch period {
        case .day:
            formatter.dateFormat = "yyyy-MM-dd"
            return formatter.string(from: date)
        case .week:
            let comps = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
            return String(format: "%04d-W%02d", comps.yearForWeekOfYear ?? 0, comps.weekOfYear ?? 0)
        case .month:
            formatter.dateFormat = "yyyy-MM"
            return formatter.string(from: date)
        case .year:
            formatter.dateFormat = "yyyy"
            return formatter.string(from: date)
        }
    }
}
