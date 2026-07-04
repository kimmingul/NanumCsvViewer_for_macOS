import Foundation

enum InspectorContentKind: Equatable {
    case empty
    case row(displayRow: Int, sourceRow: Int64)
    case columnStatistics(column: Int)
    case performance
    case analysis
    case dataQuality
}

enum InspectorCopyFormatter {
    static func text(_ value: String) -> String {
        value
    }

    static func jsonObject(headers: [String], row: [String]) -> String? {
        var object: [String: String] = [:]
        var counts: [String: Int] = [:]
        for index in headers.indices {
            let base = headers[index].isEmpty ? "column_\(index + 1)" : headers[index]
            let nextCount = (counts[base] ?? 0) + 1
            counts[base] = nextCount
            let key = nextCount == 1 ? base : "\(base)_\(nextCount)"
            object[key] = index < row.count ? row[index] : ""
        }
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
}
