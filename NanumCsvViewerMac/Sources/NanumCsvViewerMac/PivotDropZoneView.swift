import AppKit

@MainActor
final class PivotDropZoneView: NSView {
    private let zone: PivotDropZone
    private let onDrop: (PivotFieldDragPayload, PivotDropZone, Int) -> Void
    private let onRemove: (Int, PivotDropZone) -> Void
    private let titleLabel = NSTextField(labelWithString: "")
    private let stack = NSStackView()
    private var names: [String] = []
    private var itemViews: [PivotDropZoneItemView] = []

    init(
        zone: PivotDropZone,
        onDrop: @escaping (Int, PivotDropZone) -> Void,
        onRemove: @escaping (Int, PivotDropZone) -> Void = { _, _ in }
    ) {
        self.zone = zone
        self.onDrop = { payload, zone, _ in onDrop(payload.fieldIndex, zone) }
        self.onRemove = onRemove
        super.init(frame: .zero)
        configure()
    }

    init(
        zone: PivotDropZone,
        onFieldDrop: @escaping (PivotFieldDragPayload, PivotDropZone, Int) -> Void,
        onRemove: @escaping (Int, PivotDropZone) -> Void = { _, _ in }
    ) {
        self.zone = zone
        self.onDrop = onFieldDrop
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
        itemViews = []

        if items.isEmpty {
            let empty = NSTextField(labelWithString: L.t("Drop fields here", "여기에 필드 놓기"))
            empty.font = .systemFont(ofSize: 12)
            empty.textColor = .secondaryLabelColor
            empty.lineBreakMode = .byTruncatingTail
            stack.addArrangedSubview(empty)
            return
        }

        for (position, item) in items.enumerated() {
            let row = PivotDropZoneItemView(fieldIndex: item.index, zone: zone, position: position)

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
            itemViews.append(row)
        }
    }

    private func configure() {
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor
        registerForDraggedTypes([.pivotFieldPayload, .pivotFieldIndex])

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
        guard let payload = PivotFieldDragPayload.read(from: sender.draggingPasteboard) else { return [] }
        layer?.borderColor = NSColor.controlAccentColor.cgColor
        return dragOperation(for: payload)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard let payload = PivotFieldDragPayload.read(from: sender.draggingPasteboard) else { return [] }
        return dragOperation(for: payload)
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        layer?.borderColor = NSColor.separatorColor.cgColor
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        layer?.borderColor = NSColor.separatorColor.cgColor
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let payload = PivotFieldDragPayload.read(from: sender.draggingPasteboard) else { return false }
        layer?.borderColor = NSColor.separatorColor.cgColor
        onDrop(payload, zone, insertionIndex(for: sender))
        return true
    }

    @objc private func removeField(_ sender: NSButton) {
        onRemove(sender.tag, zone)
    }

    private func insertionIndex(for sender: NSDraggingInfo) -> Int {
        guard !itemViews.isEmpty else { return 0 }
        let point = convert(sender.draggingLocation, from: nil)
        for (index, itemView) in itemViews.enumerated() {
            let itemFrame = itemView.convert(itemView.bounds, to: self)
            if point.y > itemFrame.midY {
                return index
            }
        }
        return itemViews.count
    }

    private func dragOperation(for payload: PivotFieldDragPayload) -> NSDragOperation {
        payload.sourceZone == nil ? .copy : .move
    }
}

@MainActor
private final class PivotDropZoneItemView: NSStackView, NSDraggingSource {
    private let fieldIndex: Int
    private let zone: PivotDropZone
    private let position: Int
    private var dragStartEvent: NSEvent?

    init(fieldIndex: Int, zone: PivotDropZone, position: Int) {
        self.fieldIndex = fieldIndex
        self.zone = zone
        self.position = position
        super.init(frame: .zero)
        orientation = .horizontal
        alignment = .centerY
        spacing = 4
        toolTip = L.t("Drag to move field", "드래그해서 필드 이동")
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func mouseDown(with event: NSEvent) {
        dragStartEvent = event
    }

    override func mouseDragged(with event: NSEvent) {
        guard let dragStartEvent else { return }
        self.dragStartEvent = nil
        let item = PivotFieldDragPayload.pasteboardItem(
            fieldIndex: fieldIndex,
            sourceZone: zone,
            sourcePosition: position
        )
        let draggingItem = NSDraggingItem(pasteboardWriter: item)
        draggingItem.setDraggingFrame(bounds, contents: nil)
        beginDraggingSession(with: [draggingItem], event: dragStartEvent, source: self)
    }

    override func mouseUp(with event: NSEvent) {
        dragStartEvent = nil
    }

    nonisolated func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        .move
    }
}
