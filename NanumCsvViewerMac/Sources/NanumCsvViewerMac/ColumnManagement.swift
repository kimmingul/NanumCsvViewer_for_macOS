import Foundation

enum ColumnManagement {
    /// Visible data columns in on-screen (visual) order, or nil when the order
    /// is the natural full source order — so an unchanged grid still exports
    /// every column and callers can treat nil as "all columns".
    static func exportColumnOrder(visualDataColumns: [Int], hidden: Set<Int>, totalColumns: Int) -> [Int]? {
        let visible = visualDataColumns.filter { !hidden.contains($0) }
        return visible == Array(0..<totalColumns) ? nil : visible
    }

    /// Sanitizes a stored column order for a file: drops out-of-range and
    /// duplicate indices, then appends any columns missing from the stored
    /// order in source order (e.g. the file gained columns since it was saved).
    static func normalizedOrder(stored: [Int], totalColumns: Int) -> [Int] {
        var seen = Set<Int>()
        var result = stored.filter { $0 >= 0 && $0 < totalColumns && seen.insert($0).inserted }
        for index in 0..<totalColumns where !seen.contains(index) {
            result.append(index)
        }
        return result
    }
}
