import Foundation

public enum ColumnFilter: Equatable, Codable, Sendable {
    case selectedValues(column: Int, values: Set<String>, includeBlanks: Bool)
    case dateRange(column: Int, start: Date?, end: Date?)
    case numericRange(column: Int, lower: Double, upper: Double, includesUpperBound: Bool)

    public var column: Int {
        switch self {
        case .selectedValues(let column, _, _), .dateRange(let column, _, _),
             .numericRange(let column, _, _, _):
            return column
        }
    }
}

public struct ColumnFilterState: Equatable, Codable, Sendable {
    public private(set) var filters: [ColumnFilter]

    public init(filters: [ColumnFilter] = []) {
        self.filters = filters.filter { $0.column >= 0 }
    }

    private enum CodingKeys: String, CodingKey {
        case filters
    }

    public init(from decoder: Decoder) throws {
        // Skip filter cases this app version does not understand so newer
        // saved views degrade gracefully instead of failing to decode.
        let container = try decoder.container(keyedBy: CodingKeys.self)
        var filtersContainer = try container.nestedUnkeyedContainer(forKey: .filters)
        var decoded: [ColumnFilter] = []
        while !filtersContainer.isAtEnd {
            let position = filtersContainer.currentIndex
            if let filter = try? filtersContainer.decode(ColumnFilter.self) {
                decoded.append(filter)
            } else {
                _ = try? filtersContainer.decode(UnknownFilterPlaceholder.self)
            }
            if filtersContainer.currentIndex == position { break }
        }
        self.init(filters: decoded)
    }

    private struct UnknownFilterPlaceholder: Decodable {}

    public var isEmpty: Bool {
        filters.isEmpty
    }

    public mutating func setValues(column: Int, values: Set<String>, includeBlanks: Bool) {
        guard column >= 0 else { return }
        remove(column: column)
        if !values.isEmpty || includeBlanks {
            filters.append(.selectedValues(column: column, values: values, includeBlanks: includeBlanks))
        }
    }

    public mutating func setDateRange(column: Int, start: Date?, end: Date?) {
        guard column >= 0 else { return }
        remove(column: column)
        if start != nil || end != nil {
            filters.append(.dateRange(column: column, start: start, end: end))
        }
    }

    public mutating func setNumericRange(column: Int, lower: Double, upper: Double, includesUpperBound: Bool) {
        guard column >= 0, lower.isFinite, upper.isFinite, lower <= upper else { return }
        remove(column: column)
        filters.append(.numericRange(column: column, lower: lower, upper: upper, includesUpperBound: includesUpperBound))
    }

    public mutating func remove(column: Int) {
        filters.removeAll { $0.column == column }
    }

    public func filter(for column: Int) -> ColumnFilter? {
        filters.first { $0.column == column }
    }

    public func predicate() -> @Sendable ([String]) -> Bool {
        let filters = filters
        return { row in
            filters.allSatisfy { filter in
                switch filter {
                case .selectedValues(let column, let values, let includeBlanks):
                    let value = column < row.count ? row[column] : ""
                    return value.isEmpty ? includeBlanks : values.contains(value)
                case .dateRange(let column, let start, let end):
                    guard column < row.count,
                          let date = CsvDateParser.parse(row[column], allowCompactNumeric: true) else {
                        return false
                    }
                    if let start, date < start { return false }
                    if let end, date > end { return false }
                    return true
                case .numericRange(let column, let lower, let upper, let includesUpperBound):
                    guard column < row.count,
                          let number = Double(row[column].trimmingCharacters(in: .whitespaces)),
                          number.isFinite else {
                        return false
                    }
                    if number < lower { return false }
                    return includesUpperBound ? number <= upper : number < upper
                }
            }
        }
    }

    public func descriptions(columnNames: [String], blankLabel: String) -> [String] {
        filters.map { filter in
            let name = columnNames[safe: filter.column] ?? "Column \(filter.column + 1)"
            switch filter {
            case .selectedValues(_, let values, let includeBlanks):
                var labels = values.sorted {
                    $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
                }.map { #""\#($0)""# }
                if includeBlanks {
                    labels.append(blankLabel)
                }
                return "\(name) in \(labels.joined(separator: ", "))"
            case .dateRange(_, let start, let end):
                let formatter = Self.dateFormatter
                switch (start, end) {
                case (.some(let start), .some(let end)):
                    return "\(name) between \(formatter.string(from: start)) and \(formatter.string(from: end))"
                case (.some(let start), .none):
                    return "\(name) >= \(formatter.string(from: start))"
                case (.none, .some(let end)):
                    return "\(name) <= \(formatter.string(from: end))"
                case (.none, .none):
                    return name
                }
            case .numericRange(_, let lower, let upper, let includesUpperBound):
                let upperSymbol = includesUpperBound ? "<=" : "<"
                return "\(Self.numericBoundLabel(lower)) <= \(name) \(upperSymbol) \(Self.numericBoundLabel(upper))"
            }
        }
    }

    public static func numericBoundLabel(_ value: Double) -> String {
        if value == value.rounded(), abs(value) < 1e15 {
            return String(Int64(value))
        }
        return String(format: "%.4g", value)
    }

    private static var dateFormatter: DateFormatter {
        let key = "ColumnFilterState.dateFormatter"
        let dictionary = Thread.current.threadDictionary
        if let formatter = dictionary[key] as? DateFormatter {
            return formatter
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        dictionary[key] = formatter
        return formatter
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        index >= 0 && index < count ? self[index] : nil
    }
}
