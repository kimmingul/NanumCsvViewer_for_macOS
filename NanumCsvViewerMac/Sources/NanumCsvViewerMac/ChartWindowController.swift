import AppKit
import Charts
import CsvCore
import SwiftUI

enum ChartKind: String, CaseIterable, Sendable {
    case histogram
    case boxplot
    case scatter
    case correlationHeatmap
    case qqPlot
    case timeseries
    case pareto

    var title: String {
        switch self {
        case .histogram:
            return L.t("Histogram + KDE", "히스토그램 + KDE")
        case .boxplot:
            return L.t("Boxplot + ANOVA", "상자그림 + ANOVA")
        case .scatter:
            return L.t("Scatter + Regression", "산점도 + 회귀")
        case .correlationHeatmap:
            return L.t("Correlation Heatmap", "상관 히트맵")
        case .qqPlot:
            return L.t("Q-Q Plot", "Q-Q 플롯")
        case .timeseries:
            return L.t("Time Series", "시계열")
        case .pareto:
            return L.t("Pareto Chart", "파레토 차트")
        }
    }
}

enum ChartRequest: Equatable, Sendable {
    case histogram(column: Int, binCount: Int)
    case boxplot(groupColumn: Int?, valueColumn: Int)
    case scatter(xColumn: Int, yColumn: Int)
    case correlationHeatmap(columns: [Int])
    case qqPlot(column: Int)
    case timeseries(dateColumn: Int, valueColumn: Int?, period: DateBinPeriod)
    case pareto(column: Int)

    var kind: ChartKind {
        switch self {
        case .histogram: return .histogram
        case .boxplot: return .boxplot
        case .scatter: return .scatter
        case .correlationHeatmap: return .correlationHeatmap
        case .qqPlot: return .qqPlot
        case .timeseries: return .timeseries
        case .pareto: return .pareto
        }
    }
}

enum ChartRenderModel: Equatable, Sendable {
    case histogram(HistogramChartData, columnName: String)
    case boxplot(BoxplotChartData, groupName: String?, valueName: String)
    case scatter(ScatterChartData, xName: String, yName: String)
    case correlationHeatmap(CorrelationMatrixChartData, names: [String])
    case qqPlot([QQPoint], columnName: String)
    case timeseries(DateHistogram, dateName: String, valueName: String?)
    case pareto(ParetoChartData, columnName: String)
}

struct ChartWindowModel: Equatable, Sendable {
    let kind: ChartKind
    let documentName: String
    let render: ChartRenderModel
    let scopeNote: String?
}

@MainActor
final class ChartWindowController: NSWindowController, NSWindowDelegate {
    let model: ChartWindowModel
    var onClose: ((ChartWindowController) -> Void)?

    init(model: ChartWindowModel) {
        self.model = model
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 520),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "\(model.kind.title) — \(model.documentName)"
        window.minSize = NSSize(width: 480, height: 340)
        super.init(window: window)
        window.delegate = self
        window.contentView = NSHostingView(rootView: StatChartContentView(model: model))
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    nonisolated func windowWillClose(_ notification: Notification) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.onClose?(self)
        }
    }
}

