import AppKit
@preconcurrency import CsvCore

private struct PivotPreviewSection: Equatable {
    let title: String
    let measure: PivotMeasure
    let pivot: PivotTableResult
    let headers: [String]
    let rows: [[String]]
    let chartModel: PivotChartModel
}

private final class PivotPreviewDocumentStackView: NSStackView {
    override var isFlipped: Bool {
        true
    }
}

@MainActor
final class PivotBuilderWindowController: NSWindowController {
    enum InitialResultTab {
        case table
        case chart
    }

    private let csvDocument: VirtualCsvDocument
    private var fields: [PivotField]
    private var layout = PivotBuilderLayout()
    private var pivot: PivotTableResult?
    private var previewSections: [PivotPreviewSection] = []
    private var previewRows: [[String]] = []
    private var previewHeaders: [String] = []
    private var previewCancellation: CancellationFlag?
    private var typeAnalysisCancellation: CancellationFlag?
    private var previewGeneration = 0
    private var previewIsComputing = false
    private var controlSectionTitles: [String] = []
    private var filteredFieldIndexes: [Int] = []
    private var nextMeasureID = 1

    private let rootSplit = NSSplitView()
    private let controlPane = NSView()
    private let resultPane = PivotResultPaneView()
    private let fieldTable = PivotFieldTableView()
    private let fieldSearch = NSSearchField()
    private let fieldScroll = NSScrollView()
    private let tablePreview = NSTableView()
    private let tableScroll = NSScrollView()
    private let tableResultsStack = PivotPreviewDocumentStackView()
    private let chartView = PivotChartView()
    private let chartScroll = NSScrollView()
    private let chartResultsStack = PivotPreviewDocumentStackView()
    private let aggregationPopup = NSPopUpButton()
    private let previewTabs = NSSegmentedControl(labels: [], trackingMode: .selectOne, target: nil, action: nil)
    private let previewContainer = NSView()
    private let emptyPreviewLabel = NSTextField(labelWithString: "")
    private let resultSummaryLabel = NSTextField(labelWithString: "")
    private let dateGroupControlsStack = NSStackView()
    private let filterControlsStack = NSStackView()
    private var zoneViews: [PivotDropZone: PivotDropZoneView] = [:]
    private var fieldActionButtons: [PivotDropZone: NSButton] = [:]
    private var fieldActionButtonOrder: [NSButton] = []
    private var dateDimensionGroupPopups: [Int: NSPopUpButton] = [:]
    private var filterValuePopups: [Int: NSPopUpButton] = [:]
    private var filterDateGroupPopups: [Int: NSPopUpButton] = [:]
    private var measureAggregationPopups: [Int: NSPopUpButton] = [:]
    private var measureMoveButtons: [Int: [NSButton]] = [:]

    init(
        document: VirtualCsvDocument,
        columnNames: [String],
        columnStatisticsReport: ColumnStatisticsReport? = nil,
        initialResultTab: InitialResultTab = .table
    ) {
        csvDocument = document
        fields = Self.makeFields(columnNames: columnNames, columnStatisticsReport: columnStatisticsReport)
        filteredFieldIndexes = Array(fields.indices)
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
        selectResultTab(initialResultTab)
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
        let didAddDateGrouping = ensureDateGroupingDefaultsForAssignedFields()
        normalizeMeasureAggregations()
        typeAnalysisCancellation = nil
        applyFieldSearch()
        refreshZones()
        refreshDateGroupControls()
        refreshFilterControls()
        updateFieldActionButtons()
        if didAddDateGrouping {
            refreshPreview()
        }
    }

    func assignField(_ index: Int, to zone: PivotDropZone) {
        assignField(index, to: zone, targetPosition: nil)
    }

    private func assignField(_ index: Int, to zone: PivotDropZone, targetPosition: Int?) {
        guard fields.indices.contains(index) else { return }

        switch zone {
        case .rows:
            let cleanupCandidates = removeFieldFromAllZones(index)
            insertUnique(index, into: &layout.rows, at: targetPosition)
            cleanupCandidates.forEach(cleanupLayoutStateIfUnassigned)
        case .columns:
            let cleanupCandidates = removeFieldFromAllZones(index)
            insertUnique(index, into: &layout.columns, at: targetPosition)
            cleanupCandidates.forEach(cleanupLayoutStateIfUnassigned)
        case .values:
            let cleanupCandidates = removeFieldFromDimensionZones(index)
            insertMeasure(makeMeasure(fieldIndex: index), at: targetPosition)
            cleanupCandidates.forEach(cleanupLayoutStateIfUnassigned)
        case .filters:
            let cleanupCandidates = removeFieldFromAllZones(index)
            insertUnique(index, into: &layout.filters, at: targetPosition)
            cleanupCandidates.forEach(cleanupLayoutStateIfUnassigned)
        }
        ensureDateGroupingDefaultIfNeeded(for: index)
        refreshZones()
        refreshDateGroupControls()
        refreshFilterControls()
        refreshPreview()
    }

    func setAggregation(_ function: AggregationFunction) {
        guard let measure = layout.measures.first else { return }
        setMeasureAggregation(measureID: measure.id, function: function)
        aggregationPopup.selectItem(withTitle: layout.function.rawValue)
    }

    func selectResultTab(_ tab: InitialResultTab) {
        switch tab {
        case .table:
            previewTabs.selectedSegment = 0
        case .chart:
            previewTabs.selectedSegment = 1
        }
        updatePreviewVisibility()
    }

    func removeField(_ index: Int, from zone: PivotDropZone) {
        removeFieldFromLayout(index, from: zone)
        refreshZones()
        refreshDateGroupControls()
        refreshFilterControls()
        refreshPreview()
    }

