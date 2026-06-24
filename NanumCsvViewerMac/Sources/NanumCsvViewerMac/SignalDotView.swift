import AppKit

final class SignalDotView: NSView {
    var color: NSColor = .systemGray {
        didSet { needsDisplay = true }
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 10, height: 10)
    }

    override func draw(_ dirtyRect: NSRect) {
        color.setFill()
        let rect = bounds.insetBy(dx: 1, dy: 1)
        NSBezierPath(ovalIn: rect).fill()
    }
}
