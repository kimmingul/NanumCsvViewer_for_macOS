import AppKit

@MainActor
final class PivotDropZoneView: NSView {
    private let zone: PivotDropZone
    private let onDrop: (Int, PivotDropZone) -> Void
    private let titleLabel = NSTextField(labelWithString: "")
    private let stack = NSStackView()
    private var names: [String] = []

    init(zone: PivotDropZone, onDrop: @escaping (Int, PivotDropZone) -> Void) {
        self.zone = zone
        self.onDrop = onDrop
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
        self.names = names
        stack.arrangedSubviews.forEach { view in
            stack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        if names.isEmpty {
            let empty = NSTextField(labelWithString: L.t("Drop fields here", "여기에 필드 놓기"))
            empty.font = .systemFont(ofSize: 12)
            empty.textColor = .secondaryLabelColor
            empty.lineBreakMode = .byTruncatingTail
            stack.addArrangedSubview(empty)
            return
        }

        for name in names {
            let label = NSTextField(labelWithString: name)
            label.font = .systemFont(ofSize: 12)
            label.lineBreakMode = .byTruncatingTail
            stack.addArrangedSubview(label)
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
}