    private func removeFieldFromLayout(_ index: Int, from zone: PivotDropZone) {
        switch zone {
        case .rows:
            layout.rows.removeAll { $0 == index }
        case .columns:
            layout.columns.removeAll { $0 == index }
        case .values:
            if layout.measures.contains(where: { $0.id == index }) {
                layout.measures.removeAll { $0.id == index }
            } else {
                layout.measures.removeAll { $0.fieldIndex == index }
            }
        case .filters:
            layout.filters.removeAll { $0 == index }
            layout.filterSelections.removeValue(forKey: index)
        }
        cleanupDateGroupingIfUnused(for: index)
    }

    private func insertUnique(_ index: Int, into target: inout [Int], at position: Int?) {
        guard !target.contains(index) else { return }
        let insertionIndex = min(max(0, position ?? target.count), target.count)
        target.insert(index, at: insertionIndex)
    }

    private func makeMeasure(fieldIndex: Int) -> PivotMeasure {
        let measure = PivotMeasure(
            id: nextMeasureID,
            fieldIndex: fieldIndex,
            function: defaultAggregationFunction(for: fieldIndex)
        )
        nextMeasureID += 1
        return measure
    }

    private func insertMeasure(_ measure: PivotMeasure, at position: Int?) {
        let insertionIndex = min(max(0, position ?? layout.measures.count), layout.measures.count)
        layout.measures.insert(sanitizedMeasure(measure), at: insertionIndex)
    }

    private func moveAssignedField(
        _ index: Int,
        from sourceZone: PivotDropZone,
        to targetZone: PivotDropZone,
        targetPosition: Int
    ) {
        guard fields.indices.contains(index) else { return }
        if sourceZone == .values, targetZone == .values,
           let sourcePosition = positionOfField(index, in: sourceZone) {
            moveMeasure(from: sourcePosition, to: targetPosition)
            return
        }
        let sourcePosition = positionOfField(index, in: sourceZone)
        var insertionPosition = targetPosition
        if sourceZone == targetZone,
           let sourcePosition,
           sourcePosition < targetPosition {
            insertionPosition -= 1
        }

        assignField(index, to: targetZone, targetPosition: insertionPosition)
    }

    private func handleDroppedField(_ payload: PivotFieldDragPayload, to targetZone: PivotDropZone, targetPosition: Int) {
        if payload.sourceZone == .values,
           targetZone == .values,
           let sourcePosition = payload.sourcePosition {
            moveMeasure(from: sourcePosition, to: targetPosition)
        } else if let sourceZone = payload.sourceZone {
            moveAssignedField(payload.fieldIndex, from: sourceZone, to: targetZone, targetPosition: targetPosition)
        } else {
            assignField(payload.fieldIndex, to: targetZone, targetPosition: targetPosition)
        }
    }

    private func moveMeasure(from sourcePosition: Int, to targetPosition: Int) {
        guard layout.measures.indices.contains(sourcePosition) else { return }
        var insertionPosition = min(max(0, targetPosition), layout.measures.count)
        let measure = layout.measures.remove(at: sourcePosition)
        if sourcePosition < insertionPosition {
            insertionPosition -= 1
        }
        layout.measures.insert(measure, at: min(max(0, insertionPosition), layout.measures.count))
        refreshZones()
        refreshPreview()
    }

    private func moveMeasure(id: Int, offset: Int) {
        guard let sourcePosition = layout.measures.firstIndex(where: { $0.id == id }) else { return }
        let targetPosition = min(max(0, sourcePosition + offset), layout.measures.count - 1)
        guard targetPosition != sourcePosition else { return }
        let measure = layout.measures.remove(at: sourcePosition)
        layout.measures.insert(measure, at: targetPosition)
        refreshZones()
        refreshPreview()
    }

    private func positionOfField(_ index: Int, in zone: PivotDropZone) -> Int? {
        switch zone {
        case .rows:
            return layout.rows.firstIndex(of: index)
        case .columns:
            return layout.columns.firstIndex(of: index)
        case .values:
            return layout.measures.firstIndex { $0.fieldIndex == index }
        case .filters:
            return layout.filters.firstIndex(of: index)
        }
    }

    @discardableResult
    private func ensureDateGroupingDefaultIfNeeded(for index: Int) -> Bool {
        guard isDateField(index), layout.dateGroupings[index] == nil else { return false }
        layout.dateGroupings[index] = .month
        return true
    }

    @discardableResult
    private func ensureDateGroupingDefaultsForAssignedFields() -> Bool {
        var changed = false
        for index in Set(layout.rows + layout.columns + layout.filters) {
            changed = ensureDateGroupingDefaultIfNeeded(for: index) || changed
        }
        return changed
    }

    private func cleanupDateGroupingIfUnused(for index: Int) {
        guard !layout.rows.contains(index),
              !layout.columns.contains(index),
              !layout.filters.contains(index) else { return }
        layout.dateGroupings.removeValue(forKey: index)
    }

    private func isDateField(_ index: Int) -> Bool {
        fields[safe: index]?.valueType == .date
    }

    @discardableResult
    private func removeFieldFromAllZones(_ index: Int) -> Set<Int> {
        var removed: Set<Int> = []
        if layout.rows.contains(index) {
            layout.rows.removeAll { $0 == index }
            removed.insert(index)
        }
        if layout.columns.contains(index) {
            layout.columns.removeAll { $0 == index }
            removed.insert(index)
        }
        if layout.measures.contains(where: { $0.fieldIndex == index }) {
            layout.measures.removeAll { $0.fieldIndex == index }
            removed.insert(index)
        }
        if layout.filters.contains(index) {
            layout.filters.removeAll { $0 == index }
            layout.filterSelections.removeValue(forKey: index)
            removed.insert(index)
        }
        return removed
    }

