import Foundation

enum GridCopyFormatter {
    static func tsv(rows: [[String]], selection: Set<GridCellCoordinate>) -> String {
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
                return tsvEscaped(rows[row][column])
            }
            lines.append(values.joined(separator: "\t"))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    static func tsv(row: [String], columns: [Int]) -> String {
        columns.map { column in
            column >= 0 && column < row.count ? tsvEscaped(row[column]) : ""
        }.joined(separator: "\t") + "\n"
    }

    static func tsv(columnName: String, values: [String]) -> String {
        ([tsvEscaped(columnName)] + values.map(tsvEscaped)).joined(separator: "\n") + "\n"
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
