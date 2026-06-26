import AppKit
@preconcurrency import CsvCore

@MainActor
final class PivotBuilderWindowController: NSWindowController {
    private let csvDocument: VirtualCsvDocument
    private var fields: [PivotField]
    private var layout = PivotBuilderLayout()
    private var pivot: PivotTableResult?
    private var previewRows: [[String]] = []
    private var previewHeaders: [String] = []
    private var previewCancellation: CancellationFlag?
    private var typeAnalysisCancellation: CancellationFlag?
    private var previewGeneration = 0
    private var previewIsComputing = false
    private var controlSectionTitles: [String] = []

    private let rootSplit = NSSplitView()
    private let controlPane = NSView()
    private let resultPane = PivotResultPaneView()
    private let fieldTable = PivotFieldTableView()
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
    private var fieldActionButtons: [PivotDropZone: NSButton] = [:]

    init(document: VirtualCsvDocument, columnNames: [String], columnStatisticsReport: ColumnStatisticsReport? = nil) {
        csvDocument = document
        fields = Self.makeFields(columnNames: columnNames, columnStatisticsReport: columnStatisticsReport)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1180, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.minSize = NSSize(width: 900, height: 680)
        window.title = L.t("Pivot Builder", "피벗 빌더")
        super.init(window: window)
        buildInterface()
        refreshZones()
        refreshPreview()
        loadFieldTypesIfNeeded()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        previewCancellation?.cancel()
        typeAnalysisCancellation?.cancel()
    }

    private static func makeFields(
        columnNames: [String],
        columnStatisticsReport: ColumnStatisticsReport?
    ) -> [PivotField] {
        let typesByIndex = Dictionary(
            uniqueKeysWithValues: columnStatisticsReport?.columns.map { ($0.index, $0.inferredType) } ?? []
        )
        return columnNames.enumerated().map { index, name in
            PivotField(
                index: index,
                name: name.isEmpty ? "Column \(index + 1)" : name,
                valueType: typesByIndex[index]
            )
        }
    }

    private func loadFieldTypesIfNeeded() {
        guard fields.contains(where: { $0.valueType == nil }) else { return }
        let cancellation = CancellationFlag()
        typeAnalysisCancellation = cancellation
        let document = csvDocument
        DispatchQueue.global(qos: .utility).async { [weak self] in
            do {
                let report = try document.analyzeColumns(sampleLimit: 5_000, cancellation: cancellation)
                DispatchQueue.main.async { [weak self] in
                    guard let self,
                          self.typeAnalysisCancellation === cancellation else { return }
                    self.applyColumnStatistics(report)
                }
            } catch {
                DispatchQueue.main.async { [weak self] in
                    guard let self,
                          self.typeAnalysisCancellation === cancellation else { return }
                    self.typeAnalysisCancellation = nil
                }
            }
        }
    }

    private func applyColumnStatistics(_ report: ColumnStatisticsReport) {
        let typesByIndex = Dictionary(uniqueKeysWithValues: report.columns.map { ($0.index, $0.inferredType) })
        fields = fields.map { field in
            PivotField(index: field.index, name: field.name, valueType: typesByIndex[field.index])
        }
        typeAnalysisCancellation = nil
        fieldTable.reloadData()
        refreshZones()
        updateFieldActionButtons()
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

        let fieldSection = makeFieldListSection()
        let dimensionSection = makeDimensionSection()
        let measureSection = makeMeasureSection()
        controlSectionTitles = [
            L.t("Fields", "필드"),
            L.t("Dimensions", "차원"),
            L.t("Measures", "측정값")
        ]

        for section in [fieldSection, dimensionSection, measureSection] {
            section.translatesAutoresizingMaskIntoConstraints = false
            controlPane.addSubview(section)
        }

        NSLayoutConstraint.activate([
            fieldSection.leadingAnchor.constraint(equalTo: controlPane.leadingAnchor, constant: 12),
            fieldSection.trailingAnchor.constraint(equalTo: controlPane.trailingAnchor, constant: -12),
            fieldSection.topAnchor.constraint(equalTo: controlPane.topAnchor, constant: 12),
            fieldSection.heightAnchor.constraint(equalToConstant: 260),
            dimensionSection.leadingAnchor.constraint(equalTo: controlPane.leadingAnchor, constant: 12),
            dimensionSection.trailingAnchor.constraint(equalTo: controlPane.trailingAnchor, constant: -12),
            dimensionSection.topAnchor.constraint(equalTo: fieldSection.bottomAnchor, constant: 12),
            measureSection.leadingAnchor.constraint(equalTo: controlPane.leadingAnchor, constant: 12),
            measureSection.trailingAnchor.constraint(equalTo: controlPane.trailingAnchor, constant: -12),
            measureSection.topAnchor.constraint(equalTo: dimensionSection.bottomAnchor, constant: 12),
            measureSection.bottomAnchor.constraint(lessThanOrEqualTo: controlPane.bottomAnchor, constant: -12)
        ])

        return controlPane
    }

