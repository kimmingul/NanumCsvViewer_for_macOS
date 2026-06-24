import Foundation

public enum ColumnValueType: String, Sendable {
    case integer = "Integer"
    case float = "Float"
    case date = "Date"
    case boolean = "Boolean"
    case categorical = "Categorical"
    case string = "String"
    case empty = "Empty"
}

public struct NumericColumnSummary: Equatable, Sendable {
    public let min: Double
    public let max: Double
    public let mean: Double
    public let median: Double
    public let standardDeviation: Double
}

public struct TopValue: Equatable, Sendable {
    public let value: String
    public let count: Int
}

public struct ColumnSummary: Equatable, Sendable {
    public let index: Int
    public let name: String
    public let inferredType: ColumnValueType
    public let nullCount: Int
    public let nonNullCount: Int
    public let uniqueCount: Int
    public let numeric: NumericColumnSummary?
    public let topValues: [TopValue]
}

public struct ColumnStatisticsReport: Equatable, Sendable {
    public let rowSampleCount: Int
    public let columns: [ColumnSummary]
}

struct ColumnStatisticsBuilder {
    private static let nullTokens: Set<String> = ["", "na", "n/a", "null", "nil", "missing"]
    private static let booleanTokens: Set<String> = ["true", "false", "yes", "no", "y", "n", "0", "1"]

    static func summarize(headers: [String], rows: [[String]]) -> ColumnStatisticsReport {
        let columnCount = headers.count
        let columns = (0..<columnCount).map { column in
            summarizeColumn(index: column, name: headers[column], rows: rows)
        }
        return ColumnStatisticsReport(rowSampleCount: rows.count, columns: columns)
    }

    private static func summarizeColumn(index: Int, name: String, rows: [[String]]) -> ColumnSummary {
        var values: [String] = []
        var nullCount = 0
        var frequencies: [String: Int] = [:]
        var numericValues: [Double] = []
        var integerCompatible = true
        var floatCompatible = true
        var dateCompatible = true
        var booleanCompatible = true

        for row in rows {
            let raw = index < row.count ? row[index] : ""
            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if isNull(value) {
                nullCount += 1
                continue
            }
            values.append(value)
            frequencies[value, default: 0] += 1

            if let number = Double(value) {
                numericValues.append(number)
                if number.rounded(.towardZero) != number || value.contains(".") || value.lowercased().contains("e") {
                    integerCompatible = false
                }
            } else {
                integerCompatible = false
                floatCompatible = false
            }

            if parseDate(value) == nil {
                dateCompatible = false
            }
            if !booleanTokens.contains(value.lowercased()) {
                booleanCompatible = false
            }
        }

        let nonNullCount = values.count
        let inferredType: ColumnValueType
        if nonNullCount == 0 {
            inferredType = .empty
        } else if booleanCompatible {
            inferredType = .boolean
        } else if integerCompatible {
            inferredType = .integer
        } else if floatCompatible {
            inferredType = .float
        } else if dateCompatible {
            inferredType = .date
        } else if frequencies.count <= max(20, nonNullCount / 2) {
            inferredType = .categorical
        } else {
            inferredType = .string
        }

        let topValues = frequencies
            .map { TopValue(value: $0.key, count: $0.value) }
            .sorted { lhs, rhs in
                if lhs.count != rhs.count { return lhs.count > rhs.count }
                return lhs.value.localizedCaseInsensitiveCompare(rhs.value) == .orderedAscending
            }
            .prefix(10)

        return ColumnSummary(
            index: index,
            name: name,
            inferredType: inferredType,
            nullCount: nullCount,
            nonNullCount: nonNullCount,
            uniqueCount: frequencies.count,
            numeric: numericValues.isEmpty ? nil : summarizeNumbers(numericValues),
            topValues: Array(topValues)
        )
    }

    private static func isNull(_ value: String) -> Bool {
        nullTokens.contains(value.lowercased())
    }

    private static func summarizeNumbers(_ values: [Double]) -> NumericColumnSummary {
        let sorted = values.sorted()
        let sum = sorted.reduce(0, +)
        let mean = sum / Double(sorted.count)
        let median: Double
        if sorted.count % 2 == 0 {
            median = (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2
        } else {
            median = sorted[sorted.count / 2]
        }
        let variance = sorted.reduce(0) { $0 + pow($1 - mean, 2) } / Double(sorted.count)
        return NumericColumnSummary(
            min: sorted.first ?? 0,
            max: sorted.last ?? 0,
            mean: mean,
            median: median,
            standardDeviation: sqrt(variance)
        )
    }

    private static func parseDate(_ value: String) -> Date? {
        if let date = ISO8601DateFormatter().date(from: value) {
            return date
        }
        for format in ["yyyy-MM-dd", "yyyy/MM/dd", "MM/dd/yyyy", "yyyy-MM-dd HH:mm:ss", "yyyy/MM/dd HH:mm:ss"] {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = format
            if let date = formatter.date(from: value) {
                return date
            }
        }
        return nil
    }
}
