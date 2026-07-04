import AppKit

struct CsvTableCellHit {
    enum Phase {
        case mouseDown
        case mouseDragged
        case mouseUp
        case rightMouseDown
    }

    let row: Int
    let column: Int
    let modifiers: NSEvent.ModifierFlags
    let phase: Phase
}

final class CsvTableView: NSTableView {
    var cellClickHandler: ((Int, Int) -> Void)?
    var cellHitHandler: ((CsvTableCellHit) -> Void)?

    override func draw(_ dirtyRect: NSRect) {
        drawBodyRowBackgrounds(in: dirtyRect)
        super.draw(dirtyRect)
        drawBodyHorizontalGridLines(in: dirtyRect)
    }

    override func mouseDown(with event: NSEvent) {
        notifyCellHit(for: event, phase: .mouseDown)
        super.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        notifyCellHit(for: event, phase: .mouseDragged)
        super.mouseDragged(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        notifyCellHit(for: event, phase: .mouseUp)
        super.mouseUp(with: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        notifyCellHit(for: event, phase: .rightMouseDown)
        super.rightMouseDown(with: event)
    }

    private func notifyCellHit(for event: NSEvent, phase: CsvTableCellHit.Phase) {
        let point = convert(event.locationInWindow, from: nil)
        let row = self.row(at: point)
        let column = self.column(at: point)
        cellClickHandler?(row, column)
        cellHitHandler?(CsvTableCellHit(row: row, column: column, modifiers: event.modifierFlags, phase: phase))
    }

    private func drawBodyRowBackgrounds(in dirtyRect: NSRect) {
        let rowRange = bodyFillerRowRange(in: dirtyRect)
        guard rowRange.length > 0 else {
            backgroundColor.setFill()
            dirtyRect.fill()
            return
        }

        let lastRow = min(numberOfRows, rowRange.location + rowRange.length)
        for row in rowRange.location..<lastRow {
            let rowRect = bodyFillerRowRect(for: row)
            guard rowRect.maxY >= dirtyRect.minY, rowRect.minY <= dirtyRect.maxY else { continue }

            let fillerRect = NSRect(
                x: dirtyRect.minX,
                y: rowRect.minY,
                width: dirtyRect.width,
                height: rowRect.height
            ).intersection(dirtyRect)
            guard !fillerRect.isNull, fillerRect.width > 0, fillerRect.height > 0 else { continue }

            rowBackgroundColor(for: row).setFill()
            fillerRect.fill()
        }
    }

    private func bodyFillerRowRange(in dirtyRect: NSRect) -> NSRange {
        let tableRange = rows(in: dirtyRect)
        if tableRange.length > 0 || numberOfRows == 0 {
            return tableRange
        }

        let rowStride = max(rowHeight + intercellSpacing.height, 1)
        let firstRow = max(0, Int(floor(max(dirtyRect.minY, bounds.minY) / rowStride)))
        let lastRow = min(numberOfRows, Int(ceil(max(dirtyRect.maxY, bounds.minY) / rowStride)))
        guard lastRow > firstRow else { return NSRange(location: 0, length: 0) }
        return NSRange(location: firstRow, length: lastRow - firstRow)
    }

    private func bodyFillerRowRect(for row: Int) -> NSRect {
        let tableRect = rect(ofRow: row)
        if !tableRect.isNull, tableRect.height > 0 {
            return tableRect
        }

        let rowStride = max(rowHeight + intercellSpacing.height, 1)
        return NSRect(
            x: bounds.minX,
            y: CGFloat(row) * rowStride,
            width: bounds.width,
            height: rowHeight
        )
    }

    private func rowBackgroundColor(for row: Int) -> NSColor {
        if selectedRowIndexes.contains(row) {
            return NSColor.selectedContentBackgroundColor
        }
        if usesAlternatingRowBackgroundColors {
            let colors = NSColor.alternatingContentBackgroundColors
            if !colors.isEmpty {
                return colors[row % colors.count]
            }
        }
        return backgroundColor
    }

    private func drawBodyHorizontalGridLines(in dirtyRect: NSRect) {
        guard gridStyleMask.contains(.solidHorizontalGridLineMask) else { return }
        let rowRange = bodyFillerRowRange(in: dirtyRect)
        guard rowRange.length > 0 else { return }

        let lineMinX = max(dirtyRect.minX, bounds.minX)
        let lineMaxX = min(dirtyRect.maxX, bounds.maxX)
        guard lineMaxX > lineMinX + 0.5 else { return }

        let lastRow = min(numberOfRows, rowRange.location + rowRange.length)
        for row in rowRange.location..<lastRow {
            let rowRect = bodyFillerRowRect(for: row)
            let y = floor(rowRect.maxY) + 0.5
            guard y >= dirtyRect.minY, y <= dirtyRect.maxY else { continue }

            gridColor.setStroke()
            let path = NSBezierPath()
            path.lineWidth = 1
            path.move(to: NSPoint(x: lineMinX, y: y))
            path.line(to: NSPoint(x: lineMaxX, y: y))
            path.stroke()
        }
    }
}
