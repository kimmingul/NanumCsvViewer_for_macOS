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
}
