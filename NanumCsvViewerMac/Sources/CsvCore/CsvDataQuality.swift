import Foundation

public enum DataQualityScope: String, Codable, Sendable {
    case full
    case partial
    case skipped
}

public enum DataQualityRule: String, Codable, Sendable {
    case blankRate
    case sentinel
    case typeValidity
    case keyUniqueness
    case raggedRow
    case duplicateRows
}

public enum DataQualitySeverity: String, Codable, Sendable {
    case info
    case warning
    case error
}

public struct DataQualityIssue: Equatable, Codable, Sendable {
    public let rule: DataQualityRule
    public let severity: DataQualitySeverity
    public let column: Int?
    public let message: String
    public let count: Int
    public let examples: [String]
}

public struct DataQualityColumnProfile: Equatable, Codable, Sendable {
    public let column: Int
    public let name: String
    public let totalCount: Int
    public let blankCount: Int
    public let sentinelCount: Int
    public let numericCount: Int
    public let dateCount: Int
    public let distinctCount: Int
    public let distinctTruncated: Bool
    public let dominantType: String

    public var missingRate: Double {
        totalCount > 0 ? Double(blankCount + sentinelCount) / Double(totalCount) : 0
    }
}

public struct DataQualityCodebookEntry: Equatable, Codable, Sendable {
    public let value: String
    public let count: Int
}

public struct DataQualityCodebook: Equatable, Codable, Sendable {
    public let column: Int
    public let name: String
    public let entries: [DataQualityCodebookEntry]
}

public struct DataQualityReport: Equatable, Codable, Sendable {
    public let rowCount: Int
    public let scannedRowCount: Int
    public let columnCount: Int
    public let scope: DataQualityScope
    public let columnProfiles: [DataQualityColumnProfile]
    public let issues: [DataQualityIssue]
    public let codebook: [DataQualityCodebook]
    public let duplicateRowCount: Int
    public let duplicateScanTruncated: Bool
    public let score: Int
}

enum DataQualityRules {
    static let sentinelTokens: Set<String> = [
        "na", "n/a", "null", "nil", "none", "missing", "unknown", "-", "?", ".",
        "9999", "-9999", "99999", "-99999", "#n/a", "#value!", "#ref!"
    ]

    static func isSentinel(_ trimmed: String) -> Bool {
        sentinelTokens.contains(trimmed.lowercased())
    }

    static func looksLikeKeyColumn(name: String) -> Bool {
        let lowered = name.lowercased()
        if lowered == "id" || lowered == "key" || lowered == "code" || lowered == "uuid" { return true }
        if lowered.hasSuffix("_id") || lowered.hasSuffix("-id") || lowered.hasSuffix(" id") { return true }
        if lowered.hasSuffix("id") && lowered.count <= 6 { return true }
        return name.contains("번호")
    }
}

