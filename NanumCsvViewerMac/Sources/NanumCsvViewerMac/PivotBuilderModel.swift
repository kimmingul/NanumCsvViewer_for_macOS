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

struct PivotMeasure {
    let id: Int
    let fieldIndex: Int
    var function: AggregationFunction

    init(id: Int = 0, fieldIndex: Int, function: AggregationFunction) {
        self.id = id
        self.fieldIndex = fieldIndex
        self.function = function
    }
}

extension PivotMeasure: Equatable {
    static func == (lhs: PivotMeasure, rhs: PivotMeasure) -> Bool {
        lhs.fieldIndex == rhs.fieldIndex && lhs.function == rhs.function
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
    var measures: [PivotMeasure] = []
    var filters: [Int] = []
    var filterSelections: [Int: String] = [:]
    var dateGroupings: [Int: DateBinPeriod] = [:]

    var value: Int? {
        get {
            measures.first?.fieldIndex
        }
        set {
            guard let newValue else {
                measures.removeAll()
                return
            }
            if measures.isEmpty {
                measures = [PivotMeasure(fieldIndex: newValue, function: .count)]
            } else {
                measures[0] = PivotMeasure(fieldIndex: newValue, function: measures[0].function)
                if measures.count > 1 {
                    measures.removeSubrange(1..<measures.count)
                }
            }
        }
    }

    var function: AggregationFunction {
        get {
            measures.first?.function ?? .count
        }
        set {
            guard !measures.isEmpty else { return }
            measures[0].function = newValue
        }
    }

    var isRunnable: Bool {
        !measures.isEmpty
    }
}

enum PivotResultExportFormat {
    case tsv
    case csv
}

struct PivotResultTableSort: Equatable {
    let column: Int
    let ascending: Bool
}

struct PivotResultTableState: Equatable {
    var sort: PivotResultTableSort?
    var filterColumn: Int?
    var filterQuery: String = ""
}

struct PivotResultTableModel: Equatable {
    let headers: [String]
    let rows: [[String]]
    var state = PivotResultTableState()

    var visibleRows: [[String]] {
        let filtered = filteredRows()
        guard let sort = state.sort else { return filtered }
        return sortedRows(filtered, by: sort)
    }

    mutating func sort(column: Int, ascending: Bool) {
        guard column >= 0 else { return }
        state.sort = PivotResultTableSort(column: column, ascending: ascending)
    }

    mutating func toggleSort(column: Int) {
        guard column >= 0 else { return }
        if let sort = state.sort, sort.column == column {
            state.sort = PivotResultTableSort(column: column, ascending: !sort.ascending)
        } else {
            state.sort = PivotResultTableSort(column: column, ascending: true)
        }
    }

    mutating func setFilter(column: Int?, query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        state.filterColumn = column
        state.filterQuery = trimmed
    }

