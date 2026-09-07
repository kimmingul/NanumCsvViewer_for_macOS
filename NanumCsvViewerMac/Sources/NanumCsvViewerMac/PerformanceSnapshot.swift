import Foundation

struct PerformanceSnapshot: Equatable {
    let fileBytes: Int64
    let totalRows: Int
    let visibleRows: Int
    let columnCount: Int
    let storageMode: String
    let indexingElapsed: TimeInterval?
    let indexingComplete: Bool
    var memoryFootprintBytes: Int64? = nil

    func formattedLines() -> [String] {
        let storageDescription = storageMode == "Disk" ? L.t("Disk", "디스크") : storageMode
        var lines = [
            L.t("File: \(Self.formatBytes(fileBytes))", "파일: \(Self.formatBytes(fileBytes))"),
            Self.formatRows(visibleRows: visibleRows, totalRows: totalRows),
            L.t("Columns: \(columnCount.formatted(.number.locale(L.locale)))", "열: \(columnCount.formatted(.number.locale(L.locale)))"),
            L.t("Storage: \(storageDescription)", "저장 방식: \(storageDescription)")
        ]

        if let memoryFootprintBytes {
            lines.append(L.t("Memory: \(Self.formatBytes(memoryFootprintBytes))", "메모리: \(Self.formatBytes(memoryFootprintBytes))"))
        }

        if indexingComplete, let indexingElapsed {
            lines.append(L.t("Indexing: complete in \(Self.formatSeconds(indexingElapsed))", "인덱싱: \(Self.formatSeconds(indexingElapsed))에 완료"))
            if indexingElapsed > 0, totalRows > 0 {
                let throughput = Int((Double(totalRows) / indexingElapsed).rounded())
                lines.append(L.t("Throughput: \(throughput.formatted(.number.locale(L.locale))) rows/s", "처리 속도: 초당 \(throughput.formatted(.number.locale(L.locale)))행"))
            }
        } else if indexingComplete {
            lines.append(L.t("Indexing: complete", "인덱싱: 완료"))
        } else {
            lines.append(L.t("Indexing: in progress", "인덱싱: 진행 중"))
        }

        return lines
    }

    private static func formatRows(visibleRows: Int, totalRows: Int) -> String {
        if visibleRows == totalRows {
            return L.t("Rows: \(totalRows.formatted(.number.locale(L.locale)))", "행: \(totalRows.formatted(.number.locale(L.locale)))")
        }
        return L.t("Rows: \(visibleRows.formatted(.number.locale(L.locale))) / \(totalRows.formatted(.number.locale(L.locale))) visible", "행: \(visibleRows.formatted(.number.locale(L.locale))) / \(totalRows.formatted(.number.locale(L.locale))) 표시")
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
        return String(format: "%.1f %@", locale: L.locale, value, units[index])
    }

    private static func formatSeconds(_ seconds: TimeInterval) -> String {
        String(format: "%.2f s", locale: L.locale, seconds)
    }
}
