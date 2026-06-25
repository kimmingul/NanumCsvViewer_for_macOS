import Foundation

struct PerformanceSnapshot: Equatable {
    let fileBytes: Int64
    let totalRows: Int
    let visibleRows: Int
    let columnCount: Int
    let storageMode: String
    let indexingElapsed: TimeInterval?
    let indexingComplete: Bool

    func formattedLines() -> [String] {
        var lines = [
            "File: \(Self.formatBytes(fileBytes))",
            Self.formatRows(visibleRows: visibleRows, totalRows: totalRows),
            "Columns: \(columnCount.formatted())",
            "Storage: \(storageMode)"
        ]

        if indexingComplete, let indexingElapsed {
            lines.append("Indexing: complete in \(Self.formatSeconds(indexingElapsed))")
            if indexingElapsed > 0, totalRows > 0 {
                let throughput = Int((Double(totalRows) / indexingElapsed).rounded())
                lines.append("Throughput: \(throughput.formatted()) rows/s")
            }
        } else if indexingComplete {
            lines.append("Indexing: complete")
        } else {
            lines.append("Indexing: in progress")
        }

        return lines
    }

    private static func formatRows(visibleRows: Int, totalRows: Int) -> String {
        if visibleRows == totalRows {
            return "Rows: \(totalRows.formatted())"
        }
        return "Rows: \(visibleRows.formatted()) / \(totalRows.formatted()) visible"
    }

    private static func formatBytes(_ bytes: Int64) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var value = Double(bytes)
        var index = 0
        while value >= 1024, index < units.count - 1 {
            value /= 1024
            index += 1
        }
        if index == 0 {
            return "\(Int(value)) \(units[index])"
        }
        return String(format: "%.1f %@", value, units[index])
    }

    private static func formatSeconds(_ seconds: TimeInterval) -> String {
        String(format: "%.2f s", seconds)
    }
}
