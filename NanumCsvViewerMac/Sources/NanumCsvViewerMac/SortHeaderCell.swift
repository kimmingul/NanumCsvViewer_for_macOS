import AppKit

final class SortHeaderCell: NSTableHeaderCell {
    var titleText: String?
    var sortPriority: Int?
    var ascending: Bool?
    var typeText: String?
    var columnIdentifierRawValue: String?
    var filterAvailable = false
    var filterActive = false
    private(set) var lastDrawnFilterFrame: NSRect?

    override init(textCell string: String) {
        super.init(textCell: string)
        lineBreakMode = .byTruncatingTail
    }

    required init(coder: NSCoder) {
        super.init(coder: coder)
        lineBreakMode = .byTruncatingTail
    }

    override func copy(with zone: NSZone? = nil) -> Any {
        let copy = SortHeaderCell(textCell: stringValue)
        copy.objectValue = objectValue
        copy.font = font
        copy.alignment = alignment
        copy.lineBreakMode = lineBreakMode
        copy.isEnabled = isEnabled
        copy.controlSize = controlSize
        copy.backgroundStyle = backgroundStyle
        copy.baseWritingDirection = baseWritingDirection
        copy.image = image?.copy() as? NSImage
        copy.usesSingleLineMode = usesSingleLineMode
        copy.titleText = titleText
        copy.sortPriority = sortPriority
        copy.ascending = ascending
        copy.typeText = typeText
        copy.columnIdentifierRawValue = columnIdentifierRawValue
        copy.filterAvailable = filterAvailable
        copy.filterActive = filterActive
        copy.lastDrawnFilterFrame = lastDrawnFilterFrame
        return copy
    }

    override func drawInterior(withFrame cellFrame: NSRect, in controlView: NSView) {
        guard !cellFrame.isNull, cellFrame.width > 0, cellFrame.height > 0 else { return }
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: cellFrame).addClip()
        defer { NSGraphicsContext.restoreGraphicsState() }

        let titleFont = font ?? NSFont.systemFont(ofSize: 12, weight: .semibold)
        let titleAttributes = Self.titleAttributes(font: titleFont)
        let title = titleText ?? stringValue
        let titleSize = title.size(withAttributes: titleAttributes)
        let typeWidth = typeText.map { Self.badgeSize(text: $0, font: Self.typeFont).width } ?? 0
        let sortWidth = ascending.map { _ in Self.badgeSize(text: sortMarkerText, font: Self.sortFont).width } ?? 0
        let filterWidth = filterAvailable ? Self.filterButtonSize.width : 0
        let contentFrame = cellFrame.insetBy(dx: 6, dy: 0)
        let sortReservedWidth = sortWidth > 0 ? sortWidth + 6 : 0
        let filterReservedWidth = filterWidth > 0 ? filterWidth + 6 : 0
        let maxContentX = cellFrame.maxX - 6 - sortReservedWidth - filterReservedWidth
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

        let filterFrame = filterButtonFrame(withFrame: cellFrame, in: controlView)
        lastDrawnFilterFrame = filterFrame
        if let filterFrame {
            drawFilterIndicator(in: filterFrame)
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

    /// Frame to use for filter-icon hit testing: prefer the frame the icon was
    /// actually drawn at; fall back to computing from the native header rect.
    func filterHitFrame(headerFrame: NSRect, in controlView: NSView) -> NSRect? {
        guard filterAvailable else { return nil }
        if let lastDrawnFilterFrame, lastDrawnFilterFrame.intersects(headerFrame) {
            return lastDrawnFilterFrame
        }
        return filterButtonFrame(withFrame: headerFrame, in: controlView)
    }

    func filterButtonFrame(withFrame cellFrame: NSRect, in controlView: NSView) -> NSRect? {
        guard filterAvailable, !cellFrame.isNull, cellFrame.width > 0, cellFrame.height > 0 else { return nil }
        let titleFont = font ?? NSFont.systemFont(ofSize: 12, weight: .semibold)
        let titleAttributes = Self.titleAttributes(font: titleFont)
        let title = titleText ?? stringValue
        let titleSize = title.size(withAttributes: titleAttributes)
        let typeWidth = typeText.map { Self.badgeSize(text: $0, font: Self.typeFont).width } ?? 0
        let sortWidth = ascending.map { _ in Self.badgeSize(text: sortMarkerText, font: Self.sortFont).width } ?? 0
        let sortReservedWidth = sortWidth > 0 ? sortWidth + 6 : 0
        let contentMinX = cellFrame.minX + 6
        let contentTrailingX = cellFrame.maxX - 6 - sortReservedWidth
        let spacing: CGFloat = 6
        let typeSpacing: CGFloat = typeWidth > 0 ? spacing : 0
        let filterWidth = Self.filterButtonSize.width
        let maxContentX = contentTrailingX - filterWidth - spacing
        let availableTitleWidth = max(0, maxContentX - contentMinX - typeWidth - typeSpacing)
        let drawnTitleWidth = min(titleSize.width, availableTitleWidth)
        let preferredX = contentMinX + drawnTitleWidth + typeSpacing + typeWidth + spacing
        let trailingX = contentTrailingX - filterWidth
        let buttonX = min(preferredX, trailingX)
        return NSRect(
            x: buttonX,
            y: cellFrame.midY - Self.filterButtonSize.height / 2,
            width: filterWidth,
            height: Self.filterButtonSize.height
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

    private static var filterButtonSize: NSSize {
        NSSize(width: 18, height: 18)
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

    private func drawFilterIndicator(in frame: NSRect) {
        if filterActive {
            let background = NSBezierPath(roundedRect: frame.insetBy(dx: 1, dy: 1), xRadius: 5, yRadius: 5)
            NSColor.controlAccentColor.withAlphaComponent(0.16).setFill()
            background.fill()
        }

        let inset = frame.insetBy(dx: 4.5, dy: 4)
        let path = NSBezierPath()
        path.move(to: NSPoint(x: inset.minX, y: inset.maxY))
        path.line(to: NSPoint(x: inset.maxX, y: inset.maxY))
        path.line(to: NSPoint(x: inset.midX + 2, y: inset.midY))
        path.line(to: NSPoint(x: inset.midX + 2, y: inset.minY))
        path.line(to: NSPoint(x: inset.midX - 2, y: inset.minY))
        path.line(to: NSPoint(x: inset.midX - 2, y: inset.midY))
        path.close()
        (filterActive ? NSColor.controlAccentColor : NSColor.secondaryLabelColor).setFill()
        path.fill()
    }

}