extension VirtualCsvDocument {
    /// Full-file data quality profile. Unlike analysis paths this always scans
    /// every data row of the file, ignoring the active filter and the analysis
    /// row cap (Windows twin behavior).
    public func dataQualityReport(
        distinctCap: Int = 10_000,
        duplicateScanCap: Int = 1_000_000,
        codebookLimit: Int = 20,
        progress: ((Int) -> Void)? = nil,
        cancellation: CancellationFlag
    ) throws -> DataQualityReport {
        let total = dataRowsAvailable
        let columns = columnCount

        struct ColumnAccumulator {
            var blankCount = 0
            var sentinelCount = 0
            var numericCount = 0
            var dateCount = 0
            var textCount = 0
            var counts: [String: Int] = [:]
            var distinctTruncated = false
            var invalidExamples: [String] = []
        }

        var accumulators = [ColumnAccumulator](repeating: ColumnAccumulator(), count: columns)
        var raggedRowCount = 0
        var raggedExamples: [String] = []
        var rowSignatures = Set<String>()
        var duplicateRowCount = 0
        var duplicateScanTruncated = false

        for row in 0..<total {
            if row & 0x3FFF == 0 { try cancellation.check() }
            let fields = try getDataRowUncached(row)

            if fields.count != columns {
                raggedRowCount += 1
                if raggedExamples.count < 5 {
                    raggedExamples.append(L10n.rowExample(sourceRow: row + 1, fieldCount: fields.count))
                }
            }

            if rowSignatures.count < duplicateScanCap {
                let signature = fields.joined(separator: "\u{1F}")
                if !rowSignatures.insert(signature).inserted {
                    duplicateRowCount += 1
                }
            } else {
                duplicateScanTruncated = true
            }

            for column in 0..<columns {
                let value = column < fields.count ? fields[column] : ""
                let trimmed = value.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty {
                    accumulators[column].blankCount += 1
                    continue
                }
                if DataQualityRules.isSentinel(trimmed) {
                    accumulators[column].sentinelCount += 1
                    continue
                }
                if let number = Double(trimmed), number.isFinite {
                    accumulators[column].numericCount += 1
                } else if CsvDateParser.parse(trimmed, allowCompactNumeric: false) != nil {
                    accumulators[column].dateCount += 1
                } else {
                    accumulators[column].textCount += 1
                    if accumulators[column].invalidExamples.count < 5 {
                        accumulators[column].invalidExamples.append(trimmed)
                    }
                }
                if accumulators[column].counts[value] != nil || accumulators[column].counts.count < distinctCap {
                    accumulators[column].counts[value, default: 0] += 1
                } else {
                    accumulators[column].distinctTruncated = true
                }
            }

            if row & 0xFFFF == 0, total > 0 {
                progress?(Int(Int64(row) * 100 / Int64(total)))
            }
        }

        var profiles: [DataQualityColumnProfile] = []
        var issues: [DataQualityIssue] = []
        var codebook: [DataQualityCodebook] = []

        for column in 0..<columns {
            let accumulator = accumulators[column]
            let name = header.indices.contains(column) ? header[column] : "Column \(column + 1)"
            let valueCount = accumulator.numericCount + accumulator.dateCount + accumulator.textCount

            let dominantType: String
            if valueCount == 0 {
                dominantType = "Empty"
            } else if accumulator.numericCount * 5 >= valueCount * 3 {
                dominantType = "Numeric"
            } else if accumulator.dateCount * 5 >= valueCount * 3 {
                dominantType = "Date"
            } else {
                dominantType = "Text"
            }

            profiles.append(DataQualityColumnProfile(
                column: column,
                name: name,
                totalCount: total,
                blankCount: accumulator.blankCount,
                sentinelCount: accumulator.sentinelCount,
                numericCount: accumulator.numericCount,
                dateCount: accumulator.dateCount,
                distinctCount: accumulator.counts.count,
                distinctTruncated: accumulator.distinctTruncated,
                dominantType: dominantType
            ))

            if total > 0, accumulator.blankCount * 2 > total {
                issues.append(DataQualityIssue(
                    rule: .blankRate,
                    severity: .warning,
                    column: column,
                    message: L10n.blankRateMessage(name: name),
                    count: accumulator.blankCount,
                    examples: []
                ))
            }

            if accumulator.sentinelCount > 0 {
                issues.append(DataQualityIssue(
                    rule: .sentinel,
                    severity: .warning,
                    column: column,
                    message: L10n.sentinelMessage(name: name),
                    count: accumulator.sentinelCount,
                    examples: []
                ))
            }

            if dominantType == "Numeric" || dominantType == "Date" {
                let invalidCount = dominantType == "Numeric"
                    ? accumulator.dateCount + accumulator.textCount
                    : accumulator.numericCount + accumulator.textCount
                if invalidCount > 0 {
                    issues.append(DataQualityIssue(
                        rule: .typeValidity,
                        severity: .warning,
                        column: column,
                        message: L10n.typeValidityMessage(name: name, type: dominantType),
                        count: invalidCount,
                        examples: accumulator.invalidExamples
                    ))
                }
            }

            let nonBlankCount = total - accumulator.blankCount
            if DataQualityRules.looksLikeKeyColumn(name: name), nonBlankCount > 1, !accumulator.distinctTruncated {
                let duplicatedValues = accumulator.counts.filter { $0.value > 1 && !$0.key.trimmingCharacters(in: .whitespaces).isEmpty }
                if !duplicatedValues.isEmpty {
                    let examples = duplicatedValues.keys.sorted().prefix(5)
                    issues.append(DataQualityIssue(
                        rule: .keyUniqueness,
                        severity: .error,
                        column: column,
                        message: L10n.keyUniquenessMessage(name: name),
                        count: duplicatedValues.count,
                        examples: Array(examples)
                    ))
                }
            }

            if !accumulator.distinctTruncated {
                let nonBlankEntries = accumulator.counts.filter { !$0.key.trimmingCharacters(in: .whitespaces).isEmpty }
                if nonBlankEntries.count >= 2, nonBlankEntries.count <= codebookLimit,
                   nonBlankEntries.contains(where: { $0.value > 1 }) {
                    let entries = nonBlankEntries
                        .map { DataQualityCodebookEntry(value: $0.key, count: $0.value) }
                        .sorted { lhs, rhs in
                            if lhs.count != rhs.count { return lhs.count > rhs.count }
                            return lhs.value.localizedCaseInsensitiveCompare(rhs.value) == .orderedAscending
                        }
                    codebook.append(DataQualityCodebook(column: column, name: name, entries: entries))
                }
            }
        }

        if raggedRowCount > 0 {
            issues.append(DataQualityIssue(
                rule: .raggedRow,
                severity: .error,
                column: nil,
                message: L10n.raggedRowMessage(expected: columns),
                count: raggedRowCount,
                examples: raggedExamples
            ))
        }

        if duplicateRowCount > 0 {
            issues.append(DataQualityIssue(
                rule: .duplicateRows,
                severity: .info,
                column: nil,
                message: L10n.duplicateRowsMessage(),
                count: duplicateRowCount,
                examples: []
            ))
        }

        let score = Self.qualityScore(
            total: total,
            profiles: profiles,
            issues: issues,
            raggedRowCount: raggedRowCount
        )

        progress?(100)
        return DataQualityReport(
            rowCount: total,
            scannedRowCount: total,
            columnCount: columns,
            scope: .full,
            columnProfiles: profiles,
            issues: issues,
            codebook: codebook,
            duplicateRowCount: duplicateRowCount,
            duplicateScanTruncated: duplicateScanTruncated,
            score: score
        )
    }

