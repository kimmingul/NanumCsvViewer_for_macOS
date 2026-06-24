import Foundation

public struct CompiledAdvancedFilter: Sendable {
    public let expression: String
    public let predicate: @Sendable ([String]) -> Bool
}

public enum AdvancedFilterExpressionError: Error, Equatable, LocalizedError {
    case emptyExpression
    case unknownColumn(String)
    case invalidSyntax(String)

    public var errorDescription: String? {
        switch self {
        case .emptyExpression:
            return "Filter expression is empty."
        case .unknownColumn(let name):
            return "Unknown column: \(name)"
        case .invalidSyntax(let reason):
            return "Invalid filter expression: \(reason)"
        }
    }
}

public enum AdvancedFilterExpression {
    public static func compile(_ expression: String, headers: [String]) throws -> CompiledAdvancedFilter {
        let tokens = tokenize(expression)
        guard !tokens.isEmpty else { throw AdvancedFilterExpressionError.emptyExpression }
        var parser = Parser(tokens: tokens, headers: headers)
        let predicate = try parser.parseExpression()
        guard parser.isAtEnd else {
            throw AdvancedFilterExpressionError.invalidSyntax("Unexpected token '\(parser.currentToken)'")
        }
        return CompiledAdvancedFilter(expression: expression, predicate: predicate)
    }

    private static func tokenize(_ expression: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var iterator = expression.makeIterator()

        func flush() {
            if !current.isEmpty {
                tokens.append(current)
                current = ""
            }
        }

        while let character = iterator.next() {
            if character.isWhitespace {
                flush()
                continue
            }
            if character == "\"" {
                flush()
                var value = ""
                while let next = iterator.next() {
                    if next == "\"" { break }
                    if next == "\\" {
                        if let escaped = iterator.next() {
                            value.append(escaped)
                        }
                    } else {
                        value.append(next)
                    }
                }
                tokens.append("\"\(value)\"")
                continue
            }
            if ["(", ")"].contains(character) {
                flush()
                tokens.append(String(character))
                continue
            }
            if ["=", "!", "<", ">"].contains(character) {
                flush()
                var op = String(character)
                if let next = iterator.next() {
                    if next == "=" {
                        op.append(next)
                    } else {
                        current.append(next)
                    }
                }
                tokens.append(op)
                continue
            }
            current.append(character)
        }
        flush()
        return tokens
    }

    private struct Parser {
        let tokens: [String]
        let headers: [String]
        var position = 0

        var isAtEnd: Bool { position >= tokens.count }
        var currentToken: String { isAtEnd ? "" : tokens[position] }

        mutating func parseExpression() throws -> @Sendable ([String]) -> Bool {
            try parseOr()
        }

        private mutating func parseOr() throws -> @Sendable ([String]) -> Bool {
            var lhs = try parseAnd()
            while matchKeyword("OR") {
                let rhs = try parseAnd()
                let previous = lhs
                lhs = { row in previous(row) || rhs(row) }
            }
            return lhs
        }

        private mutating func parseAnd() throws -> @Sendable ([String]) -> Bool {
            var lhs = try parsePrimary()
            while matchKeyword("AND") {
                let rhs = try parsePrimary()
                let previous = lhs
                lhs = { row in previous(row) && rhs(row) }
            }
            return lhs
        }

        private mutating func parsePrimary() throws -> @Sendable ([String]) -> Bool {
            if match("(") {
                let predicate = try parseExpression()
                guard match(")") else {
                    throw AdvancedFilterExpressionError.invalidSyntax("Missing closing parenthesis")
                }
                return predicate
            }
            return try parseComparison()
        }

        private mutating func parseComparison() throws -> @Sendable ([String]) -> Bool {
            let columnName = try consume("Expected column name")
            let column = try columnIndex(named: columnName)
            let op = try consume("Expected operator")
            let value = unquote(try consume("Expected comparison value"))

            switch op.lowercased() {
            case "contains":
                return { row in
                    guard column < row.count else { return false }
                    return row[column].range(of: value, options: [.caseInsensitive, .diacriticInsensitive]) != nil
                }
            case "==", "=":
                return { row in column < row.count && row[column] == value }
            case "!=":
                return { row in column >= row.count || row[column] != value }
            case ">", ">=", "<", "<=":
                return { row in
                    guard column < row.count else { return false }
                    return Self.compare(row[column], to: value, op: op)
                }
            default:
                throw AdvancedFilterExpressionError.invalidSyntax("Unsupported operator '\(op)'")
            }
        }

        private mutating func consume(_ message: String) throws -> String {
            guard !isAtEnd else { throw AdvancedFilterExpressionError.invalidSyntax(message) }
            let token = tokens[position]
            position += 1
            return token
        }

        private mutating func match(_ token: String) -> Bool {
            guard !isAtEnd, tokens[position] == token else { return false }
            position += 1
            return true
        }

        private mutating func matchKeyword(_ keyword: String) -> Bool {
            guard !isAtEnd, tokens[position].caseInsensitiveCompare(keyword) == .orderedSame else { return false }
            position += 1
            return true
        }

        private func columnIndex(named name: String) throws -> Int {
            if let index = headers.firstIndex(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) {
                return index
            }
            if name.lowercased().hasPrefix("column"),
               let number = Int(name.drop { !$0.isNumber }),
               headers.indices.contains(number - 1) {
                return number - 1
            }
            throw AdvancedFilterExpressionError.unknownColumn(name)
        }

        private func unquote(_ token: String) -> String {
            guard token.hasPrefix("\""), token.hasSuffix("\""), token.count >= 2 else { return token }
            return String(token.dropFirst().dropLast())
        }

        private static func compare(_ lhs: String, to rhs: String, op: String) -> Bool {
            let comparison: ComparisonResult
            if let left = Double(lhs.trimmingCharacters(in: .whitespacesAndNewlines)),
               let right = Double(rhs.trimmingCharacters(in: .whitespacesAndNewlines)) {
                comparison = left == right ? .orderedSame : (left < right ? .orderedAscending : .orderedDescending)
            } else {
                comparison = lhs.localizedCaseInsensitiveCompare(rhs)
            }

            switch op {
            case ">": return comparison == .orderedDescending
            case ">=": return comparison == .orderedDescending || comparison == .orderedSame
            case "<": return comparison == .orderedAscending
            case "<=": return comparison == .orderedAscending || comparison == .orderedSame
            default: return false
            }
        }
    }
}