    func exportString(format: PivotResultExportFormat) -> String {
        let rows = [headers] + visibleRows
        let lines = rows.map { row in
            switch format {
            case .tsv:
                return row.joined(separator: "\t")
            case .csv:
                return row.map(Self.csvEscaped).joined(separator: ",")
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private func filteredRows() -> [[String]] {
        guard !state.filterQuery.isEmpty else { return rows }
        return rows.filter { row in
            if let column = state.filterColumn {
                return row[safe: column]?.range(
                    of: state.filterQuery,
                    options: [.caseInsensitive, .diacriticInsensitive]
                ) != nil
            }
            return row.contains { value in
                value.range(
                    of: state.filterQuery,
                    options: [.caseInsensitive, .diacriticInsensitive]
                ) != nil
            }
        }
    }

    private func sortedRows(_ rows: [[String]], by sort: PivotResultTableSort) -> [[String]] {
        let pinnedTotal: [[String]]
        let sortableRows: [[String]]
        if let last = rows.last, isTotalRow(last) {
            pinnedTotal = [last]
            sortableRows = Array(rows.dropLast())
        } else {
            pinnedTotal = []
            sortableRows = rows
        }

        let sorted = sortableRows.enumerated().sorted { lhs, rhs in
            let comparison = compare(
                lhs.element[safe: sort.column] ?? "",
                rhs.element[safe: sort.column] ?? ""
            )
            if comparison == .orderedSame {
                return lhs.offset < rhs.offset
            }
            return sort.ascending ? comparison == .orderedAscending : comparison == .orderedDescending
        }.map(\.element)
        return sorted + pinnedTotal
    }

    private func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
        if let lhsNumber = Self.numberValue(lhs), let rhsNumber = Self.numberValue(rhs) {
            if lhsNumber < rhsNumber { return .orderedAscending }
            if lhsNumber > rhsNumber { return .orderedDescending }
            return .orderedSame
        }
        return lhs.localizedCaseInsensitiveCompare(rhs)
    }

    private func isTotalRow(_ row: [String]) -> Bool {
        row.first == L.t("Total", "합계")
    }

    private static func numberValue(_ text: String) -> Double? {
        // Use the same locale-aware parser as the aggregation so the result
        // table sorts numerically on exactly the values it aggregated.
        CsvNumber.parse(text)
    }

    private static func csvEscaped(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r") {
            return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return value
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

enum PivotChartKind: String, CaseIterable, Hashable {
    case bar
    case groupedBar
    case stackedBar
    case line

    var title: String {
        switch self {
        case .bar:
            return L.t("Bar", "막대")
        case .groupedBar:
            return L.t("Grouped", "묶은 막대")
        case .stackedBar:
            return L.t("Stacked", "누적 막대")
        case .line:
            return L.t("Line", "꺾은선")
        }
    }
}

struct PivotChartPoint: Equatable, Identifiable {
    let category: String
    let series: String
    let value: Double

    var id: String {
        "\(category)\u{1F}\(series)"
    }
}

struct PivotChartModel: Equatable {
    let categories: [String]
    let series: [PivotChartSeries]
    let unsupportedReason: String?
    let points: [PivotChartPoint]
    let recommendedKind: PivotChartKind
    let xAxisTitle: String
    let seriesTitle: String
    let valueTitle: String

    init(
        categories: [String],
        series: [PivotChartSeries],
        unsupportedReason: String?,
        points: [PivotChartPoint]? = nil,
        recommendedKind: PivotChartKind = .bar,
        xAxisTitle: String = "",
        seriesTitle: String = "",
        valueTitle: String = ""
    ) {
        self.categories = categories
        self.series = series
        self.unsupportedReason = unsupportedReason
        self.points = points ?? Self.makePoints(categories: categories, series: series)
        self.recommendedKind = recommendedKind
        self.xAxisTitle = xAxisTitle
        self.seriesTitle = seriesTitle
        self.valueTitle = valueTitle.isEmpty ? series.first?.name ?? "" : valueTitle
    }

    static func make(from pivot: PivotTableResult) -> PivotChartModel {
        if pivot.rowColumns.isEmpty {
            let categories = pivot.columnColumns.isEmpty
                ? [L.t("Total", "합계")]
                : pivot.columnKeys.map { label($0, fallback: L.t("Total", "합계")) }
            let values = pivot.columnColumns.isEmpty
                ? [pivot.value(row: [], column: [])]
                : pivot.columnKeys.map { pivot.value(row: [], column: $0) }
            let series = [PivotChartSeries(name: pivot.function.rawValue, values: values)]
            return PivotChartModel(
                categories: categories,
                series: series,
                unsupportedReason: nil,
                recommendedKind: recommendedKind(categories: categories, seriesCount: series.count),
                xAxisTitle: pivot.columnColumns.isEmpty ? L.t("Metric", "지표") : L.t("Columns", "열"),
                seriesTitle: L.t("Measure", "측정값"),
                valueTitle: pivot.function.rawValue
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
        return PivotChartModel(
            categories: categories,
            series: series,
            unsupportedReason: nil,
            recommendedKind: recommendedKind(categories: categories, seriesCount: series.count),
            xAxisTitle: rowAxisTitle(for: pivot),
            seriesTitle: pivot.columnColumns.isEmpty ? L.t("Measure", "측정값") : L.t("Columns", "열"),
            valueTitle: pivot.function.rawValue
        )
    }

    private static func label(_ key: [String], fallback: String) -> String {
        let joined = key.joined(separator: " | ")
        return joined.isEmpty ? fallback : joined
    }

    private static func rowAxisTitle(for pivot: PivotTableResult) -> String {
        if !pivot.rowColumnNames.isEmpty {
            return pivot.rowColumnNames.joined(separator: " | ")
        }
        return pivot.rowColumns.map { "Column \($0 + 1)" }.joined(separator: " | ")
    }

    private static func makePoints(categories: [String], series: [PivotChartSeries]) -> [PivotChartPoint] {
        categories.enumerated().flatMap { index, category in
            series.map { item in
                PivotChartPoint(
                    category: category,
                    series: item.name,
                    value: item.values[safe: index] ?? 0
                )
            }
        }
    }

    private static func recommendedKind(categories: [String], seriesCount: Int) -> PivotChartKind {
        if looksTemporal(categories) {
            return .line
        }
        return seriesCount > 1 ? .groupedBar : .bar
    }

    private static func looksTemporal(_ categories: [String]) -> Bool {
        let nonNullCategories = categories.filter { !$0.isEmpty && $0 != "null" }
        guard nonNullCategories.count >= 2 else { return false }
        return nonNullCategories.allSatisfy { category in
            category.range(
                of: #"^\d{4}(-\d{2}){0,2}$|^\d{4}-W\d{2}$"#,
                options: .regularExpression
            ) != nil
        }
    }
}

extension NSPasteboard.PasteboardType {
    static let pivotFieldIndex = NSPasteboard.PasteboardType("com.nanum.csvviewer.pivot-field-index")
    static let pivotFieldPayload = NSPasteboard.PasteboardType("com.nanum.csvviewer.pivot-field-payload")
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
