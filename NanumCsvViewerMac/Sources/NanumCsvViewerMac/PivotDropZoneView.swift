import AppKit

@MainActor
final class PivotDropZoneView: NSView {
    private let zone: PivotDropZone
    private let onDrop: (Int, PivotDropZone) -> Void
    private let onRemove: (Int, PivotDropZone) -> Void
    private let titleLabel = NSTextField(labelWithString: "")
    private let stack = NSStackView()
    private var names: [String] = []

    init(
        zone: PivotDropZone,
        onDrop: @escaping (Int, PivotDropZone) -> Void,
        onRemove: @escaping (Int, PivotDropZone) -> Void = { _, _ in }
    ) {
        self.zone = zone
        self.onDrop = onDrop
        self.onRemove = onRemove
        super.init(frame: .zero)
        configure()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var fieldNamesForTesting: [String] {
        names
    }

    func setFieldNames(_ names: [String]) {
        setFieldItems(names.enumerated().map { (index: $0.offset, name: $0.element, removable: false) })
    }

    func setFields(_ fields: [PivotField]) {
        setFieldItems(fields.map { (index: $0.index, name: $0.name, removable: true) })
    }

    func setFieldItems(_ items: [(index: Int, name: String, removable: Bool)]) {
        names = items.map(\.name)
        stack.arrangedSubviews.forEach { view in
            stack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        if items.isEmpty {
            let empty = NSTextField(labelWithString: L.t("Drop fields here", "여기에 필드 놓기"))
            empty.font = .systemFont(ofSize: 12)
            empty.textColor = .secondaryLabelColor
            empty.lineBreakMode = .byTruncatingTail
            stack.addArrangedSubview(empty)
            return
        }

        for item in items {
            let row = NSStackView()
            row.orientation = .horizontal
            row.alignment = .centerY
            row.spacing = 4

            let label = NSTextField(labelWithString: item.name)
            label.font = .systemFont(ofSize: 12)
            label.lineBreakMode = .byTruncatingTail
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            row.addArrangedSubview(label)

            if item.removable {
                let button = NSButton()
                button.title = ""
                button.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: L.t("Remove field", "필드 제거"))
                button.imageScaling = .scaleProportionallyDown
                button.bezelStyle = .inline
                button.isBordered = false
                button.tag = item.index
                button.target = self
                button.action = #selector(removeField(_:))
                button.toolTip = L.t("Remove field", "필드 제거")
                button.widthAnchor.constraint(equalToConstant: 18).isActive = true
                button.heightAnchor.constraint(equalToConstant: 18).isActive = true
                row.addArrangedSubview(button)
            }

            stack.addArrangedSubview(row)
        }
    }

    private func configure() {
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor
        registerForDraggedTypes([.pivotFieldIndex])

        titleLabel.stringValue = zone.title
        titleLabel.font = .systemFont(ofSize: 12, weight: .semibold)

        stack.orientation = .vertical
        stack.spacing = 4

        let root = NSStackView(views: [titleLabel, stack])
        root.orientation = .vertical
        root.spacing = 6
        root.edgeInsets = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        root.translatesAutoresizingMaskIntoConstraints = false
        addSubview(root)

        setFieldNames([])

        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: leadingAnchor),
            root.trailingAnchor.constraint(equalTo: trailingAnchor),
            root.topAnchor.constraint(equalTo: topAnchor),
            root.bottomAnchor.constraint(equalTo: bottomAnchor),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 92)
        ])
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        sender.draggingPasteboard.string(forType: .pivotFieldIndex) == nil ? [] : .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let raw = sender.draggingPasteboard.string(forType: .pivotFieldIndex),
              let index = Int(raw) else { return false }
        onDrop(index, zone)
        return true
    }

    @objc private func removeField(_ sender: NSButton) {
        onRemove(sender.tag, zone)
    }
}
