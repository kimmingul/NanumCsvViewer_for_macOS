import AppKit

struct GridTableLayoutColumn {
    let identifier: NSUserInterfaceItemIdentifier
    let baseWidth: CGFloat
    let minWidth: CGFloat
    let isHidden: Bool
    let isDataColumn: Bool
}

struct GridTableLayoutResult {
    let targetWidths: [NSUserInterfaceItemIdentifier: CGFloat]
    let documentWidth: CGFloat
    let needsHorizontalScroller: Bool
}

enum GridTableLayout {
    private static let epsilon: CGFloat = 0.5

    static func compute(columns: [GridTableLayoutColumn], viewportWidth: CGFloat) -> GridTableLayoutResult {
        guard viewportWidth > 0 else {
            return GridTableLayoutResult(targetWidths: [:], documentWidth: 0, needsHorizontalScroller: false)
        }

        let visibleColumns = columns.filter { !$0.isHidden }
        let baseWidths = Dictionary(
            uniqueKeysWithValues: visibleColumns.map { column in
                (column.identifier, max(column.baseWidth, column.minWidth))
            }
        )
        let baseTotal = visibleColumns.reduce(CGFloat(0)) { total, column in
            total + (baseWidths[column.identifier] ?? column.minWidth)
        }

        var targetWidths = baseWidths
        if baseTotal <= viewportWidth + epsilon,
           let fillColumn = visibleColumns.last(where: \.isDataColumn) {
            let extra = max(0, viewportWidth - baseTotal)
            targetWidths[fillColumn.identifier] = (targetWidths[fillColumn.identifier] ?? fillColumn.minWidth) + extra
        }

        let targetTotal = visibleColumns.reduce(CGFloat(0)) { total, column in
            total + (targetWidths[column.identifier] ?? column.minWidth)
        }

        return GridTableLayoutResult(
            targetWidths: targetWidths,
            documentWidth: max(targetTotal, viewportWidth),
            needsHorizontalScroller: baseTotal > viewportWidth + epsilon
        )
    }
}

enum GridTableGeometry {
    static func headerFrame(
        forColumn columnIndex: Int,
        in tableView: NSTableView,
        headerView: NSTableHeaderView
    ) -> NSRect {
        guard columnIndex >= 0, columnIndex < tableView.tableColumns.count else {
            return .null
        }

        let height = headerView.bounds.height > 0 ? headerView.bounds.height : 28
        let calculated = calculatedHeaderFrame(forColumn: columnIndex, in: tableView, height: height)
        let proposed = headerView.headerRect(ofColumn: columnIndex)
        if !proposed.isNull,
           proposed.width > 0,
           proposed.height > 0,
           abs(proposed.minX - calculated.minX) <= 0.5,
           abs(proposed.width - calculated.width) <= 0.5 {
            return NSRect(x: proposed.minX, y: 0, width: proposed.width, height: height)
        }

        return calculated
    }

    private static func calculatedHeaderFrame(
        forColumn columnIndex: Int,
        in tableView: NSTableView,
        height: CGFloat
    ) -> NSRect {
        var x: CGFloat = 0
        for index in 0..<columnIndex {
            let column = tableView.tableColumns[index]
            if !column.isHidden {
                x += column.width
            }
        }
        let column = tableView.tableColumns[columnIndex]
        return NSRect(
            x: x,
            y: 0,
            width: column.isHidden ? 0 : column.width,
            height: height
        )
    }
}
