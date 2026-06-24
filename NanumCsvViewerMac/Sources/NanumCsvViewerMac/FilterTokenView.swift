import AppKit

final class FilterTokenView: NSView {
    var onEdit: (() -> Void)?
    var onRemove: (() -> Void)?

    private let titleButton = NSButton()
    private let closeButton = NSButton()

    init(title: String, editable: Bool) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 8
        updateBackground()

        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 3
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 8, bottom: 0, right: 4)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        titleButton.title = title
        titleButton.isBordered = false
        titleButton.bezelStyle = .inline
        titleButton.font = .systemFont(ofSize: 11, weight: .regular)
        titleButton.contentTintColor = .secondaryLabelColor
        titleButton.lineBreakMode = .byTruncatingMiddle
        titleButton.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        titleButton.widthAnchor.constraint(lessThanOrEqualToConstant: 180).isActive = true
        if editable {
            titleButton.target = self
            titleButton.action = #selector(editToken)
            titleButton.toolTip = L.t("Edit filter", "필터 편집")
        }

        closeButton.title = ""
        closeButton.isBordered = false
        closeButton.bezelStyle = .inline
        closeButton.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: L.t("Remove filter", "필터 제거"))
        closeButton.imageScaling = .scaleProportionallyDown
        closeButton.contentTintColor = .tertiaryLabelColor
        closeButton.target = self
        closeButton.action = #selector(removeToken)
        closeButton.toolTip = L.t("Remove filter", "필터 제거")
        closeButton.widthAnchor.constraint(equalToConstant: 16).isActive = true
        closeButton.heightAnchor.constraint(equalToConstant: 16).isActive = true

        stack.addArrangedSubview(titleButton)
        stack.addArrangedSubview(closeButton)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            heightAnchor.constraint(equalToConstant: 22)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateBackground()
    }

    private func updateBackground() {
        layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.12).cgColor
    }

    @objc private func editToken() {
        onEdit?()
    }

    @objc private func removeToken() {
        onRemove?()
    }
}
