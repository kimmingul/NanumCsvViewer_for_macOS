import AppKit
@preconcurrency import CsvCore

@MainActor
final class PivotBuilderWindowController: NSWindowController {
    private let csvDocument: VirtualCsvDocument
    private let fields: [PivotField]
    private var layout = PivotBuilderLayout()
    private var pivot: PivotTableResult?
    private var previewRows: [[String]] = []
    private var previewHeaders: [String] = []
    private var previewCancellation: CancellationFlag?
    private var previewGeneration = 0
    private var previewIsComputing = false

    private let rootSplit = NSSplitView()
    private let controlPane = NSView()
    private let resultPane = PivotResultPaneView()
    private let fieldTable = NSTableView()
    private let fieldScroll = NSScrollView()
    private let tablePreview = NSTableView()
    private let tableScroll = NSScrollView()
    private let chartView = PivotChartView()
    private let aggregationPopup = NSPopUpButton()
    private let previewTabs = NSSegmentedControl(labels: [], trackingMode: .selectOne, target: nil, action: nil)
    private let previewContainer = NSView()
    private let emptyPreviewLabel = NSTextField(labelWithString: "")
    private let resultSummaryLabel = NSTextField(labelWithString: "")
    private var zoneViews: [PivotDropZone: PivotDropZoneView] = [:]

    init(document: VirtualCsvDocument, columnNames: [String]) {
        csvDocument = document
        fields = columnNames.enumerated().map { index, name in
            PivotField(index: index, name: name.isEmpty ? "Column \(index + 1)" : name, typeHint: nil)
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1180, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.minSize = NSSize(width: 900, height: 560)
        window.title = L.t("Pivot Builder", "피벗 빌더")
        super.init(window: window)
        buildInterface()
        refreshZones()
        refreshPreview()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func assignField(_ index: Int, to zone: PivotDropZone) {
        guard fields.indices.contains(index) else { return }
        switch zone {
        case .rows:
            appendUnique(index, to: &layout.rows)
        case .columns:
            appendUnique(index, to: &layout.columns)
        case .values:
            layout.value = index
        case .filters:
            appendUnique(index, to: &layout.filters)
        }
        refreshZones()
        refreshPreview()
    }

    func setAggregation(_ function: AggregationFunction) {
        layout.function = function
        aggregationPopup.selectItem(withTitle: function.rawValue)
        refreshZones()
        refreshPreview()
    }

    func removeField(_ index: Int, from zone: PivotDropZone) {
        switch zone {
        case .rows:
            layout.rows.removeAll { $0 == index }
        case .columns:
            layout.columns.removeAll { $0 == index }
        case .values:
            if layout.value == index {
                layout.value = nil
            }
        case .filters:
            layout.filters.removeAll { $0 == index }
        }
        refreshZones()
        refreshPreview()
    }

    private func appendUnique(_ index: Int, to target: inout [Int]) {
        guard !target.contains(index) else { return }
        target.append(index)
    }

    private func buildInterface() {
        guard let contentView = window?.contentView else { return }

        rootSplit.isVertical = true
        rootSplit.dividerStyle = .thin
        rootSplit.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(rootSplit)

        NSLayoutConstraint.activate([
            rootSplit.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            rootSplit.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            rootSplit.topAnchor.constraint(equalTo: contentView.topAnchor),
            rootSplit.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])

        rootSplit.addArrangedSubview(makeConfigurationPane())
        rootSplit.addArrangedSubview(makeResultsPane())
        rootSplit.setPosition(400, ofDividerAt: 0)
    }

    private func makeConfigurationPane() -> NSView {
        controlPane.translatesAutoresizingMaskIntoConstraints = false
        controlPane.widthAnchor.constraint(greaterThanOrEqualToConstant: 340).isActive = true
        controlPane.widthAnchor.constraint(lessThanOrEqualToConstant: 480).isActive = true

        let root = NSStackView()
        root.orientation = .vertical
        root.spacing = 12
        root.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        root.translatesAutoresizingMaskIntoConstraints = false
        controlPane.addSubview(root)

        let aggregationSection = makeAggregationSection()
        root.addArrangedSubview(makeFieldListSection())
        root.addArrangedSubview(makeDropZoneSection())
        root.addArrangedSubview(aggregationSection)
        root.setVisibilityPriority(.mustHold, for: aggregationSection)

        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: controlPane.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: controlPane.trailingAnchor),
            root.topAnchor.constraint(equalTo: controlPane.topAnchor),
            root.bottomAnchor.constraint(equalTo: controlPane.bottomAnchor)
        ])

