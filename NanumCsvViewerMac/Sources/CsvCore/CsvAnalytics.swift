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

public struct PivotTableResult: Equatable, Sendable {
    public let rowColumns: [Int]
    public let rowColumnNames: [String]
    public let columnColumns: [Int]
    public let valueColumn: Int
    public let function: AggregationFunction
    public let rowKeys: [[String]]
    public let columnKeys: [[String]]
    public let values: [PivotCellKey: Double]

    public func value(row: [String], column: [String]) -> Double {
        values[PivotCellKey(row: row, column: column)] ?? 0
    }

    public func exportCsv(to outputPath: String) throws {
        FileManager.default.createFile(atPath: outputPath, contents: nil)
        let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: outputPath))
        defer { try? handle.close() }

        func write(_ fields: [String]) throws {
            let line = fields.map(csvEscaped).joined(separator: ",") + "\n"
            try handle.write(contentsOf: Data(line.utf8))
        }

        let rowHeader = rowColumnNames.isEmpty ? rowColumns.map { "Column \($0 + 1)" }.joined(separator: " | ") : rowColumnNames.joined(separator: " | ")
        try write([rowHeader] + columnKeys.map { $0.joined(separator: " | ") })
        for row in rowKeys {
            try write([row.joined(separator: " | ")] + columnKeys.map { formatNumber(value(row: row, column: $0)) })
        }
    }

    private func csvEscaped(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r") {
            return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return value
    }

    private func formatNumber(_ value: Double) -> String {
        value.rounded(.towardZero) == value ? String(format: "%.0f", value) : String(format: "%.3f", value)
    }
}

public struct PivotFilter: Equatable, Sendable {
    public let column: Int
    public let selectedValue: String?

    public init(column: Int, selectedValue: String?) {
        self.column = column
        self.selectedValue = selectedValue
    }
}

public struct PivotCellKey: Hashable, Codable, Sendable {
    public let row: [String]
    public let column: [String]
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
        // Non-finite values (inf/NaN, e.g. from "inf" or an overflowing literal
        // like "1e400") would make bin width inf/NaN and trap in `Int(...)`
        // inside `histogram`. They carry no distribution meaning — drop them.
        let sorted = values.filter { $0.isFinite }.sorted()
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
            guard dateColumn < row.count,
                  let date = CsvDateParser.parse(row[dateColumn], allowCompactNumeric: true) else { continue }
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

    static func pivotTable(
        rows: [[String]],
        rowColumns: [Int],
        rowColumnNames: [String] = [],
        columnColumns: [Int],
        valueColumn: Int,
        function: AggregationFunction,
        filters: [PivotFilter] = [],
        dateGroupings: [Int: DateBinPeriod] = [:],
        cancellation: CancellationFlag? = nil
    ) throws -> PivotTableResult {
        var raw: [PivotCellKey: [String]] = [:]
        var rowKeySet: Set<[String]> = []
        var columnKeySet: Set<[String]> = []
        let activeFilters = filters.filter { $0.selectedValue != nil }

        for (index, row) in rows.enumerated() {
            if index & 0x3FFF == 0 { try cancellation?.check() }
            guard pivotRow(row, matches: activeFilters, dateGroupings: dateGroupings) else { continue }
            let rowKey = rowColumns.map { pivotKeyValue(row: row, column: $0, dateGroupings: dateGroupings) }
            let columnKey = columnColumns.map { pivotKeyValue(row: row, column: $0, dateGroupings: dateGroupings) }
            let value = valueColumn < row.count ? row[valueColumn] : ""
            rowKeySet.insert(rowKey)
            columnKeySet.insert(columnKey)
            raw[PivotCellKey(row: rowKey, column: columnKey), default: []].append(value)
        }

        let rowKeys = rowKeySet.sorted { $0.joined(separator: "\u{1F}") < $1.joined(separator: "\u{1F}") }
        let columnKeys = columnKeySet.sorted { $0.joined(separator: "\u{1F}") < $1.joined(separator: "\u{1F}") }
        var values: [PivotCellKey: Double] = [:]
        for (index, element) in raw.enumerated() {
            if index & 0x3FFF == 0 { try cancellation?.check() }
            let (key, cellValues) = element
            let numbers = cellValues.compactMap { Double($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            values[key] = aggregate(function, rawValues: cellValues, numbers: numbers)
        }

        return PivotTableResult(
            rowColumns: rowColumns,
            rowColumnNames: rowColumnNames,
            columnColumns: columnColumns,
            valueColumn: valueColumn,
            function: function,
            rowKeys: rowKeys,
            columnKeys: columnKeys,
            values: values
        )
    }

    static func pivotKeyValue(row: [String], column: Int, dateGroupings: [Int: DateBinPeriod]) -> String {
        let raw = column < row.count ? row[column] : ""
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if isPivotNull(trimmed) {
            return "null"
        }
        guard let period = dateGroupings[column],
              let date = CsvDateParser.parse(raw, allowCompactNumeric: true) else {
            return raw
        }
        return dateLabel(date, period: period)
    }

    private static func pivotRow(
        _ row: [String],
        matches filters: [PivotFilter],
        dateGroupings: [Int: DateBinPeriod]
    ) -> Bool {
        for filter in filters {
            guard let selectedValue = filter.selectedValue else { continue }
            if pivotKeyValue(row: row, column: filter.column, dateGroupings: dateGroupings) != selectedValue {
                return false
            }
        }
        return true
    }

    private static func isPivotNull(_ value: String) -> Bool {
        ["", "na", "n/a", "null", "nil", "missing"].contains(value.lowercased())
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
