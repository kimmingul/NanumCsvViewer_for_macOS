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

    private let fieldTable = NSTableView()
    private let fieldScroll = NSScrollView()
    private let tablePreview = NSTableView()
    private let tableScroll = NSScrollView()
    private let chartView = PivotChartView()
    private let aggregationPopup = NSPopUpButton()
    private let previewTabs = NSSegmentedControl(labels: [], trackingMode: .selectOne, target: nil, action: nil)
    private let previewContainer = NSView()
    private let emptyPreviewLabel = NSTextField(labelWithString: "")
    private var zoneViews: [PivotDropZone: PivotDropZoneView] = [:]

    init(document: VirtualCsvDocument, columnNames: [String]) {
        csvDocument = document
        fields = columnNames.enumerated().map { index, name in
            PivotField(index: index, name: name.isEmpty ? "Column \(index + 1)" : name, typeHint: nil)
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1040, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
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

    private func appendUnique(_ index: Int, to target: inout [Int]) {
        guard !target.contains(index) else { return }
        target.append(index)
    }

    private func buildInterface() {
        guard let contentView = window?.contentView else { return }

        let split = NSSplitView()
        split.isVertical = true
        split.dividerStyle = .thin
        split.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(split)

        NSLayoutConstraint.activate([
            split.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            split.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            split.topAnchor.constraint(equalTo: contentView.topAnchor),
            split.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])

        split.addArrangedSubview(makeFieldListPane())
        split.addArrangedSubview(makeBuilderPane())
        split.setPosition(260, ofDividerAt: 0)
    }

    private func makeFieldListPane() -> NSView {
        let pane = NSView()
        pane.translatesAutoresizingMaskIntoConstraints = false
        pane.widthAnchor.constraint(greaterThanOrEqualToConstant: 220).isActive = true

        let title = NSTextField(labelWithString: L.t("Fields", "필드"))
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        title.translatesAutoresizingMaskIntoConstraints = false

        fieldTable.headerView = nil
        fieldTable.delegate = self
        fieldTable.dataSource = self
        fieldTable.allowsMultipleSelection = false
        fieldTable.usesAlternatingRowBackgroundColors = false
        fieldTable.rowHeight = 28
        fieldTable.registerForDraggedTypes([.pivotFieldIndex])

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("field"))
        column.title = L.t("Field", "필드")
        column.width = 220
        fieldTable.addTableColumn(column)

        fieldScroll.documentView = fieldTable
        fieldScroll.hasVerticalScroller = true
        fieldScroll.translatesAutoresizingMaskIntoConstraints = false

        pane.addSubview(title)
        pane.addSubview(fieldScroll)
        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: pane.leadingAnchor, constant: 12),
            title.trailingAnchor.constraint(equalTo: pane.trailingAnchor, constant: -12),
            title.topAnchor.constraint(equalTo: pane.topAnchor, constant: 12),
            fieldScroll.leadingAnchor.constraint(equalTo: pane.leadingAnchor, constant: 12),
            fieldScroll.trailingAnchor.constraint(equalTo: pane.trailingAnchor, constant: -12),
            fieldScroll.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 8),
            fieldScroll.bottomAnchor.constraint(equalTo: pane.bottomAnchor, constant: -12)
        ])
        return pane
    }

    private func makeBuilderPane() -> NSView {
        let pane = NSView()
        pane.translatesAutoresizingMaskIntoConstraints = false

        let root = NSStackView()
        root.orientation = .vertical
        root.spacing = 10
        root.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        root.translatesAutoresizingMaskIntoConstraints = false
        pane.addSubview(root)

        root.addArrangedSubview(makeDropZoneGrid())
        root.addArrangedSubview(makePreviewHeader())
        root.addArrangedSubview(previewContainer)
        root.setVisibilityPriority(.mustHold, for: previewContainer)

        configurePreviewContainer()

        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: pane.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: pane.trailingAnchor),
            root.topAnchor.constraint(equalTo: pane.topAnchor),
            root.bottomAnchor.constraint(equalTo: pane.bottomAnchor)
        ])
        return pane
    }

    private func makeDropZoneGrid() -> NSView {
        let grid = NSGridView()
        grid.translatesAutoresizingMaskIntoConstraints = false
        grid.rowSpacing = 10
        grid.columnSpacing = 10

        let rows = makeDropZone(.rows)
        let columns = makeDropZone(.columns)
        let values = makeDropZone(.values)
        let filters = makeDropZone(.filters)
        grid.addRow(with: [rows, columns])
        grid.addRow(with: [values, filters])
        grid.widthAnchor.constraint(greaterThanOrEqualToConstant: 560).isActive = true
        return grid
    }

    private func makeDropZone(_ zone: PivotDropZone) -> PivotDropZoneView {
        let view = PivotDropZoneView(zone: zone) { [weak self] index, zone in
            self?.assignField(index, to: zone)
        }
        zoneViews[zone] = view
        return view
    }

    private func makePreviewHeader() -> NSView {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8

        previewTabs.segmentCount = 2
        previewTabs.setLabel(L.t("Table", "테이블"), forSegment: 0)
        previewTabs.setLabel(L.t("Chart", "차트"), forSegment: 1)
        previewTabs.selectedSegment = 0
        previewTabs.target = self
        previewTabs.action = #selector(previewTabChanged(_:))

        aggregationPopup.removeAllItems()
        aggregationPopup.addItems(withTitles: AggregationFunction.allCases.map(\.rawValue))
        aggregationPopup.selectItem(withTitle: layout.function.rawValue)
        aggregationPopup.target = self
        aggregationPopup.action = #selector(aggregationChanged(_:))

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        stack.addArrangedSubview(previewTabs)
        stack.addArrangedSubview(spacer)
        stack.addArrangedSubview(NSTextField(labelWithString: L.t("Aggregation", "집계")))
        stack.addArrangedSubview(aggregationPopup)
        return stack
    }

    private func configurePreviewContainer() {
        previewContainer.translatesAutoresizingMaskIntoConstraints = false
        previewContainer.heightAnchor.constraint(greaterThanOrEqualToConstant: 260).isActive = true

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
            "Drag fields into Rows, Columns, and Values to build a pivot table.",
            "행, 열, 값에 필드를 끌어 놓아 피벗 테이블을 만드세요."
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
        zoneViews[.rows]?.setFieldNames(layout.rows.map { fields[$0].name })
        zoneViews[.columns]?.setFieldNames(layout.columns.map { fields[$0].name })
        if let value = layout.value {
            zoneViews[.values]?.setFieldNames(["\(layout.function.rawValue) of \(fields[value].name)"])
        } else {
            zoneViews[.values]?.setFieldNames([])
        }
        zoneViews[.filters]?.setFieldNames(layout.filters.map { fields[$0].name })
    }

    private func refreshPreview() {
        guard layout.isRunnable, let value = layout.value else {
            pivot = nil
            previewHeaders = []
            previewRows = []
            rebuildPreviewColumns()
            chartView.update(model: nil)
            updatePreviewVisibility()
            return
        }

        do {
            let result = try csvDocument.pivotTable(
                rowColumns: layout.rows,
                columnColumns: layout.columns,
                valueColumn: value,
                function: layout.function,
                cancellation: CancellationFlag()
            )
            pivot = result
            previewHeaders = [layout.rows.map { fields[$0].name }.joined(separator: " | ")]
                + result.columnKeys.map { $0.joined(separator: " | ") }
            previewRows = result.rowKeys.map { rowKey in
                [rowKey.joined(separator: " | ")]
                    + result.columnKeys.map { Self.formatNumber(result.value(row: rowKey, column: $0)) }
            }
            rebuildPreviewColumns()
            chartView.update(model: PivotChartModel.make(from: result))
            updatePreviewVisibility()
        } catch {
            pivot = nil
            previewHeaders = []
            previewRows = []
            rebuildPreviewColumns()
            chartView.update(model: nil)
            emptyPreviewLabel.stringValue = error.localizedDescription
            updatePreviewVisibility()
        }
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
}
#endif

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
