import Foundation

public enum ColumnTypeConversionRule: Equatable, Sendable {
    case allow
    case validateSample
    case block
}

public enum ColumnTypeConversion {
    private static let nullTokens: Set<String> = ["", "na", "n/a", "null", "nil", "missing"]
    private static let booleanTokens: Set<String> = ["true", "false", "yes", "no", "y", "n", "0", "1"]

    /// Classifies a manual type override the way the Windows twin does:
    /// widening conversions are allowed, narrowing conversions that can be
    /// checked against data require sample validation, and lossy or
    /// meaningless conversions are blocked.
    public static func classify(from current: ColumnValueType, to target: ColumnValueType) -> ColumnTypeConversionRule {
        guard current != target else { return .allow }
        switch target {
        case .empty:
            return .block
        case .string, .categorical:
            return .allow
        case .float:
            return current == .integer ? .allow : .validateSample
        case .integer:
            return current == .float ? .block : .validateSample
        case .date, .boolean:
            return .validateSample
        }
    }

    /// Checks whether non-null sample values can represent the target type.
    /// Returns up to 5 failing examples so the UI can show why.
    public static func validateSample(values: [String], to target: ColumnValueType) -> (passed: Bool, failures: [String]) {
        var failures: [String] = []
        for raw in values {
            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if nullTokens.contains(value.lowercased()) { continue }
            if !isConvertible(value, to: target) {
                failures.append(value)
                if failures.count >= 5 { break }
            }
        }
        return (failures.isEmpty, failures)
    }

    private static func isConvertible(_ value: String, to target: ColumnValueType) -> Bool {
        switch target {
        case .integer:
            guard let number = CsvNumber.parse(value) else { return false }
            return number.rounded(.towardZero) == number && !value.contains(".")
                && !value.lowercased().contains("e")
        case .float:
            return CsvNumber.parse(value) != nil
        case .date:
            return CsvDateParser.parse(value, allowCompactNumeric: true) != nil
        case .boolean:
            return booleanTokens.contains(value.lowercased())
        case .string, .categorical:
            return true
        case .empty:
            return false
        }
    }
}

extension ColumnStatisticsReport {
    /// Returns a report whose inferred types are replaced by manual overrides;
    /// passing an empty dictionary restores automatic inference.
    public func applyingOverrides(_ overrides: [Int: ColumnValueType]) -> ColumnStatisticsReport {
        guard !overrides.isEmpty else { return self }
        return ColumnStatisticsReport(
            rowSampleCount: rowSampleCount,
            columns: columns.map { column in
                guard let override = overrides[column.index], override != column.inferredType else {
                    return column
                }
                return ColumnSummary(
                    index: column.index,
                    name: column.name,
                    inferredType: override,
                    nullCount: column.nullCount,
                    nonNullCount: column.nonNullCount,
                    uniqueCount: column.uniqueCount,
                    numeric: column.numeric,
                    topValues: column.topValues
                )
            }
        )
    }
}
