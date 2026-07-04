import AppKit

final class CsvTableHeaderView: NSTableHeaderView {
    var filterClickHandler: ((Int, NSRect) -> Void)?

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
        guard let columnIndex = (0..<tableView.tableColumns.count).first(where: { index in
            headerFrame(forColumn: index).contains(point)
        }) else { return nil }
        let column = tableView.tableColumns[columnIndex]
        guard column.identifier.rawValue.hasPrefix("c"),
              let dataColumn = Int(column.identifier.rawValue.dropFirst()),
              let cell = column.headerCell as? SortHeaderCell else {
            return nil
        }
        let frame = headerFrame(forColumn: columnIndex)
        guard let filterFrame = cell.filterButtonFrame(withFrame: frame, in: self),
              filterFrame.contains(point) else {
            return nil
        }
        return (dataColumn, filterFrame)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard tableView != nil else {
            super.draw(dirtyRect)
            return
        }

        if let columnsRect = visibleColumnsRect(in: dirtyRect) {
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(rect: columnsRect).addClip()
            super.draw(dirtyRect)
            NSGraphicsContext.restoreGraphicsState()
        }
        clearTrailingFiller(in: dirtyRect)
    }

    private func clearTrailingFiller(in dirtyRect: NSRect) {
        guard let tableView, let columnsMaxX = visibleColumnsMaxX() else { return }
        guard columnsMaxX < bounds.maxX else { return }

        let filler = NSRect(
            x: max(columnsMaxX, bounds.minX),
            y: bounds.minY,
            width: bounds.maxX - max(columnsMaxX, bounds.minX),
            height: bounds.height
        ).intersection(dirtyRect)
        guard !filler.isNull, filler.width > 0, filler.height > 0 else { return }

        tableView.backgroundColor.setFill()
        filler.fill()
    }

    private func visibleColumnsRect(in dirtyRect: NSRect) -> NSRect? {
        guard let columnsMaxX = visibleColumnsMaxX() else { return nil }
        let maxX = min(columnsMaxX, bounds.maxX)
        guard maxX > bounds.minX else { return nil }

        let columnsRect = NSRect(
            x: bounds.minX,
            y: bounds.minY,
            width: maxX - bounds.minX,
            height: bounds.height
        ).intersection(dirtyRect)
        guard !columnsRect.isNull, columnsRect.width > 0, columnsRect.height > 0 else { return nil }
        return columnsRect
    }

    private func visibleColumnsMaxX() -> CGFloat? {
        guard let tableView else { return nil }
        var maxX = bounds.minX

        for columnIndex in 0..<tableView.numberOfColumns {
            let column = tableView.tableColumns[columnIndex]
            guard !column.isHidden else { continue }
            let rect = headerFrame(forColumn: columnIndex)
            guard !rect.isNull, rect.width > 0 else { continue }
            maxX = max(maxX, rect.maxX)
        }

        return maxX
    }

    private func headerFrame(forColumn columnIndex: Int) -> NSRect {
        guard let tableView, columnIndex >= 0, columnIndex < tableView.tableColumns.count else {
            return .null
        }
        return GridTableGeometry.headerFrame(forColumn: columnIndex, in: tableView, headerView: self)
    }
}