    @discardableResult
    private func removeFieldFromDimensionZones(_ index: Int) -> Set<Int> {
        var removed: Set<Int> = []
        if layout.rows.contains(index) {
            layout.rows.removeAll { $0 == index }
            removed.insert(index)
        }
        if layout.columns.contains(index) {
            layout.columns.removeAll { $0 == index }
            removed.insert(index)
        }
        if layout.filters.contains(index) {
            layout.filters.removeAll { $0 == index }
            layout.filterSelections.removeValue(forKey: index)
            removed.insert(index)
        }
        return removed
    }

    private func cleanupLayoutStateIfUnassigned(_ index: Int) {
        guard !layout.rows.contains(index),
              !layout.columns.contains(index),
              !layout.measures.contains(where: { $0.fieldIndex == index }),
              !layout.filters.contains(index) else { return }
        layout.dateGroupings.removeValue(forKey: index)
        layout.filterSelections.removeValue(forKey: index)
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

        fieldSearch.placeholderString = L.t("Search fields", "필드 검색")
        fieldSearch.sendsSearchStringImmediately = true
        fieldSearch.target = self
        fieldSearch.action = #selector(fieldSearchChanged(_:))
        fieldSearch.translatesAutoresizingMaskIntoConstraints = false

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
        section.addSubview(fieldSearch)
        section.addSubview(actions)
        section.addSubview(fieldScroll)
        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: section.leadingAnchor),
            title.trailingAnchor.constraint(equalTo: section.trailingAnchor),
            title.topAnchor.constraint(equalTo: section.topAnchor),
            fieldSearch.leadingAnchor.constraint(equalTo: section.leadingAnchor),
            fieldSearch.trailingAnchor.constraint(equalTo: section.trailingAnchor),
            fieldSearch.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 8),
            actions.leadingAnchor.constraint(equalTo: section.leadingAnchor),
            actions.trailingAnchor.constraint(equalTo: section.trailingAnchor),
            actions.topAnchor.constraint(equalTo: fieldSearch.bottomAnchor, constant: 8),
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

        fieldActionButtonOrder = []
        for zone in [PivotDropZone.rows, .columns, .filters, .values] {
            let button = NSButton(title: zone.title, target: self, action: #selector(addSelectedFieldFromButton(_:)))
            button.image = NSImage(systemSymbolName: "plus.circle", accessibilityDescription: zone.title)
            button.imagePosition = .imageLeading
            button.bezelStyle = .rounded
            button.controlSize = .small
            button.tag = Self.tag(for: zone)
            button.toolTip = L.t("Add selected field to \(zone.title)", "선택한 필드를 \(zone.title)에 추가")
            fieldActionButtons[zone] = button
            fieldActionButtonOrder.append(button)
            stack.addArrangedSubview(button)
        }
        return stack
    }

    private func makeDimensionSection() -> NSView {
        let section = NSView()
        section.heightAnchor.constraint(greaterThanOrEqualToConstant: 230).isActive = true

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
        dateGroupControlsStack.orientation = .vertical
        dateGroupControlsStack.spacing = 6
        dateGroupControlsStack.translatesAutoresizingMaskIntoConstraints = false
        firstRow.addArrangedSubview(rows)
        firstRow.addArrangedSubview(columns)

        section.addSubview(title)
        section.addSubview(firstRow)
        section.addSubview(dateGroupControlsStack)
        section.addSubview(filters)
        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: section.leadingAnchor),
            title.trailingAnchor.constraint(equalTo: section.trailingAnchor),
            title.topAnchor.constraint(equalTo: section.topAnchor),
            firstRow.leadingAnchor.constraint(equalTo: section.leadingAnchor),
            firstRow.trailingAnchor.constraint(equalTo: section.trailingAnchor),
            firstRow.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 8),
            firstRow.heightAnchor.constraint(greaterThanOrEqualToConstant: 92),
            dateGroupControlsStack.leadingAnchor.constraint(equalTo: section.leadingAnchor),
            dateGroupControlsStack.trailingAnchor.constraint(equalTo: section.trailingAnchor),
            dateGroupControlsStack.topAnchor.constraint(equalTo: firstRow.bottomAnchor, constant: 8),
            filters.leadingAnchor.constraint(equalTo: section.leadingAnchor),
            filters.trailingAnchor.constraint(equalTo: section.trailingAnchor),
            filters.topAnchor.constraint(equalTo: dateGroupControlsStack.bottomAnchor, constant: 8),
            filters.heightAnchor.constraint(equalTo: rows.heightAnchor),
            filters.bottomAnchor.constraint(equalTo: section.bottomAnchor)
        ])
        refreshDateGroupControls()
        return section
    }

    private func makeMeasureSection() -> NSView {
        let section = NSView()
        section.heightAnchor.constraint(greaterThanOrEqualToConstant: 190).isActive = true

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

        header.addArrangedSubview(title)
        header.addArrangedSubview(spacer)

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
            values.heightAnchor.constraint(greaterThanOrEqualToConstant: 148),
            values.bottomAnchor.constraint(equalTo: section.bottomAnchor)
        ])
        return section
    }

    private func makeDropZone(_ zone: PivotDropZone) -> PivotDropZoneView {
        let view = PivotDropZoneView(zone: zone) { [weak self] payload, zone, targetPosition in
            self?.handleDroppedField(payload, to: zone, targetPosition: targetPosition)
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
        filterControlsStack.orientation = .vertical
        filterControlsStack.spacing = 6
        filterControlsStack.translatesAutoresizingMaskIntoConstraints = true
        resultPane.addSubview(filterControlsStack)
        resultPane.addSubview(previewContainer)
        configurePreviewContainer()
        previewContainer.translatesAutoresizingMaskIntoConstraints = true
        resultPane.setContent(header: header, filters: filterControlsStack, preview: previewContainer)
        refreshFilterControls()
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
        tableResultsStack.orientation = .vertical
        tableResultsStack.alignment = .centerX
        tableResultsStack.distribution = .fill
        tableResultsStack.spacing = 42
        tableResultsStack.edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        tableScroll.documentView = tableResultsStack
        tableScroll.hasVerticalScroller = true
        tableScroll.hasHorizontalScroller = true

        chartResultsStack.orientation = .vertical
        chartResultsStack.alignment = .centerX
        chartResultsStack.distribution = .fill
        chartResultsStack.spacing = 42
        chartScroll.documentView = chartResultsStack
        chartScroll.hasVerticalScroller = true
        chartScroll.hasHorizontalScroller = false

        emptyPreviewLabel.font = .systemFont(ofSize: 13)
        emptyPreviewLabel.textColor = .secondaryLabelColor
        emptyPreviewLabel.alignment = .center
        emptyPreviewLabel.stringValue = L.t(
            "Add a field to Values. Rows and Columns are optional.",
            "값에 필드를 추가하세요. 행과 열은 선택 사항입니다."
        )

        for view in [tableScroll, chartScroll, emptyPreviewLabel] {
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

    @objc private func measureAggregationChanged(_ sender: NSPopUpButton) {
        guard let title = sender.selectedItem?.title,
              let function = AggregationFunction(rawValue: title) else { return }
        setMeasureAggregation(measureID: sender.tag, function: function)
    }

    @objc private func moveMeasureUp(_ sender: NSButton) {
        moveMeasure(id: sender.tag, offset: -1)
    }

    @objc private func moveMeasureDown(_ sender: NSButton) {
        moveMeasure(id: sender.tag, offset: 1)
    }

    @objc private func filterValueChanged(_ sender: NSPopUpButton) {
        let column = sender.tag
        let selected = sender.selectedItem?.representedObject as? String
        setFilterSelection(column: column, value: selected)
    }

    @objc private func dateGroupingChanged(_ sender: NSPopUpButton) {
        guard let period = selectedDatePeriod(in: sender) else { return }
        setDateGrouping(column: sender.tag, period: period)
    }

    @objc private func fieldDoubleClicked(_ sender: NSTableView) {
        addSelectedFieldToDefaultZone()
    }

    @objc private func fieldSearchChanged(_ sender: NSSearchField) {
        applyFieldSearch()
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
            title: L.t("Add to Filters", "필터에 추가"),
            action: #selector(addSelectedFieldToFilters(_:)),
            keyEquivalent: ""
        ))
        menu.addItem(NSMenuItem(
            title: L.t("Add to Values", "값에 추가"),
            action: #selector(addSelectedFieldToValues(_:)),
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

    private func setMeasureAggregation(column: Int, function: AggregationFunction) {
        guard let measure = layout.measures.first(where: { $0.fieldIndex == column }) else { return }
        setMeasureAggregation(measureID: measure.id, function: function)
    }

    private func setMeasureAggregation(measureID: Int, function: AggregationFunction) {
        guard let index = layout.measures.firstIndex(where: { $0.id == measureID }) else { return }
        let fieldIndex = layout.measures[index].fieldIndex
        guard allowedAggregationFunctions(for: fieldIndex).contains(function) else { return }
        layout.measures[index].function = function
        refreshZones()
        refreshPreview()
    }

    private func allowedAggregationFunctions(for fieldIndex: Int) -> [AggregationFunction] {
        switch fields[safe: fieldIndex]?.valueType {
        case .integer, .float:
            return [.count, .sum, .mean, .median, .min, .max, .standardDeviation, .uniqueCount]
        case .categorical, .string, .date, .boolean, .empty:
            return [.count, .uniqueCount]
        case nil:
            return [.count, .sum, .mean, .median, .min, .max, .standardDeviation, .uniqueCount]
        }
    }

    private func defaultAggregationFunction(for fieldIndex: Int) -> AggregationFunction {
        allowedAggregationFunctions(for: fieldIndex).first ?? .count
    }

    private func sanitizedMeasure(_ measure: PivotMeasure) -> PivotMeasure {
        guard allowedAggregationFunctions(for: measure.fieldIndex).contains(measure.function) else {
            return PivotMeasure(
                id: measure.id,
                fieldIndex: measure.fieldIndex,
                function: defaultAggregationFunction(for: measure.fieldIndex)
            )
        }
        return measure
    }

    private func normalizeMeasureAggregations() {
        layout.measures = layout.measures.map(sanitizedMeasure)
    }

    private func setFilterSelection(column: Int, value: String?) {
        guard layout.filters.contains(column) else { return }
        if let value {
            layout.filterSelections[column] = value
        } else {
            layout.filterSelections.removeValue(forKey: column)
        }
        refreshZones()
        refreshFilterControls()
        refreshPreview()
    }

    private func setDateGrouping(column: Int, period: DateBinPeriod) {
        guard isDateField(column) else { return }
        let previous = layout.dateGroupings[column]
        layout.dateGroupings[column] = period
        if previous != period {
            layout.filterSelections.removeValue(forKey: column)
        }
        refreshZones()
        refreshDateGroupControls()
        refreshFilterControls()
        refreshPreview()
    }

    private func selectedField() -> PivotField? {
        fieldForVisibleRow(fieldTable.selectedRow)
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

    private func applyFieldSearch() {
        let query = fieldSearch.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            filteredFieldIndexes = Array(fields.indices)
        } else {
            filteredFieldIndexes = fields.indices.filter { index in
                let field = fields[index]
                return field.name.localizedCaseInsensitiveContains(query)
                    || (field.typeHint?.localizedCaseInsensitiveContains(query) ?? false)
            }
        }
        fieldTable.reloadData()
        fieldTable.deselectAll(nil)
        updateFieldActionButtons()
    }

    private func fieldForVisibleRow(_ row: Int) -> PivotField? {
        guard let fieldIndex = filteredFieldIndexes[safe: row] else { return nil }
        return fields[safe: fieldIndex]
    }

    private func refreshZones() {
        zoneViews[.rows]?.setFieldItems(layout.rows.compactMap { fieldItem(for: $0, zone: .rows) })
        zoneViews[.columns]?.setFieldItems(layout.columns.compactMap { fieldItem(for: $0, zone: .columns) })
        measureAggregationPopups = [:]
        measureMoveButtons = [:]
        zoneViews[.values]?.setFieldItems(layout.measures.enumerated().compactMap { position, measure in
            guard fields.indices.contains(measure.fieldIndex) else { return nil }
            return (
                index: measure.fieldIndex,
                name: fields[measure.fieldIndex].name,
                removable: true,
                accessory: makeMeasureAccessory(for: measure, position: position),
                removeID: measure.id
            )
        })
        zoneViews[.filters]?.setFieldItems(layout.filters.compactMap { fieldItem(for: $0, zone: .filters) })
    }

    private func makeMeasureAccessory(for measure: PivotMeasure, position: Int) -> NSView {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 4
        stack.addArrangedSubview(makeMeasureAggregationPopup(for: measure))
        let up = makeMeasureMoveButton(
            symbolName: "chevron.up",
            tooltip: L.t("Move measure up", "측정값 위로 이동"),
            action: #selector(moveMeasureUp(_:)),
            measure: measure,
            isEnabled: position > 0
        )
        let down = makeMeasureMoveButton(
            symbolName: "chevron.down",
            tooltip: L.t("Move measure down", "측정값 아래로 이동"),
            action: #selector(moveMeasureDown(_:)),
            measure: measure,
            isEnabled: position < layout.measures.count - 1
        )
        stack.addArrangedSubview(up)
        stack.addArrangedSubview(down)
        measureMoveButtons[measure.id] = [up, down]
        return stack
    }

    private func makeMeasureAggregationPopup(for measure: PivotMeasure) -> NSPopUpButton {
        let popup = NSPopUpButton()
        popup.controlSize = .small
        popup.tag = measure.id
        popup.target = self
        popup.action = #selector(measureAggregationChanged(_:))
        popup.addItems(withTitles: allowedAggregationFunctions(for: measure.fieldIndex).map(\.rawValue))
        popup.selectItem(withTitle: measure.function.rawValue)
        popup.widthAnchor.constraint(equalToConstant: 132).isActive = true
        measureAggregationPopups[measure.id] = popup
        return popup
    }

    private func makeMeasureMoveButton(
        symbolName: String,
        tooltip: String,
        action: Selector,
        measure: PivotMeasure,
        isEnabled: Bool
    ) -> NSButton {
        let button = NSButton()
        button.title = ""
        button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: tooltip)
        button.imageScaling = .scaleProportionallyDown
        button.bezelStyle = .inline
        button.isBordered = false
        button.tag = measure.id
        button.target = self
        button.action = action
        button.toolTip = tooltip
        button.isEnabled = isEnabled
        button.widthAnchor.constraint(equalToConstant: 18).isActive = true
        button.heightAnchor.constraint(equalToConstant: 18).isActive = true
        return button
    }

    private func refreshDateGroupControls() {
        dateGroupControlsStack.arrangedSubviews.forEach { view in
            dateGroupControlsStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        dateDimensionGroupPopups = [:]

        let indexes = orderedUnique(layout.rows + layout.columns).filter(isDateField)
        dateGroupControlsStack.isHidden = indexes.isEmpty
        for index in indexes {
            dateGroupControlsStack.addArrangedSubview(makeDateDimensionControlRow(for: index))
        }
    }

    private func makeDateDimensionControlRow(for index: Int) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 6

        let label = NSTextField(labelWithString: L.t("Group \(fields[index].name) by", "\(fields[index].name) 그룹"))
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.lineBreakMode = .byTruncatingTail
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let popup = makeDateGroupingPopup(for: index)
        dateDimensionGroupPopups[index] = popup

        row.addArrangedSubview(label)
        row.addArrangedSubview(popup)
        return row
    }

    private func fieldItem(for index: Int, zone: PivotDropZone) -> (index: Int, name: String, removable: Bool)? {
        guard fields.indices.contains(index) else { return nil }
        return (index: index, name: assignedFieldTitle(index, zone: zone), removable: true)
    }

    private func assignedFieldTitle(_ index: Int, zone: PivotDropZone) -> String {
        guard let field = fields[safe: index] else { return L.t("Field", "필드") }
        var title = field.name
        if isDateField(index), let period = layout.dateGroupings[index] {
            title += " (\(period.rawValue))"
        }
        if zone == .filters {
            let selected = layout.filterSelections[index] ?? L.t("All", "전체")
            title += ": \(selected)"
        }
        return title
    }

    private func refreshFilterControls() {
        filterControlsStack.arrangedSubviews.forEach { view in
            filterControlsStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        filterValuePopups = [:]
        filterDateGroupPopups = [:]
        filterControlsStack.isHidden = layout.filters.isEmpty

        for index in layout.filters {
            guard fields.indices.contains(index) else { continue }
            filterControlsStack.addArrangedSubview(makeFilterControlRow(for: index))
        }
        resultPane.needsLayout = true
    }

    private func makeFilterControlRow(for index: Int) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 6

        let label = NSTextField(labelWithString: fields[index].name)
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.lineBreakMode = .byTruncatingTail
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        row.addArrangedSubview(label)

        if isDateField(index) {
            let groupingPopup = makeDateGroupingPopup(for: index)
            filterDateGroupPopups[index] = groupingPopup
            row.addArrangedSubview(groupingPopup)
        }

        let valuePopup = NSPopUpButton()
        valuePopup.controlSize = .small
        valuePopup.tag = index
        valuePopup.target = self
        valuePopup.action = #selector(filterValueChanged(_:))
        valuePopup.widthAnchor.constraint(greaterThanOrEqualToConstant: 120).isActive = true
        valuePopup.addItem(withTitle: L.t("All", "전체"))
        valuePopup.lastItem?.representedObject = nil
        let selectedValue = layout.filterSelections[index]
        var selectedIndex = 0
        for option in filterOptions(for: index) {
            valuePopup.addItem(withTitle: option.isEmpty ? L.t("(Blank)", "(빈 값)") : option)
            valuePopup.lastItem?.representedObject = option
            if option == selectedValue {
                selectedIndex = valuePopup.numberOfItems - 1
            }
        }
        valuePopup.selectItem(at: selectedIndex)
        filterValuePopups[index] = valuePopup
        row.addArrangedSubview(valuePopup)
        return row
    }

    private func makeDateGroupingPopup(for index: Int) -> NSPopUpButton {
        let popup = NSPopUpButton()
        popup.controlSize = .small
        popup.tag = index
        popup.target = self
        popup.action = #selector(dateGroupingChanged(_:))
        for period in [DateBinPeriod.year, .month, .day] {
            popup.addItem(withTitle: period.rawValue)
            popup.lastItem?.representedObject = period.rawValue
        }
        popup.selectItem(withTitle: (layout.dateGroupings[index] ?? .month).rawValue)
        return popup
    }

    private func filterOptions(for index: Int) -> [String] {
        do {
            return try csvDocument.pivotFilterValues(
                column: index,
                dateGrouping: layout.dateGroupings[index],
                cancellation: CancellationFlag()
            )
        } catch {
            return []
        }
    }

    private func selectedDatePeriod(in popup: NSPopUpButton) -> DateBinPeriod? {
        guard let rawValue = popup.selectedItem?.representedObject as? String else { return nil }
        return DateBinPeriod(rawValue: rawValue)
    }

    private func orderedUnique(_ values: [Int]) -> [Int] {
        var seen: Set<Int> = []
        var output: [Int] = []
        for value in values where !seen.contains(value) {
            seen.insert(value)
            output.append(value)
        }
        return output
    }

    private func refreshPreview() {
        previewCancellation?.cancel()
        previewGeneration += 1
        let generation = previewGeneration

        guard layout.isRunnable else {
            previewIsComputing = false
            previewCancellation = nil
            pivot = nil
            previewSections = []
            previewHeaders = []
            previewRows = []
            rebuildPreviewSections()
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
        let filters = layout.filterSelections.map { PivotFilter(column: $0.key, selectedValue: $0.value) }
        let dateGroupings = layout.dateGroupings
        let measures = layout.measures
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let results = try measures.map { measure in
                    let result = try document.pivotTable(
                        rowColumns: rows,
                        columnColumns: columns,
                        valueColumn: measure.fieldIndex,
                        function: measure.function,
                        filters: filters,
                        dateGroupings: dateGroupings,
                        cancellation: cancellation
                    )
                    return (measure: measure, result: result)
                }
                DispatchQueue.main.async { [weak self] in
                    guard let self,
                          self.previewGeneration == generation,
                          self.previewCancellation === cancellation else { return }
                    self.previewIsComputing = false
                    self.applyPreview(results)
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
                    self.previewSections = []
                    self.previewHeaders = []
                    self.previewRows = []
                    self.rebuildPreviewSections()
                    self.chartView.update(model: nil)
                    self.resultSummaryLabel.stringValue = L.t("Error", "오류")
                    self.emptyPreviewLabel.stringValue = error.localizedDescription
                    self.updatePreviewVisibility()
                }
            }
        }
    }

    private func applyPreview(_ results: [(measure: PivotMeasure, result: PivotTableResult)]) {
        previewSections = results.map { makePreviewSection(result: $0.result, measure: $0.measure) }
        pivot = previewSections.first?.pivot
        previewHeaders = previewSections.first?.headers ?? []
        previewRows = previewSections.first?.rows ?? []

        rebuildPreviewSections()
        chartView.update(model: previewSections.first?.chartModel)
        let rowCount = previewSections.reduce(0) { $0 + $1.rows.count }
        let sectionCount = previewSections.count
        resultSummaryLabel.stringValue = L.t(
            "\(sectionCount.formatted()) measures, \(rowCount.formatted()) rows",
            "\(sectionCount.formatted())개 측정값, \(rowCount.formatted())행"
        )
        updatePreviewVisibility()
    }

    private func makePreviewSection(result: PivotTableResult, measure: PivotMeasure) -> PivotPreviewSection {
        let valueHeader = measureTitle(measure)
        let headers: [String]
        let rows: [[String]]
        if result.rowColumns.isEmpty, result.columnColumns.isEmpty {
            headers = [L.t("Metric", "지표"), valueHeader]
            rows = [[L.t("Total", "합계"), Self.formatNumber(result.value(row: [], column: []))]]
        } else if result.columnColumns.isEmpty {
            headers = [rowHeaderTitle(), valueHeader]
            var bodyRows = result.rowKeys.map { rowKey in
                [Self.label(rowKey, fallback: L.t("Total", "합계")), Self.formatNumber(result.value(row: rowKey, column: []))]
            }
            bodyRows.append([
                L.t("Total", "합계"),
                Self.formatNumber(result.rowKeys.reduce(0) { $0 + result.value(row: $1, column: []) })
            ])
            rows = bodyRows
        } else {
            let hasRows = !result.rowColumns.isEmpty
            let rowHeader = hasRows ? rowHeaderTitle() : ""
            headers = [rowHeader]
                + result.columnKeys.map { Self.label($0, fallback: L.t("Total", "합계")) }
                + [L.t("Total", "합계")]
            let rowKeys = hasRows ? result.rowKeys : [[]]
            var bodyRows = rowKeys.map { rowKey in
                let values = result.columnKeys.map { result.value(row: rowKey, column: $0) }
                return [Self.label(rowKey, fallback: L.t("Total", "합계"))]
                    + values.map(Self.formatNumber)
                    + [Self.formatNumber(values.reduce(0, +))]
            }
            if hasRows {
                let columnTotals = result.columnKeys.map { columnKey in
                    rowKeys.reduce(0) { $0 + result.value(row: $1, column: columnKey) }
                }
                bodyRows.append(
                    [L.t("Total", "합계")]
                        + columnTotals.map(Self.formatNumber)
                        + [Self.formatNumber(columnTotals.reduce(0, +))]
                )
            }
            rows = bodyRows
        }
        return PivotPreviewSection(
            title: valueHeader,
            measure: measure,
            pivot: result,
            headers: headers,
            rows: rows,
            chartModel: PivotChartModel.make(from: result)
        )
    }

    private func rowHeaderTitle() -> String {
        let title = layout.rows.map { assignedFieldTitle($0, zone: .rows) }.joined(separator: " | ")
        return title.isEmpty ? L.t("Total", "합계") : title
    }

    private func measureTitle(_ measure: PivotMeasure) -> String {
        let valueName = fields[safe: measure.fieldIndex]?.name ?? L.t("Value", "값")
        return "\(measure.function.rawValue) of \(valueName)"
    }

    private static func label(_ key: [String], fallback: String) -> String {
        let joined = key.joined(separator: " | ")
        return joined.isEmpty ? fallback : joined
    }

    private func rebuildPreviewSections() {
        for column in tablePreview.tableColumns {
            tablePreview.removeTableColumn(column)
        }
        tableResultsStack.arrangedSubviews.forEach { view in
            tableResultsStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        chartResultsStack.arrangedSubviews.forEach { view in
            chartResultsStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        for (index, header) in previewHeaders.enumerated() {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("pivot_\(index)"))
            column.title = header
            column.width = index == 0 ? 160 : 110
            tablePreview.addTableColumn(column)
        }
        tablePreview.reloadData()

        for (index, section) in previewSections.enumerated() {
            tableResultsStack.addArrangedSubview(makeTableSectionView(section))
            chartResultsStack.addArrangedSubview(makeChartSectionView(section, reusePrimaryChart: index == 0))
        }
        sizePreviewDocumentViews()
    }

    private func updatePreviewVisibility() {
        let hasPreview = !previewSections.isEmpty
        emptyPreviewLabel.isHidden = hasPreview
        tableScroll.isHidden = !hasPreview || previewTabs.selectedSegment != 0
        chartScroll.isHidden = !hasPreview || previewTabs.selectedSegment != 1
        sizePreviewDocumentViews()
    }

    private func makeTableSectionView(_ section: PivotPreviewSection) -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 6

        let title = NSTextField(labelWithString: section.title)
        title.font = .systemFont(ofSize: 12, weight: .semibold)
        title.textColor = .labelColor
        stack.addArrangedSubview(title)

        let allRows = [section.headers] + section.rows
        let gridRows = allRows.map { row in
            row.map { value -> NSView in
                let label = NSTextField(labelWithString: value)
                label.font = .systemFont(ofSize: 12)
                label.lineBreakMode = .byTruncatingTail
                label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
                return label
            }
        }
        let grid = NSGridView(views: gridRows)
        grid.rowSpacing = 5
        grid.columnSpacing = 14
        for columnIndex in 0..<(section.headers.count) {
            grid.column(at: columnIndex).xPlacement = columnIndex == 0 ? .leading : .trailing
        }
        for cellIndex in 0..<(section.headers.count) {
            if let label = grid.cell(atColumnIndex: cellIndex, rowIndex: 0).contentView as? NSTextField {
                label.font = .systemFont(ofSize: 12, weight: .semibold)
            }
        }
        stack.addArrangedSubview(grid)
        return stack
    }

    private func makeChartSectionView(_ section: PivotPreviewSection, reusePrimaryChart: Bool) -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 6

        let title = NSTextField(labelWithString: section.title)
        title.font = .systemFont(ofSize: 12, weight: .semibold)
        stack.addArrangedSubview(title)

        let chart = reusePrimaryChart ? chartView : PivotChartView()
        chart.update(model: section.chartModel)
        chart.translatesAutoresizingMaskIntoConstraints = false
        chart.heightAnchor.constraint(equalToConstant: 240).isActive = true
        stack.addArrangedSubview(chart)
        return stack
    }

    private func sizePreviewDocumentViews() {
        let width = max(previewContainer.bounds.width - 2, 320)
        tableResultsStack.frame = NSRect(
            origin: .zero,
            size: NSSize(width: width, height: max(tableResultsStack.fittingSize.height, 1))
        )
        chartResultsStack.frame = NSRect(
            origin: .zero,
            size: NSSize(width: width, height: max(chartResultsStack.fittingSize.height, 1))
        )
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
            tableView === fieldTable ? filteredFieldIndexes.count : previewRows.count
        }
    }

    nonisolated func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        MainActor.assumeIsolated {
            if tableView === fieldTable {
                guard let field = fieldForVisibleRow(row) else { return nil }
                return makeFieldCell(tableView: tableView, field: field)
            }

            let columnIndex = tableView.tableColumns.firstIndex { $0 === tableColumn } ?? 0
            let text = previewRows[safe: row]?[safe: columnIndex] ?? ""
            return makeCell(tableView: tableView, identifier: "pivotCell", text: text)
        }
    }

    nonisolated func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        MainActor.assumeIsolated {
            guard tableView === fieldTable,
                  let field = fieldForVisibleRow(row) else { return nil }
            return PivotFieldDragPayload.pasteboardItem(fieldIndex: field.index)
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

    func setMeasureAggregationForTesting(column: Int, function: AggregationFunction) {
        setMeasureAggregation(column: column, function: function)
    }

    func setMeasureAggregationForTesting(measureAt index: Int, function: AggregationFunction) {
        guard let measure = layout.measures[safe: index] else { return }
        setMeasureAggregation(measureID: measure.id, function: function)
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

    func previewHeadersForTesting(section: Int) -> [String] {
        previewSections[safe: section]?.headers ?? []
    }

    func previewRowForTesting(_ row: Int) -> [String] {
        previewRows[safe: row] ?? []
    }

    func previewRowForTesting(section: Int, row: Int) -> [String] {
        previewSections[safe: section]?.rows[safe: row] ?? []
    }

    var previewSectionCountForTesting: Int {
        previewSections.count
    }

    var previewSectionTitlesForTesting: [String] {
        previewSections.map(\.title)
    }

    var measureAggregationControlCountForTesting: Int {
        measureAggregationPopups.count
    }

    func measureAggregationOptionTitlesForTesting(measureAt index: Int) -> [String] {
        guard let measure = layout.measures[safe: index],
              let popup = measureAggregationPopups[measure.id] else { return [] }
        return popup.itemArray.map(\.title)
    }

    var measureMoveControlCountForTesting: Int {
        measureMoveButtons.values.reduce(0) { $0 + $1.count }
    }

    func measureRowControlsAreOrderedForTesting(measureAt index: Int) -> Bool {
        guard let measure = layout.measures[safe: index],
              let popup = measureAggregationPopups[measure.id],
              let buttons = measureMoveButtons[measure.id],
              buttons.count == 2,
              let accessory = popup.superview as? NSStackView else { return false }
        return accessory.arrangedSubviews.count == 3
            && accessory.arrangedSubviews[0] === popup
            && accessory.arrangedSubviews[1] === buttons[0]
            && accessory.arrangedSubviews[2] === buttons[1]
    }

    func moveMeasureDownForTesting(measureAt index: Int) {
        guard let measure = layout.measures[safe: index] else { return }
        moveMeasure(id: measure.id, offset: 1)
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

    var previewTableDocumentHeightForTesting: CGFloat {
        tableResultsStack.frame.height
    }

    var previewTableSectionGapForTesting: CGFloat {
        let sections = tableResultsStack.arrangedSubviews
        guard sections.count >= 2 else { return 0 }
        let first = sections[0].frame
        let second = sections[1].frame
        if first.minY >= second.maxY {
            return first.minY - second.maxY
        }
        if second.minY >= first.maxY {
            return second.minY - first.maxY
        }
        return 0
    }

    var previewTableFirstSectionCenterDeltaForTesting: CGFloat {
        guard let first = tableResultsStack.arrangedSubviews.first else { return .greatestFiniteMagnitude }
        return abs(first.frame.midX - tableResultsStack.bounds.midX)
    }

    func dropZoneHeightForTesting(_ zone: PivotDropZone) -> CGFloat {
        zoneViews[zone]?.frame.height ?? 0
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

    var fieldActionButtonTitlesForTesting: [String] {
        fieldActionButtonOrder.map(\.title)
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

    func moveAssignedFieldForTesting(
        _ index: Int,
        from sourceZone: PivotDropZone,
        to targetZone: PivotDropZone,
        targetPosition: Int
    ) {
        moveAssignedField(index, from: sourceZone, to: targetZone, targetPosition: targetPosition)
    }

    func setFilterSelectionForTesting(column: Int, value: String?) {
        setFilterSelection(column: column, value: value)
    }

    func setDateGroupingForTesting(column: Int, period: DateBinPeriod) {
        setDateGrouping(column: column, period: period)
    }

    var dateDimensionGroupingControlCountForTesting: Int {
        dateDimensionGroupPopups.count
    }

    var resultFilterControlCountForTesting: Int {
        filterValuePopups.count
    }

    var resultPaneContainsFilterControlsForTesting: Bool {
        filterControlsStack.isDescendant(of: resultPane)
    }

    var controlPaneContainsFilterControlsForTesting: Bool {
        filterControlsStack.isDescendant(of: controlPane)
    }

    func selectDateGroupingPopupForTesting(column: Int, period: DateBinPeriod) {
        guard let popup = dateDimensionGroupPopups[column] ?? filterDateGroupPopups[column] else { return }
        popup.selectItem(withTitle: period.rawValue)
        dateGroupingChanged(popup)
    }

    func setFieldSearchTextForTesting(_ text: String) {
        fieldSearch.stringValue = text
        applyFieldSearch()
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
    private weak var filtersView: NSView?
    private weak var previewView: NSView?

    func setContent(header: NSView, filters: NSView, preview: NSView) {
        headerView = header
        filtersView = filters
        previewView = preview
        needsLayout = true
    }

    override func layout() {
        super.layout()

        let margin: CGFloat = 12
        let spacing: CGFloat = 10
        let headerHeight = max(28, headerView?.fittingSize.height ?? 28)
        let filtersVisible = !(filtersView?.isHidden ?? true)
        let filtersHeight = filtersVisible ? max(30, filtersView?.fittingSize.height ?? 30) : 0
        let filtersSpacing = filtersVisible ? spacing : 0
        let usableWidth = max(0, bounds.width - margin * 2)
        let previewHeight = max(0, bounds.height - margin * 2 - spacing - headerHeight - filtersSpacing - filtersHeight)

        let headerY = bounds.height - margin - headerHeight
        headerView?.frame = NSRect(
            x: margin,
            y: headerY,
            width: usableWidth,
            height: headerHeight
        )
        if filtersVisible {
            filtersView?.frame = NSRect(
                x: margin,
                y: headerY - spacing - filtersHeight,
                width: usableWidth,
                height: filtersHeight
            )
        } else {
            filtersView?.frame = NSRect(x: margin, y: headerY - spacing, width: usableWidth, height: 0)
        }
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
