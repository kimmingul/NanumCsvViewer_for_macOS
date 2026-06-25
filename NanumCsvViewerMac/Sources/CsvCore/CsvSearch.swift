import Foundation

public enum CsvSearchMode: String, Codable, Sendable {
    case contains
    case regex
    case fuzzy
}

public enum CsvSearchError: Error, Equatable {
    case invalidRegularExpression(String)
}

public struct CsvSearchQuery: Equatable, Codable, Sendable {
    public let text: String
    public let mode: CsvSearchMode
    public let column: Int?

    public init(text: String, mode: CsvSearchMode, column: Int?) throws {
        self.text = text
        self.mode = mode
        self.column = column
        if mode == .regex {
            do {
                _ = try NSRegularExpression(pattern: text, options: [.caseInsensitive])
            } catch {
                throw CsvSearchError.invalidRegularExpression(text)
            }
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let text = try container.decode(String.self, forKey: .text)
        let mode = try container.decode(CsvSearchMode.self, forKey: .mode)
        let column = try container.decodeIfPresent(Int.self, forKey: .column)
        try self.init(text: text, mode: mode, column: column)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(text, forKey: .text)
        try container.encode(mode, forKey: .mode)
        try container.encodeIfPresent(column, forKey: .column)
    }

    private enum CodingKeys: String, CodingKey {
        case text
        case mode
        case column
    }
}

public struct CsvSearchMatch: Equatable, Sendable {
    public let viewRow: Int
    public let sourceRowNumber: Int64
    public let column: Int
    public let value: String

    public init(viewRow: Int, sourceRowNumber: Int64, column: Int, value: String) {
        self.viewRow = viewRow
        self.sourceRowNumber = sourceRowNumber
        self.column = column
        self.value = value
    }
}

enum CsvSearchMatcher {
    static func firstMatch(in row: [String], query: CsvSearchQuery) throws -> (column: Int, value: String)? {
        let columns: [Int]
        if let column = query.column {
            guard column >= 0, column < row.count else { return nil }
            columns = [column]
        } else {
            columns = Array(row.indices)
        }

        for column in columns {
            let value = row[column]
            if try matches(value, query: query) {
                return (column, value)
            }
        }
        return nil
    }

    private static func matches(_ value: String, query: CsvSearchQuery) throws -> Bool {
        switch query.mode {
        case .contains:
            return value.range(of: query.text, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        case .regex:
            let regex = try NSRegularExpression(pattern: query.text, options: [.caseInsensitive])
            let range = NSRange(value.startIndex..<value.endIndex, in: value)
            return regex.firstMatch(in: value, range: range) != nil
        case .fuzzy:
            return fuzzyContains(value, query: query.text)
        }
    }

    private static func fuzzyContains(_ value: String, query: String) -> Bool {
        let needle = normalized(query)
        guard !needle.isEmpty else { return true }
        var remaining = needle[...]
        for character in normalized(value) {
            if character == remaining.first {
                remaining.removeFirst()
                if remaining.isEmpty { return true }
            }
        }
        return false
    }

    private static func normalized(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
