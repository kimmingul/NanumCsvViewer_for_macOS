import AppKit

final class SortHeaderCell: NSTableHeaderCell {
    var titleText: String?
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
        let titleFont = font ?? NSFont.systemFont(ofSize: 12, weight: .semibold)
        let titleAttributes = Self.titleAttributes(font: titleFont)
        let title = titleText ?? stringValue
        let titleSize = title.size(withAttributes: titleAttributes)
        let typeWidth = typeText.map { Self.badgeSize(text: $0, font: Self.typeFont).width } ?? 0
        let sortWidth = ascending.map { _ in Self.badgeSize(text: sortMarkerText, font: Self.sortFont).width } ?? 0
        let contentFrame = cellFrame.insetBy(dx: 6, dy: 0)
        let sortReservedWidth = sortWidth > 0 ? sortWidth + 6 : 0
        let maxContentX = cellFrame.maxX - 6 - sortReservedWidth
        let typeSpacing: CGFloat = typeWidth > 0 ? 6 : 0
        let availableTitleWidth = max(0, maxContentX - contentFrame.minX - typeWidth - typeSpacing)
        let drawnTitleWidth = min(titleSize.width, availableTitleWidth)

        let titleFrame = NSRect(
            x: contentFrame.minX,
            y: cellFrame.midY - titleSize.height / 2,
            width: availableTitleWidth,
            height: titleSize.height
        )
        title.draw(in: titleFrame, withAttributes: titleAttributes)

        if let typeText, typeWidth > 0 {
            let typeX = min(contentFrame.minX + drawnTitleWidth + typeSpacing, maxContentX - typeWidth)
            let frame = Self.badgeFrame(text: typeText, font: Self.typeFont, leadingX: typeX, cellFrame: cellFrame)
            drawBadge(
                text: typeText,
                frame: frame,
                font: Self.typeFont,
                foreground: .controlAccentColor,
                background: NSColor.controlAccentColor.withAlphaComponent(0.16)
            )
        }

        guard ascending != nil else { return }
        let marker = sortMarkerText
        let frame = Self.badgeFrame(text: marker, font: Self.sortFont, trailingX: cellFrame.maxX - 6, cellFrame: cellFrame)
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

    private static func titleAttributes(font: NSFont) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        return [
            .font: font,
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph
        ]
    }

    private static func badgeSize(text: String, font: NSFont) -> NSSize {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font
        ]
        let size = text.size(withAttributes: attributes)
        return NSSize(width: size.width + 8, height: size.height + 3)
    }

    private static func badgeFrame(text: String, font: NSFont, leadingX: CGFloat, cellFrame: NSRect) -> NSRect {
        let padded = badgeSize(text: text, font: font)
        return NSRect(
            x: leadingX,
            y: cellFrame.midY - padded.height / 2,
            width: padded.width,
            height: padded.height
        )
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
