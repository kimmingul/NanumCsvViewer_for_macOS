import AppKit

final class FilterBarView: NSVisualEffectView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        material = .headerView
        blendingMode = .withinWindow
        state = .active
        wantsLayer = true
        updateLayerColors()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        material = .headerView
        blendingMode = .withinWindow
        state = .active
        wantsLayer = true
        updateLayerColors()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateLayerColors()
    }

    private func updateLayerColors() {
        layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.72).cgColor
        layer?.borderWidth = 0
        layer?.borderColor = nil
    }
}
