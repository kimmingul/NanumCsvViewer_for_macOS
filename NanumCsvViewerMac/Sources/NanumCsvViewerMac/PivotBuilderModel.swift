import AppKit
@preconcurrency import CsvCore

struct PivotField: Equatable {
    let index: Int
    let name: String
    let valueType: ColumnValueType?

    var typeHint: String? {
        valueType?.rawValue
    }

    var isMeasureCandidate: Bool {
        valueType == .integer || valueType == .float
    }

    var displayName: String {
        typeHint.map { "\(name)  \($0)" } ?? name
    }
}

enum PivotDropZone: String, CaseIterable, Codable {
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
        value != nil
    }
}

struct PivotFieldDragPayload: Codable, Equatable {
    let fieldIndex: Int
    let sourceZone: PivotDropZone?
    let sourcePosition: Int?

    static func pasteboardItem(fieldIndex: Int, sourceZone: PivotDropZone? = nil, sourcePosition: Int? = nil) -> NSPasteboardItem {
        let payload = PivotFieldDragPayload(fieldIndex: fieldIndex, sourceZone: sourceZone, sourcePosition: sourcePosition)
        let item = NSPasteboardItem()
        if let data = try? JSONEncoder().encode(payload),
           let encoded = String(data: data, encoding: .utf8) {
            item.setString(encoded, forType: .pivotFieldPayload)
        }
        item.setString(String(fieldIndex), forType: .pivotFieldIndex)
        return item
    }

    static func read(from pasteboard: NSPasteboard) -> PivotFieldDragPayload? {
        if let encoded = pasteboard.string(forType: .pivotFieldPayload),
           let data = encoded.data(using: .utf8),
           let payload = try? JSONDecoder().decode(PivotFieldDragPayload.self, from: data) {
            return payload
        }
        guard let raw = pasteboard.string(forType: .pivotFieldIndex),
              let fieldIndex = Int(raw) else { return nil }
        return PivotFieldDragPayload(fieldIndex: fieldIndex, sourceZone: nil, sourcePosition: nil)
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
        if pivot.rowColumns.isEmpty {
            let categories = pivot.columnColumns.isEmpty
                ? [L.t("Total", "합계")]
                : pivot.columnKeys.map { label($0, fallback: L.t("Total", "합계")) }
            let values = pivot.columnColumns.isEmpty
                ? [pivot.value(row: [], column: [])]
                : pivot.columnKeys.map { pivot.value(row: [], column: $0) }
            return PivotChartModel(
                categories: categories,
                series: [PivotChartSeries(name: pivot.function.rawValue, values: values)],
                unsupportedReason: nil
            )
        }

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
        let columnKeys = pivot.columnColumns.isEmpty ? [[]] : pivot.columnKeys
        let series = columnKeys.map { columnKey in
            PivotChartSeries(
                name: label(columnKey, fallback: pivot.function.rawValue),
                values: pivot.rowKeys.map { rowKey in
                    pivot.value(row: rowKey, column: columnKey)
                }
            )
        }
        return PivotChartModel(categories: categories, series: series, unsupportedReason: nil)
    }

    private static func label(_ key: [String], fallback: String) -> String {
        let joined = key.joined(separator: " | ")
        return joined.isEmpty ? fallback : joined
    }
}

extension NSPasteboard.PasteboardType {
    static let pivotFieldIndex = NSPasteboard.PasteboardType("com.nanum.csvviewer.pivot-field-index")
    static let pivotFieldPayload = NSPasteboard.PasteboardType("com.nanum.csvviewer.pivot-field-payload")
}
