import CsvCore
import Foundation

enum GridCopyFormatter {
    static func tsv(rows: [[String]], selection: Set<GridCellCoordinate>, sanitizeFormulas: Bool = false) -> String {
        guard let range = boundingRect(for: selection) else { return "" }
        var lines: [String] = []
        for row in range.rows {
            let values = range.columns.map { column -> String in
                guard selection.contains(GridCellCoordinate(row: row, column: column)),
                      row >= 0,
                      row < rows.count,
                      column >= 0,
                      column < rows[row].count else {
                    return ""
                }
                return cell(rows[row][column], sanitizeFormulas: sanitizeFormulas)
            }
            lines.append(values.joined(separator: "\t"))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    static func tsv(row: [String], columns: [Int], sanitizeFormulas: Bool = false) -> String {
        columns.map { column in
            column >= 0 && column < row.count ? cell(row[column], sanitizeFormulas: sanitizeFormulas) : ""
        }.joined(separator: "\t") + "\n"
    }

    static func tsv(columnName: String, values: [String], sanitizeFormulas: Bool = false) -> String {
        ([cell(columnName, sanitizeFormulas: sanitizeFormulas)]
            + values.map { cell($0, sanitizeFormulas: sanitizeFormulas) }).joined(separator: "\n") + "\n"
    }

    private static func cell(_ value: String, sanitizeFormulas: Bool) -> String {
        tsvEscaped(sanitizeFormulas ? CsvFormulaSanitizer.sanitize(value) : value)
    }

    private static func boundingRect(for selection: Set<GridCellCoordinate>) -> ClosedRangeGrid? {
        guard let first = selection.first else { return nil }
        var minRow = first.row
        var maxRow = first.row
        var minColumn = first.column
        var maxColumn = first.column
        for cell in selection {
            minRow = min(minRow, cell.row)
            maxRow = max(maxRow, cell.row)
            minColumn = min(minColumn, cell.column)
            maxColumn = max(maxColumn, cell.column)
        }
        return ClosedRangeGrid(rows: minRow...maxRow, columns: minColumn...maxColumn)
    }

    private static func tsvEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
    }
}
