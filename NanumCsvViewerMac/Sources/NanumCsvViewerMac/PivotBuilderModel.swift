import AppKit
@preconcurrency import CsvCore

struct PivotField: Equatable {
    let index: Int
    let name: String
    let typeHint: String?

    var displayName: String {
        typeHint.map { "\(name)  \($0)" } ?? name
    }
}

enum PivotDropZone: String, CaseIterable {
    case rows
    case columns
    case values
    case filters

    var title: String {
        switch self {
        case .rows:
            return L.t("Rows", "행")
        case .columns:
            return L.t("Columns", "열")
        case .values:
            return L.t("Values", "값")
        case .filters:
            return L.t("Filters", "필터")
        }
    }
}

struct PivotBuilderLayout: Equatable {
    var rows: [Int] = []
    var columns: [Int] = []
    var value: Int?
    var filters: [Int] = []
    var function: AggregationFunction = .sum

    var isRunnable: Bool {
        !rows.isEmpty && !columns.isEmpty && value != nil
    }
}

struct PivotChartSeries: Equatable {
    let name: String
    let values: [Double]
}

struct PivotChartModel: Equatable {
    let categories: [String]
    let series: [PivotChartSeries]
    let unsupportedReason: String?

    static func make(from pivot: PivotTableResult) -> PivotChartModel {
        guard pivot.rowColumns.count == 1 else {
            return PivotChartModel(
                categories: [],
                series: [],
                unsupportedReason: L.t(
                    "Charts currently support one row field.",
                    "차트는 현재 하나의 행 필드만 지원합니다."
                )
            )
        }

        let categories = pivot.rowKeys.map { $0.joined(separator: " | ") }
        let series = pivot.columnKeys.map { columnKey in
            PivotChartSeries(
                name: columnKey.joined(separator: " | "),
                values: pivot.rowKeys.map { rowKey in
                    pivot.value(row: rowKey, column: columnKey)
                }
            )
        }
        return PivotChartModel(categories: categories, series: series, unsupportedReason: nil)
    }
}

extension NSPasteboard.PasteboardType {
    static let pivotFieldIndex = NSPasteboard.PasteboardType("com.nanum.csvviewer.pivot-field-index")
}
