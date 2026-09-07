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

/// Bounds the dense result consumed by tables and exports, not just occupied cells.
public enum PivotResourceLimits {
    public static let maximumRows = 100_000
    public static let maximumColumns = 256
    public static let maximumCells = 1_000_000
}

public enum CsvResourceLimitError: Error, LocalizedError, Equatable {
    case pivotDimensions
    case distinctValues(Int)

    public var errorDescription: String? {
        switch self {
        case .pivotDimensions:
            return "This pivot exceeds the safe result size (100,000 rows, 256 columns, or 1,000,000 cells). Filter the data, group dates, or move a high-cardinality field from Columns to Rows."
        case .distinctValues(let limit):
            return "This column has more than \(limit.formatted()) distinct values. Use an exact-value or expression filter instead of listing every category."
        }
    }
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
            let numbers = values.compactMap { CsvNumber.parse($0) }
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
                return CsvNumber.parse(row[column])
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
        var accumulator = PivotAccumulator(
            rowColumns: rowColumns, rowColumnNames: rowColumnNames,
            columnColumns: columnColumns, valueColumn: valueColumn,
            function: function, filters: filters, dateGroupings: dateGroupings
        )
        for (index, row) in rows.enumerated() {
            if index & 0xFFF == 0 { try cancellation?.check() }
            try accumulator.add(row)
        }
        return try accumulator.result(cancellation: cancellation)
    }

    struct PivotAccumulator {
        let rowColumns: [Int]
        let rowColumnNames: [String]
        let columnColumns: [Int]
        let valueColumn: Int
        let function: AggregationFunction
        let filters: [PivotFilter]
        let dateGroupings: [Int: DateBinPeriod]
        private var cells: [PivotCellKey: CellAccumulator] = [:]
        private var rowKeys: Set<[String]> = []
        private var columnKeys: Set<[String]> = []

        init(rowColumns: [Int], rowColumnNames: [String], columnColumns: [Int],
             valueColumn: Int, function: AggregationFunction, filters: [PivotFilter],
             dateGroupings: [Int: DateBinPeriod]) {
            self.rowColumns = rowColumns
            self.rowColumnNames = rowColumnNames
            self.columnColumns = columnColumns
            self.valueColumn = valueColumn
            self.function = function
            self.filters = filters.compactMap { filter in
                guard let value = filter.selectedValue else { return nil }
                let normalized = isPivotNull(value.trimmingCharacters(in: .whitespacesAndNewlines)) ? "null" : value
                return PivotFilter(column: filter.column, selectedValue: normalized)
            }
            self.dateGroupings = dateGroupings
        }

        mutating func add(_ row: [String]) throws {
            guard pivotRow(row, matches: filters, dateGroupings: dateGroupings) else { return }
            let rowKey = rowColumns.map { pivotKeyValue(row: row, column: $0, dateGroupings: dateGroupings) }
            let columnKey = columnColumns.map { pivotKeyValue(row: row, column: $0, dateGroupings: dateGroupings) }
            rowKeys.insert(rowKey)
            columnKeys.insert(columnKey)
            // Division avoids overflow; even sparse diagonals become dense in the UI.
            guard rowKeys.count <= PivotResourceLimits.maximumRows,
                  columnKeys.count <= PivotResourceLimits.maximumColumns,
                  rowKeys.count <= PivotResourceLimits.maximumCells / max(1, columnKeys.count) else {
                throw CsvResourceLimitError.pivotDimensions
            }
            let value = valueColumn >= 0 && valueColumn < row.count ? row[valueColumn] : ""
            cells[PivotCellKey(row: rowKey, column: columnKey), default: CellAccumulator()].add(value, function: function)
        }

        func result(cancellation: CancellationFlag?) throws -> PivotTableResult {
            try cancellation?.check()
            // Cache sort labels once instead of allocating strings in every comparison.
            func sortedKeys(_ keys: Set<[String]>) throws -> [[String]] {
                let sorted = try keys.map { key in
                    try cancellation?.check()
                    return (key: key, label: key.joined(separator: "\u{1F}"))
                }.sorted { $0.label < $1.label }
                try cancellation?.check()
                return sorted.map(\.key)
            }
            let sortedRows = try sortedKeys(rowKeys)
            let sortedColumns = try sortedKeys(columnKeys)
            var values: [PivotCellKey: Double] = [:]
            values.reserveCapacity(cells.count)
            for (key, cell) in cells {
                try cancellation?.check()
                values[key] = cell.value(function)
            }
            try cancellation?.check()
            return PivotTableResult(
                rowColumns: rowColumns, rowColumnNames: rowColumnNames,
                columnColumns: columnColumns, valueColumn: valueColumn,
                function: function, rowKeys: sortedRows,
                columnKeys: sortedColumns, values: values
            )
        }
    }

    private struct CellAccumulator {
        var count = 0
        var numericCount = 0
        var sum = 0.0
        var mean = 0.0
        var m2 = 0.0
        var minimum: Double?
        var maximum: Double?
        var numbers: [Double] = []
        var unique: Set<String> = []

        mutating func add(_ raw: String, function: AggregationFunction) {
            count += 1
            if function == .count { return }
            if function == .uniqueCount {
                unique.insert(raw)
                return
            }
            guard let number = CsvNumber.parse(raw) else { return }
            numericCount += 1
            switch function {
            case .sum, .mean:
                sum += number
            case .median:
                numbers.append(number)
            case .min:
                if minimum == nil || number < minimum! { minimum = number }
            case .max:
                if maximum == nil || number > maximum! { maximum = number }
            case .standardDeviation:
                let delta = number - mean
                mean += delta / Double(numericCount)
                m2 += delta * (number - mean)
            case .count, .uniqueCount:
                break
            }
        }

        func value(_ function: AggregationFunction) -> Double {
            switch function {
            case .count: return Double(count)
            case .sum: return sum
            case .mean: return numericCount == 0 ? 0 : sum / Double(numericCount)
            case .median: return percentile(numbers.sorted(), 0.5)
            case .min: return minimum ?? 0
            case .max: return maximum ?? 0
            case .uniqueCount: return Double(unique.count)
            case .standardDeviation: return numericCount == 0 ? 0 : sqrt(m2 / Double(numericCount))
            }
        }
    }

    static func pivotKeyValue(row: [String], column: Int, dateGroupings: [Int: DateBinPeriod]) -> String {
        let raw = column >= 0 && column < row.count ? row[column] : ""
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
