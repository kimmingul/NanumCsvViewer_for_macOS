import AppKit

final class CsvTableView: NSTableView {
    var cellClickHandler: ((Int, Int) -> Void)?

    override func mouseDown(with event: NSEvent) {
        notifyCellHit(for: event)
        super.mouseDown(with: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        notifyCellHit(for: event)
        super.rightMouseDown(with: event)
    }

    private func notifyCellHit(for event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let row = self.row(at: point)
        let column = self.column(at: point)
        cellClickHandler?(row, column)
    }
}
