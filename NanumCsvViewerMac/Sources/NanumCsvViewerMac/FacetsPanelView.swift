import AppKit
import CsvCore

struct FacetPanelEntry: Equatable {
    enum Kind: Equatable {
        case value(String)
        case numericRange(lower: Double, upper: Double, includesUpperBound: Bool)
    }

    let label: String
    let count: Int
    let maxCount: Int
    let kind: Kind
    let isActive: Bool
}

struct FacetPanelSection: Equatable {
    let column: Int
    let title: String
    let entries: [FacetPanelEntry]
    let footnote: String?
}

final class FacetsPanelView: NSView {
    static let preferredWidth: CGFloat = 232

    var selectionHandler: ((_ column: Int, _ kind: FacetPanelEntry.Kind) -> Void)?

    private let titleLabel = NSTextField(labelWithString: L.t("Facets", "패싯"))
    private let noteLabel = NSTextField(wrappingLabelWithString: "")
    private let messageLabel = NSTextField(wrappingLabelWithString: "")
    private let sectionsStack = NSStackView()
    private let scrollView = NSScrollView()
    private(set) var renderedSections: [FacetPanelSection] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        buildLayout()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func buildLayout() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(separator)

        titleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        titleLabel.textColor = .secondaryLabelColor
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        noteLabel.font = .systemFont(ofSize: 10)
        noteLabel.textColor = .tertiaryLabelColor
        noteLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(noteLabel)

        messageLabel.font = .systemFont(ofSize: 11)
        messageLabel.textColor = .secondaryLabelColor
        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(messageLabel)

        sectionsStack.orientation = .vertical
        sectionsStack.alignment = .leading
        sectionsStack.spacing = 12
        sectionsStack.edgeInsets = NSEdgeInsets(top: 4, left: 0, bottom: 8, right: 0)

        let clipContent = FlippedStackContainer(stack: sectionsStack)
        clipContent.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = clipContent
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)

        NSLayoutConstraint.activate([
            clipContent.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            clipContent.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            clipContent.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor)
        ])

        NSLayoutConstraint.activate([
            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.topAnchor.constraint(equalTo: topAnchor),
            separator.bottomAnchor.constraint(equalTo: bottomAnchor),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12),
            noteLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            noteLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            noteLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            messageLabel.topAnchor.constraint(equalTo: noteLabel.bottomAnchor, constant: 10),
            messageLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            messageLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            scrollView.topAnchor.constraint(equalTo: noteLabel.bottomAnchor, constant: 6),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    func render(sections: [FacetPanelSection], note: String?) {
        renderedSections = sections
        noteLabel.stringValue = note ?? ""
        noteLabel.isHidden = note == nil
        messageLabel.stringValue = ""
        messageLabel.isHidden = true
        rebuildSections()
    }

    func renderMessage(_ text: String) {
        renderedSections = []
        noteLabel.stringValue = ""
        noteLabel.isHidden = true
        messageLabel.stringValue = text
        messageLabel.isHidden = false
        rebuildSections()
    }

    private func rebuildSections() {
        sectionsStack.arrangedSubviews.forEach { view in
            sectionsStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        for section in renderedSections {
            let sectionView = makeSectionView(section)
            sectionsStack.addArrangedSubview(sectionView)
            sectionView.widthAnchor.constraint(equalTo: sectionsStack.widthAnchor).isActive = true
        }
        sectionsStack.layoutSubtreeIfNeeded()
    }

    private func makeSectionView(_ section: FacetPanelSection) -> NSView {
        let container = NSStackView()
        container.orientation = .vertical
        container.alignment = .leading
        container.spacing = 3

        let header = NSTextField(labelWithString: section.title)
        header.font = .systemFont(ofSize: 11, weight: .semibold)
        header.textColor = .labelColor
        header.lineBreakMode = .byTruncatingTail
        container.addArrangedSubview(header)

        for entry in section.entries {
            let row = FacetBarRowView(entry: entry)
            row.clickHandler = { [weak self] in
                self?.selectionHandler?(section.column, entry.kind)
            }
            row.translatesAutoresizingMaskIntoConstraints = false
            row.heightAnchor.constraint(equalToConstant: 20).isActive = true
            container.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: container.widthAnchor).isActive = true
        }

        if let footnote = section.footnote {
            let label = NSTextField(labelWithString: footnote)
            label.font = .systemFont(ofSize: 9)
            label.textColor = .tertiaryLabelColor
            label.lineBreakMode = .byTruncatingTail
            container.addArrangedSubview(label)
        }
        return container
    }
}

/// NSScrollView document views grow downward; a flipped container keeps the
/// first facet section pinned to the top.
private final class FlippedStackContainer: NSView {
    override var isFlipped: Bool { true }

    init(stack: NSStackView) {
        super.init(frame: .zero)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

final class FacetBarRowView: NSControl {
    let entry: FacetPanelEntry
    var clickHandler: (() -> Void)?

    private let valueLabel = NSTextField(labelWithString: "")
    private let countLabel = NSTextField(labelWithString: "")

    init(entry: FacetPanelEntry) {
        self.entry = entry
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 4
        toolTip = "\(entry.label) (\(entry.count.formatted()))"

        valueLabel.stringValue = entry.label
        valueLabel.font = .systemFont(ofSize: 11, weight: entry.isActive ? .semibold : .regular)
        valueLabel.textColor = .labelColor
        valueLabel.lineBreakMode = .byTruncatingTail
        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(valueLabel)

        countLabel.stringValue = entry.count.formatted()
        countLabel.font = .monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        countLabel.textColor = .secondaryLabelColor
        countLabel.alignment = .right
        countLabel.translatesAutoresizingMaskIntoConstraints = false
        countLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        addSubview(countLabel)

        NSLayoutConstraint.activate([
            valueLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            valueLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            countLabel.leadingAnchor.constraint(greaterThanOrEqualTo: valueLabel.trailingAnchor, constant: 4),
            countLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            countLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        setAccessibilityRole(.button)
        setAccessibilityLabel("\(entry.label), \(entry.count)")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let fraction = entry.maxCount > 0 ? CGFloat(entry.count) / CGFloat(entry.maxCount) : 0
        let barWidth = max(2, bounds.width * fraction)
        let barRect = NSRect(x: 0, y: 0, width: barWidth, height: bounds.height)
        let color = entry.isActive
            ? NSColor.controlAccentColor.withAlphaComponent(0.42)
            : NSColor.controlAccentColor.withAlphaComponent(0.16)
        color.setFill()
        NSBezierPath(roundedRect: barRect, xRadius: 4, yRadius: 4).fill()
        if entry.isActive {
            NSColor.controlAccentColor.withAlphaComponent(0.9).setStroke()
            let outline = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 4, yRadius: 4)
            outline.lineWidth = 1
            outline.stroke()
        }
    }

    override func mouseDown(with event: NSEvent) {
        clickHandler?()
    }
}
