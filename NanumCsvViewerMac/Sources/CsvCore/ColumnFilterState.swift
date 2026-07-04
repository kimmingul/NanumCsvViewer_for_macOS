import Foundation

public enum ColumnFilter: Equatable, Codable, Sendable {
    case selectedValues(column: Int, values: Set<String>, includeBlanks: Bool)
    case dateRange(column: Int, start: Date?, end: Date?)

    public var column: Int {
        switch self {
        case .selectedValues(let column, _, _), .dateRange(let column, _, _):
            return column
        }
    }
}

public struct ColumnFilterState: Equatable, Codable, Sendable {
    public private(set) var filters: [ColumnFilter]

    public init(filters: [ColumnFilter] = []) {
        self.filters = filters.filter { $0.column >= 0 }
    }

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

    public mutating func remove(column: Int) {
        filters.removeAll { $0.column == column }
    }

    public func filter(for column: Int) -> ColumnFilter? {
        filters.first { $0.column == column }
    }

    public func predicate() -> ([String]) -> Bool {
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
            }
        }
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
