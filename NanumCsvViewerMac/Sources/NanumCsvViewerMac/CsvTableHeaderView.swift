import AppKit

final class CsvTableHeaderView: NSTableHeaderView {
    var filterClickHandler: ((Int, NSRect) -> Void)?
    var headerMenuProvider: ((Int) -> NSMenu?)?

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        let columnIndex = column(at: point)
        guard let tableView, columnIndex >= 0, columnIndex < tableView.tableColumns.count else {
            return super.menu(for: event)
        }
        let identifier = tableView.tableColumns[columnIndex].identifier.rawValue
        guard identifier.hasPrefix("c"), let dataColumn = Int(identifier.dropFirst()) else {
            return super.menu(for: event)
        }
        return headerMenuProvider?(dataColumn) ?? super.menu(for: event)
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let hit = filterHit(at: point) {
            filterClickHandler?(hit.dataColumn, hit.frame)
            return
        }
        super.mouseDown(with: event)
    }

    func filterHit(at point: NSPoint) -> (dataColumn: Int, frame: NSRect)? {
        guard let tableView else { return nil }
        let columnIndex = column(at: point)
        guard columnIndex >= 0, columnIndex < tableView.tableColumns.count else { return nil }
        let column = tableView.tableColumns[columnIndex]
        guard column.identifier.rawValue.hasPrefix("c"),
              let dataColumn = Int(column.identifier.rawValue.dropFirst()),
              let cell = column.headerCell as? SortHeaderCell else {
            return nil
        }
        guard let filterFrame = cell.filterHitFrame(
            headerFrame: headerRect(ofColumn: columnIndex),
            in: self
        ), filterFrame.contains(point) else {
            return nil
        }
        return (dataColumn, filterFrame)
    }
}
