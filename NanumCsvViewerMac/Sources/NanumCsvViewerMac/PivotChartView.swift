import AppKit
import Charts
import SwiftUI

@MainActor
final class PivotChartView: NSView {
    private var model: PivotChartModel?
    private let hostingView: NSHostingView<PivotChartContentView>

    override init(frame frameRect: NSRect) {
        hostingView = NSHostingView(rootView: PivotChartContentView(model: nil))
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var modelForTesting: PivotChartModel? {
        model
    }

    var usesSwiftChartsSurfaceForTesting: Bool {
        subviews.contains(hostingView)
    }

    func update(model: PivotChartModel?) {
        self.model = model
        hostingView.rootView = PivotChartContentView(model: model)
    }
}

private struct PivotChartContentView: View {
    let model: PivotChartModel?
    @State private var selectedKind: PivotChartKind?
    @State private var selectedCategory: String?

    var body: some View {
        Group {
            if let model {
                if let reason = model.unsupportedReason {
                    emptyState(reason)
                } else if model.points.isEmpty {
                    emptyState(L.t("No pivot data to chart.", "차트로 표시할 피벗 데이터가 없습니다."))
                } else {
                    chartContent(model)
                }
            } else {
                emptyState(L.t(
                    "Drag a field into Values to preview a chart.",
                    "값에 필드를 끌어 놓으면 차트를 미리 볼 수 있습니다."
                ))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func chartContent(_ model: PivotChartModel) -> some View {
        let kind = selectedKind ?? model.recommendedKind
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Picker("", selection: chartKindBinding(defaultKind: model.recommendedKind)) {
                    ForEach(PivotChartKind.allCases, id: \.self) { item in
                        Text(item.title).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 320)

                Spacer(minLength: 12)
            }

            chart(model, kind: kind)
        }
        .padding(10)
    }

    private func chart(_ model: PivotChartModel, kind: PivotChartKind) -> some View {
        Chart(model.points) { point in
            switch kind {
            case .bar:
                BarMark(
                    x: .value(model.xAxisTitle, point.category),
                    y: .value(model.valueTitle, point.value)
                )
                .foregroundStyle(by: .value(model.seriesTitle, point.series))
            case .groupedBar:
                BarMark(
                    x: .value(model.xAxisTitle, point.category),
                    y: .value(model.valueTitle, point.value)
                )
                .foregroundStyle(by: .value(model.seriesTitle, point.series))
                .position(by: .value(model.seriesTitle, point.series))
            case .stackedBar:
                BarMark(
                    x: .value(model.xAxisTitle, point.category),
                    y: .value(model.valueTitle, point.value)
                )
                .foregroundStyle(by: .value(model.seriesTitle, point.series))
            case .line:
                LineMark(
                    x: .value(model.xAxisTitle, point.category),
                    y: .value(model.valueTitle, point.value)
                )
                .foregroundStyle(by: .value(model.seriesTitle, point.series))
                .interpolationMethod(.catmullRom)
                PointMark(
                    x: .value(model.xAxisTitle, point.category),
                    y: .value(model.valueTitle, point.value)
                )
                .foregroundStyle(by: .value(model.seriesTitle, point.series))
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 6)) {
                AxisGridLine()
                AxisTick()
                AxisValueLabel()
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading)
        }
        .chartLegend(model.series.count > 1 ? .visible : .hidden)
        .chartXSelection(value: $selectedCategory)
        .chartOverlay { proxy in
            GeometryReader { geometry in
                if let selectedCategory,
                   let selectedX = proxy.position(forX: selectedCategory),
                   let plotAnchor = proxy.plotFrame {
                    let plotFrame = geometry[plotAnchor]
                    let selectedPoints = model.points.filter { $0.category == selectedCategory }
                    if !selectedPoints.isEmpty {
                        let tooltipValue = selectedPoints.map(\.value).max() ?? 0
                        let selectedY = proxy.position(forY: tooltipValue) ?? 0
                        PivotChartTooltip(category: selectedCategory, points: selectedPoints)
                            .allowsHitTesting(false)
                            .position(
                                x: tooltipXPosition(
                                    plotX: plotFrame.minX + selectedX,
                                    plotFrame: plotFrame
                                ),
                                y: tooltipYPosition(
                                    plotY: plotFrame.minY + selectedY,
                                    plotFrame: plotFrame
                                )
                            )
                    }
                }
            }
        }
        .frame(minHeight: 190)
    }

    private func tooltipXPosition(plotX: CGFloat, plotFrame: CGRect) -> CGFloat {
        let horizontalInset: CGFloat = 92
        return min(max(plotX, plotFrame.minX + horizontalInset), plotFrame.maxX - horizontalInset)
    }

    private func tooltipYPosition(plotY: CGFloat, plotFrame: CGRect) -> CGFloat {
        let verticalInset: CGFloat = 42
        return min(max(plotY - 44, plotFrame.minY + verticalInset), plotFrame.maxY - verticalInset)
    }

    private func chartKindBinding(defaultKind: PivotChartKind) -> Binding<PivotChartKind> {
        Binding(
            get: { selectedKind ?? defaultKind },
            set: { selectedKind = $0 }
        )
    }

    private func emptyState(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding()
    }
}

private struct PivotChartTooltip: View {
    let category: String
    let points: [PivotChartPoint]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(category)
                .font(.caption.weight(.semibold))
            ForEach(points) { point in
                HStack(spacing: 6) {
                    Text(point.series)
                    Spacer(minLength: 8)
                    Text(format(point.value))
                        .monospacedDigit()
                }
            }
        }
        .font(.caption)
        .foregroundStyle(.primary)
        .padding(8)
        .frame(minWidth: 140)
        .fixedSize(horizontal: true, vertical: true)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
        )
    }

    private func format(_ value: Double) -> String {
        if value.rounded(.towardZero) == value {
            return String(format: "%.0f", value)
        }
        return String(format: "%.3f", value)
    }
}