    private func makeFieldListSection() -> NSView {
        let section = NSView()

        let title = NSTextField(labelWithString: L.t("Fields", "필드"))
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        title.alignment = .left
        title.translatesAutoresizingMaskIntoConstraints = false

        fieldTable.headerView = nil
        fieldTable.delegate = self
        fieldTable.dataSource = self
        fieldTable.allowsMultipleSelection = false
        fieldTable.usesAlternatingRowBackgroundColors = false
        fieldTable.rowHeight = 28
        fieldTable.registerForDraggedTypes([.pivotFieldIndex])
        fieldTable.setDraggingSourceOperationMask(.copy, forLocal: true)
        fieldTable.target = self
        fieldTable.doubleAction = #selector(fieldDoubleClicked(_:))
        fieldTable.menu = makeFieldContextMenu()

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("field"))
        column.title = L.t("Field", "필드")
        column.width = 220
        fieldTable.addTableColumn(column)

        fieldScroll.documentView = fieldTable
        fieldScroll.hasVerticalScroller = true
        fieldScroll.autohidesScrollers = true
        fieldScroll.scrollerStyle = .overlay
        fieldScroll.translatesAutoresizingMaskIntoConstraints = false
        fieldScroll.widthAnchor.constraint(greaterThanOrEqualToConstant: 300).isActive = true

        let actions = makeFieldActionBar()
        actions.translatesAutoresizingMaskIntoConstraints = false

