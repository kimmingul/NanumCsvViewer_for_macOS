import AppKit

final class SortHeaderCell: NSTableHeaderCell {
    var sortPriority: Int?
    var ascending: Bool?

    override init(textCell string: String) {
        super.init(textCell: string)
        lineBreakMode = .byTruncatingTail
    }

    required init(coder: NSCoder) {
        super.init(coder: coder)
        lineBreakMode = .byTruncatingTail
    }

    override func drawInterior(withFrame cellFrame: NSRect, in controlView: NSView) {
        var titleFrame = cellFrame.insetBy(dx: 6, dy: 0)
        if ascending != nil {
            titleFrame.size.width = max(0, titleFrame.width - (sortPriority == nil ? 24 : 40))
        }
        super.drawInterior(withFrame: titleFrame, in: controlView)

        guard let ascending else { return }
        let marker = sortPriority.map { "\($0)\(ascending ? "▲" : "▼")" } ?? (ascending ? "▲" : "▼")
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .semibold),
            .foregroundColor: NSColor.controlAccentColor
        ]
        let size = marker.size(withAttributes: attributes)
        let padded = NSSize(width: size.width + 8, height: size.height + 3)
        let markerFrame = NSRect(
            x: cellFrame.maxX - padded.width - 6,
            y: cellFrame.midY - padded.height / 2,
            width: padded.width,
            height: padded.height
        )

        let path = NSBezierPath(roundedRect: markerFrame, xRadius: 5, yRadius: 5)
        NSColor.controlAccentColor.withAlphaComponent(0.12).setFill()
        path.fill()

        marker.draw(
            in: NSRect(
                x: markerFrame.midX - size.width / 2,
                y: markerFrame.midY - size.height / 2,
                width: size.width,
                height: size.height
            ),
            withAttributes: attributes
        )
    }
}
