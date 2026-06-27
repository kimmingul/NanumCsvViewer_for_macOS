import AppKit

final class SortHeaderCell: NSTableHeaderCell {
    var sortPriority: Int?
    var ascending: Bool?
    var typeText: String?

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
        let typeWidth = typeText.map { Self.badgeSize(text: $0, font: Self.typeFont).width } ?? 0
        let sortWidth = ascending.map { _ in Self.badgeSize(text: sortMarkerText, font: Self.sortFont).width } ?? 0
        let badgeSpacing: CGFloat = typeWidth > 0 && sortWidth > 0 ? 4 : 0
        let reservedWidth = typeWidth + sortWidth + badgeSpacing
        if reservedWidth > 0 {
            titleFrame.size.width = max(0, titleFrame.width - reservedWidth - 8)
        }
        super.drawInterior(withFrame: titleFrame, in: controlView)

        var trailingX = cellFrame.maxX - 6
        if let typeText {
            let frame = Self.badgeFrame(text: typeText, font: Self.typeFont, trailingX: trailingX, cellFrame: cellFrame)
            drawBadge(
                text: typeText,
                frame: frame,
                font: Self.typeFont,
                foreground: .secondaryLabelColor,
                background: NSColor.controlBackgroundColor.withAlphaComponent(0.9)
            )
            trailingX = frame.minX - 4
        }

        guard ascending != nil else { return }
        let marker = sortMarkerText
        let frame = Self.badgeFrame(text: marker, font: Self.sortFont, trailingX: trailingX, cellFrame: cellFrame)
        drawBadge(
            text: marker,
            frame: frame,
            font: Self.sortFont,
            foreground: .controlAccentColor,
            background: NSColor.controlAccentColor.withAlphaComponent(0.12)
        )
    }

    private var sortMarkerText: String {
        guard let ascending else { return "" }
        return sortPriority.map { "\($0)\(ascending ? "▲" : "▼")" } ?? (ascending ? "▲" : "▼")
    }

    private static var sortFont: NSFont {
        NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .semibold)
    }

    private static var typeFont: NSFont {
        NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .semibold)
    }

    private static func badgeSize(text: String, font: NSFont) -> NSSize {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font
        ]
        let size = text.size(withAttributes: attributes)
        return NSSize(width: size.width + 8, height: size.height + 3)
    }

    private static func badgeFrame(text: String, font: NSFont, trailingX: CGFloat, cellFrame: NSRect) -> NSRect {
        let padded = badgeSize(text: text, font: font)
        return NSRect(
            x: trailingX - padded.width,
            y: cellFrame.midY - padded.height / 2,
            width: padded.width,
            height: padded.height
        )
    }

    private func drawBadge(text: String, frame: NSRect, font: NSFont, foreground: NSColor, background: NSColor) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: foreground
        ]

        let path = NSBezierPath(roundedRect: frame, xRadius: 5, yRadius: 5)
        background.setFill()
        path.fill()

        let size = text.size(withAttributes: attributes)
        text.draw(
            in: NSRect(
                x: frame.midX - size.width / 2,
                y: frame.midY - size.height / 2,
                width: size.width,
                height: size.height
            ),
            withAttributes: attributes
        )
    }
}
