import Foundation

public enum CsvSearchMode: String, Codable, Sendable {
    case contains
    case regex
    case fuzzy
}

public enum CsvSearchError: Error, Equatable, LocalizedError {
    case invalidRegularExpression(String)
    case unsafeRegularExpression(String)

    public var errorDescription: String? {
        switch self {
        case .invalidRegularExpression(let pattern):
            return "'\(pattern)' is not a valid regular expression."
        case .unsafeRegularExpression(let pattern):
            return "'\(pattern)' uses nested quantifiers that can hang the search and was rejected."
        }
    }
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
            // Reject the classic exponential-backtracking shapes up front.
            // NSRegularExpression has no match deadline, so a hostile pattern
            // could otherwise hang a search uninterruptibly. This is a heuristic
            // gate (defense-in-depth), not a proof of safety — a killable,
            // process-isolated search is the complete fix (tracked separately).
            if Self.hasNestedQuantifier(text) {
                throw CsvSearchError.unsafeRegularExpression(text)
            }
            do {
                _ = try NSRegularExpression(pattern: text, options: [.caseInsensitive])
            } catch {
                throw CsvSearchError.invalidRegularExpression(text)
            }
        }
    }

    /// Detects a quantifier applied to a group whose body also contains a
    /// quantifier — e.g. `(a+)+`, `(a*)*`, `(.*)+` — the catastrophic-
    /// backtracking shapes. Escapes and character classes are skipped.
    static func hasNestedQuantifier(_ pattern: String) -> Bool {
        func isQuantifierStart(_ character: Character) -> Bool {
            character == "*" || character == "+" || character == "{"
        }
        let chars = Array(pattern)
        var groupBodyHasQuantifier: [Bool] = []
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c == "\\" {
                i += 2
                continue
            }
            if c == "[" {
                i += 1
                if i < chars.count, chars[i] == "^" { i += 1 }
                if i < chars.count, chars[i] == "]" { i += 1 }
                while i < chars.count, chars[i] != "]" {
                    if chars[i] == "\\" { i += 1 }
                    i += 1
                }
                i += 1
                if i < chars.count, isQuantifierStart(chars[i]), !groupBodyHasQuantifier.isEmpty {
                    groupBodyHasQuantifier[groupBodyHasQuantifier.count - 1] = true
                }
                continue
            }
            if c == "(" {
                groupBodyHasQuantifier.append(false)
                i += 1
                continue
            }
            if c == ")" {
                let bodyHadQuantifier = groupBodyHasQuantifier.popLast() ?? false
                let quantified = i + 1 < chars.count && isQuantifierStart(chars[i + 1])
                if bodyHadQuantifier, quantified {
                    return true
                }
                // The parent's body now contains a quantifier if this group held
                // one internally or is itself quantified (catches ((a+))+).
                if bodyHadQuantifier || quantified, !groupBodyHasQuantifier.isEmpty {
                    groupBodyHasQuantifier[groupBodyHasQuantifier.count - 1] = true
                }
                i += 1
                continue
            }
            if isQuantifierStart(c), !groupBodyHasQuantifier.isEmpty {
                groupBodyHasQuantifier[groupBodyHasQuantifier.count - 1] = true
            }
            i += 1
        }
        return false
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

struct CsvSearchMatcher {
    let query: CsvSearchQuery
    private let regex: NSRegularExpression?

    init(query: CsvSearchQuery) throws {
        self.query = query
        if query.mode == .regex {
            do {
                self.regex = try NSRegularExpression(pattern: query.text, options: [.caseInsensitive])
            } catch {
                throw CsvSearchError.invalidRegularExpression(query.text)
            }
        } else {
            self.regex = nil
        }
    }

    func firstMatch(in row: [String]) -> (column: Int, value: String)? {
        let columns: [Int]
        if let column = query.column {
            guard column >= 0, column < row.count else { return nil }
            columns = [column]
        } else {
            columns = Array(row.indices)
        }

        for column in columns {
            let value = row[column]
            if matches(value) {
                return (column, value)
            }
        }
        return nil
    }

    private func matches(_ value: String) -> Bool {
        switch query.mode {
        case .contains:
            return value.range(of: query.text, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        case .regex:
            guard let regex else { return false }
            let range = NSRange(value.startIndex..<value.endIndex, in: value)
            return regex.firstMatch(in: value, range: range) != nil
        case .fuzzy:
            return Self.fuzzyContains(value, query: query.text)
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
