import AppKit

@MainActor
final class PivotChartView: NSView {
    private var model: PivotChartModel?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var modelForTesting: PivotChartModel? {
        model
    }

    func update(model: PivotChartModel?) {
        self.model = model
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let model else {
            drawCentered(L.t(
                "Drag a field into Values to preview a chart.",
                "값에 필드를 끌어 놓으면 차트를 미리 볼 수 있습니다."
            ))
            return
        }
        if let reason = model.unsupportedReason {
            drawCentered(reason)
            return
        }
        guard !model.categories.isEmpty, !model.series.isEmpty else {
            drawCentered(L.t("No pivot data to chart.", "차트로 표시할 피벗 데이터가 없습니다."))
            return
        }
        drawBars(model)
    }

    private func drawCentered(_ text: String) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        let size = text.size(withAttributes: attributes)
        text.draw(
            at: NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2),
            withAttributes: attributes
        )
    }

    private func drawBars(_ model: PivotChartModel) {
        let plot = bounds.insetBy(dx: 42, dy: 34)
        guard plot.width > 20, plot.height > 20 else { return }

        NSColor.separatorColor.setStroke()
        NSBezierPath(rect: plot).stroke()

        let maxValue = max(1, model.series.flatMap(\.values).max() ?? 1)
        let categoryWidth = plot.width / CGFloat(max(1, model.categories.count))
        let seriesCount = max(1, model.series.count)
        let palette: [NSColor] = [.systemBlue, .systemGreen, .systemOrange, .systemPurple, .systemRed]

        for categoryIndex in model.categories.indices {
            let groupX = plot.minX + CGFloat(categoryIndex) * categoryWidth
            let barWidth = max(2, (categoryWidth - 10) / CGFloat(seriesCount))
            for seriesIndex in model.series.indices {
                let value = model.series[seriesIndex].values[safe: categoryIndex] ?? 0
                let height = plot.height * CGFloat(value / maxValue)
                let rect = NSRect(
                    x: groupX + 5 + CGFloat(seriesIndex) * barWidth,
                    y: plot.minY,
                    width: max(1, barWidth - 2),
                    height: height
                )
                palette[seriesIndex % palette.count].setFill()
                rect.fill()
            }
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