        section.addSubview(title)
        section.addSubview(actions)
        section.addSubview(fieldScroll)
        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: section.leadingAnchor),
            title.trailingAnchor.constraint(equalTo: section.trailingAnchor),
            title.topAnchor.constraint(equalTo: section.topAnchor),
            actions.leadingAnchor.constraint(equalTo: section.leadingAnchor),
            actions.trailingAnchor.constraint(equalTo: section.trailingAnchor),
            actions.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 8),
            fieldScroll.leadingAnchor.constraint(equalTo: section.leadingAnchor),
            fieldScroll.trailingAnchor.constraint(equalTo: section.trailingAnchor),
            fieldScroll.topAnchor.constraint(equalTo: actions.bottomAnchor, constant: 8),
            fieldScroll.bottomAnchor.constraint(equalTo: section.bottomAnchor)
        ])
        updateFieldActionButtons()
        return section
    }

    private func makeFieldActionBar() -> NSView {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 6
        stack.distribution = .fillEqually

        for zone in [PivotDropZone.rows, .columns, .values, .filters] {
            let button = NSButton(title: zone.title, target: self, action: #selector(addSelectedFieldFromButton(_:)))
            button.image = NSImage(systemSymbolName: "plus.circle", accessibilityDescription: zone.title)
            button.imagePosition = .imageLeading
            button.bezelStyle = .rounded
            button.controlSize = .small
            button.tag = Self.tag(for: zone)
            button.toolTip = L.t("Add selected field to \(zone.title)", "선택한 필드를 \(zone.title)에 추가")
            fieldActionButtons[zone] = button
            stack.addArrangedSubview(button)
        }
        return stack
    }

    private func makeDimensionSection() -> NSView {
        let section = NSView()
        section.heightAnchor.constraint(greaterThanOrEqualToConstant: 222).isActive = true

        let title = NSTextField(labelWithString: L.t("Dimensions", "차원"))
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        title.alignment = .left
        title.translatesAutoresizingMaskIntoConstraints = false

        let firstRow = NSStackView()
        firstRow.orientation = .horizontal
        firstRow.spacing = 8
        firstRow.distribution = .fillEqually
        firstRow.translatesAutoresizingMaskIntoConstraints = false

        let rows = makeDropZone(.rows)
        let columns = makeDropZone(.columns)
        let filters = makeDropZone(.filters)
        filters.translatesAutoresizingMaskIntoConstraints = false
        firstRow.addArrangedSubview(rows)
        firstRow.addArrangedSubview(columns)

        section.addSubview(title)
        section.addSubview(firstRow)
        section.addSubview(filters)
        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: section.leadingAnchor),
            title.trailingAnchor.constraint(equalTo: section.trailingAnchor),
            title.topAnchor.constraint(equalTo: section.topAnchor),
            firstRow.leadingAnchor.constraint(equalTo: section.leadingAnchor),
            firstRow.trailingAnchor.constraint(equalTo: section.trailingAnchor),
            firstRow.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 8),
            firstRow.heightAnchor.constraint(greaterThanOrEqualToConstant: 92),
            filters.leadingAnchor.constraint(equalTo: section.leadingAnchor),
            filters.trailingAnchor.constraint(equalTo: section.trailingAnchor),
            filters.topAnchor.constraint(equalTo: firstRow.bottomAnchor, constant: 8),
            filters.heightAnchor.constraint(greaterThanOrEqualToConstant: 92),
            filters.bottomAnchor.constraint(equalTo: section.bottomAnchor)
        ])
        return section
    }

    private func makeMeasureSection() -> NSView {
        let section = NSView()
        section.heightAnchor.constraint(greaterThanOrEqualToConstant: 138).isActive = true

        let header = NSStackView()
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 8
        header.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: L.t("Measures", "측정값"))
        title.font = .systemFont(ofSize: 13, weight: .semibold)

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        aggregationPopup.removeAllItems()
        aggregationPopup.addItems(withTitles: AggregationFunction.allCases.map(\.rawValue))
        aggregationPopup.selectItem(withTitle: layout.function.rawValue)
        aggregationPopup.target = self
        aggregationPopup.action = #selector(aggregationChanged(_:))

        let aggregationLabel = NSTextField(labelWithString: L.t("Aggregation", "집계"))
        aggregationLabel.font = .systemFont(ofSize: 12, weight: .medium)
        aggregationLabel.textColor = .secondaryLabelColor

        header.addArrangedSubview(title)
        header.addArrangedSubview(spacer)
        header.addArrangedSubview(aggregationLabel)
        header.addArrangedSubview(aggregationPopup)

        let values = makeDropZone(.values)
        values.translatesAutoresizingMaskIntoConstraints = false

        section.addSubview(header)
        section.addSubview(values)
        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: section.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: section.trailingAnchor),
            header.topAnchor.constraint(equalTo: section.topAnchor),
            values.leadingAnchor.constraint(equalTo: section.leadingAnchor),
            values.trailingAnchor.constraint(equalTo: section.trailingAnchor),
            values.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 8),
            values.heightAnchor.constraint(greaterThanOrEqualToConstant: 92),
            values.bottomAnchor.constraint(equalTo: section.bottomAnchor)
        ])
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
        tablePreview.usesAlternatingRowBackgroundColors = false
        tablePreview.gridStyleMask = .solidHorizontalGridLineMask
        tablePreview.rowHeight = 24
        tableScroll.documentView = tablePreview
        tableScroll.hasVerticalScroller = true
        tableScroll.hasHorizontalScroller = true

        emptyPreviewLabel.font = .systemFont(ofSize: 13)
        emptyPreviewLabel.textColor = .secondaryLabelColor
        emptyPreviewLabel.alignment = .center
        emptyPreviewLabel.stringValue = L.t(
            "Add a field to Values. Rows and Columns are optional.",
            "값에 필드를 추가하세요. 행과 열은 선택 사항입니다."
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

    @objc private func fieldDoubleClicked(_ sender: NSTableView) {
        addSelectedFieldToDefaultZone()
    }

    @objc private func addSelectedFieldFromButton(_ sender: NSButton) {
        guard let zone = Self.zone(for: sender.tag) else { return }
        addSelectedField(to: zone)
    }

    @objc private func addSelectedFieldToRows(_ sender: Any?) {
        addSelectedField(to: .rows)
    }

    @objc private func addSelectedFieldToColumns(_ sender: Any?) {
        addSelectedField(to: .columns)
    }

    @objc private func addSelectedFieldToValues(_ sender: Any?) {
        addSelectedField(to: .values)
    }

    @objc private func addSelectedFieldToFilters(_ sender: Any?) {
        addSelectedField(to: .filters)
    }

    private func makeFieldContextMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(
            title: L.t("Add to Rows", "행에 추가"),
            action: #selector(addSelectedFieldToRows(_:)),
            keyEquivalent: ""
        ))
        menu.addItem(NSMenuItem(
            title: L.t("Add to Columns", "열에 추가"),
            action: #selector(addSelectedFieldToColumns(_:)),
            keyEquivalent: ""
        ))
        menu.addItem(NSMenuItem(
            title: L.t("Add to Values", "값에 추가"),
            action: #selector(addSelectedFieldToValues(_:)),
            keyEquivalent: ""
        ))
        menu.addItem(NSMenuItem(
            title: L.t("Add to Filters", "필터에 추가"),
            action: #selector(addSelectedFieldToFilters(_:)),
            keyEquivalent: ""
        ))
        for item in menu.items {
            item.target = self
        }
        return menu
    }

    private func addSelectedFieldToDefaultZone() {
        guard let selected = selectedField() else { return }
        assignField(selected.index, to: selected.isMeasureCandidate ? .values : .rows)
    }

    private func addSelectedField(to zone: PivotDropZone) {
        guard let selected = selectedField() else { return }
        assignField(selected.index, to: zone)
    }

    private func selectedField() -> PivotField? {
        fields[safe: fieldTable.selectedRow]
    }

    private func updateFieldActionButtons() {
        let hasSelection = selectedField() != nil
        for button in fieldActionButtons.values {
            button.isEnabled = hasSelection
        }
    }

    private static func tag(for zone: PivotDropZone) -> Int {
        switch zone {
        case .rows:
            return 1
        case .columns:
            return 2
        case .values:
            return 3
        case .filters:
            return 4
        }
    }

    private static func zone(for tag: Int) -> PivotDropZone? {
        switch tag {
        case 1:
            return .rows
        case 2:
            return .columns
        case 3:
            return .values
        case 4:
            return .filters
        default:
            return nil
        }
    }

    private static func isMeasureZone(_ zone: PivotDropZone) -> Bool {
        zone == .values
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
                "Add a field to Values. Rows and Columns are optional.",
                "값에 필드를 추가하세요. 행과 열은 선택 사항입니다."
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
                return makeFieldCell(tableView: tableView, field: fields[row])
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

    nonisolated func tableViewSelectionDidChange(_ notification: Notification) {
        MainActor.assumeIsolated {
            guard notification.object as? NSTableView === fieldTable else { return }
            updateFieldActionButtons()
        }
    }

    private func makeFieldCell(tableView: NSTableView, field: PivotField) -> PivotFieldCellView {
        let viewIdentifier = NSUserInterfaceItemIdentifier("fieldCell")
        if let reused = tableView.makeView(withIdentifier: viewIdentifier, owner: self) as? PivotFieldCellView {
            reused.configure(field: field)
            return reused
        }

        let view = PivotFieldCellView()
        view.identifier = viewIdentifier
        view.configure(field: field)
        return view
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

    var fieldListRowCountForTesting: Int {
        fieldTable.numberOfRows
    }

    var fieldListScrollHeightForTesting: CGFloat {
        fieldScroll.frame.height
    }

    var fieldListScrollWidthForTesting: CGFloat {
        fieldScroll.frame.width
    }

    var fieldListScrollMinXForTesting: CGFloat {
        fieldScroll.convert(fieldScroll.bounds, to: controlPane).minX
    }

    var fieldListTableHeightForTesting: CGFloat {
        fieldTable.frame.height
    }

    var fieldListTableWidthForTesting: CGFloat {
        fieldTable.frame.width
    }

    var fieldListVisibleRowsForTesting: NSRange {
        fieldTable.rows(in: fieldScroll.contentView.bounds)
    }

    var fieldListToLayoutGapForTesting: CGFloat {
        guard let rowsView = zoneViews[.rows] else { return .greatestFiniteMagnitude }
        let fieldRect = fieldScroll.convert(fieldScroll.bounds, to: controlPane)
        let rowsRect = rowsView.convert(rowsView.bounds, to: controlPane)
        return fieldRect.minY - rowsRect.maxY
    }

    var pivotTableUsesAlternatingRowsForTesting: Bool {
        tablePreview.usesAlternatingRowBackgroundColors
    }

    var fieldListAutohidesScrollersForTesting: Bool {
        fieldScroll.autohidesScrollers
    }

    var controlSectionTitlesForTesting: [String] {
        controlSectionTitles
    }

    func isMeasureZoneForTesting(_ zone: PivotDropZone) -> Bool {
        Self.isMeasureZone(zone)
    }

    func selectFieldForTesting(row: Int) {
        guard row >= 0, row < fieldTable.numberOfRows else { return }
        fieldTable.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        updateFieldActionButtons()
    }

    func addSelectedFieldToDefaultZoneForTesting() {
        addSelectedFieldToDefaultZone()
    }

    func addSelectedFieldForTesting(to zone: PivotDropZone) {
        addSelectedField(to: zone)
    }

    func fieldListVisibleTextForTesting(row: Int) -> String? {
        guard row >= 0, row < fieldTable.numberOfRows else { return nil }
        let view = fieldTable.view(atColumn: 0, row: row, makeIfNecessary: true) as? NSTableCellView
        return view?.textField?.stringValue
    }

    func fieldListTypeTextForTesting(row: Int) -> String? {
        guard row >= 0, row < fieldTable.numberOfRows else { return nil }
        let view = fieldTable.view(atColumn: 0, row: row, makeIfNecessary: true) as? PivotFieldCellView
        return view?.typeTextForTesting
    }
}
#endif

@MainActor
private final class PivotFieldTableView: NSTableView {
    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        let clickedRow = row(at: point)
        if clickedRow >= 0 {
            selectRowIndexes(IndexSet(integer: clickedRow), byExtendingSelection: false)
        }
        return super.menu(for: event)
    }
}

@MainActor
private final class PivotFieldCellView: NSTableCellView {
    private let nameLabel = NSTextField(labelWithString: "")
    private let typeLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var typeTextForTesting: String {
        typeLabel.stringValue
    }

    func configure(field: PivotField) {
        nameLabel.stringValue = field.name
        typeLabel.stringValue = field.typeHint ?? L.t("Unknown", "알 수 없음")
        typeLabel.isHidden = field.typeHint == nil
    }

    private func configure() {
        textField = nameLabel

        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        typeLabel.font = .systemFont(ofSize: 10, weight: .medium)
        typeLabel.textColor = .secondaryLabelColor
        typeLabel.alignment = .center
        typeLabel.lineBreakMode = .byTruncatingTail
        typeLabel.translatesAutoresizingMaskIntoConstraints = false
        typeLabel.wantsLayer = true
        typeLabel.layer?.cornerRadius = 5
        typeLabel.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        typeLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        addSubview(nameLabel)
        addSubview(typeLabel)
        NSLayoutConstraint.activate([
            nameLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            nameLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            typeLabel.leadingAnchor.constraint(greaterThanOrEqualTo: nameLabel.trailingAnchor, constant: 8),
            typeLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            typeLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            typeLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 68)
        ])
    }
}

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