    private static func qualityScore(
        total: Int,
        profiles: [DataQualityColumnProfile],
        issues: [DataQualityIssue],
        raggedRowCount: Int
    ) -> Int {
        guard total > 0, !profiles.isEmpty else { return 100 }
        var penalty = 0.0
        for profile in profiles {
            penalty += profile.missingRate * 20 / Double(profiles.count)
        }
        for issue in issues {
            switch issue.rule {
            case .typeValidity:
                penalty += min(15, Double(issue.count) * 100 / Double(max(total, 1)) * 3)
            case .keyUniqueness:
                penalty += 15
            case .raggedRow:
                penalty += min(20, Double(raggedRowCount) * 100 / Double(max(total, 1)) * 4)
            case .blankRate, .sentinel, .duplicateRows:
                break
            }
        }
        return max(0, min(100, Int((100 - penalty).rounded())))
    }

    /// English-only technical strings; the app layer renders localized report
    /// framing while issue messages stay stable for JSON export.
    private enum L10n {
        static func rowExample(sourceRow: Int, fieldCount: Int) -> String {
            "row \(sourceRow): \(fieldCount) fields"
        }

        static func blankRateMessage(name: String) -> String {
            "Column '\(name)' is more than half blank"
        }

        static func sentinelMessage(name: String) -> String {
            "Column '\(name)' contains sentinel/missing tokens"
        }

        static func typeValidityMessage(name: String, type: String) -> String {
            "Column '\(name)' is mostly \(type) but has non-conforming values"
        }

        static func keyUniquenessMessage(name: String) -> String {
            "Key column '\(name)' has duplicated values"
        }

        static func raggedRowMessage(expected: Int) -> String {
            "Rows with a field count different from the \(expected)-column header"
        }

        static func duplicateRowsMessage() -> String {
            "Exact duplicate rows"
        }
    }
}