        return controlPane
    }

    private func makeFieldListSection() -> NSView {
        let section = NSStackView()
        section.orientation = .vertical
        section.spacing = 8
        section.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: L.t("Fields", "필드"))
        title.font = .systemFont(ofSize: 13, weight: .semibold)

        fieldTable.headerView = nil
        fieldTable.delegate = self
        fieldTable.dataSource = self
        fieldTable.allowsMultipleSelection = false
        fieldTable.usesAlternatingRowBackgroundColors = false
        fieldTable.rowHeight = 28
        fieldTable.registerForDraggedTypes([.pivotFieldIndex])
        fieldTable.setDraggingSourceOperationMask(.copy, forLocal: true)

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("field"))
        column.title = L.t("Field", "필드")
        column.width = 220
        fieldTable.addTableColumn(column)

        fieldScroll.documentView = fieldTable
        fieldScroll.hasVerticalScroller = true
        fieldScroll.translatesAutoresizingMaskIntoConstraints = false
        fieldScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 180).isActive = true

        section.addArrangedSubview(title)
        section.addArrangedSubview(fieldScroll)
        return section
    }

    private func makeDropZoneSection() -> NSView {
        let section = NSStackView()
        section.orientation = .vertical
        section.spacing = 8
        section.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: L.t("Layout", "레이아웃"))
        title.font = .systemFont(ofSize: 13, weight: .semibold)

        let firstRow = NSStackView()
        firstRow.orientation = .horizontal
        firstRow.spacing = 8
        firstRow.distribution = .fillEqually

        let secondRow = NSStackView()
        secondRow.orientation = .horizontal
        secondRow.spacing = 8
        secondRow.distribution = .fillEqually

        let rows = makeDropZone(.rows)
        let columns = makeDropZone(.columns)
        let values = makeDropZone(.values)
        let filters = makeDropZone(.filters)
        firstRow.addArrangedSubview(rows)
        firstRow.addArrangedSubview(columns)
        secondRow.addArrangedSubview(values)
        secondRow.addArrangedSubview(filters)

        section.addArrangedSubview(title)
        section.addArrangedSubview(firstRow)
        section.addArrangedSubview(secondRow)
        return section
    }

    private func makeDropZone(_ zone: PivotDropZone) -> PivotDropZoneView {
        let view = PivotDropZoneView(zone: zone) { [weak self] index, zone in
            self?.assignField(index, to: zone)
        } onRemove: { [weak self] index, zone in
            self?.removeField(index, from: zone)
        }
        zoneViews[zone] = view
        return view
    }

    private func makeAggregationSection() -> NSView {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8

        aggregationPopup.removeAllItems()
        aggregationPopup.addItems(withTitles: AggregationFunction.allCases.map(\.rawValue))
        aggregationPopup.selectItem(withTitle: layout.function.rawValue)
        aggregationPopup.target = self
        aggregationPopup.action = #selector(aggregationChanged(_:))

        let label = NSTextField(labelWithString: L.t("Aggregation", "집계"))
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        stack.addArrangedSubview(label)
        stack.addArrangedSubview(aggregationPopup)
        return stack
    }

    private func makeResultsPane() -> NSView {
        resultPane.translatesAutoresizingMaskIntoConstraints = false
        resultPane.widthAnchor.constraint(greaterThanOrEqualToConstant: 520).isActive = true

        let header = makeResultHeader()
        header.translatesAutoresizingMaskIntoConstraints = true
        resultPane.addSubview(header)
        resultPane.addSubview(previewContainer)
        configurePreviewContainer()
        previewContainer.translatesAutoresizingMaskIntoConstraints = true
        resultPane.setContent(header: header, preview: previewContainer)
        return resultPane
    }

    private func makeResultHeader() -> NSView {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8

        let title = NSTextField(labelWithString: L.t("Pivot Result", "피벗 결과"))
        title.font = .systemFont(ofSize: 13, weight: .semibold)

        previewTabs.segmentCount = 2
        previewTabs.setLabel(L.t("Pivot Table", "피벗 테이블"), forSegment: 0)
        previewTabs.setLabel(L.t("Pivot Chart", "피벗 차트"), forSegment: 1)
        previewTabs.selectedSegment = 0
        previewTabs.target = self
        previewTabs.action = #selector(previewTabChanged(_:))

        resultSummaryLabel.font = .systemFont(ofSize: 12)
        resultSummaryLabel.textColor = .secondaryLabelColor
        resultSummaryLabel.lineBreakMode = .byTruncatingTail
        resultSummaryLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        stack.addArrangedSubview(title)
        stack.addArrangedSubview(resultSummaryLabel)
        stack.addArrangedSubview(spacer)
        stack.addArrangedSubview(previewTabs)
        return stack
    }

    private func configurePreviewContainer() {
        previewContainer.setContentHuggingPriority(.defaultLow, for: .vertical)
        previewContainer.setContentCompressionResistancePriority(.defaultHigh, for: .vertical)

        tablePreview.delegate = self
        tablePreview.dataSource = self
        tablePreview.usesAlternatingRowBackgroundColors = true
        tablePreview.rowHeight = 24
        tableScroll.documentView = tablePreview
        tableScroll.hasVerticalScroller = true
        tableScroll.hasHorizontalScroller = true

        emptyPreviewLabel.font = .systemFont(ofSize: 13)
        emptyPreviewLabel.textColor = .secondaryLabelColor
        emptyPreviewLabel.alignment = .center
        emptyPreviewLabel.stringValue = L.t(
            "Drag a field into Values. Rows and Columns are optional.",
            "값에 필드를 끌어 놓으세요. 행과 열은 선택 사항입니다."
        )

        for view in [tableScroll, chartView, emptyPreviewLabel] {
            view.translatesAutoresizingMaskIntoConstraints = false
            previewContainer.addSubview(view)
            NSLayoutConstraint.activate([
                view.leadingAnchor.constraint(equalTo: previewContainer.leadingAnchor),
                view.trailingAnchor.constraint(equalTo: previewContainer.trailingAnchor),
                view.topAnchor.constraint(equalTo: previewContainer.topAnchor),
                view.bottomAnchor.constraint(equalTo: previewContainer.bottomAnchor)
            ])
        }
        updatePreviewVisibility()
    }

    @objc private func previewTabChanged(_ sender: NSSegmentedControl) {
        updatePreviewVisibility()
    }

    @objc private func aggregationChanged(_ sender: NSPopUpButton) {
        guard let title = sender.selectedItem?.title,
              let function = AggregationFunction(rawValue: title) else { return }
        setAggregation(function)
    }

    private func refreshZones() {
        zoneViews[.rows]?.setFields(layout.rows.compactMap { fields[safe: $0] })
        zoneViews[.columns]?.setFields(layout.columns.compactMap { fields[safe: $0] })
        if let value = layout.value {
            zoneViews[.values]?.setFieldItems([
                (index: value, name: "\(layout.function.rawValue) of \(fields[value].name)", removable: true)
            ])
        } else {
            zoneViews[.values]?.setFieldItems([])
        }
        zoneViews[.filters]?.setFields(layout.filters.compactMap { fields[safe: $0] })
    }

    private func refreshPreview() {
        previewCancellation?.cancel()
        previewGeneration += 1
        let generation = previewGeneration

        guard layout.isRunnable, let value = layout.value else {
            previewIsComputing = false
            previewCancellation = nil
            pivot = nil
            previewHeaders = []
            previewRows = []
            rebuildPreviewColumns()
            chartView.update(model: nil)
            resultSummaryLabel.stringValue = L.t("No result", "결과 없음")
            emptyPreviewLabel.stringValue = L.t(
                "Drag a field into Values. Rows and Columns are optional.",
                "값에 필드를 끌어 놓으세요. 행과 열은 선택 사항입니다."
            )
            updatePreviewVisibility()
            return
        }

        let cancellation = CancellationFlag()
        previewCancellation = cancellation
        previewIsComputing = true
        resultSummaryLabel.stringValue = L.t("Calculating...", "계산 중...")
        emptyPreviewLabel.stringValue = L.t("Calculating pivot...", "피벗 계산 중...")
        updatePreviewVisibility()

        let document = csvDocument
        let rows = layout.rows
        let columns = layout.columns
        let function = layout.function
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let result = try document.pivotTable(
                    rowColumns: rows,
                    columnColumns: columns,
                    valueColumn: value,
                    function: function,
                    cancellation: cancellation
                )
                DispatchQueue.main.async { [weak self] in
                    guard let self,
                          self.previewGeneration == generation,
                          self.previewCancellation === cancellation else { return }
                    self.previewIsComputing = false
                    self.applyPreview(result, valueColumn: value)
                }
            } catch CsvError.cancelled {
                return
            } catch {
                DispatchQueue.main.async { [weak self] in
                    guard let self,
                          self.previewGeneration == generation,
                          self.previewCancellation === cancellation else { return }
                    self.previewIsComputing = false
                    self.pivot = nil
                    self.previewHeaders = []
                    self.previewRows = []
                    self.rebuildPreviewColumns()
                    self.chartView.update(model: nil)
                    self.resultSummaryLabel.stringValue = L.t("Error", "오류")
                    self.emptyPreviewLabel.stringValue = error.localizedDescription
                    self.updatePreviewVisibility()
                }
            }
        }
    }

    private func applyPreview(_ result: PivotTableResult, valueColumn: Int) {
        pivot = result
        let valueName = fields[safe: valueColumn]?.name ?? L.t("Value", "값")
        let valueHeader = "\(result.function.rawValue) of \(valueName)"

        if result.rowColumns.isEmpty, result.columnColumns.isEmpty {
            previewHeaders = [L.t("Metric", "지표"), valueHeader]
            previewRows = [[L.t("Total", "합계"), Self.formatNumber(result.value(row: [], column: []))]]
        } else if result.columnColumns.isEmpty {
            previewHeaders = [rowHeaderTitle(), valueHeader]
            previewRows = result.rowKeys.map { rowKey in
                [Self.label(rowKey, fallback: L.t("Total", "합계")), Self.formatNumber(result.value(row: rowKey, column: []))]
            }
        } else {
            let rowHeader = result.rowColumns.isEmpty ? L.t("Total", "합계") : rowHeaderTitle()
            previewHeaders = [rowHeader] + result.columnKeys.map { Self.label($0, fallback: L.t("Total", "합계")) }
            let rowKeys = result.rowColumns.isEmpty ? [[]] : result.rowKeys
            previewRows = rowKeys.map { rowKey in
                [Self.label(rowKey, fallback: L.t("Total", "합계"))]
                    + result.columnKeys.map { Self.formatNumber(result.value(row: rowKey, column: $0)) }
            }
        }

        rebuildPreviewColumns()
        chartView.update(model: PivotChartModel.make(from: result))
        resultSummaryLabel.stringValue = L.t(
            "\(previewRows.count.formatted()) rows x \(previewHeaders.count.formatted()) columns",
            "\(previewRows.count.formatted())행 x \(previewHeaders.count.formatted())열"
        )
        updatePreviewVisibility()
    }

    private func rowHeaderTitle() -> String {
        let title = layout.rows.compactMap { fields[safe: $0]?.name }.joined(separator: " | ")
        return title.isEmpty ? L.t("Total", "합계") : title
    }

    private static func label(_ key: [String], fallback: String) -> String {
        let joined = key.joined(separator: " | ")
        return joined.isEmpty ? fallback : joined
    }

    private func rebuildPreviewColumns() {
        for column in tablePreview.tableColumns {
            tablePreview.removeTableColumn(column)
        }

        for (index, header) in previewHeaders.enumerated() {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("pivot_\(index)"))
            column.title = header
            column.width = index == 0 ? 160 : 110
            tablePreview.addTableColumn(column)
        }
        tablePreview.reloadData()
    }

    private func updatePreviewVisibility() {
        let hasPreview = !previewHeaders.isEmpty
        emptyPreviewLabel.isHidden = hasPreview
        tableScroll.isHidden = !hasPreview || previewTabs.selectedSegment != 0
        chartView.isHidden = !hasPreview || previewTabs.selectedSegment != 1
    }

    private static func formatNumber(_ value: Double) -> String {
        if value.rounded(.towardZero) == value {
            return String(format: "%.0f", value)
        }
        return String(format: "%.3f", value)
    }
}