struct StatChartContentView: View {
    let model: ChartWindowModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            chartBody
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(12)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(headline)
                .font(.system(size: 13, weight: .semibold))
            if let badge = badgeText {
                Text(badge)
                    .font(.system(size: 11).monospacedDigit())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color(nsColor: .controlBackgroundColor), in: Capsule())
                    .overlay(Capsule().stroke(Color(nsColor: .separatorColor), lineWidth: 0.5))
            }
            Spacer()
            if let scopeNote = model.scopeNote {
                Text(scopeNote)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var headline: String {
        switch model.render {
        case .histogram(_, let columnName):
            return "\(model.kind.title) — \(columnName)"
        case .boxplot(_, let groupName, let valueName):
            if let groupName {
                return "\(model.kind.title) — \(valueName) \(L.t("by", "×")) \(groupName)"
            }
            return "\(model.kind.title) — \(valueName)"
        case .scatter(_, let xName, let yName):
            return "\(model.kind.title) — \(xName) × \(yName)"
        case .correlationHeatmap(_, let names):
            return "\(model.kind.title) — \(names.count) \(L.t("columns", "개 컬럼"))"
        case .qqPlot(_, let columnName):
            return "\(model.kind.title) — \(columnName)"
        case .timeseries(let histogram, let dateName, let valueName):
            let value = valueName.map { " × \($0)" } ?? ""
            return "\(model.kind.title) — \(dateName)\(value) (\(histogram.period.rawValue))"
        case .pareto(_, let columnName):
            return "\(model.kind.title) — \(columnName)"
        }
    }

    private var badgeText: String? {
        switch model.render {
        case .histogram(let data, _):
            guard let normality = data.normality else { return nil }
            let verdict = normality.pValue >= 0.05
                ? L.t("normal ✓", "정규성 ✓")
                : L.t("non-normal ✗", "비정규 ✗")
            return "Shapiro-Wilk W=\(Self.compact(normality.wStatistic)) p=\(Self.compact(normality.pValue)) \(verdict)"
        case .boxplot(let data, _, _):
            guard let anova = data.anova else { return nil }
            return "ANOVA F=\(Self.compact(anova.fStatistic)) p=\(Self.compact(anova.pValue))"
        case .scatter(let data, _, _):
            guard let fit = data.regression else { return nil }
            return "y = \(Self.compact(fit.slope))x + \(Self.compact(fit.intercept)) · R²=\(Self.compact(fit.rSquared))"
        case .qqPlot, .correlationHeatmap, .timeseries:
            return nil
        case .pareto(let data, _):
            return L.t("n=\(data.totalCount.formatted())", "n=\(data.totalCount.formatted())")
        }
    }

    @ViewBuilder
    private var chartBody: some View {
        switch model.render {
        case .histogram(let data, let columnName):
            histogramChart(data, columnName: columnName)
        case .boxplot(let data, _, let valueName):
            boxplotChart(data, valueName: valueName)
        case .scatter(let data, let xName, let yName):
            scatterChart(data, xName: xName, yName: yName)
        case .correlationHeatmap(let data, let names):
            heatmapChart(data, names: names)
        case .qqPlot(let points, _):
            qqChart(points)
        case .timeseries(let histogram, _, let valueName):
            timeseriesChart(histogram, valueName: valueName)
        case .pareto(let data, _):
            paretoChart(data)
        }
    }

    private func histogramChart(_ data: HistogramChartData, columnName: String) -> some View {
        let bins = data.distribution.bins
        let binWidth = bins.first.map { $0.upperBound - $0.lowerBound } ?? 1
        let densityScale = Double(data.distribution.count) * max(binWidth, .ulpOfOne)
        return Chart {
            ForEach(Array(bins.enumerated()), id: \.offset) { _, bin in
                RectangleMark(
                    xStart: .value(columnName, bin.lowerBound),
                    xEnd: .value(columnName, bin.upperBound),
                    yStart: .value(L.t("Count", "빈도"), 0),
                    yEnd: .value(L.t("Count", "빈도"), bin.count)
                )
                .foregroundStyle(Color.accentColor.opacity(0.55))
            }
            ForEach(Array(data.density.enumerated()), id: \.offset) { _, point in
                LineMark(
                    x: .value(columnName, point.x),
                    y: .value("KDE", point.density * densityScale)
                )
                .foregroundStyle(.orange)
                .lineStyle(StrokeStyle(lineWidth: 2))
            }
        }
        .chartYAxisLabel(L.t("Count", "빈도"))
    }

    private func boxplotChart(_ data: BoxplotChartData, valueName: String) -> some View {
        // A zero-height bar is invisible, so the median tick needs a small
        // thickness derived from the overall value span.
        let lows = data.groups.map { Swift.min($0.summary.whiskerLow, $0.summary.outliers.min() ?? $0.summary.whiskerLow) }
        let highs = data.groups.map { Swift.max($0.summary.whiskerHigh, $0.summary.outliers.max() ?? $0.summary.whiskerHigh) }
        let span = (highs.max() ?? 1) - (lows.min() ?? 0)
        let medianHalfThickness = Swift.max(span, .ulpOfOne) * 0.004
        return Chart {
            ForEach(Array(data.groups.enumerated()), id: \.offset) { _, group in
                RuleMark(
                    x: .value(L.t("Group", "그룹"), group.label),
                    yStart: .value(valueName, group.summary.whiskerLow),
                    yEnd: .value(valueName, group.summary.whiskerHigh)
                )
                .foregroundStyle(Color.secondary)
                .lineStyle(StrokeStyle(lineWidth: 1))

                BarMark(
                    x: .value(L.t("Group", "그룹"), group.label),
                    yStart: .value(valueName, group.summary.quartile1),
                    yEnd: .value(valueName, group.summary.quartile3),
                    width: .ratio(0.55)
                )
                .foregroundStyle(Color.accentColor.opacity(0.45))

                BarMark(
                    x: .value(L.t("Group", "그룹"), group.label),
                    yStart: .value(valueName, group.summary.median - medianHalfThickness),
                    yEnd: .value(valueName, group.summary.median + medianHalfThickness),
                    width: .ratio(0.55)
                )
                .foregroundStyle(Color.primary)

                ForEach(Array(group.summary.outliers.enumerated()), id: \.offset) { _, outlier in
                    PointMark(
                        x: .value(L.t("Group", "그룹"), group.label),
                        y: .value(valueName, outlier)
                    )
                    .symbolSize(18)
                    .foregroundStyle(Color.red.opacity(0.7))
                }
            }
        }
        .chartYAxisLabel(valueName)
    }

    private func scatterChart(_ data: ScatterChartData, xName: String, yName: String) -> some View {
        Chart {
            if let grid = data.densityGrid {
                let xStep = (grid.xRange.upperBound - grid.xRange.lowerBound) / Double(grid.columns)
                let yStep = (grid.yRange.upperBound - grid.yRange.lowerBound) / Double(grid.rows)
                ForEach(0..<grid.rows, id: \.self) { row in
                    ForEach(0..<grid.columns, id: \.self) { column in
                        let count = grid.count(atColumn: column, row: row)
                        if count > 0 {
                            RectangleMark(
                                xStart: .value(xName, grid.xRange.lowerBound + Double(column) * xStep),
                                xEnd: .value(xName, grid.xRange.lowerBound + Double(column + 1) * xStep),
                                yStart: .value(yName, grid.yRange.lowerBound + Double(row) * yStep),
                                yEnd: .value(yName, grid.yRange.lowerBound + Double(row + 1) * yStep)
                            )
                            .foregroundStyle(Color.accentColor.opacity(0.15 + 0.85 * Double(count) / Double(max(grid.maxCount, 1))))
                        }
                    }
                }
            } else {
                ForEach(Array(data.points.enumerated()), id: \.offset) { _, point in
                    PointMark(
                        x: .value(xName, point.x),
                        y: .value(yName, point.y)
                    )
                    .symbolSize(14)
                    .foregroundStyle(Color.accentColor.opacity(0.55))
                }
            }
            if let fit = data.regression, let domain = regressionDomain(data) {
                LineMark(
                    x: .value(xName, domain.lowerBound),
                    y: .value(yName, fit.intercept + fit.slope * domain.lowerBound),
                    series: .value("fit", "fit")
                )
                .foregroundStyle(.orange)
                LineMark(
                    x: .value(xName, domain.upperBound),
                    y: .value(yName, fit.intercept + fit.slope * domain.upperBound),
                    series: .value("fit", "fit")
                )
                .foregroundStyle(.orange)
            }
        }
        .chartXAxisLabel(xName)
        .chartYAxisLabel(yName)
    }

    private func regressionDomain(_ data: ScatterChartData) -> ClosedRange<Double>? {
        if let grid = data.densityGrid {
            return grid.xRange
        }
        guard let minX = data.points.map(\.x).min(), let maxX = data.points.map(\.x).max(), minX < maxX else {
            return nil
        }
        return minX...maxX
    }

    private func heatmapChart(_ data: CorrelationMatrixChartData, names: [String]) -> some View {
        Chart {
            ForEach(0..<data.columns.count, id: \.self) { row in
                ForEach(0..<data.columns.count, id: \.self) { column in
                    if let value = data.value(row: row, column: column) {
                        RectangleMark(
                            x: .value("x", names[safe: column] ?? "\(column)"),
                            y: .value("y", names[safe: row] ?? "\(row)")
                        )
                        .foregroundStyle(Self.correlationColor(value))
                        .annotation(position: .overlay) {
                            // Cells fade to white near r=0, so the label must
                            // stay dark regardless of the app appearance.
                            Text(String(format: "%.2f", value))
                                .font(.system(size: 9).monospacedDigit())
                                .foregroundStyle(abs(value) > 0.6 ? Color.white : Color.black)
                        }
                    }
                }
            }
        }
        .chartLegend(.hidden)
    }

    private func qqChart(_ points: [QQPoint]) -> some View {
        let line = Self.qqReferenceLine(points)
        return Chart {
            ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                PointMark(
                    x: .value(L.t("Theoretical quantile", "이론 분위수"), point.theoretical),
                    y: .value(L.t("Sample quantile", "표본 분위수"), point.sample)
                )
                .symbolSize(14)
                .foregroundStyle(Color.accentColor.opacity(0.6))
            }
            if let line, let first = points.first, let last = points.last {
                LineMark(
                    x: .value("t", first.theoretical),
                    y: .value("s", line.intercept + line.slope * first.theoretical),
                    series: .value("ref", "ref")
                )
                .foregroundStyle(.orange)
                LineMark(
                    x: .value("t", last.theoretical),
                    y: .value("s", line.intercept + line.slope * last.theoretical),
                    series: .value("ref", "ref")
                )
                .foregroundStyle(.orange)
            }
        }
        .chartXAxisLabel(L.t("Theoretical quantile", "이론 분위수"))
        .chartYAxisLabel(L.t("Sample quantile", "표본 분위수"))
    }

    private func timeseriesChart(_ histogram: DateHistogram, valueName: String?) -> some View {
        let usesValue = histogram.valueColumn != nil
        let yTitle = usesValue
            ? (valueName ?? L.t("Sum", "합계"))
            : L.t("Count", "빈도")
        return Chart {
            ForEach(Array(histogram.bins.enumerated()), id: \.offset) { _, bin in
                LineMark(
                    x: .value(L.t("Period", "기간"), bin.label),
                    y: .value(yTitle, usesValue ? (bin.sum ?? 0) : Double(bin.count))
                )
                PointMark(
                    x: .value(L.t("Period", "기간"), bin.label),
                    y: .value(yTitle, usesValue ? (bin.sum ?? 0) : Double(bin.count))
                )
                .symbolSize(16)
            }
        }
        .chartYAxisLabel(yTitle)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 8)) {
                AxisGridLine()
                AxisTick()
                AxisValueLabel()
            }
        }
    }

    private func paretoChart(_ data: ParetoChartData) -> some View {
        let maxCount = Double(data.entries.map(\.count).max() ?? 1)
        return Chart {
            ForEach(Array(data.entries.enumerated()), id: \.offset) { _, entry in
                BarMark(
                    x: .value(L.t("Category", "범주"), entry.label),
                    y: .value(L.t("Count", "빈도"), entry.count)
                )
                .foregroundStyle(Color.accentColor.opacity(0.55))
            }
            ForEach(Array(data.entries.enumerated()), id: \.offset) { _, entry in
                LineMark(
                    x: .value(L.t("Category", "범주"), entry.label),
                    y: .value("cum", entry.cumulativePercent / 100 * maxCount)
                )
                .foregroundStyle(.orange)
                PointMark(
                    x: .value(L.t("Category", "범주"), entry.label),
                    y: .value("cum", entry.cumulativePercent / 100 * maxCount)
                )
                .foregroundStyle(.orange)
                .annotation(position: .top) {
                    Text(String(format: "%.0f%%", entry.cumulativePercent))
                        .font(.system(size: 9).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .chartYAxisLabel(L.t("Count (line: cumulative %)", "빈도 (선: 누적 %)"))
    }

    static func correlationColor(_ value: Double) -> Color {
        let clamped = max(-1, min(1, value))
        if clamped >= 0 {
            return Color(red: 1 - 0.75 * clamped, green: 1 - 0.55 * clamped, blue: 1)
        }
        return Color(red: 1, green: 1 + 0.55 * clamped, blue: 1 + 0.75 * clamped)
    }

    static func qqReferenceLine(_ points: [QQPoint]) -> (slope: Double, intercept: Double)? {
        guard points.count >= 4 else { return nil }
        let q1Index = points.count / 4
        let q3Index = points.count * 3 / 4
        let t1 = points[q1Index].theoretical
        let t3 = points[q3Index].theoretical
        let s1 = points[q1Index].sample
        let s3 = points[q3Index].sample
        guard t3 > t1 else { return nil }
        let slope = (s3 - s1) / (t3 - t1)
        return (slope, s1 - slope * t1)
    }

    static func compact(_ value: Double) -> String {
        if !value.isFinite { return "—" }
        if abs(value) >= 1000 || (abs(value) < 0.001 && value != 0) {
            return String(format: "%.2e", value)
        }
        return String(format: "%.3g", value)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        index >= 0 && index < count ? self[index] : nil
    }
}