extension PivotBuilderWindowController: NSTableViewDataSource, NSTableViewDelegate {
    nonisolated func numberOfRows(in tableView: NSTableView) -> Int {
        MainActor.assumeIsolated {
            tableView === fieldTable ? fields.count : previewRows.count
        }
    }

    nonisolated func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        MainActor.assumeIsolated {
            if tableView === fieldTable {
                return makeCell(tableView: tableView, identifier: "fieldCell", text: fields[row].displayName)
            }

            let columnIndex = tableView.tableColumns.firstIndex { $0 === tableColumn } ?? 0
            let text = previewRows[safe: row]?[safe: columnIndex] ?? ""
            return makeCell(tableView: tableView, identifier: "pivotCell", text: text)
        }
    }

    nonisolated func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        MainActor.assumeIsolated {
            guard tableView === fieldTable, fields.indices.contains(row) else { return nil }
            let item = NSPasteboardItem()
            item.setString(String(fields[row].index), forType: .pivotFieldIndex)
            return item
        }
    }

    private func makeCell(tableView: NSTableView, identifier: String, text: String) -> NSTableCellView {
        let viewIdentifier = NSUserInterfaceItemIdentifier(identifier)
        if let reused = tableView.makeView(withIdentifier: viewIdentifier, owner: self) as? NSTableCellView {
            reused.textField?.stringValue = text
            return reused
        }

        let view = NSTableCellView()
        view.identifier = viewIdentifier
        let label = NSTextField(labelWithString: text)
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        view.textField = label
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 6),
            label.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -6),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
        return view
    }
}

#if DEBUG
extension PivotBuilderWindowController {
    func assignFieldForTesting(_ index: Int, to zone: PivotDropZone) {
        assignField(index, to: zone)
    }

    func setAggregationForTesting(_ function: AggregationFunction) {
        setAggregation(function)
    }

    func removeFieldForTesting(_ index: Int, from zone: PivotDropZone) {
        removeField(index, from: zone)
    }

    var layoutForTesting: PivotBuilderLayout {
        layout
    }

    var previewHeadersForTesting: [String] {
        previewHeaders
    }

    func previewRowForTesting(_ row: Int) -> [String] {
        previewRows[safe: row] ?? []
    }

    var chartModelForTesting: PivotChartModel? {
        chartView.modelForTesting
    }

    func layoutWindowForTesting() {
        for _ in 0..<3 {
            window?.layoutIfNeeded()
            window?.contentView?.layoutSubtreeIfNeeded()
            rootSplit.layoutSubtreeIfNeeded()
            resultPane.layoutSubtreeIfNeeded()
            previewContainer.layoutSubtreeIfNeeded()
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
    }

    var windowContentWidthForTesting: CGFloat {
        window?.contentView?.bounds.width ?? 0
    }

    var controlPaneWidthForTesting: CGFloat {
        controlPane.frame.width
    }

    var resultPaneWidthForTesting: CGFloat {
        resultPane.frame.width
    }

    var resultPaneHeightForTesting: CGFloat {
        resultPane.frame.height
    }

    var previewPaneHeightForTesting: CGFloat {
        previewContainer.frame.height
    }
}
#endif

@MainActor
private final class PivotResultPaneView: NSView {
    private weak var headerView: NSView?
    private weak var previewView: NSView?

    func setContent(header: NSView, preview: NSView) {
        headerView = header
        previewView = preview
        needsLayout = true
    }

    override func layout() {
        super.layout()

        let margin: CGFloat = 12
        let spacing: CGFloat = 10
        let headerHeight = max(28, headerView?.fittingSize.height ?? 28)
        let usableWidth = max(0, bounds.width - margin * 2)
        let previewHeight = max(0, bounds.height - margin * 2 - spacing - headerHeight)

        headerView?.frame = NSRect(
            x: margin,
            y: bounds.height - margin - headerHeight,
            width: usableWidth,
            height: headerHeight
        )
        previewView?.frame = NSRect(
            x: margin,
            y: margin,
            width: usableWidth,
            height: previewHeight
        )
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
