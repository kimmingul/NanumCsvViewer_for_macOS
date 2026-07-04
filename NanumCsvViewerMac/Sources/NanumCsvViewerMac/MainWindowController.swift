import AppKit
import UniformTypeIdentifiers
@preconcurrency import CsvCore

private extension NSUserInterfaceItemIdentifier {
    static let analysisPromptRow = NSUserInterfaceItemIdentifier("analysisPromptRow")
    static let analysisPromptRunButton = NSUserInterfaceItemIdentifier("analysisPromptRunButton")
    static let analysisPromptCancelButton = NSUserInterfaceItemIdentifier("analysisPromptCancelButton")
}

@MainActor
private final class AnalysisPromptPanel: NSPanel {
    var runHandler: (() -> Void)?

    @objc func run(_ sender: Any?) {
        runHandler?()
    }

    @objc func cancel(_ sender: Any?) {
        sheetParent?.endSheet(self, returnCode: .cancel)
        orderOut(nil)
    }
}

private struct AnalysisPromptSheet {
    let panel: AnalysisPromptPanel
    let buildRequest: () -> AnalysisRequest?
}

#if DEBUG
struct AnalysisPromptLayoutMetrics {
    let windowSize: NSSize
    let rowCount: Int
    let minimumPopupWidth: CGFloat
    let runButtonSize: NSSize
    let cancelButtonSize: NSSize
}
#endif

#if DEBUG
private extension NSView {
    var allDescendantsForTesting: [NSView] {
        subviews + subviews.flatMap(\.allDescendantsForTesting)
    }
}
#endif

@MainActor
final class MainWindowController: NSWindowController {
    private static let persistentIndexDefaultsKey = "NanumCsvViewerMac.PersistentIndexEnabled"
    private static let deleteIndexCacheOnCloseDefaultsKey = "NanumCsvViewerMac.DeleteIndexCacheOnClose"
    private static let hiddenColumnsDefaultsKey = "NanumCsvViewerMac.HiddenColumnIndexes"
    private static let facetsVisibleDefaultsKey = "NanumCsvViewerMac.FacetsPanelVisible"
    private static let inspectorVisibleDefaultsKey = "NanumCsvViewerMac.InspectorVisible"
    private static let savedViewStoreDefaultsKey = "NanumCsvViewerMac.SavedViewStore"
    private static let autoRestoreViewDefaultsKey = "NanumCsvViewerMac.AutoRestoreView"
    private static let rowDensityDefaultsKey = "NanumCsvViewerMac.RowDensity"
    private static var facetRowCap: Int { VirtualCsvDocument.analysisRowLimit }
    private static let facetColumnLimit = 24
    private static let savedViewsDefaultsKey = "NanumCsvViewerMac.SavedViewsByPath"
    private static let tableCellPreviewLimit = 512
    private static let earlyColumnStatisticsRowThreshold = 200
    private static let analysisPromptPanelWidth: CGFloat = 600
    private static let analysisPromptContentWidth: CGFloat = 540
    private static let analysisPromptLabelWidth: CGFloat = 150
    private static let analysisPromptPopupWidth: CGFloat = 340
    private static let analysisPromptButtonWidth: CGFloat = 96

    private let tableView = CsvTableView()
    private let scrollView = NSScrollView()
    private let selectedValueBar = NSVisualEffectView()
    private let selectedAddressLabel = NSTextField(labelWithString: "")
    private let selectedValueExpandButton = NSButton()
    private let selectedValueTextView = NSTextView()
    private let selectedValueScrollView = NSScrollView()
    private let detailHeaderLabel = NSTextField(labelWithString: L.t("Inspector", "인스펙터"))
    private let detailTextView = NSTextView()
    private let inspectorActionBar = NSStackView()
    private let inspectorCopyTextButton = NSButton()
    private let inspectorCopyJsonButton = NSButton()
    private let analysisActionBar = NSStackView()
    private let analysisCopyButton = NSButton()
    private let analysisExportButton = NSButton()
    private let analysisCancelButton = NSButton()
    private let statusLabel = NSTextField(labelWithString: L.t("Open a CSV or text file.", "CSV 또는 텍스트 파일을 여세요."))
    private let documentInfoLabel = NSTextField(labelWithString: L.t("No file", "파일 없음"))
    private let storageModeLabel = NSTextField(labelWithString: "")
    private let progressLabel = NSTextField(labelWithString: "")
    private let progressIndicator = NSProgressIndicator()
    private let signalDot = SignalDotView()
    private let signalLabel = NSTextField(labelWithString: L.t("Idle", "대기"))
    private let findField = NSSearchField()
    private let filterField = NSSearchField()
    private let filterColumnPopup = NSPopUpButton()
    private let encodingPopup = NSPopUpButton()
    private let detailToggleButton = NSButton()
    private let filterToggleButton = NSButton()
    private let sortControl = NSSegmentedControl(labels: ["", "", ""], trackingMode: .momentary, target: nil, action: nil)
    private let filterByCellButton = NSButton()
    private let applyFilterButton = NSButton()
    private let clearFilterButton = NSButton()
    private let findNextButton = NSButton()
    private var closeToolbarItem: NSToolbarItem?
    private var pivotToolbarItem: NSToolbarItem?
    private let mainSplit = NSSplitView()
    private let contentContainer = CsvDropView()
    private let filterBarView = FilterBarView()
    private let filterTokensStack = NSStackView()
    private let emptyStateView = CsvDropView()
    private let detailPanel = NSView()
    private var selectedValueBarHeightConstraint: NSLayoutConstraint?
    private var selectedValueScrollHeightConstraint: NSLayoutConstraint?
    private var selectedValueExpanded = false
    private var didSetInitialSplit = false
    private var preferredInspectorWidth: CGFloat = 360

    private var csvDocument: VirtualCsvDocument?
    private var indexCancellation: CancellationFlag?
    private var operationCancellation: CancellationFlag?
    private var findCancellation: CancellationFlag?
    private var prefetchCancellation: CancellationFlag?
    private var columnFilterValuesCancellation: CancellationFlag?
    private var rowTimer: Timer?
    private var lastKnownRowCount = 0
    private var lastHighlightedRows = IndexSet()
    private var busy = false
    private var indexing = false
    private var indexingElapsed: TimeInterval?
    private var currentDataColumn = 0
    private var columnNames: [String] = []
    private var sortKeys: [SortKey] = []
    private var textCondition: (@Sendable ([String]) -> Bool)?
    private var textConditionDescription = ""
    private var textFilterTerm = ""
    private var textFilterColumn = -1
    private var columnFilterState = ColumnFilterState()
    private var gridSelection = GridSelectionModel()
    private var columnFilterPopover: NSPopover?
    private let facetsPanel = FacetsPanelView()
    private var facetsWidthConstraint: NSLayoutConstraint?
    private var facetsCancellation: CancellationFlag?
    private var facetRefreshWorkItem: DispatchWorkItem?
    private var facetGeneration = 0
    private var detailUpdateWorkItem: DispatchWorkItem?
    private var columnStatisticsReport: ColumnStatisticsReport?
    private var baseColumnStatisticsReport: ColumnStatisticsReport?
    private var columnTypeOverrides: [Int: ColumnValueType] = [:]
    private var columnStatisticsCancellation: CancellationFlag?
    private var analysisCancellation: CancellationFlag?
    private var currentAnalysisReport: AnalysisReport?
    private var currentInspectorContentKind: InspectorContentKind = .empty
    private var gridColumnBaseWidths: [NSUserInterfaceItemIdentifier: CGFloat] = [:]
    private var applyingGridLayout = false
    private var gridLayoutPassCount = 0
    private var earlyColumnStatisticsRequested = false
    private var acceptedColumnStatisticsPriority = 0
    private var hiddenColumnIndexes: Set<Int> = []
    private var currentFilePath: String?
    private var pivotBuilderWindow: PivotBuilderWindowController?
    private var chartWindows: [ChartWindowController] = []
    private var chartCancellation: CancellationFlag?
    private var currentDataQualityReport: DataQualityReport?
    private var dataQualityCancellation: CancellationFlag?
    var openAdditionalFilesHandler: (([URL], NSWindow?) -> Void)?
    var closeHandler: ((MainWindowController) -> Void)?

    private var hasAnyFilter: Bool {
        textCondition != nil || !columnFilterState.isEmpty
    }

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1180, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Nanum CSV Viewer"
        window.titlebarAppearsTransparent = false
        window.tabbingIdentifier = "NanumCsvViewerMac.Documents"
        window.tabbingMode = .preferred
        super.init(window: window)
        VirtualCsvDocument.persistentIndexEnabled = UserDefaults.standard.object(forKey: Self.persistentIndexDefaultsKey) as? Bool ?? true
        VirtualCsvDocument.deletePersistentIndexOnClose = UserDefaults.standard.object(forKey: Self.deleteIndexCacheOnCloseDefaultsKey) as? Bool ?? false
        hiddenColumnIndexes = Set(UserDefaults.standard.array(forKey: Self.hiddenColumnsDefaultsKey) as? [Int] ?? [])
        buildInterface()
        configureToolbar()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func close() {
        cancelAll()
        rowTimer?.invalidate()
        detailUpdateWorkItem?.cancel()
        NotificationCenter.default.removeObserver(self)
        closeHandler?(self)
        super.close()
    }

    private func buildInterface() {
        guard let contentView = window?.contentView else { return }

        let root = NSStackView()
        root.orientation = .vertical
        root.alignment = .width
        root.spacing = 0
        root.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(root)

        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            root.topAnchor.constraint(equalTo: contentView.topAnchor),
            root.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])

        root.addArrangedSubview(makeFilterBar())
        root.addArrangedSubview(makeContentArea())
        root.addArrangedSubview(makeStatusBar())
        root.setVisibilityPriority(.mustHold, for: contentContainer)

        configureTable()
        configureDetailPanel()
        configureEncodingPopup()
        configureEmptyState()
        configureDropTargets()
        setFilterBarVisible(false)
        // The Windows twin shows the detail panel by default on first launch.
        let inspectorVisible = UserDefaults.standard.object(forKey: Self.inspectorVisibleDefaultsKey) as? Bool ?? true
        setInspectorVisible(inspectorVisible, rememberWidth: false, animated: false)
        if UserDefaults.standard.bool(forKey: Self.facetsVisibleDefaultsKey) {
            setFacetsPanelVisible(true, persist: false)
        }
        updateFeatureState()
        refreshSignal()
        updateEmptyState()
    }

    private func configureToolbar() {
        let toolbar = NSToolbar(identifier: "mainToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        toolbar.autosavesConfiguration = false
        window?.toolbarStyle = .unifiedCompact
        window?.titleVisibility = .visible
        window?.toolbar = toolbar
    }

    private func makeFilterBar() -> NSView {
        configureFilterControls()

        let visual = filterBarView
        visual.translatesAutoresizingMaskIntoConstraints = false
        visual.heightAnchor.constraint(equalToConstant: 46).isActive = true

        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 7, left: 12, bottom: 7, right: 12)
        stack.translatesAutoresizingMaskIntoConstraints = false
        visual.addSubview(stack)

        let label = NSTextField(labelWithString: L.t("Filter", "필터"))
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        label.textColor = .secondaryLabelColor

        let actionStack = NSStackView()
        actionStack.orientation = .horizontal
        actionStack.alignment = .centerY
        actionStack.spacing = 5

        stack.addArrangedSubview(label)
        stack.addArrangedSubview(filterColumnPopup)
        stack.addArrangedSubview(filterField)
        actionStack.addArrangedSubview(applyFilterButton)
        actionStack.addArrangedSubview(clearFilterButton)
        actionStack.addArrangedSubview(filterByCellButton)
        stack.addArrangedSubview(actionStack)
        stack.addArrangedSubview(makeFilterBarSeparator())
        stack.addArrangedSubview(filterTokensStack)

        filterTokensStack.orientation = .horizontal
        filterTokensStack.alignment = .centerY
        filterTokensStack.spacing = 4
        filterTokensStack.setContentHuggingPriority(.defaultLow, for: .horizontal)
        filterTokensStack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        stack.addArrangedSubview(spacer)

        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        visual.addSubview(separator)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: visual.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: visual.trailingAnchor),
            stack.topAnchor.constraint(equalTo: visual.topAnchor),
            stack.bottomAnchor.constraint(equalTo: visual.bottomAnchor),
            separator.leadingAnchor.constraint(equalTo: visual.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: visual.trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: visual.bottomAnchor)
        ])

        return visual
    }

    private func makeFilterBarSeparator() -> NSBox {
        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.heightAnchor.constraint(equalToConstant: 18).isActive = true
        return separator
    }

    private func makeContentArea() -> NSView {
        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        let split = makeMainSplit()
        split.translatesAutoresizingMaskIntoConstraints = false
        emptyStateView.translatesAutoresizingMaskIntoConstraints = false

        contentContainer.addSubview(split)
        contentContainer.addSubview(emptyStateView)

        NSLayoutConstraint.activate([
            split.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            split.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            split.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            split.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor),
            emptyStateView.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            emptyStateView.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            emptyStateView.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            emptyStateView.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor)
        ])

        return contentContainer
    }

    private func makeMainSplit() -> NSView {
        mainSplit.isVertical = true
        mainSplit.dividerStyle = .thin
        mainSplit.delegate = self
        mainSplit.autosaveName = "NanumCsvViewerMac.MainSplit"

        let left = NSStackView()
        left.orientation = .vertical
        left.spacing = 0
        left.setContentHuggingPriority(.defaultLow, for: .horizontal)
        left.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        left.addArrangedSubview(makeSelectedValueBar())
        left.addArrangedSubview(makeGridRowWithFacets())

        detailPanel.wantsLayer = true
        detailPanel.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        detailPanel.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        detailPanel.setContentCompressionResistancePriority(.required, for: .horizontal)
        detailPanel.widthAnchor.constraint(greaterThanOrEqualToConstant: 260).isActive = true
        detailPanel.widthAnchor.constraint(lessThanOrEqualToConstant: 520).isActive = true

        mainSplit.addArrangedSubview(left)
        mainSplit.addArrangedSubview(detailPanel)
        mainSplit.setHoldingPriority(.defaultLow, forSubviewAt: 0)
        mainSplit.setHoldingPriority(.defaultHigh, forSubviewAt: 1)
        DispatchQueue.main.async { [weak self] in
            self?.setInitialSplitPosition()
        }
        return mainSplit
    }

    private func makeGridRowWithFacets() -> NSView {
        let gridRow = NSView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        facetsPanel.translatesAutoresizingMaskIntoConstraints = false
        gridRow.addSubview(scrollView)
        gridRow.addSubview(facetsPanel)

        let widthConstraint = facetsPanel.widthAnchor.constraint(equalToConstant: 0)
        facetsWidthConstraint = widthConstraint
        facetsPanel.isHidden = true
        facetsPanel.selectionHandler = { [weak self] column, kind in
            self?.handleFacetSelection(column: column, kind: kind)
        }

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: gridRow.leadingAnchor),
            scrollView.topAnchor.constraint(equalTo: gridRow.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: gridRow.bottomAnchor),
            facetsPanel.leadingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            facetsPanel.trailingAnchor.constraint(equalTo: gridRow.trailingAnchor),
            facetsPanel.topAnchor.constraint(equalTo: gridRow.topAnchor),
            facetsPanel.bottomAnchor.constraint(equalTo: gridRow.bottomAnchor),
            widthConstraint
        ])
        return gridRow
    }

    private func setInitialSplitPosition() {
        guard !didSetInitialSplit, mainSplit.arrangedSubviews.count == 2, mainSplit.bounds.width > 0 else { return }
        didSetInitialSplit = true
        restoreInspectorWidth(animated: false)
    }

    private var isInspectorVisible: Bool {
        mainSplit.arrangedSubviews.contains { $0 === detailPanel } && !detailPanel.isHidden
    }

    private func setInspectorVisible(_ visible: Bool, rememberWidth: Bool = true, animated: Bool = false) {
        if visible {
            guard !isInspectorVisible else { return }
            if !mainSplit.arrangedSubviews.contains(where: { $0 === detailPanel }) {
                mainSplit.addArrangedSubview(detailPanel)
                mainSplit.setHoldingPriority(.defaultHigh, forSubviewAt: mainSplit.arrangedSubviews.count - 1)
            }
            detailPanel.isHidden = false
            mainSplit.adjustSubviews()
            DispatchQueue.main.async { [weak self] in
                self?.restoreInspectorWidth(animated: animated)
                self?.updateDetailPanel()
            }
        } else {
            if rememberWidth {
                rememberInspectorWidth()
            }
            detailPanel.isHidden = true
            if mainSplit.arrangedSubviews.contains(where: { $0 === detailPanel }) {
                mainSplit.removeArrangedSubview(detailPanel)
                detailPanel.removeFromSuperview()
            }
            mainSplit.adjustSubviews()
        }
        detailToggleButton.state = visible ? .on : .off
    }

    private func rememberInspectorWidth() {
        guard isInspectorVisible, detailPanel.frame.width > 0 else { return }
        preferredInspectorWidth = clampedInspectorWidth(detailPanel.frame.width)
    }

    private func restoreInspectorWidth(animated: Bool) {
        guard mainSplit.arrangedSubviews.count == 2, mainSplit.bounds.width > 0 else { return }
        let width = clampedInspectorWidth(preferredInspectorWidth)
        let position = max(520, mainSplit.bounds.width - width)
        let updates = {
            self.mainSplit.setPosition(position, ofDividerAt: 0)
            self.mainSplit.layoutSubtreeIfNeeded()
        }
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.16
                updates()
            }
        } else {
            updates()
        }
    }

    private func clampedInspectorWidth(_ width: CGFloat) -> CGFloat {
        let available = max(280, mainSplit.bounds.width - 520)
        let maximum = min(520, available)
        return min(max(width, 280), maximum)
    }

    private func makeSelectedValueBar() -> NSView {
        let bar = selectedValueBar
        bar.material = .contentBackground
        bar.blendingMode = .withinWindow
        bar.state = .active
        bar.translatesAutoresizingMaskIntoConstraints = false
        bar.isHidden = true
        let height = bar.heightAnchor.constraint(equalToConstant: 34)
        selectedValueBarHeightConstraint = height
        height.isActive = true

        selectedAddressLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        selectedAddressLabel.textColor = .secondaryLabelColor
        selectedAddressLabel.alignment = .right
        selectedAddressLabel.translatesAutoresizingMaskIntoConstraints = false

        selectedValueTextView.isEditable = false
        selectedValueTextView.isSelectable = true
        selectedValueTextView.drawsBackground = false
        selectedValueTextView.font = .systemFont(ofSize: 13, weight: .regular)
        selectedValueTextView.textColor = .labelColor
        selectedValueTextView.textContainerInset = NSSize(width: 2, height: 3)
        selectedValueTextView.textContainer?.widthTracksTextView = true
        selectedValueTextView.isVerticallyResizable = true
        selectedValueScrollView.documentView = selectedValueTextView
        selectedValueScrollView.hasVerticalScroller = false
        selectedValueScrollView.autohidesScrollers = true
        selectedValueScrollView.drawsBackground = false
        selectedValueScrollView.borderType = .noBorder
        selectedValueScrollView.translatesAutoresizingMaskIntoConstraints = false

        selectedValueExpandButton.title = ""
        selectedValueExpandButton.bezelStyle = .texturedRounded
        selectedValueExpandButton.controlSize = .small
        selectedValueExpandButton.imageScaling = .scaleProportionallyDown
        selectedValueExpandButton.target = self
        selectedValueExpandButton.action = #selector(toggleSelectedValueExpansion(_:))
        selectedValueExpandButton.toolTip = L.t("Expand selected value", "선택값 펼치기")
        selectedValueExpandButton.translatesAutoresizingMaskIntoConstraints = false
        updateSelectedValueExpansionButton()

        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false

        bar.addSubview(selectedAddressLabel)
        bar.addSubview(selectedValueScrollView)
        bar.addSubview(selectedValueExpandButton)
        bar.addSubview(separator)
        let scrollHeight = selectedValueScrollView.heightAnchor.constraint(equalToConstant: 24)
        selectedValueScrollHeightConstraint = scrollHeight
        NSLayoutConstraint.activate([
            selectedAddressLabel.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 10),
            selectedAddressLabel.topAnchor.constraint(equalTo: bar.topAnchor, constant: 8),
            selectedAddressLabel.widthAnchor.constraint(equalToConstant: 170),
            selectedValueScrollView.leadingAnchor.constraint(equalTo: selectedAddressLabel.trailingAnchor, constant: 10),
            selectedValueScrollView.trailingAnchor.constraint(equalTo: selectedValueExpandButton.leadingAnchor, constant: -8),
            selectedValueScrollView.topAnchor.constraint(equalTo: bar.topAnchor, constant: 5),
            scrollHeight,
            selectedValueExpandButton.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -10),
            selectedValueExpandButton.topAnchor.constraint(equalTo: bar.topAnchor, constant: 5),
            selectedValueExpandButton.widthAnchor.constraint(equalToConstant: 28),
            selectedValueExpandButton.heightAnchor.constraint(equalToConstant: 24),
            separator.leadingAnchor.constraint(equalTo: bar.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: bar.trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: bar.bottomAnchor)
        ])
        return bar
    }

    private func makeStatusBar() -> NSView {
        let visual = NSVisualEffectView()
        visual.material = .underWindowBackground
        visual.blendingMode = .withinWindow
        visual.state = .active
        visual.translatesAutoresizingMaskIntoConstraints = false
        visual.setContentHuggingPriority(.defaultLow, for: .horizontal)
        visual.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        visual.heightAnchor.constraint(equalToConstant: 28).isActive = true

        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 3, left: 10, bottom: 3, right: 10)
        stack.translatesAutoresizingMaskIntoConstraints = false
        visual.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: visual.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: visual.trailingAnchor),
            stack.topAnchor.constraint(equalTo: visual.topAnchor),
            stack.bottomAnchor.constraint(equalTo: visual.bottomAnchor)
        ])

        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        stack.addArrangedSubview(statusLabel)

        progressLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        progressLabel.alignment = .right
        progressLabel.widthAnchor.constraint(equalToConstant: 42).isActive = true
        progressLabel.isHidden = true
        stack.addArrangedSubview(progressLabel)

        progressIndicator.isIndeterminate = false
        progressIndicator.minValue = 0
        progressIndicator.maxValue = 100
        progressIndicator.controlSize = .small
        progressIndicator.widthAnchor.constraint(equalToConstant: 150).isActive = true
        progressIndicator.isHidden = true
        stack.addArrangedSubview(progressIndicator)

        stack.addArrangedSubview(makeStatusSeparator())
        configureStatusMetricLabel(documentInfoLabel)
        stack.addArrangedSubview(documentInfoLabel)
        configureStatusMetricLabel(storageModeLabel)
        storageModeLabel.isHidden = true
        stack.addArrangedSubview(storageModeLabel)

        let rightSpacer = NSView()
        rightSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        rightSpacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        stack.addArrangedSubview(rightSpacer)

        encodingPopup.controlSize = .small
        encodingPopup.widthAnchor.constraint(equalToConstant: 136).isActive = true
        stack.addArrangedSubview(encodingPopup)
        stack.addArrangedSubview(signalDot)
        stack.addArrangedSubview(signalLabel)
        return visual
    }

    private func makeStatusSeparator() -> NSBox {
        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.heightAnchor.constraint(equalToConstant: 14).isActive = true
        return separator
    }

    private func configureStatusMetricLabel(_ label: NSTextField) {
        label.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byTruncatingTail
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
    }

    private func configureTable() {
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = false
        scrollView.scrollerStyle = .legacy
        let headerView = CsvTableHeaderView(frame: NSRect(x: 0, y: 0, width: 0, height: 28))
        headerView.filterClickHandler = { [weak self] column, frame in
            self?.showColumnFilterPopover(column: column, relativeTo: frame)
        }
        headerView.headerMenuProvider = { [weak self] column in
            self?.makeColumnHeaderMenu(column: column)
        }
        tableView.headerView = headerView
        tableView.delegate = self
        tableView.dataSource = self
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.gridStyleMask = [.solidHorizontalGridLineMask, .solidVerticalGridLineMask]
        tableView.rowSizeStyle = .custom
        tableView.rowHeight = currentRowDensity.rowHeight
        tableView.allowsMultipleSelection = false
        tableView.allowsColumnResizing = true
        tableView.allowsColumnReordering = true
        tableView.columnAutoresizingStyle = .noColumnAutoresizing
        tableView.doubleAction = #selector(copySelectedCellToPasteboard(_:))
        tableView.target = self
        scrollView.postsFrameChangedNotifications = true
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(tableViewportDidResize(_:)),
            name: NSView.frameDidChangeNotification,
            object: scrollView
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(visibleRowsDidChange(_:)),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )
        tableView.cellHitHandler = { [weak self] hit in
            guard let self else { return }
            handleTableCellHit(hit)
        }
        configureContextMenu()
    }

    private func configureContextMenu() {
        let menu = NSMenu()
        let copy = NSMenuItem(title: L.t("Copy Cell", "셀 복사"), action: #selector(copySelectedCellToPasteboard(_:)), keyEquivalent: "")
        copy.target = self
        menu.addItem(copy)
        let copyCsv = NSMenuItem(title: L.t("Copy as CSV", "CSV로 복사"), action: #selector(copySelectedCellAsCsv(_:)), keyEquivalent: "")
        copyCsv.target = self
        menu.addItem(copyCsv)
        let copyJson = NSMenuItem(title: L.t("Copy as JSON", "JSON으로 복사"), action: #selector(copySelectedCellAsJson(_:)), keyEquivalent: "")
        copyJson.target = self
        menu.addItem(copyJson)
        let copyRow = NSMenuItem(title: L.t("Copy Entire Row", "행 전체 복사"), action: #selector(copyEntireCurrentRow(_:)), keyEquivalent: "")
        copyRow.target = self
        menu.addItem(copyRow)
        let copyColumn = NSMenuItem(title: L.t("Copy Entire Column", "열 전체 복사"), action: #selector(copyEntireCurrentColumn(_:)), keyEquivalent: "")
        copyColumn.target = self
        menu.addItem(copyColumn)
        let filter = NSMenuItem(title: L.t("Filter by This Cell", "이 셀 값으로 필터"), action: #selector(filterBySelectedCell(_:)), keyEquivalent: "")
        filter.target = self
        menu.addItem(filter)
        menu.addItem(.separator())
        let hide = NSMenuItem(title: L.t("Hide Column", "컬럼 숨기기"), action: #selector(hideCurrentColumn(_:)), keyEquivalent: "")
        hide.target = self
        menu.addItem(hide)
        menu.addItem(.separator())
        let sortAsc = NSMenuItem(title: L.t("Sort Ascending", "오름차순 정렬"), action: #selector(sortAscending(_:)), keyEquivalent: "")
        sortAsc.target = self
        menu.addItem(sortAsc)
        let sortDesc = NSMenuItem(title: L.t("Sort Descending", "내림차순 정렬"), action: #selector(sortDescending(_:)), keyEquivalent: "")
        sortDesc.target = self
        menu.addItem(sortDesc)
        tableView.menu = menu
    }

    private func configureDetailPanel() {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        detailPanel.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: detailPanel.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: detailPanel.trailingAnchor),
            stack.topAnchor.constraint(equalTo: detailPanel.topAnchor),
            stack.bottomAnchor.constraint(equalTo: detailPanel.bottomAnchor)
        ])

        detailHeaderLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        detailHeaderLabel.backgroundColor = .controlBackgroundColor
        detailHeaderLabel.isBezeled = false
        detailHeaderLabel.drawsBackground = true
        detailHeaderLabel.lineBreakMode = .byTruncatingTail
        detailHeaderLabel.heightAnchor.constraint(equalToConstant: 34).isActive = true
        stack.addArrangedSubview(detailHeaderLabel)

        inspectorActionBar.orientation = .horizontal
        inspectorActionBar.alignment = .centerY
        inspectorActionBar.spacing = 8
        inspectorActionBar.edgeInsets = NSEdgeInsets(top: 6, left: 12, bottom: 6, right: 12)
        configureAnalysisActionButton(inspectorCopyTextButton, title: L.t("Copy (TEXT)", "복사(TEXT)"), symbol: "doc.on.doc", action: #selector(copyInspectorText(_:)))
        configureAnalysisActionButton(inspectorCopyJsonButton, title: L.t("Copy (JSON)", "복사(JSON)"), symbol: "curlybraces", action: #selector(copyInspectorJson(_:)))
        inspectorActionBar.addArrangedSubview(inspectorCopyTextButton)
        inspectorActionBar.addArrangedSubview(inspectorCopyJsonButton)
        let inspectorSpacer = NSView()
        inspectorSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        inspectorActionBar.addArrangedSubview(inspectorSpacer)
        stack.addArrangedSubview(inspectorActionBar)

        analysisActionBar.orientation = .horizontal
        analysisActionBar.alignment = .centerY
        analysisActionBar.spacing = 8
        analysisActionBar.edgeInsets = NSEdgeInsets(top: 7, left: 12, bottom: 7, right: 12)
        analysisActionBar.isHidden = true
        configureAnalysisActionButton(analysisCopyButton, title: L.t("Copy", "복사"), symbol: "doc.on.doc", action: #selector(copyAnalysisResult(_:)))
        configureAnalysisActionButton(analysisExportButton, title: L.t("Export...", "내보내기..."), symbol: "square.and.arrow.up", action: #selector(exportAnalysisResult(_:)))
        configureAnalysisActionButton(analysisCancelButton, title: L.t("Cancel", "취소"), symbol: "xmark.circle", action: #selector(cancelAnalysis(_:)))
        analysisActionBar.addArrangedSubview(analysisCopyButton)
        analysisActionBar.addArrangedSubview(analysisExportButton)
        let actionSpacer = NSView()
        actionSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        analysisActionBar.addArrangedSubview(actionSpacer)
        analysisActionBar.addArrangedSubview(analysisCancelButton)
        stack.addArrangedSubview(analysisActionBar)

        detailTextView.isEditable = false
        detailTextView.isSelectable = true
        detailTextView.textContainerInset = NSSize(width: 14, height: 12)
        detailTextView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        detailTextView.backgroundColor = .windowBackgroundColor
        let detailScroll = NSScrollView()
        detailScroll.documentView = detailTextView
        detailScroll.hasVerticalScroller = true
        detailScroll.drawsBackground = false
        stack.addArrangedSubview(detailScroll)
    }

    private func configureAnalysisActionButton(_ button: NSButton, title: String, symbol: String, action: Selector) {
        button.title = title
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        button.imagePosition = .imageLeading
        button.imageScaling = .scaleProportionallyDown
        button.bezelStyle = .rounded
        button.controlSize = .small
        button.font = .systemFont(ofSize: 12)
        button.target = self
        button.action = action
    }

    private func configureEmptyState() {
        emptyStateView.wantsLayer = true
        emptyStateView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        emptyStateView.addSubview(stack)

        let imageView = NSImageView()
        imageView.image = NSImage(systemSymbolName: "tablecells", accessibilityDescription: nil)
        imageView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 48, weight: .regular)
        imageView.contentTintColor = .tertiaryLabelColor

        let title = NSTextField(labelWithString: L.t("Open a CSV File", "CSV 파일 열기"))
        title.font = .systemFont(ofSize: 22, weight: .semibold)
        title.textColor = .labelColor

        let subtitle = NSTextField(labelWithString: L.t("Large files open quickly and continue indexing in the background.", "대용량 파일은 빠르게 열리고 백그라운드에서 계속 인덱싱됩니다."))
        subtitle.font = .systemFont(ofSize: 13)
        subtitle.textColor = .secondaryLabelColor
        subtitle.alignment = .center
        subtitle.maximumNumberOfLines = 2

        let button = NSButton(title: L.t("Open CSV...", "CSV 열기..."), target: self, action: #selector(openDocument(_:)))
        button.bezelStyle = .rounded
        button.controlSize = .large

        stack.addArrangedSubview(imageView)
        stack.addArrangedSubview(title)
        stack.addArrangedSubview(subtitle)
        stack.addArrangedSubview(button)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: emptyStateView.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: emptyStateView.centerYAnchor, constant: -24),
            subtitle.widthAnchor.constraint(lessThanOrEqualToConstant: 440)
        ])
    }

    private func configureDropTargets() {
        let handler: ([URL], String?) -> Void = { [weak self] urls, text in
            self?.openDroppedContent(urls: urls, text: text)
        }
        contentContainer.dropHandler = handler
        emptyStateView.dropHandler = handler
    }

    private func configureEncodingPopup() {
        encodingPopup.removeAllItems()
        encodingPopup.addItems(withTitles: CsvEncodingName.selectable)
        encodingPopup.target = self
        encodingPopup.action = #selector(changeEncoding(_:))
        encodingPopup.isEnabled = false
    }

}

private extension NSToolbarItem.Identifier {
    static let openFile = NSToolbarItem.Identifier("openFile")
    static let closeDocument = NSToolbarItem.Identifier("closeDocument")
    static let sortGroup = NSToolbarItem.Identifier("sortGroup")
    static let pivot = NSToolbarItem.Identifier("pivot")
    static let findGroup = NSToolbarItem.Identifier("findGroup")
    static let filterToggle = NSToolbarItem.Identifier("filterToggle")
    static let detail = NSToolbarItem.Identifier("detail")
}

extension MainWindowController: NSToolbarDelegate {
    nonisolated func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.openFile, .closeDocument, .sortGroup, .pivot, .findGroup, .filterToggle, .detail, .flexibleSpace, .space]
    }

    nonisolated func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.openFile, .closeDocument, .sortGroup, .pivot, .findGroup, .filterToggle, .flexibleSpace, .detail]
    }

    nonisolated func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        MainActor.assumeIsolated {
            switch itemIdentifier {
            case .openFile:
                let item = NSToolbarItem(itemIdentifier: itemIdentifier)
                item.label = L.t("Open", "열기")
                item.paletteLabel = item.label
                item.toolTip = L.t("Open CSV or text file", "CSV 또는 텍스트 파일 열기")
                item.image = NSImage(systemSymbolName: "folder", accessibilityDescription: item.label)
                item.target = self
                item.action = #selector(openDocument(_:))
                return item

            case .closeDocument:
                let item = NSToolbarItem(itemIdentifier: itemIdentifier)
                item.label = L.t("Close", "닫기")
                item.paletteLabel = item.label
                item.toolTip = L.t("Close current file", "현재 파일 닫기")
                item.image = NSImage(systemSymbolName: "xmark.circle", accessibilityDescription: item.label)
                item.target = self
                item.action = #selector(closeCurrentDocument(_:))
                item.isEnabled = csvDocument != nil
                closeToolbarItem = item
                return item

            case .sortGroup:
                configureSortControl()
                return viewToolbarItem(identifier: itemIdentifier, label: L.t("Sort", "정렬"), view: sortControl, minWidth: 104, maxWidth: 104)

            case .pivot:
                let item = NSToolbarItem(itemIdentifier: itemIdentifier)
                item.label = L.t("Pivot", "피벗")
                item.paletteLabel = item.label
                item.toolTip = L.t("Open pivot builder", "피벗 빌더 열기")
                item.image = NSImage(systemSymbolName: "tablecells", accessibilityDescription: item.label)
                item.target = self
                item.action = #selector(showPivotTable(_:))
                item.isEnabled = csvDocument?.indexingComplete == true && !busy && columnNames.count >= 2
                pivotToolbarItem = item
                return item

            case .findGroup:
                configureFindControls()
                let stack = toolbarStack(spacing: 5)
                stack.addArrangedSubview(findField)
                stack.addArrangedSubview(findNextButton)
                return viewToolbarItem(identifier: itemIdentifier, label: L.t("Find", "찾기"), view: stack, minWidth: 224, maxWidth: 260)

            case .filterToggle:
                configureFilterToolbarButton()
                return viewToolbarItem(identifier: itemIdentifier, label: L.t("Filter", "필터"), view: filterToggleButton, minWidth: 32, maxWidth: 40)

            case .detail:
                configureDetailToolbarButton()
                return viewToolbarItem(identifier: itemIdentifier, label: L.t("Inspector", "인스펙터"), view: detailToggleButton, minWidth: 32, maxWidth: 40)

            default:
                return nil
            }
        }
    }

    private func toolbarStack(spacing: CGFloat) -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = spacing
        return stack
    }

    private func viewToolbarItem(identifier: NSToolbarItem.Identifier, label: String, view: NSView, minWidth: CGFloat, maxWidth: CGFloat) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = label
        item.paletteLabel = label
        item.view = view
        view.widthAnchor.constraint(greaterThanOrEqualToConstant: minWidth).isActive = true
        view.widthAnchor.constraint(lessThanOrEqualToConstant: maxWidth).isActive = true
        view.heightAnchor.constraint(greaterThanOrEqualToConstant: 24).isActive = true
        return item
    }

    private func configureSortControl() {
        sortControl.segmentStyle = .rounded
        sortControl.target = self
        sortControl.action = #selector(sortSegmentChanged(_:))
        sortControl.setImage(NSImage(systemSymbolName: "arrow.up", accessibilityDescription: L.t("Sort Ascending", "오름차순 정렬")), forSegment: 0)
        sortControl.setImage(NSImage(systemSymbolName: "arrow.down", accessibilityDescription: L.t("Sort Descending", "내림차순 정렬")), forSegment: 1)
        sortControl.setImage(NSImage(systemSymbolName: "arrow.up.arrow.down.circle", accessibilityDescription: L.t("Clear Sort", "정렬 해제")), forSegment: 2)
        sortControl.setToolTip(L.t("Sort ascending", "오름차순 정렬"), forSegment: 0)
        sortControl.setToolTip(L.t("Sort descending", "내림차순 정렬"), forSegment: 1)
        sortControl.setToolTip(L.t("Clear sort", "정렬 해제"), forSegment: 2)
        for index in 0..<3 {
            sortControl.setWidth(32, forSegment: index)
        }
        sortControl.isEnabled = csvDocument?.indexingComplete == true && !busy
    }

    private func configureFindControls() {
        findField.placeholderString = L.t("Find", "찾기")
        findField.target = self
        findField.action = #selector(findNext(_:))
        findField.controlSize = .small
        findField.widthAnchor.constraint(equalToConstant: 180).isActive = true

        configureToolbarButton(findNextButton, symbol: "arrow.forward.circle", tooltip: L.t("Find next", "다음 찾기"), action: #selector(findNext(_:)))
        findNextButton.isEnabled = csvDocument != nil && !busy
    }

    private func configureFilterControls() {
        filterColumnPopup.controlSize = .small
        filterColumnPopup.widthAnchor.constraint(equalToConstant: 150).isActive = true

        filterField.placeholderString = L.t("Filter or expression", "필터 또는 표현식")
        filterField.target = self
        filterField.action = #selector(applyTextFilter(_:))
        filterField.controlSize = .small
        filterField.sendsSearchStringImmediately = false
        if let cell = filterField.cell as? NSSearchFieldCell {
            cell.sendsWholeSearchString = true
        }
        filterField.widthAnchor.constraint(greaterThanOrEqualToConstant: 220).isActive = true
        filterField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        filterField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        configureFilterBarButton(applyFilterButton, symbol: "checkmark.circle", title: L.t("Apply", "적용"), tooltip: L.t("Apply filter", "필터 적용"), action: #selector(applyTextFilter(_:)), width: 76)
        configureFilterBarButton(clearFilterButton, symbol: "xmark.circle", title: L.t("Clear", "해제"), tooltip: L.t("Clear filter", "필터 해제"), action: #selector(clearFilter(_:)), width: 72)
        configureFilterBarButton(filterByCellButton, symbol: "line.3.horizontal.decrease.circle", title: L.t("Cell", "셀값"), tooltip: L.t("Filter by selected cell", "선택 셀 값으로 필터"), action: #selector(filterBySelectedCell(_:)), width: 70)
        let ready = csvDocument?.indexingComplete == true && !busy
        filterByCellButton.isEnabled = ready
        applyFilterButton.isEnabled = ready
        clearFilterButton.isEnabled = ready
    }

    private func configureFilterBarButton(_ button: NSButton, symbol: String, title: String, tooltip: String, action: Selector, width: CGFloat) {
        button.title = title
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip)
        button.imagePosition = .imageLeading
        button.imageScaling = .scaleProportionallyDown
        button.bezelStyle = .rounded
        button.controlSize = .small
        button.font = .systemFont(ofSize: 12, weight: .regular)
        button.target = self
        button.action = action
        button.toolTip = tooltip
        button.widthAnchor.constraint(equalToConstant: width).isActive = true
        button.heightAnchor.constraint(equalToConstant: 26).isActive = true
    }

    private func configureDetailToolbarButton() {
        configureToolbarButton(detailToggleButton, symbol: "sidebar.right", tooltip: L.t("Toggle inspector", "인스펙터 토글"), action: #selector(toggleDetailPanel(_:)))
        detailToggleButton.setButtonType(.toggle)
        detailToggleButton.state = isInspectorVisible ? .on : .off
    }

    private func configureFilterToolbarButton() {
        configureToolbarButton(filterToggleButton, symbol: "line.3.horizontal.decrease.circle", tooltip: L.t("Show or hide filters", "필터 보이기/숨기기"), action: #selector(toggleFilterBar(_:)))
        filterToggleButton.setButtonType(.toggle)
        filterToggleButton.state = filterBarView.isHidden ? .off : .on
    }

    private func configureToolbarButton(_ button: NSButton, symbol: String, tooltip: String, action: Selector) {
        button.title = ""
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip)
        button.imageScaling = .scaleProportionallyDown
        button.bezelStyle = .texturedRounded
        button.controlSize = .small
        button.target = self
        button.action = action
        button.toolTip = tooltip
        button.widthAnchor.constraint(equalToConstant: 28).isActive = true
        button.heightAnchor.constraint(equalToConstant: 24).isActive = true
    }

    @objc private func sortSegmentChanged(_ sender: NSSegmentedControl) {
        switch sender.selectedSegment {
        case 0: sortAscending(sender)
        case 1: sortDescending(sender)
        case 2: clearSort(sender)
        default: break
        }
    }
}

extension MainWindowController: NSSplitViewDelegate {
    nonisolated func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposedMinimumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        MainActor.assumeIsolated {
            splitView === mainSplit ? 520 : proposedMinimumPosition
        }
    }

    nonisolated func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposedMaximumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        MainActor.assumeIsolated {
            guard splitView === mainSplit else { return proposedMaximumPosition }
            return max(520, splitView.bounds.width - 280)
        }
    }
}

extension MainWindowController: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        do {
            let hasDocument = csvDocument != nil
            let ready = csvDocument?.indexingComplete == true && !busy
            let hasSelection = tableView.selectedRow >= 0

            switch menuItem.action {
            case #selector(openDocument(_:)), #selector(openFromClipboard(_:)), #selector(showUsage(_:)):
                return true
            case #selector(closeCurrentDocument(_:)):
                return hasDocument
            case #selector(copyAnalysisResult(_:)), #selector(exportAnalysisResult(_:)):
                return currentAnalysisReport != nil && analysisCancellation == nil
            case #selector(cancelAnalysis(_:)):
                return analysisCancellation != nil
            case #selector(exportCurrentView(_:)), #selector(exportCurrentViewAsMarkdown(_:)), #selector(exportCurrentViewAsJson(_:)), #selector(exportCurrentViewAsHtml(_:)):
                return ready
            case #selector(focusFindField(_:)), #selector(findNext(_:)):
                return hasDocument && !busy
            case #selector(goToRow(_:)):
                return hasDocument && !busy
            case #selector(copySelectedCellToPasteboard(_:)), #selector(copySelectedCellAsCsv(_:)), #selector(copySelectedCellAsJson(_:)), #selector(copyEntireCurrentRow(_:)), #selector(copyEntireCurrentColumn(_:)):
                return hasDocument && hasSelection
            case #selector(copyInspectorText(_:)):
                return !detailTextView.string.isEmpty
            case #selector(copyInspectorJson(_:)):
                if case .row = currentInspectorContentKind { return true }
                return false
            case #selector(applyTextFilter(_:)), #selector(filterBySelectedCell(_:)), #selector(sortAscending(_:)), #selector(sortDescending(_:)):
                return ready
            case #selector(clearFilter(_:)):
                return hasDocument && hasAnyFilter
            case #selector(clearSort(_:)):
                return hasDocument && !sortKeys.isEmpty
            case #selector(toggleFilterBar(_:)):
                menuItem.state = filterBarView.isHidden ? .off : .on
                return hasDocument
            case #selector(toggleDetailPanel(_:)):
                menuItem.state = isInspectorVisible ? .on : .off
                return hasDocument
            case #selector(toggleFacetsPanel(_:)):
                menuItem.state = isFacetsPanelVisible ? .on : .off
                return true
            case #selector(showColumnStatistics(_:)):
                return ready
            case #selector(showPerformanceDashboard(_:)):
                return hasDocument
            case #selector(showAllColumns(_:)):
                return hasDocument && !hiddenColumnIndexes.isEmpty
            case #selector(saveCurrentView(_:)), #selector(restoreSavedView(_:)):
                return hasDocument && ready
            case #selector(toggleAutoRestoreView(_:)):
                menuItem.state = UserDefaults.standard.bool(forKey: Self.autoRestoreViewDefaultsKey) ? .on : .off
                return true
            case #selector(changeRowDensity(_:)):
                menuItem.state = (menuItem.representedObject as? String) == currentRowDensity.rawValue ? .on : .off
                return true
            case #selector(hideCurrentColumn(_:)):
                return hasDocument && currentDataColumn >= 0
            case #selector(togglePersistentIndex(_:)):
                menuItem.state = VirtualCsvDocument.persistentIndexEnabled ? .on : .off
                return true
            case #selector(toggleDeleteIndexCacheOnClose(_:)):
                menuItem.state = VirtualCsvDocument.deletePersistentIndexOnClose ? .on : .off
                return true
            case #selector(showIndexFolder(_:)), #selector(clearIndexFolder(_:)):
                return true
            case #selector(showNumericDistribution(_:)), #selector(showDateHistogram(_:)), #selector(showDuplicateRows(_:)), #selector(showGroupBy(_:)), #selector(showPivotTable(_:)), #selector(showPivotChart(_:)), #selector(showCorrelation(_:)), #selector(showTTest(_:)), #selector(showChiSquare(_:)), #selector(showQuickStats(_:)), #selector(showDescriptiveStatistics(_:)), #selector(showFrequencyAnalysis(_:)), #selector(showOneWayAnova(_:)), #selector(showNormalityTest(_:)):
                return ready
            case #selector(showHistogramChartWindow(_:)), #selector(showBoxplotChartWindow(_:)), #selector(showScatterChartWindow(_:)), #selector(showCorrelationHeatmapWindow(_:)), #selector(showQQPlotChartWindow(_:)), #selector(showTimeseriesChartWindow(_:)), #selector(showParetoChartWindow(_:)):
                return ready
            case #selector(runDataQualityProfile(_:)):
                return ready
            case #selector(exportDataQualityMarkdown(_:)), #selector(exportDataQualityHtml(_:)), #selector(exportDataQualityJson(_:)):
                return currentDataQualityReport != nil && !busy
            case #selector(changeEncodingFromMenu(_:)):
                if let name = menuItem.representedObject as? String {
                    menuItem.state = name == csvDocument?.encodingName ? .on : .off
                }
                return hasDocument && !busy
            default:
                return true
            }
        }
    }
}

extension MainWindowController {
    @objc func openDocument(_ sender: Any?) {
        let panel = NSOpenPanel()
        var openTypes: [UTType] = [.commaSeparatedText, .plainText]
        for ext in ["db", "sqlite", "sqlite3", "xlsx", "xlsm"] {
            if let type = UTType(filenameExtension: ext) {
                openTypes.append(type)
            }
        }
        panel.allowedContentTypes = openTypes
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.beginSheetModal(for: window!) { [weak self] response in
            guard response == .OK, !panel.urls.isEmpty else { return }
            Task { @MainActor in
                self?.openURLs(panel.urls)
            }
        }
    }

    @objc func openFromClipboard(_ sender: Any?) {
        guard let text = NSPasteboard.general.string(forType: .string) else {
            statusLabel.stringValue = L.t("Clipboard does not contain CSV text or a file path.", "클립보드에 CSV 텍스트나 파일 경로가 없습니다.")
            return
        }
        do {
            let importResult = try ClipboardImportResolver.resolve(text: text)
            openURLs([importResult.url])
            statusLabel.stringValue = importResultStatus(importResult)
        } catch ClipboardImportResolver.ImportError.emptyClipboardText {
            statusLabel.stringValue = L.t("Clipboard is empty.", "클립보드가 비어 있습니다.")
        } catch {
            presentError(error)
        }
    }

    @objc func closeCurrentDocument(_ sender: Any?) {
        guard let closingDocument = csvDocument else { return }

        cancelAll()
        indexCancellation = nil
        operationCancellation = nil
        findCancellation = nil
        prefetchCancellation = nil
        columnFilterValuesCancellation = nil
        columnStatisticsCancellation = nil
        analysisCancellation = nil
        facetsCancellation = nil
        facetRefreshWorkItem = nil
        rowTimer = nil
        detailUpdateWorkItem = nil

        pivotBuilderWindow?.close()
        pivotBuilderWindow = nil
        closeAllChartWindows()
        chartCancellation = nil

        if VirtualCsvDocument.deletePersistentIndexOnClose {
            closingDocument.deletePersistentIndex()
        }

        csvDocument = nil
        currentFilePath = nil
        indexingElapsed = nil
        lastKnownRowCount = 0
        columnStatisticsReport = nil
        baseColumnStatisticsReport = nil
        columnTypeOverrides = [:]
        currentAnalysisReport = nil
        currentDataQualityReport = nil
        earlyColumnStatisticsRequested = false
        acceptedColumnStatisticsPriority = 0

        while tableView.tableColumns.count > 0 {
            tableView.removeTableColumn(tableView.tableColumns[0])
        }
        columnNames.removeAll()
        filterColumnPopup.removeAllItems()
        filterColumnPopup.addItem(withTitle: L.t("All Columns", "전체 열"))
        filterColumnPopup.selectItem(at: 0)
        tableView.deselectAll(nil)

        resetViewState()
        tableView.reloadData()
        setProgressVisible(false)
        updateProgress(0)
        statusLabel.stringValue = L.t("Open a CSV or text file.", "CSV 또는 텍스트 파일을 여세요.")
        window?.title = "Nanum CSV Viewer"
        updateAnalysisActionBar(running: false)
        updateEmptyState()
        updateFeatureState()
        if isFacetsPanelVisible {
            refreshFacetsNow()
        }
    }

    @objc func exportCurrentView(_ sender: Any?) {
        exportCurrentView(format: .csv, defaultName: "export.csv")
    }

    @objc func exportCurrentViewAsMarkdown(_ sender: Any?) {
        exportCurrentView(format: .markdown, defaultName: "export.md")
    }

    @objc func exportCurrentViewAsJson(_ sender: Any?) {
        exportCurrentView(format: .json, defaultName: "export.json")
    }

    @objc func exportCurrentViewAsHtml(_ sender: Any?) {
        exportCurrentView(format: .html, defaultName: "export.html")
    }

    private func exportCurrentView(format: VirtualCsvDocument.ExportFormat, defaultName: String) {
        guard let doc = csvDocument, doc.indexingComplete, !busy else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [
            .commaSeparatedText,
            UTType(filenameExtension: "md") ?? .plainText,
            .json,
            .html
        ]
        panel.nameFieldStringValue = defaultName
        panel.beginSheetModal(for: window!) { [weak self, weak doc] response in
            guard response == .OK, let url = panel.url, let doc else { return }
            Task { @MainActor in
                let resolvedFormat = self?.exportFormat(for: url, fallback: format) ?? format
                let selectedColumns = self?.visibleColumnIndexesForExport()
                self?.runViewOperation(message: L.t("Exporting...", "내보내는 중...")) { flag, progress in
                    try doc.exportCurrentView(to: url.path, format: resolvedFormat, selectedColumns: selectedColumns, cancellation: flag)
                    progress(100)
                } completion: { [weak self] in
                    self?.statusLabel.stringValue = L.t("Exported current view.", "현재 보기를 내보냈습니다.")
                }
            }
        }
    }

    private func exportFormat(for url: URL, fallback: VirtualCsvDocument.ExportFormat) -> VirtualCsvDocument.ExportFormat {
        switch url.pathExtension.lowercased() {
        case "csv": return .csv
        case "md", "markdown": return .markdown
        case "json": return .json
        case "html", "htm": return .html
        default: return fallback
        }
    }

    private func visibleColumnIndexesForExport() -> [Int]? {
        let visible = columnNames.indices.filter { index in
            tableView.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier("c\(index)"))?.isHidden != true
        }
        return visible.count == columnNames.count ? nil : visible
    }

    var hasOpenDocument: Bool {
        csvDocument != nil
    }

    func openFileURL(_ url: URL) {
        if SqliteWorkbook.hasSqliteExtension(url.path) || SqliteWorkbook.isSqliteFile(path: url.path) {
            openSqliteDatabase(url)
            return
        }
        if XlsxWorkbook.hasXlsxExtension(url.path), XlsxWorkbook.isXlsxFile(path: url.path) {
            openXlsxWorkbook(url)
            return
        }
        openFile(url)
    }

    private func openXlsxWorkbook(_ url: URL) {
        do {
            let sheets = try XlsxWorkbook.sheetNames(path: url.path)
            guard !sheets.isEmpty else {
                statusLabel.stringValue = L.t("No sheets found in the workbook.", "통합 문서에 시트가 없습니다.")
                return
            }
            if sheets.count == 1 {
                openXlsxSheets(url, sheets: sheets)
                return
            }
            presentXlsxSheetPicker(url: url, sheets: sheets)
        } catch {
            presentError(error)
        }
    }

    private func presentXlsxSheetPicker(url: URL, sheets: [String]) {
        let alert = NSAlert()
        alert.messageText = L.t("Open Excel Sheet", "Excel 시트 열기")
        alert.informativeText = L.t(
            "\(url.lastPathComponent) contains \(sheets.count) sheets. The workbook is opened read-only.",
            "\(url.lastPathComponent)에 시트가 \(sheets.count)개 있습니다. 통합 문서는 읽기 전용으로 열립니다."
        )
        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 280, height: 25))
        popup.addItems(withTitles: sheets)
        alert.accessoryView = popup
        alert.addButton(withTitle: L.t("Open", "열기"))
        alert.addButton(withTitle: L.t("Open All in Tabs", "모두 탭으로 열기"))
        alert.addButton(withTitle: L.t("Cancel", "취소"))
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            openXlsxSheets(url, sheets: [popup.titleOfSelectedItem ?? sheets[0]])
        case .alertSecondButtonReturn:
            openXlsxSheets(url, sheets: sheets)
        default:
            break
        }
    }

    private func openXlsxSheets(_ url: URL, sheets: [String]) {
        guard !sheets.isEmpty else { return }
        let base = url.deletingPathExtension().lastPathComponent
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("NanumCsvViewerXlsx", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        operationCancellation?.cancel()
        let cancellation = CancellationFlag()
        operationCancellation = cancellation
        setBusy(true, message: L.t("Converting Excel sheet...", "Excel 시트 변환 중..."))
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
                var destinations: [URL] = []
                for sheet in sheets {
                    let safeName = sheet
                        .replacingOccurrences(of: "/", with: "_")
                        .replacingOccurrences(of: ":", with: "_")
                    let destination = tempDir.appendingPathComponent("\(base).\(safeName).csv")
                    try XlsxWorkbook.exportSheetToCsv(path: url.path, sheet: sheet, destination: destination, cancellation: cancellation)
                    destinations.append(destination)
                }
                DispatchQueue.main.async {
                    guard let self, self.operationCancellation === cancellation else { return }
                    self.operationCancellation = nil
                    self.setBusy(false)
                    guard let first = destinations.first else { return }
                    self.openFile(first)
                    let rest = Array(destinations.dropFirst())
                    if !rest.isEmpty {
                        self.openAdditionalFilesHandler?(rest, self.window)
                    }
                }
            } catch CsvError.cancelled {
                DispatchQueue.main.async {
                    guard let self, self.operationCancellation === cancellation else { return }
                    self.operationCancellation = nil
                    self.setBusy(false)
                    self.statusLabel.stringValue = L.t("Excel conversion cancelled.", "Excel 변환이 취소되었습니다.")
                }
            } catch {
                DispatchQueue.main.async {
                    guard let self else { return }
                    if self.operationCancellation === cancellation {
                        self.operationCancellation = nil
                    }
                    self.setBusy(false)
                    self.presentError(error)
                }
            }
        }
    }

    private func openSqliteDatabase(_ url: URL) {
        do {
            let tables = try SqliteWorkbook.tableNames(path: url.path)
            guard !tables.isEmpty else {
                statusLabel.stringValue = L.t("No tables found in the database.", "데이터베이스에 테이블이 없습니다.")
                return
            }
            if tables.count == 1 {
                openSqliteTables(url, tables: tables)
                return
            }
            presentSqliteTablePicker(url: url, tables: tables)
        } catch {
            presentError(error)
        }
    }

    private func presentSqliteTablePicker(url: URL, tables: [String]) {
        let alert = NSAlert()
        alert.messageText = L.t("Open SQLite Table", "SQLite 테이블 열기")
        alert.informativeText = L.t(
            "\(url.lastPathComponent) contains \(tables.count) tables/views. The database is opened read-only.",
            "\(url.lastPathComponent)에 테이블/뷰가 \(tables.count)개 있습니다. 데이터베이스는 읽기 전용으로 열립니다."
        )
        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 280, height: 25))
        popup.addItems(withTitles: tables)
        alert.accessoryView = popup
        alert.addButton(withTitle: L.t("Open", "열기"))
        alert.addButton(withTitle: L.t("Open All in Tabs", "모두 탭으로 열기"))
        alert.addButton(withTitle: L.t("Cancel", "취소"))
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            openSqliteTables(url, tables: [popup.titleOfSelectedItem ?? tables[0]])
        case .alertSecondButtonReturn:
            openSqliteTables(url, tables: tables)
        default:
            break
        }
    }

    private func openSqliteTables(_ url: URL, tables: [String]) {
        guard !tables.isEmpty else { return }
        let base = url.deletingPathExtension().lastPathComponent
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("NanumCsvViewerSqlite", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        operationCancellation?.cancel()
        let cancellation = CancellationFlag()
        operationCancellation = cancellation
        setBusy(true, message: L.t("Converting SQLite table...", "SQLite 테이블 변환 중..."))
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
                var destinations: [URL] = []
                for table in tables {
                    let safeName = table
                        .replacingOccurrences(of: "/", with: "_")
                        .replacingOccurrences(of: ":", with: "_")
                    let destination = tempDir.appendingPathComponent("\(base).\(safeName).csv")
                    try SqliteWorkbook.exportTableToCsv(path: url.path, table: table, destination: destination, cancellation: cancellation)
                    destinations.append(destination)
                }
                DispatchQueue.main.async {
                    guard let self, self.operationCancellation === cancellation else { return }
                    self.operationCancellation = nil
                    self.setBusy(false)
                    guard let first = destinations.first else { return }
                    self.openFile(first)
                    let rest = Array(destinations.dropFirst())
                    if !rest.isEmpty {
                        self.openAdditionalFilesHandler?(rest, self.window)
                    }
                }
            } catch CsvError.cancelled {
                DispatchQueue.main.async {
                    guard let self, self.operationCancellation === cancellation else { return }
                    self.operationCancellation = nil
                    self.setBusy(false)
                    self.statusLabel.stringValue = L.t("SQLite conversion cancelled.", "SQLite 변환이 취소되었습니다.")
                }
            } catch {
                DispatchQueue.main.async {
                    guard let self else { return }
                    if self.operationCancellation === cancellation {
                        self.operationCancellation = nil
                    }
                    self.setBusy(false)
                    self.presentError(error)
                }
            }
        }
    }

    private func openURLs(_ urls: [URL]) {
        let route = DocumentOpenRouting.route(urls: urls, currentWindowHasDocument: csvDocument != nil)
        if let currentURL = route.currentWindowURL {
            openFile(currentURL)
        }
        if !route.additionalWindowURLs.isEmpty {
            openAdditionalFilesHandler?(route.additionalWindowURLs, window)
        }
    }

    private func openDroppedContent(urls: [URL], text: String?) {
        if !urls.isEmpty {
            openURLs(urls)
            return
        }
        guard let text else { return }
        do {
            let importResult = try ClipboardImportResolver.resolve(text: text)
            openURLs([importResult.url])
            statusLabel.stringValue = importResultStatus(importResult)
        } catch ClipboardImportResolver.ImportError.emptyClipboardText {
            statusLabel.stringValue = L.t("Dropped text is empty.", "드롭한 텍스트가 비어 있습니다.")
        } catch {
            presentError(error)
        }
    }

    private func importResultStatus(_ result: ClipboardImportResolver.ImportResult) -> String {
        switch result {
        case .existingFile:
            return L.t("Opened file from clipboard.", "클립보드의 파일을 열었습니다.")
        case .createdFile:
            return L.t("Opened CSV text from clipboard.", "클립보드의 CSV 텍스트를 열었습니다.")
        }
    }

    private func openFile(_ url: URL) {
        cancelAll()
        closeAllChartWindows()
        do {
            let doc = try VirtualCsvDocument.open(path: url.path)
            csvDocument = doc
            currentFilePath = url.path
            indexingElapsed = nil
            columnStatisticsReport = nil
            baseColumnStatisticsReport = nil
            columnTypeOverrides = [:]
            currentAnalysisReport = nil
            currentDataQualityReport = nil
            analysisCancellation?.cancel()
            analysisCancellation = nil
            columnStatisticsCancellation?.cancel()
            columnStatisticsCancellation = nil
            earlyColumnStatisticsRequested = false
            acceptedColumnStatisticsPriority = 0
            window?.title = "Nanum CSV Viewer - \(url.lastPathComponent)"
            resetViewState()
            buildColumns(from: doc.header)
            syncEncodingPopup()
            tableView.reloadData()
            lastKnownRowCount = 0
            updateAnalysisActionBar(running: false)
            updateEmptyState()
            startIndexing(csvDocument: doc)
            updateFeatureState()
            if isFacetsPanelVisible {
                refreshFacetsNow()
            }
        } catch {
            indexingElapsed = nil
            currentFilePath = nil
            presentError(error)
            statusLabel.stringValue = L.t("Open failed.", "열기에 실패했습니다.")
            updateEmptyState()
            updateFeatureState()
        }
    }

    private func startIndexing(csvDocument doc: VirtualCsvDocument) {
        let cancellation = CancellationFlag()
        indexCancellation = cancellation
        indexing = true
        setProgressVisible(true)
        updateProgress(0)
        statusLabel.stringValue = L.t("Loading...", "불러오는 중...")
        refreshSignal()
        startRowTimer()

        DispatchQueue.global(qos: .userInitiated).async { [weak self, weak doc] in
            guard let doc else { return }
            let start = Date()
            do {
                try doc.runIndexing(progress: { progress in
                    DispatchQueue.main.async {
                        self?.onIndexProgress(progress)
                    }
                }, cancellation: cancellation)
                let elapsed = Date().timeIntervalSince(start)
                DispatchQueue.main.async {
                    self?.onIndexingComplete(elapsed: elapsed, csvDocument: doc)
                }
            } catch CsvError.cancelled {
                DispatchQueue.main.async {
                    self?.indexing = false
                    self?.rowTimer?.invalidate()
                    self?.setProgressVisible(false)
                    self?.updateFeatureState()
                }
            } catch {
                DispatchQueue.main.async {
                    self?.indexing = false
                    self?.rowTimer?.invalidate()
                    self?.setProgressVisible(false)
                    self?.presentError(error)
                    self?.updateFeatureState()
                }
            }
        }
    }

    private func onIndexProgress(_ progress: IndexProgress) {
        updateProgress(progress.percent)
        updateStatusMetrics()
        let rows = csvDocument?.dataRowsAvailable ?? max(0, Int(progress.rowsSoFar - 2))
        statusLabel.stringValue = L.t(
            "Loading \(rows.formatted()) rows  \(formatBytes(progress.bytesProcessed)) / \(formatBytes(progress.fileLength))",
            "\(rows.formatted())행 로딩 중  \(formatBytes(progress.bytesProcessed)) / \(formatBytes(progress.fileLength))"
        )
    }

    private func onIndexingComplete(elapsed: TimeInterval, csvDocument doc: VirtualCsvDocument) {
        guard doc === csvDocument else { return }
        rowTimer?.invalidate()
        indexing = false
        indexingElapsed = elapsed
        setProgressVisible(false)
        refreshRowCount()
        updateFeatureState()
        statusLabel.stringValue = ""
        refreshColumnStatistics(for: doc, final: true)
        scheduleFacetRefresh(delay: 0)
        autoRestoreSavedViewIfEnabled()
    }

    private func startRowTimer() {
        rowTimer?.invalidate()
        rowTimer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshRowCount()
            }
        }
    }

    private func refreshRowCount() {
        let count = csvDocument?.displayRowCount ?? 0
        if count != lastKnownRowCount {
            lastKnownRowCount = count
            tableView.reloadData()
            scheduleVisibleRowPrefetch()
        }
        updateStatusMetrics()
        if let doc = csvDocument {
            maybeRefreshEarlyColumnStatistics(for: doc)
        }
    }

    private func buildColumns(from header: [String]) {
        while tableView.tableColumns.count > 0 {
            tableView.removeTableColumn(tableView.tableColumns[0])
        }
        gridColumnBaseWidths.removeAll()

        columnNames = header.enumerated().map { index, name in
            name.isEmpty ? L.t("Column \(index + 1)", "\(index + 1)열") : name
        }

        let rowColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("rowNumber"))
        rowColumn.title = "#"
        rowColumn.headerCell = NSTableHeaderCell(textCell: "#")
        rowColumn.width = 76
        rowColumn.minWidth = 56
        tableView.addTableColumn(rowColumn)
        gridColumnBaseWidths[rowColumn.identifier] = rowColumn.width

        for (index, name) in columnNames.enumerated() {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("c\(index)"))
            column.title = name
            let headerCell = SortHeaderCell(textCell: name)
            headerCell.columnIdentifierRawValue = column.identifier.rawValue
            column.headerCell = headerCell
            column.width = 150
            column.minWidth = 60
            column.isHidden = hiddenColumnIndexes.contains(index)
            tableView.addTableColumn(column)
            gridColumnBaseWidths[column.identifier] = column.width
        }

        filterColumnPopup.removeAllItems()
        filterColumnPopup.addItem(withTitle: L.t("All Columns", "전체 열"))
        filterColumnPopup.addItems(withTitles: columnNames)
        filterColumnPopup.selectItem(at: 0)
        updateSortHeaders()
        DispatchQueue.main.async { [weak self] in
            self?.updateTableDocumentWidthForViewport()
        }
    }

    @objc func focusFindField(_ sender: Any?) {
        window?.makeFirstResponder(findField)
        findField.currentEditor()?.selectAll(nil)
    }

    @objc func findNext(_ sender: Any?) {
        guard let doc = csvDocument, !busy else { return }
        let term = findField.stringValue
        guard !term.isEmpty else { return }
        let total = doc.displayRowCount
        guard total > 0 else { return }
        let query: CsvSearchQuery
        do {
            query = try SearchFieldParser.parse(term, column: nil)
        } catch {
            presentError(error)
            return
        }

        findCancellation?.cancel()
        let cancellation = CancellationFlag()
        findCancellation = cancellation
        let start = tableView.selectedRow >= 0 ? tableView.selectedRow + 1 : 0
        setBusy(true, message: L.t("Searching...", "검색 중..."))

        DispatchQueue.global(qos: .userInitiated).async { [weak self, weak doc] in
            guard let doc else { return }
            let match: CsvSearchMatch?
            do {
                match = try doc.findNext(query: query, start: start, wrap: true, cancellation: cancellation)
            } catch {
                return
            }
            DispatchQueue.main.async {
                guard doc === self?.csvDocument else { return }
                self?.setBusy(false)
                if let match {
                    self?.tableView.selectRowIndexes(IndexSet(integer: match.viewRow), byExtendingSelection: false)
                    self?.tableView.scrollRowToVisible(match.viewRow)
                    self?.currentDataColumn = match.column
                    self?.updateSelectedValue()
                    self?.statusLabel.stringValue = L.t(
                        "Found \"\(term)\" at source row \(match.sourceRowNumber.formatted()).",
                        "\"\(term)\" 검색 결과: 원본 \(match.sourceRowNumber.formatted())행"
                    )
                } else {
                    self?.statusLabel.stringValue = L.t("No match for \"\(term)\".", "\"\(term)\" 검색 결과가 없습니다.")
                }
            }
        }
    }

    @objc func applyTextFilter(_ sender: Any?) {
        guard let doc = csvDocument, doc.indexingComplete, !busy else { return }
        let term = filterField.stringValue
        let hadTextCondition = textCondition != nil

        if term.isEmpty {
            textCondition = nil
            textConditionDescription = ""
            textFilterTerm = ""
            textFilterColumn = -1
            if hadTextCondition {
                rebuildFilter(message: L.t("Updating filter...", "필터 갱신 중..."))
            } else {
                updateFilterStatus()
            }
            return
        }

        let selected = filterColumnPopup.indexOfSelectedItem
        let column = selected <= 0 ? -1 : selected - 1
        let configured: (predicate: @Sendable ([String]) -> Bool, usesExpression: Bool)
        do {
            configured = try configureTextCondition(term: term, column: column, document: doc)
        } catch {
            presentError(error)
            return
        }
        let activePredicate = configured.predicate
        textFilterTerm = term
        textFilterColumn = column
        setFilterBarVisible(true)
        let canUseColumnFastPath = !configured.usesExpression && column >= 0 && (!hadTextCondition || columnFilterState.isEmpty)
        if canUseColumnFastPath {
            let withinCurrentView = !hadTextCondition && !columnFilterState.isEmpty
            runViewOperation(message: L.t("Applying filter...", "필터 적용 중...")) { flag, progress in
                try doc.filterColumnContains(column: column, term: term, withinCurrentView: withinCurrentView, progress: progress, cancellation: flag)
            } completion: { [weak self] in
                self?.updateFilterStatus()
            }
        } else if hadTextCondition {
            rebuildFilter(message: L.t("Applying filter...", "필터 적용 중..."))
        } else {
            runViewOperation(message: L.t("Applying filter...", "필터 적용 중...")) { flag, progress in
                try doc.filterWithinView(activePredicate, progress: progress, cancellation: flag)
            } completion: { [weak self] in
                self?.updateFilterStatus()
            }
        }
    }

    private func configureTextCondition(term: String, column: Int, document: VirtualCsvDocument) throws -> (predicate: @Sendable ([String]) -> Bool, usesExpression: Bool) {
        if Self.looksLikeExpression(term) {
            let compiled = try AdvancedFilterExpression.compile(term, headers: document.header)
            textCondition = compiled.predicate
            textConditionDescription = L.t("expression: \(truncated(term))", "표현식: \(truncated(term))")
            return (compiled.predicate, true)
        }

        let predicate = Self.containsPredicate(term: term, column: column)
        let columnName = column < 0 ? L.t("all columns", "전체 열") : columnNames[safe: column] ?? L.t("column \(column + 1)", "\(column + 1)열")
        textCondition = predicate
        textConditionDescription = L.t("\(columnName) contains \"\(truncated(term))\"", "\(columnName)에 \"\(truncated(term))\" 포함")
        return (predicate, false)
    }

    @objc func filterBySelectedCell(_ sender: Any?) {
        guard let doc = csvDocument, doc.indexingComplete, !busy else { return }
        let rowIndex = tableView.selectedRow
        guard rowIndex >= 0, currentDataColumn >= 0 else {
            statusLabel.stringValue = L.t("Select a cell first.", "먼저 셀을 선택하세요.")
            return
        }

        do {
            let row = try doc.getDisplayRow(rowIndex)
            let column = currentDataColumn
            let value = column < row.count ? row[column] : ""
            columnFilterState.setValues(column: column, values: value.isEmpty ? [] : [value], includeBlanks: value.isEmpty)
            setFilterBarVisible(true)
            rebuildFilter(message: L.t("Applying cell filter...", "셀값 필터 적용 중..."))
        } catch {
            presentError(error)
        }
    }

    @objc func clearFilter(_ sender: Any?) {
        guard let doc = csvDocument else { return }
        textCondition = nil
        textConditionDescription = ""
        textFilterTerm = ""
        textFilterColumn = -1
        columnFilterState = ColumnFilterState()
        sortKeys.removeAll()
        doc.clearView()
        updateSortHeaders()
        refreshRowCount()
        tableView.reloadData()
        updateFilterStatus()
    }

    private func rebuildFilter(message: String) {
        guard let doc = csvDocument else { return }
        sortKeys.removeAll()
        updateSortHeaders()

        guard hasAnyFilter else {
            doc.clearView()
            refreshRowCount()
            tableView.reloadData()
            updateFilterStatus()
            return
        }

        let combined = combinedPredicate()
        runViewOperation(message: message) { flag, progress in
            try doc.applyFilter(combined, progress: progress, cancellation: flag)
        } completion: { [weak self] in
            self?.updateFilterStatus()
        }
    }

    private func combinedPredicate() -> @Sendable ([String]) -> Bool {
        let text = textCondition
        let columnPredicate = columnFilterState.predicate()
        let hasColumnFilters = !columnFilterState.isEmpty
        return { row in
            if let text, !text(row) { return false }
            if hasColumnFilters, !columnPredicate(row) { return false }
            return true
        }
    }

    private nonisolated static func containsPredicate(term: String, column: Int) -> @Sendable ([String]) -> Bool {
        if column < 0 {
            return { row in row.contains { $0.range(of: term, options: [.caseInsensitive, .diacriticInsensitive]) != nil } }
        }
        return { row in
            column < row.count && row[column].range(of: term, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }

    nonisolated static func looksLikeExpression(_ text: String) -> Bool {
        if text.range(of: #"(?i)\b(and|or|contains)\b"#, options: .regularExpression) != nil {
            return true
        }
        return text.contains("==")
            || text.contains("!=")
            || text.contains(">=")
            || text.contains("<=")
            || text.contains(">")
            || text.contains("<")
            || text.contains("=")
    }

    private func updateFilterStatus() {
        guard csvDocument != nil else { return }
        refreshFilterTokens()
        scheduleFacetRefresh()
        if !hasAnyFilter {
            statusLabel.stringValue = ""
            updateFeatureState()
            return
        }
        var parts: [String] = []
        if textCondition != nil { parts.append(textConditionDescription) }
        parts.append(contentsOf: columnFilterDescriptions())
        statusLabel.stringValue = L.t(
            "Filter: \(parts.joined(separator: " AND "))",
            "필터: \(parts.joined(separator: " AND "))"
        )
        updateFeatureState()
    }

    @objc func sortAscending(_ sender: Any?) {
        sortCurrentColumn(ascending: true)
    }

    @objc func sortDescending(_ sender: Any?) {
        sortCurrentColumn(ascending: false)
    }

    private func sortCurrentColumn(ascending: Bool) {
        guard let doc = csvDocument, doc.indexingComplete, !busy, !columnNames.isEmpty else { return }
        let column = max(0, min(currentDataColumn, columnNames.count - 1))
        sortKeys = [SortKey(column: column, ascending: ascending)]
        runSort()
    }

    @objc func clearSort(_ sender: Any?) {
        guard let doc = csvDocument, !busy else { return }
        sortKeys.removeAll()
        updateSortHeaders()
        if hasAnyFilter {
            doc.resetViewOrder()
            updateFilterStatus()
        } else {
            doc.clearView()
            statusLabel.stringValue = L.t("Sort cleared.", "정렬 해제.")
        }
        tableView.reloadData()
    }

    private func toggleSort(column: Int, additive: Bool) {
        guard let doc = csvDocument, doc.indexingComplete, !busy else { return }
        if additive {
            if let idx = sortKeys.firstIndex(where: { $0.column == column }) {
                sortKeys[idx] = SortKey(column: column, ascending: !sortKeys[idx].ascending)
            } else {
                sortKeys.append(SortKey(column: column, ascending: true))
            }
        } else {
            let ascending = sortKeys.count == 1 && sortKeys[0].column == column ? !sortKeys[0].ascending : true
            sortKeys = [SortKey(column: column, ascending: ascending)]
        }
        runSort()
    }

    private func runSort() {
        guard let doc = csvDocument, !sortKeys.isEmpty else { return }
        let keys = sortKeys
        runViewOperation(message: L.t("Sorting...", "정렬 중...")) { flag, progress in
            try doc.sort(keys: keys, progress: progress, cancellation: flag)
        } completion: { [weak self] in
            guard let self else { return }
            updateSortHeaders()
            let names = sortKeys.map { key in
                "\(self.columnNames[safe: key.column] ?? "Column \(key.column + 1)") \(key.ascending ? "▲" : "▼")"
            }.joined(separator: " → ")
            statusLabel.stringValue = L.t("Sorted by \(names).", "\(names) 기준 정렬.")
        }
    }

    private func updateSortHeaders() {
        for (index, name) in columnNames.enumerated() {
            let column = tableView.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier("c\(index)"))
            let typeText = columnTypeText(index)
            let displayTitle = headerDisplayTitle(columnName: name, typeText: typeText)
            let filterAvailable = isColumnFilterAvailable(column: index)
            let filterActive = columnFilterState.filter(for: index) != nil
            column?.title = displayTitle
            if let sortIndex = sortKeys.firstIndex(where: { $0.column == index }) {
                let key = sortKeys[sortIndex]
                let priority = sortKeys.count > 1 ? sortIndex + 1 : nil
                if let header = column?.headerCell as? SortHeaderCell {
                    header.stringValue = displayTitle
                    header.titleText = name
                    header.sortPriority = priority
                    header.ascending = key.ascending
                    header.typeText = typeText
                    header.columnIdentifierRawValue = column?.identifier.rawValue
                    header.filterAvailable = filterAvailable
                    header.filterActive = filterActive
                }
                column?.headerToolTip = headerTooltip(columnName: name, typeText: typeText, sortKey: key, priority: priority)
            } else {
                if let header = column?.headerCell as? SortHeaderCell {
                    header.stringValue = displayTitle
                    header.titleText = name
                    header.sortPriority = nil
                    header.ascending = nil
                    header.typeText = typeText
                    header.columnIdentifierRawValue = column?.identifier.rawValue
                    header.filterAvailable = filterAvailable
                    header.filterActive = filterActive
                }
                column?.headerToolTip = headerTooltip(columnName: name, typeText: typeText, sortKey: nil, priority: nil)
            }
        }
        tableView.headerView?.needsDisplay = true
    }

    private func columnTypeText(_ index: Int) -> String? {
        columnStatisticsReport?.columns[safe: index]?.inferredType.rawValue
    }

    private func isColumnFilterAvailable(column: Int) -> Bool {
        guard let type = columnStatisticsReport?.columns[safe: column]?.inferredType else { return false }
        return type == .categorical || type == .date
    }

    private func headerDisplayTitle(columnName: String, typeText: String?) -> String {
        guard let typeText else { return columnName }
        return "\(columnName)  [\(typeText)]"
    }

    private func headerTooltip(columnName: String, typeText: String?, sortKey: SortKey?, priority: Int?) -> String? {
        var lines = [columnName]
        if let typeText {
            lines.append(L.t("Type: \(typeText)", "타입: \(typeText)"))
        }
        if let sortKey {
            lines.append(L.t(
                "Sorted \(sortKey.ascending ? "ascending" : "descending")\(priority.map { ", priority \($0)" } ?? "")",
                "\(sortKey.ascending ? "오름차순" : "내림차순") 정렬\(priority.map { ", \($0)순위" } ?? "")"
            ))
        }
        return lines.count > 1 ? lines.joined(separator: "\n") : nil
    }

    @objc func toggleDetailPanel(_ sender: Any?) {
        let show: Bool
        if sender as? NSMenuItem != nil {
            show = !isInspectorVisible
            detailToggleButton.state = show ? .on : .off
        } else {
            show = detailToggleButton.state == .on
        }
        setInspectorVisible(show, animated: true)
        UserDefaults.standard.set(show, forKey: Self.inspectorVisibleDefaultsKey)
    }

    var isFacetsPanelVisible: Bool {
        !facetsPanel.isHidden
    }

    @objc func toggleFacetsPanel(_ sender: Any?) {
        setFacetsPanelVisible(facetsPanel.isHidden, persist: true)
    }

    func setFacetsPanelVisible(_ visible: Bool, persist: Bool) {
        guard visible == facetsPanel.isHidden else { return }
        facetsPanel.isHidden = !visible
        facetsWidthConstraint?.constant = visible ? FacetsPanelView.preferredWidth : 0
        if persist {
            UserDefaults.standard.set(visible, forKey: Self.facetsVisibleDefaultsKey)
        }
        if visible {
            refreshFacetsNow()
        } else {
            facetRefreshWorkItem?.cancel()
            facetsCancellation?.cancel()
            facetsCancellation = nil
        }
    }

    func scheduleFacetRefresh(delay: TimeInterval = 0.15) {
        facetRefreshWorkItem?.cancel()
        guard isFacetsPanelVisible else { return }
        let workItem = DispatchWorkItem { [weak self] in
            self?.refreshFacetsNow()
        }
        facetRefreshWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func refreshFacetsNow() {
        guard isFacetsPanelVisible else { return }
        facetGeneration += 1
        let generation = facetGeneration
        facetsCancellation?.cancel()
        facetsCancellation = nil

        guard let doc = csvDocument else {
            facetsPanel.renderMessage(L.t("Open a document to see facets.", "문서를 열면 패싯이 표시됩니다."))
            return
        }
        guard doc.indexingComplete else {
            facetsPanel.renderMessage(L.t("Loading...", "불러오는 중..."))
            return
        }
        let requests = facetColumnRequests()
        guard !requests.isEmpty else {
            facetsPanel.renderMessage(L.t("No columns to summarize.", "요약할 컬럼이 없습니다."))
            return
        }

        let cancellation = CancellationFlag()
        facetsCancellation = cancellation
        let basePredicate = textCondition
        var predicateBuilder: [Int: @Sendable ([String]) -> Bool] = [:]
        for filter in columnFilterState.filters {
            predicateBuilder[filter.column] = ColumnFilterState(filters: [filter]).predicate()
        }
        let columnPredicates = predicateBuilder
        let rowCap = Self.facetRowCap
        let filterSnapshot = columnFilterState
        let names = columnNames

        DispatchQueue.global(qos: .userInitiated).async { [weak self, weak doc] in
            guard let doc else { return }
            do {
                let report = try doc.facetSummaries(
                    columns: requests,
                    basePredicate: basePredicate,
                    columnPredicates: columnPredicates,
                    rowCap: rowCap,
                    cancellation: cancellation
                )
                DispatchQueue.main.async {
                    guard let self, self.facetGeneration == generation, doc === self.csvDocument else { return }
                    self.facetsCancellation = nil
                    let sections = Self.facetSections(
                        report: report,
                        columnNames: names,
                        filterState: filterSnapshot,
                        blankLabel: L.t("(Blank)", "(빈 값)")
                    )
                    let note = report.isRowCapped
                        ? L.t(
                            "Showing first \(report.scannedRowCount.formatted()) rows",
                            "처음 \(report.scannedRowCount.formatted())행 기준"
                        )
                        : nil
                    self.facetsPanel.render(sections: sections, note: note)
                }
            } catch CsvError.cancelled {
                DispatchQueue.main.async {
                    guard let self, self.facetGeneration == generation else { return }
                    self.facetsCancellation = nil
                }
            } catch {
                DispatchQueue.main.async {
                    guard let self, self.facetGeneration == generation else { return }
                    self.facetsCancellation = nil
                    self.facetsPanel.renderMessage(L.t("Facet scan failed.", "패싯 스캔에 실패했습니다."))
                }
            }
        }
    }

    private func facetColumnRequests() -> [FacetColumnRequest] {
        let visible = (0..<columnNames.count).filter { !hiddenColumnIndexes.contains($0) }
        return visible.prefix(Self.facetColumnLimit).map { column in
            let type = columnStatisticsReport?.columns[safe: column]?.inferredType
            return FacetColumnRequest(column: column, wantsHistogram: type == .integer || type == .float)
        }
    }

    static func facetSections(
        report: FacetReport,
        columnNames: [String],
        filterState: ColumnFilterState,
        blankLabel: String
    ) -> [FacetPanelSection] {
        report.summaries.compactMap { summary in
            let title = columnNames.indices.contains(summary.column)
                ? columnNames[summary.column]
                : "Column \(summary.column + 1)"
            let activeFilter = filterState.filter(for: summary.column)
            switch summary.content {
            case .topValues(let bins, let otherCount, let distinctTruncated):
                guard !bins.isEmpty else { return nil }
                var activeValues: Set<String> = []
                var activeBlanks = false
                if case .selectedValues(_, let values, let includeBlanks)? = activeFilter {
                    activeValues = values
                    activeBlanks = includeBlanks
                }
                let maxCount = bins.map(\.count).max() ?? 0
                let entries = bins.map { bin in
                    FacetPanelEntry(
                        label: bin.value.isEmpty ? blankLabel : bin.value,
                        count: bin.count,
                        maxCount: maxCount,
                        kind: .value(bin.value),
                        isActive: bin.value.isEmpty ? activeBlanks : activeValues.contains(bin.value)
                    )
                }
                var footnotes: [String] = []
                if otherCount > 0 {
                    footnotes.append(L.t("+\(otherCount.formatted()) in other values", "기타 값 \(otherCount.formatted())개"))
                }
                if distinctTruncated {
                    footnotes.append(L.t("approximate", "근사치"))
                }
                return FacetPanelSection(
                    column: summary.column,
                    title: title,
                    entries: entries,
                    footnote: footnotes.isEmpty ? nil : footnotes.joined(separator: " · ")
                )
            case .histogram(let bins, _, let nonNumericCount):
                guard !bins.isEmpty else { return nil }
                var activeRange: (lower: Double, upper: Double, includesUpperBound: Bool)?
                if case .numericRange(_, let lower, let upper, let includesUpperBound)? = activeFilter {
                    activeRange = (lower, upper, includesUpperBound)
                }
                let maxCount = bins.map(\.count).max() ?? 0
                let entries = bins.enumerated().map { index, bin in
                    let includesUpperBound = index == bins.count - 1
                    let label = "\(ColumnFilterState.numericBoundLabel(bin.lowerBound)) – \(ColumnFilterState.numericBoundLabel(bin.upperBound))"
                    let isActive = activeRange.map {
                        $0.lower == bin.lowerBound && $0.upper == bin.upperBound && $0.includesUpperBound == includesUpperBound
                    } ?? false
                    return FacetPanelEntry(
                        label: label,
                        count: bin.count,
                        maxCount: maxCount,
                        kind: .numericRange(
                            lower: bin.lowerBound,
                            upper: bin.upperBound,
                            includesUpperBound: includesUpperBound
                        ),
                        isActive: isActive
                    )
                }
                let footnote = nonNumericCount > 0
                    ? L.t("\(nonNumericCount.formatted()) non-numeric", "숫자 아님 \(nonNumericCount.formatted())개")
                    : nil
                return FacetPanelSection(
                    column: summary.column,
                    title: title,
                    entries: entries,
                    footnote: footnote
                )
            }
        }
    }

    func handleFacetSelection(column: Int, kind: FacetPanelEntry.Kind) {
        guard csvDocument?.indexingComplete == true, !busy else { return }
        let current = columnFilterState.filter(for: column)
        switch kind {
        case .value(let value):
            var values: Set<String> = []
            var includeBlanks = false
            if case .selectedValues(_, let currentValues, let currentBlanks)? = current {
                values = currentValues
                includeBlanks = currentBlanks
            }
            if value.isEmpty {
                includeBlanks.toggle()
            } else if values.contains(value) {
                values.remove(value)
            } else {
                values.insert(value)
            }
            if values.isEmpty && !includeBlanks {
                clearColumnFilter(column: column)
            } else {
                applyColumnFilter(.selectedValues(column: column, values: values, includeBlanks: includeBlanks))
            }
        case .numericRange(let lower, let upper, let includesUpperBound):
            if case .numericRange(_, let currentLower, let currentUpper, let currentInclusive)? = current,
               currentLower == lower, currentUpper == upper, currentInclusive == includesUpperBound {
                clearColumnFilter(column: column)
            } else {
                applyColumnFilter(.numericRange(column: column, lower: lower, upper: upper, includesUpperBound: includesUpperBound))
            }
        }
    }

    @objc func toggleFilterBar(_ sender: Any?) {
        setFilterBarVisible(filterBarView.isHidden, focus: true)
    }

    @objc func toggleSelectedValueExpansion(_ sender: Any?) {
        selectedValueExpanded.toggle()
        updateSelectedValueExpansionLayout()
    }

    @objc func goToRow(_ sender: Any?) {
        guard let doc = csvDocument, !busy else { return }
        let alert = NSAlert()
        alert.messageText = L.t("Go to Row", "행으로 이동")
        alert.informativeText = L.t("Enter a source row number.", "원본 행 번호를 입력하세요.")
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        input.placeholderString = "1"
        if tableView.selectedRow >= 0 {
            input.stringValue = "\(doc.getSourceRowNumber(tableView.selectedRow))"
        }
        alert.accessoryView = input
        alert.addButton(withTitle: L.t("Go", "이동"))
        alert.addButton(withTitle: L.t("Cancel", "취소"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let trimmed = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let rowNumber = Int64(trimmed), rowNumber > 0 else {
            statusLabel.stringValue = L.t("Enter a valid row number.", "올바른 행 번호를 입력하세요.")
            return
        }
        guard let displayRow = doc.displayIndexForSourceRowNumber(rowNumber) else {
            let suffix = doc.indexingComplete ? "" : L.t(" Indexing is still in progress.", " 아직 인덱싱 중입니다.")
            statusLabel.stringValue = L.t("Row \(rowNumber.formatted()) is not currently visible.\(suffix)", "\(rowNumber.formatted())행은 현재 표시되지 않습니다.\(suffix)")
            return
        }
        tableView.selectRowIndexes(IndexSet(integer: displayRow), byExtendingSelection: false)
        tableView.scrollRowToVisible(displayRow)
        statusLabel.stringValue = L.t("Moved to row \(rowNumber.formatted()).", "\(rowNumber.formatted())행으로 이동했습니다.")
    }

    @objc func showColumnStatistics(_ sender: Any?) {
        guard csvDocument != nil else { return }
        let column = max(0, min(currentDataColumn, max(0, columnNames.count - 1)))
        setInspectorVisible(true, animated: true)
        renderColumnStatistics(column: column)
    }

    @objc func showPerformanceDashboard(_ sender: Any?) {
        guard let snapshot = performanceSnapshot() else { return }
        setInspectorVisible(true, animated: true)
        detailHeaderLabel.stringValue = L.t("Performance", "성능")
        detailTextView.string = snapshot.formattedLines().joined(separator: "\n")
        currentInspectorContentKind = .performance
        updateInspectorCopyButtons()
    }

    @objc func showNumericDistribution(_ sender: Any?) {
        beginAnalysis(.numericDistribution, sender: sender)
    }

    @objc func showDateHistogram(_ sender: Any?) {
        beginAnalysis(.dateHistogram, sender: sender)
    }

    @objc func showDuplicateRows(_ sender: Any?) {
        beginAnalysis(.duplicateRows, sender: sender)
    }

    @objc func showGroupBy(_ sender: Any?) {
        beginAnalysis(.groupBy, sender: sender)
    }

    @objc func showPivotTable(_ sender: Any?) {
        guard let builder = makePivotBuilder(initialResultTab: .table) else { return }
        pivotBuilderWindow = builder
        builder.showWindow(sender)
        builder.window?.makeKeyAndOrderFront(sender)
    }

    @objc func showPivotChart(_ sender: Any?) {
        guard let builder = makePivotBuilder(initialResultTab: .chart) else { return }
        pivotBuilderWindow = builder
        builder.showWindow(sender)
        builder.window?.makeKeyAndOrderFront(sender)
    }

    private func makePivotBuilder(initialResultTab: PivotBuilderWindowController.InitialResultTab = .table) -> PivotBuilderWindowController? {
        guard let doc = csvDocument, doc.indexingComplete, !busy, columnNames.count >= 2 else { return nil }
        return PivotBuilderWindowController(
            document: doc,
            columnNames: columnNames,
            columnStatisticsReport: columnStatisticsReport,
            initialResultTab: initialResultTab
        )
    }

    @objc func showCorrelation(_ sender: Any?) {
        beginAnalysis(.correlation, sender: sender)
    }

    @objc func showTTest(_ sender: Any?) {
        beginAnalysis(.independentTTest, sender: sender)
    }

    @objc func showChiSquare(_ sender: Any?) {
        beginAnalysis(.chiSquare, sender: sender)
    }

    @objc func showQuickStats(_ sender: Any?) {
        beginAnalysis(.documentSummary, sender: nil)
    }

    @objc func showDescriptiveStatistics(_ sender: Any?) {
        beginAnalysis(.descriptiveStatistics, sender: sender)
    }

    @objc func showFrequencyAnalysis(_ sender: Any?) {
        beginAnalysis(.frequencyAnalysis, sender: sender)
    }

    @objc func showOneWayAnova(_ sender: Any?) {
        beginAnalysis(.oneWayAnova, sender: sender)
    }

    @objc func showNormalityTest(_ sender: Any?) {
        beginAnalysis(.normalityTest, sender: sender)
    }

    private func beginAnalysis(_ kind: AnalysisKind, sender: Any?) {
        guard let doc = csvDocument, doc.indexingComplete, !busy || kind == .documentSummary else { return }
        guard let defaultRequest = defaultAnalysisRequest(for: kind) else {
            statusLabel.stringValue = L.t("No valid columns for this analysis.", "이 분석에 사용할 수 있는 컬럼이 없습니다.")
            return
        }
        if sender is NSMenuItem, kind != .documentSummary {
            promptAnalysisRequest(kind: kind, defaultRequest: defaultRequest)
        } else {
            performAnalysis(defaultRequest)
        }
    }

    private func defaultAnalysisRequest(for kind: AnalysisKind) -> AnalysisRequest? {
        guard csvDocument != nil else { return nil }
        let selected = clampedCurrentDataColumn()
        switch kind {
        case .numericDistribution:
            let column = isNumericColumn(selected) ? selected : (firstNumericColumn(excluding: -1) ?? selected)
            return .numericDistribution(column: column, binCount: 10)
        case .dateHistogram:
            let dateColumn = isDateColumn(selected) ? selected : (firstDateColumn(excluding: -1) ?? selected)
            return .dateHistogram(dateColumn: dateColumn, valueColumn: firstNumericColumn(excluding: dateColumn), period: .month)
        case .duplicateRows:
            let second = min(selected + 1, max(0, columnNames.count - 1))
            return .duplicateRows(columns: selected == second ? [selected] : [selected, second])
        case .groupBy:
            return .groupBy(
                groupColumns: [selected],
                valueColumn: firstNumericColumn(excluding: selected) ?? selected,
                functions: [.count, .sum, .mean, .median, .min, .max, .uniqueCount, .standardDeviation]
            )
        case .correlation:
            let x = firstNumericColumn(excluding: -1) ?? selected
            let y = firstNumericColumn(excluding: x) ?? selected
            guard x != y || columnNames.count == 1 else { return nil }
            return .correlation(xColumn: x, yColumn: y)
        case .independentTTest:
            let groupColumn = firstNonNumericColumn(excluding: -1) ?? selected
            let valueColumn = firstNumericColumn(excluding: groupColumn) ?? selected
            guard let groups = topGroups(column: groupColumn, limit: 2), groups.count == 2 else { return nil }
            return .independentTTest(groupColumn: groupColumn, valueColumn: valueColumn, groupA: groups[0], groupB: groups[1])
        case .chiSquare:
            let rowColumn = firstNonNumericColumn(excluding: -1) ?? selected
            let columnColumn = firstNonNumericColumn(excluding: rowColumn) ?? min(rowColumn + 1, max(0, columnNames.count - 1))
            return .chiSquare(rowColumn: rowColumn, columnColumn: columnColumn)
        case .descriptiveStatistics:
            let numericColumns = columnNames.indices.filter { isNumericColumn($0) }
            let fallback = isNumericColumn(selected) ? [selected] : []
            let columns = numericColumns.isEmpty ? fallback : Array(numericColumns.prefix(6))
            guard !columns.isEmpty else { return nil }
            return .descriptiveStatistics(columns: columns)
        case .frequencyAnalysis:
            let column = isNumericColumn(selected) ? (firstNonNumericColumn(excluding: -1) ?? selected) : selected
            return .frequencyAnalysis(column: column)
        case .oneWayAnova:
            let groupColumn = firstNonNumericColumn(excluding: -1) ?? selected
            guard let valueColumn = firstNumericColumn(excluding: groupColumn) else { return nil }
            return .oneWayAnova(groupColumn: groupColumn, valueColumn: valueColumn)
        case .normalityTest:
            let column = isNumericColumn(selected) ? selected : (firstNumericColumn(excluding: -1) ?? selected)
            guard isNumericColumn(column) else { return nil }
            return .normalityTest(column: column)
        case .documentSummary:
            return .documentSummary
        }
    }

    private func promptAnalysisRequest(kind: AnalysisKind, defaultRequest: AnalysisRequest) {
        let sheet = makeAnalysisPromptSheet(kind: kind, defaultRequest: defaultRequest)
        sheet.panel.runHandler = { [weak self, weak panel = sheet.panel] in
            guard let self,
                  let panel,
                  let request = sheet.buildRequest() else { return }
            panel.sheetParent?.endSheet(panel, returnCode: .OK)
            panel.orderOut(nil)
            self.performAnalysis(request)
        }
        window?.beginSheet(sheet.panel)
    }

    private func makeAnalysisPromptSheet(kind: AnalysisKind, defaultRequest: AnalysisRequest) -> AnalysisPromptSheet {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.widthAnchor.constraint(equalToConstant: Self.analysisPromptContentWidth).isActive = true

        var buildRequest: (() -> AnalysisRequest?)?
        switch defaultRequest {
        case .numericDistribution(let column, let binCount):
            let columnPopup = makeColumnPopup(preferredTypes: [.integer, .float], selected: column)
            let binsField = NSTextField(string: "\(binCount)")
            binsField.widthAnchor.constraint(equalToConstant: 120).isActive = true
            addAnalysisPromptRow(to: stack, label: L.t("Column", "컬럼"), control: columnPopup)
            addAnalysisPromptRow(to: stack, label: L.t("Bins", "구간"), control: binsField)
            buildRequest = {
                .numericDistribution(column: self.selectedColumn(in: columnPopup) ?? column, binCount: max(1, Int(binsField.stringValue) ?? binCount))
            }
        case .dateHistogram(let dateColumn, let valueColumn, let period):
            let datePopup = makeColumnPopup(preferredTypes: [.date], selected: dateColumn)
            let valuePopup = makeColumnPopup(preferredTypes: [.integer, .float], selected: valueColumn ?? -1, includeNone: true)
            let periodPopup = NSPopUpButton()
            periodPopup.widthAnchor.constraint(equalToConstant: Self.analysisPromptPopupWidth).isActive = true
            for item in DateBinPeriod.allCases {
                periodPopup.addItem(withTitle: item.rawValue)
                periodPopup.lastItem?.representedObject = item.rawValue
            }
            periodPopup.selectItem(withTitle: period.rawValue)
            addAnalysisPromptRow(to: stack, label: L.t("Date column", "날짜 컬럼"), control: datePopup)
            addAnalysisPromptRow(to: stack, label: L.t("Value column", "값 컬럼"), control: valuePopup)
            addAnalysisPromptRow(to: stack, label: L.t("Period", "단위"), control: periodPopup)
            buildRequest = {
                let period = DateBinPeriod(rawValue: periodPopup.titleOfSelectedItem ?? DateBinPeriod.month.rawValue) ?? .month
                return .dateHistogram(dateColumn: self.selectedColumn(in: datePopup) ?? dateColumn, valueColumn: self.selectedColumn(in: valuePopup), period: period)
            }
        case .duplicateRows(let columns):
            let first = columns.first ?? clampedCurrentDataColumn()
            let second = columns.dropFirst().first ?? -1
            let firstPopup = makeColumnPopup(selected: first)
            let secondPopup = makeColumnPopup(selected: second, includeNone: true)
            addAnalysisPromptRow(to: stack, label: L.t("Primary column", "기준 컬럼"), control: firstPopup)
            addAnalysisPromptRow(to: stack, label: L.t("Second column", "두 번째 컬럼"), control: secondPopup)
            buildRequest = {
                let values = [self.selectedColumn(in: firstPopup), self.selectedColumn(in: secondPopup)].compactMap { $0 }
                return .duplicateRows(columns: Array(Set(values)).sorted())
            }
        case .groupBy(let groupColumns, let valueColumn, let functions):
            let groupPopup = makeColumnPopup(selected: groupColumns.first ?? clampedCurrentDataColumn())
            let valuePopup = makeColumnPopup(preferredTypes: [.integer, .float], selected: valueColumn)
            let functionPopup = NSPopUpButton()
            functionPopup.widthAnchor.constraint(equalToConstant: Self.analysisPromptPopupWidth).isActive = true
            [L.t("All summary metrics", "모든 요약 지표"), "Count", "Sum", "Mean"].forEach { functionPopup.addItem(withTitle: $0) }
            addAnalysisPromptRow(to: stack, label: L.t("Group column", "그룹 컬럼"), control: groupPopup)
            addAnalysisPromptRow(to: stack, label: L.t("Value column", "값 컬럼"), control: valuePopup)
            addAnalysisPromptRow(to: stack, label: L.t("Metrics", "지표"), control: functionPopup)
            buildRequest = {
                let selectedFunctions: [AggregationFunction]
                switch functionPopup.indexOfSelectedItem {
                case 1: selectedFunctions = [.count]
                case 2: selectedFunctions = [.sum]
                case 3: selectedFunctions = [.mean]
                default: selectedFunctions = functions
                }
                return .groupBy(groupColumns: [self.selectedColumn(in: groupPopup) ?? 0], valueColumn: self.selectedColumn(in: valuePopup) ?? valueColumn, functions: selectedFunctions)
            }
        case .correlation(let xColumn, let yColumn):
            let xPopup = makeColumnPopup(preferredTypes: [.integer, .float], selected: xColumn)
            let yPopup = makeColumnPopup(preferredTypes: [.integer, .float], selected: yColumn)
            addAnalysisPromptRow(to: stack, label: "X", control: xPopup)
            addAnalysisPromptRow(to: stack, label: "Y", control: yPopup)
            buildRequest = { .correlation(xColumn: self.selectedColumn(in: xPopup) ?? xColumn, yColumn: self.selectedColumn(in: yPopup) ?? yColumn) }
        case .independentTTest(let groupColumn, let valueColumn, let groupA, let groupB):
            let groupPopup = makeColumnPopup(preferredTypes: [.categorical, .string, .boolean], selected: groupColumn)
            let valuePopup = makeColumnPopup(preferredTypes: [.integer, .float], selected: valueColumn)
            let groupAField = NSTextField(string: groupA)
            let groupBField = NSTextField(string: groupB)
            groupAField.widthAnchor.constraint(equalToConstant: Self.analysisPromptPopupWidth).isActive = true
            groupBField.widthAnchor.constraint(equalToConstant: Self.analysisPromptPopupWidth).isActive = true
            addAnalysisPromptRow(to: stack, label: L.t("Group column", "그룹 컬럼"), control: groupPopup)
            addAnalysisPromptRow(to: stack, label: L.t("Value column", "값 컬럼"), control: valuePopup)
            addAnalysisPromptRow(to: stack, label: "A", control: groupAField)
            addAnalysisPromptRow(to: stack, label: "B", control: groupBField)
            buildRequest = {
                .independentTTest(groupColumn: self.selectedColumn(in: groupPopup) ?? groupColumn, valueColumn: self.selectedColumn(in: valuePopup) ?? valueColumn, groupA: groupAField.stringValue, groupB: groupBField.stringValue)
            }
        case .chiSquare(let rowColumn, let columnColumn):
            let rowPopup = makeColumnPopup(preferredTypes: [.categorical, .string, .boolean], selected: rowColumn)
            let columnPopup = makeColumnPopup(preferredTypes: [.categorical, .string, .boolean], selected: columnColumn)
            addAnalysisPromptRow(to: stack, label: L.t("Rows", "행"), control: rowPopup)
            addAnalysisPromptRow(to: stack, label: L.t("Columns", "열"), control: columnPopup)
            buildRequest = { .chiSquare(rowColumn: self.selectedColumn(in: rowPopup) ?? rowColumn, columnColumn: self.selectedColumn(in: columnPopup) ?? columnColumn) }
        case .descriptiveStatistics(let columns):
            let scopePopup = NSPopUpButton()
            scopePopup.widthAnchor.constraint(equalToConstant: Self.analysisPromptPopupWidth).isActive = true
            scopePopup.addItem(withTitle: L.t("All numeric columns", "모든 숫자 컬럼"))
            scopePopup.addItem(withTitle: L.t("Single column", "단일 컬럼"))
            let columnPopup = makeColumnPopup(preferredTypes: [.integer, .float], selected: columns.first ?? clampedCurrentDataColumn())
            addAnalysisPromptRow(to: stack, label: L.t("Scope", "범위"), control: scopePopup)
            addAnalysisPromptRow(to: stack, label: L.t("Column", "컬럼"), control: columnPopup)
            buildRequest = {
                if scopePopup.indexOfSelectedItem == 0 {
                    let numericColumns = self.columnNames.indices.filter { self.isNumericColumn($0) }
                    return .descriptiveStatistics(columns: numericColumns.isEmpty ? columns : numericColumns)
                }
                let column = self.selectedColumn(in: columnPopup) ?? columns.first ?? 0
                return .descriptiveStatistics(columns: [column])
            }
        case .frequencyAnalysis(let column):
            let columnPopup = makeColumnPopup(selected: column)
            addAnalysisPromptRow(to: stack, label: L.t("Column", "컬럼"), control: columnPopup)
            buildRequest = { .frequencyAnalysis(column: self.selectedColumn(in: columnPopup) ?? column) }
        case .oneWayAnova(let groupColumn, let valueColumn):
            let groupPopup = makeColumnPopup(preferredTypes: [.categorical, .string, .boolean], selected: groupColumn)
            let valuePopup = makeColumnPopup(preferredTypes: [.integer, .float], selected: valueColumn)
            addAnalysisPromptRow(to: stack, label: L.t("Group column", "그룹 컬럼"), control: groupPopup)
            addAnalysisPromptRow(to: stack, label: L.t("Value column", "값 컬럼"), control: valuePopup)
            buildRequest = {
                .oneWayAnova(groupColumn: self.selectedColumn(in: groupPopup) ?? groupColumn, valueColumn: self.selectedColumn(in: valuePopup) ?? valueColumn)
            }
        case .normalityTest(let column):
            let columnPopup = makeColumnPopup(preferredTypes: [.integer, .float], selected: column)
            addAnalysisPromptRow(to: stack, label: L.t("Column", "컬럼"), control: columnPopup)
            buildRequest = { .normalityTest(column: self.selectedColumn(in: columnPopup) ?? column) }
        case .documentSummary:
            buildRequest = { .documentSummary }
        }

        return makeAnalysisPromptSheet(
            title: kind.title,
            informativeText: L.t("Choose analysis parameters, then run.", "분석 조건을 선택한 뒤 실행하세요."),
            form: stack,
            buildRequest: buildRequest ?? { nil }
        )
    }

    private func makeAnalysisPromptSheet(
        title: String,
        informativeText: String,
        form: NSStackView,
        buildRequest: @escaping () -> AnalysisRequest?
    ) -> AnalysisPromptSheet {
        let rowCount = form.arrangedSubviews.count
        let contentHeight = max(CGFloat(280), CGFloat(176 + rowCount * 42))
        let panel = AnalysisPromptPanel(
            contentRect: NSRect(x: 0, y: 0, width: Self.analysisPromptPanelWidth, height: contentHeight),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        panel.title = title
        panel.isReleasedWhenClosed = false

        let contentView = NSView()
        contentView.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView = contentView

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let descriptionLabel = NSTextField(labelWithString: informativeText)
        descriptionLabel.font = .systemFont(ofSize: 12)
        descriptionLabel.textColor = .secondaryLabelColor
        descriptionLabel.lineBreakMode = .byWordWrapping
        descriptionLabel.maximumNumberOfLines = 2
        descriptionLabel.translatesAutoresizingMaskIntoConstraints = false

        let buttonRow = NSStackView()
        buttonRow.orientation = .horizontal
        buttonRow.alignment = .centerY
        buttonRow.spacing = 8
        buttonRow.translatesAutoresizingMaskIntoConstraints = false

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let cancelButton = NSButton(title: L.t("Cancel", "취소"), target: panel, action: #selector(AnalysisPromptPanel.cancel(_:)))
        cancelButton.identifier = .analysisPromptCancelButton
        cancelButton.bezelStyle = .rounded
        cancelButton.widthAnchor.constraint(equalToConstant: Self.analysisPromptButtonWidth).isActive = true

        let runButton = NSButton(title: L.t("Run", "실행"), target: panel, action: #selector(AnalysisPromptPanel.run(_:)))
        runButton.identifier = .analysisPromptRunButton
        runButton.bezelStyle = .rounded
        runButton.keyEquivalent = "\r"
        runButton.widthAnchor.constraint(equalToConstant: Self.analysisPromptButtonWidth).isActive = true

        buttonRow.addArrangedSubview(spacer)
        buttonRow.addArrangedSubview(cancelButton)
        buttonRow.addArrangedSubview(runButton)

        contentView.addSubview(titleLabel)
        contentView.addSubview(descriptionLabel)
        contentView.addSubview(form)
        contentView.addSubview(buttonRow)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 28),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -28),
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 24),
            descriptionLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            descriptionLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            descriptionLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 6),
            form.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            form.trailingAnchor.constraint(lessThanOrEqualTo: titleLabel.trailingAnchor),
            form.topAnchor.constraint(equalTo: descriptionLabel.bottomAnchor, constant: 18),
            buttonRow.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            buttonRow.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            buttonRow.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -22),
            form.bottomAnchor.constraint(lessThanOrEqualTo: buttonRow.topAnchor, constant: -18)
        ])

        return AnalysisPromptSheet(panel: panel, buildRequest: buildRequest)
    }

    // MARK: - Visualization chart windows

    @objc func showHistogramChartWindow(_ sender: Any?) {
        startChartFlow(kind: .histogram, prompt: sender is NSMenuItem)
    }

    @objc func showBoxplotChartWindow(_ sender: Any?) {
        startChartFlow(kind: .boxplot, prompt: sender is NSMenuItem)
    }

    @objc func showScatterChartWindow(_ sender: Any?) {
        startChartFlow(kind: .scatter, prompt: sender is NSMenuItem)
    }

    @objc func showCorrelationHeatmapWindow(_ sender: Any?) {
        startChartFlow(kind: .correlationHeatmap, prompt: false)
    }

    @objc func showQQPlotChartWindow(_ sender: Any?) {
        startChartFlow(kind: .qqPlot, prompt: sender is NSMenuItem)
    }

    @objc func showTimeseriesChartWindow(_ sender: Any?) {
        startChartFlow(kind: .timeseries, prompt: sender is NSMenuItem)
    }

    @objc func showParetoChartWindow(_ sender: Any?) {
        startChartFlow(kind: .pareto, prompt: sender is NSMenuItem)
    }

    private func startChartFlow(kind: ChartKind, prompt: Bool) {
        guard csvDocument?.indexingComplete == true, !busy else { return }
        guard let defaultRequest = defaultChartRequest(for: kind) else {
            statusLabel.stringValue = L.t("No suitable columns for this chart.", "이 차트에 적합한 컬럼이 없습니다.")
            return
        }
        if prompt {
            promptChartRequest(kind: kind, defaultRequest: defaultRequest)
        } else {
            openChartWindow(request: defaultRequest)
        }
    }

    func defaultChartRequest(for kind: ChartKind) -> ChartRequest? {
        guard csvDocument != nil else { return nil }
        let selected = clampedCurrentDataColumn()
        switch kind {
        case .histogram:
            let column = isNumericColumn(selected) ? selected : (firstNumericColumn(excluding: -1) ?? selected)
            guard isNumericColumn(column) || columnStatisticsReport == nil else { return nil }
            return .histogram(column: column, binCount: 20)
        case .boxplot:
            guard let valueColumn = isNumericColumn(selected) ? selected : firstNumericColumn(excluding: -1) else { return nil }
            return .boxplot(groupColumn: firstNonNumericColumn(excluding: -1), valueColumn: valueColumn)
        case .scatter:
            guard let x = firstNumericColumn(excluding: -1), let y = firstNumericColumn(excluding: x) else { return nil }
            return .scatter(xColumn: x, yColumn: y)
        case .correlationHeatmap:
            let numericColumns = columnNames.indices.filter { isNumericColumn($0) }
            guard numericColumns.count >= 2 else { return nil }
            return .correlationHeatmap(columns: Array(numericColumns.prefix(12)))
        case .qqPlot:
            let column = isNumericColumn(selected) ? selected : (firstNumericColumn(excluding: -1) ?? selected)
            guard isNumericColumn(column) || columnStatisticsReport == nil else { return nil }
            return .qqPlot(column: column)
        case .timeseries:
            let dateColumn = isDateColumn(selected) ? selected : (firstDateColumn(excluding: -1) ?? selected)
            return .timeseries(dateColumn: dateColumn, valueColumn: nil, period: .month)
        case .pareto:
            let column = isNumericColumn(selected) ? (firstNonNumericColumn(excluding: -1) ?? selected) : selected
            return .pareto(column: column)
        }
    }

    private func promptChartRequest(kind: ChartKind, defaultRequest: ChartRequest) {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.widthAnchor.constraint(equalToConstant: Self.analysisPromptContentWidth).isActive = true

        var buildRequest: () -> ChartRequest? = { nil }
        switch defaultRequest {
        case .histogram(let column, let binCount):
            let columnPopup = makeColumnPopup(preferredTypes: [.integer, .float], selected: column)
            let binsField = NSTextField(string: "\(binCount)")
            binsField.widthAnchor.constraint(equalToConstant: 120).isActive = true
            addAnalysisPromptRow(to: stack, label: L.t("Column", "컬럼"), control: columnPopup)
            addAnalysisPromptRow(to: stack, label: L.t("Bins", "구간"), control: binsField)
            buildRequest = {
                .histogram(column: self.selectedColumn(in: columnPopup) ?? column, binCount: max(2, Int(binsField.stringValue) ?? binCount))
            }
        case .boxplot(let groupColumn, let valueColumn):
            let valuePopup = makeColumnPopup(preferredTypes: [.integer, .float], selected: valueColumn)
            let groupPopup = makeColumnPopup(preferredTypes: [.categorical, .string, .boolean], selected: groupColumn ?? -1, includeNone: true)
            addAnalysisPromptRow(to: stack, label: L.t("Value column", "값 컬럼"), control: valuePopup)
            addAnalysisPromptRow(to: stack, label: L.t("Group column", "그룹 컬럼"), control: groupPopup)
            buildRequest = {
                .boxplot(groupColumn: self.selectedColumn(in: groupPopup), valueColumn: self.selectedColumn(in: valuePopup) ?? valueColumn)
            }
        case .scatter(let xColumn, let yColumn):
            let xPopup = makeColumnPopup(preferredTypes: [.integer, .float], selected: xColumn)
            let yPopup = makeColumnPopup(preferredTypes: [.integer, .float], selected: yColumn)
            addAnalysisPromptRow(to: stack, label: "X", control: xPopup)
            addAnalysisPromptRow(to: stack, label: "Y", control: yPopup)
            buildRequest = {
                .scatter(xColumn: self.selectedColumn(in: xPopup) ?? xColumn, yColumn: self.selectedColumn(in: yPopup) ?? yColumn)
            }
        case .correlationHeatmap(let columns):
            buildRequest = { .correlationHeatmap(columns: columns) }
        case .qqPlot(let column):
            let columnPopup = makeColumnPopup(preferredTypes: [.integer, .float], selected: column)
            addAnalysisPromptRow(to: stack, label: L.t("Column", "컬럼"), control: columnPopup)
            buildRequest = { .qqPlot(column: self.selectedColumn(in: columnPopup) ?? column) }
        case .timeseries(let dateColumn, let valueColumn, let period):
            let datePopup = makeColumnPopup(preferredTypes: [.date], selected: dateColumn)
            let valuePopup = makeColumnPopup(preferredTypes: [.integer, .float], selected: valueColumn ?? -1, includeNone: true)
            let periodPopup = NSPopUpButton()
            periodPopup.widthAnchor.constraint(equalToConstant: Self.analysisPromptPopupWidth).isActive = true
            for item in DateBinPeriod.allCases {
                periodPopup.addItem(withTitle: item.rawValue)
            }
            periodPopup.selectItem(withTitle: period.rawValue)
            addAnalysisPromptRow(to: stack, label: L.t("Date column", "날짜 컬럼"), control: datePopup)
            addAnalysisPromptRow(to: stack, label: L.t("Value column", "값 컬럼"), control: valuePopup)
            addAnalysisPromptRow(to: stack, label: L.t("Period", "단위"), control: periodPopup)
            buildRequest = {
                let period = DateBinPeriod(rawValue: periodPopup.titleOfSelectedItem ?? DateBinPeriod.month.rawValue) ?? .month
                return .timeseries(
                    dateColumn: self.selectedColumn(in: datePopup) ?? dateColumn,
                    valueColumn: self.selectedColumn(in: valuePopup),
                    period: period
                )
            }
        case .pareto(let column):
            let columnPopup = makeColumnPopup(preferredTypes: [.categorical, .string, .boolean], selected: column)
            addAnalysisPromptRow(to: stack, label: L.t("Column", "컬럼"), control: columnPopup)
            buildRequest = { .pareto(column: self.selectedColumn(in: columnPopup) ?? column) }
        }

        let sheet = makeAnalysisPromptSheet(
            title: kind.title,
            informativeText: L.t("Choose chart parameters, then run.", "차트 조건을 선택한 뒤 실행하세요."),
            form: stack,
            buildRequest: { nil }
        )
        sheet.panel.runHandler = { [weak self, weak panel = sheet.panel] in
            guard let self, let panel, let request = buildRequest() else { return }
            panel.sheetParent?.endSheet(panel, returnCode: .OK)
            panel.orderOut(nil)
            self.openChartWindow(request: request)
        }
        window?.beginSheet(sheet.panel)
    }

    func openChartWindow(request: ChartRequest) {
        guard let doc = csvDocument, doc.indexingComplete, !busy else { return }
        chartCancellation?.cancel()
        let cancellation = CancellationFlag()
        chartCancellation = cancellation
        let names = columnNames
        let documentName = (currentFilePath as NSString?)?.lastPathComponent ?? "CSV"
        let scopeNote = doc.analysisRowsTruncated
            ? L.t(
                "Showing first \(VirtualCsvDocument.analysisRowLimit.formatted()) rows",
                "처음 \(VirtualCsvDocument.analysisRowLimit.formatted())행 기준"
            )
            : nil
        setBusy(true, message: L.t("Preparing chart...", "차트 준비 중..."))

        DispatchQueue.global(qos: .userInitiated).async { [weak self, weak doc] in
            guard let doc else { return }
            do {
                let render = try Self.buildChartRender(request: request, document: doc, columnNames: names, cancellation: cancellation)
                DispatchQueue.main.async {
                    guard let self, doc === self.csvDocument, self.chartCancellation === cancellation else { return }
                    self.chartCancellation = nil
                    self.setBusy(false)
                    guard let render else {
                        self.statusLabel.stringValue = L.t("Not enough data for this chart.", "차트를 그릴 데이터가 부족합니다.")
                        return
                    }
                    self.statusLabel.stringValue = ""
                    self.presentChartWindow(ChartWindowModel(
                        kind: request.kind,
                        documentName: documentName,
                        render: render,
                        scopeNote: scopeNote
                    ))
                }
            } catch CsvError.cancelled {
                DispatchQueue.main.async {
                    guard let self, self.chartCancellation === cancellation else { return }
                    self.chartCancellation = nil
                    self.setBusy(false)
                }
            } catch {
                DispatchQueue.main.async {
                    guard let self, self.chartCancellation === cancellation else { return }
                    self.chartCancellation = nil
                    self.setBusy(false)
                    self.presentError(error)
                }
            }
        }
    }

    private nonisolated static func buildChartRender(
        request: ChartRequest,
        document: VirtualCsvDocument,
        columnNames: [String],
        cancellation: CancellationFlag
    ) throws -> ChartRenderModel? {
        func name(_ index: Int) -> String {
            columnNames.indices.contains(index) ? columnNames[index] : "Column \(index + 1)"
        }
        switch request {
        case .histogram(let column, let binCount):
            let data = try document.histogramChartData(column: column, binCount: binCount, cancellation: cancellation)
            guard data.distribution.count > 0 else { return nil }
            return .histogram(data, columnName: name(column))
        case .boxplot(let groupColumn, let valueColumn):
            let data = try document.boxplotChartData(groupColumn: groupColumn, valueColumn: valueColumn, cancellation: cancellation)
            guard !data.groups.isEmpty else { return nil }
            return .boxplot(data, groupName: groupColumn.map(name), valueName: name(valueColumn))
        case .scatter(let xColumn, let yColumn):
            let data = try document.scatterChartData(xColumn: xColumn, yColumn: yColumn, cancellation: cancellation)
            guard data.totalPairCount > 0 else { return nil }
            return .scatter(data, xName: name(xColumn), yName: name(yColumn))
        case .correlationHeatmap(let columns):
            guard columns.count >= 2 else { return nil }
            let data = try document.correlationMatrixChartData(columns: columns, cancellation: cancellation)
            return .correlationHeatmap(data, names: data.columns.map(name))
        case .qqPlot(let column):
            let points = try document.qqChartData(column: column, cancellation: cancellation)
            guard !points.isEmpty else { return nil }
            return .qqPlot(points, columnName: name(column))
        case .timeseries(let dateColumn, let valueColumn, let period):
            let histogram = try document.dateHistogram(dateColumn: dateColumn, valueColumn: valueColumn, period: period, cancellation: cancellation)
            guard !histogram.bins.isEmpty else { return nil }
            return .timeseries(histogram, dateName: name(dateColumn), valueName: valueColumn.map(name))
        case .pareto(let column):
            let data = try document.paretoChartData(column: column, cancellation: cancellation)
            guard !data.entries.isEmpty else { return nil }
            return .pareto(data, columnName: name(column))
        }
    }

    // MARK: - Data quality

    @objc func runDataQualityProfile(_ sender: Any?) {
        guard let doc = csvDocument, doc.indexingComplete, !busy else { return }
        dataQualityCancellation?.cancel()
        let cancellation = CancellationFlag()
        dataQualityCancellation = cancellation
        let fileName = (currentFilePath as NSString?)?.lastPathComponent ?? "CSV"

        setInspectorVisible(true, animated: true)
        detailHeaderLabel.stringValue = L.t("Data Quality", "데이터 품질")
        detailTextView.string = L.t("Profiling full file...", "전체 파일을 프로파일링 중...")
        currentInspectorContentKind = .dataQuality
        updateInspectorCopyButtons()
        setBusy(true, message: L.t("Profiling data quality...", "데이터 품질 프로파일링 중..."))
        setProgressVisible(true)
        updateProgress(0)

        DispatchQueue.global(qos: .userInitiated).async { [weak self, weak doc] in
            guard let doc else { return }
            do {
                let report = try doc.dataQualityReport(
                    progress: { pct in
                        DispatchQueue.main.async {
                            guard let self, self.dataQualityCancellation === cancellation else { return }
                            self.updateProgress(pct)
                        }
                    },
                    cancellation: cancellation
                )
                DispatchQueue.main.async {
                    guard let self, doc === self.csvDocument, self.dataQualityCancellation === cancellation else { return }
                    self.dataQualityCancellation = nil
                    self.setProgressVisible(false)
                    self.setBusy(false)
                    self.currentDataQualityReport = report
                    self.detailHeaderLabel.stringValue = L.t("Data Quality", "데이터 품질")
                    self.detailTextView.string = DataQualityReportFormatter.markdown(report: report, fileName: fileName)
                    self.currentInspectorContentKind = .dataQuality
                    self.updateInspectorCopyButtons()
                    self.statusLabel.stringValue = L.t(
                        "Data quality score: \(report.score)/100",
                        "데이터 품질 점수: \(report.score)/100"
                    )
                }
            } catch CsvError.cancelled {
                DispatchQueue.main.async {
                    guard let self, self.dataQualityCancellation === cancellation else { return }
                    self.dataQualityCancellation = nil
                    self.setProgressVisible(false)
                    self.setBusy(false)
                    self.statusLabel.stringValue = L.t("Data quality scan cancelled.", "데이터 품질 스캔이 취소되었습니다.")
                }
            } catch {
                DispatchQueue.main.async {
                    guard let self, self.dataQualityCancellation === cancellation else { return }
                    self.dataQualityCancellation = nil
                    self.setProgressVisible(false)
                    self.setBusy(false)
                    self.presentError(error)
                }
            }
        }
    }

    @objc func exportDataQualityMarkdown(_ sender: Any?) {
        exportDataQualityReport(fileExtension: "md") { report, fileName in
            Data(DataQualityReportFormatter.markdown(report: report, fileName: fileName).utf8)
        }
    }

    @objc func exportDataQualityHtml(_ sender: Any?) {
        exportDataQualityReport(fileExtension: "html") { report, fileName in
            Data(DataQualityReportFormatter.html(report: report, fileName: fileName).utf8)
        }
    }

    @objc func exportDataQualityJson(_ sender: Any?) {
        exportDataQualityReport(fileExtension: "json") { report, _ in
            try DataQualityReportFormatter.json(report: report)
        }
    }

    private func exportDataQualityReport(
        fileExtension: String,
        encode: @escaping (DataQualityReport, String) throws -> Data
    ) {
        guard let report = currentDataQualityReport, let window else { return }
        let fileName = (currentFilePath as NSString?)?.lastPathComponent ?? "CSV"
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\((fileName as NSString).deletingPathExtension)-quality.\(fileExtension)"
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try encode(report, fileName).write(to: url, options: .atomic)
                self?.statusLabel.stringValue = L.t("Report exported.", "리포트를 내보냈습니다.")
            } catch {
                self?.presentError(error)
            }
        }
    }

    private func presentChartWindow(_ model: ChartWindowModel) {
        let controller = ChartWindowController(model: model)
        controller.onClose = { [weak self] closed in
            self?.chartWindows.removeAll { $0 === closed }
        }
        chartWindows.append(controller)
        controller.showWindow(nil)
    }

    // Chart windows show a snapshot of one document's data; switching or
    // closing the document invalidates them, matching the Windows twin.
    func closeAllChartWindows() {
        let windows = chartWindows
        chartWindows.removeAll()
        for controller in windows {
            controller.onClose = nil
            controller.close()
        }
    }

    private func addAnalysisPromptRow(to stack: NSStackView, label: String, control: NSView) {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        row.translatesAutoresizingMaskIntoConstraints = false
        row.identifier = .analysisPromptRow
        row.widthAnchor.constraint(equalToConstant: Self.analysisPromptContentWidth).isActive = true
        let text = NSTextField(labelWithString: label)
        text.lineBreakMode = .byTruncatingTail
        text.widthAnchor.constraint(equalToConstant: Self.analysisPromptLabelWidth).isActive = true
        control.setContentHuggingPriority(.defaultLow, for: .horizontal)
        control.setContentCompressionResistancePriority(.required, for: .horizontal)
        row.addArrangedSubview(text)
        row.addArrangedSubview(control)
        stack.addArrangedSubview(row)
    }

    private func makeColumnPopup(preferredTypes: Set<ColumnValueType> = [], selected: Int, includeNone: Bool = false) -> NSPopUpButton {
        let popup = NSPopUpButton()
        popup.widthAnchor.constraint(equalToConstant: Self.analysisPromptPopupWidth).isActive = true
        if includeNone {
            popup.addItem(withTitle: L.t("None", "없음"))
            popup.lastItem?.representedObject = -1
        }
        let candidates = analysisColumnCandidates(preferredTypes: preferredTypes)
        for candidate in candidates {
            popup.addItem(withTitle: candidate.title)
            popup.lastItem?.representedObject = candidate.index
        }
        if let item = popup.itemArray.first(where: { ($0.representedObject as? Int) == selected }) {
            popup.select(item)
        } else {
            popup.selectItem(at: includeNone ? min(1, popup.numberOfItems - 1) : 0)
        }
        return popup
    }

    private func selectedColumn(in popup: NSPopUpButton) -> Int? {
        guard let value = popup.selectedItem?.representedObject as? Int, value >= 0 else { return nil }
        return value
    }

    private func analysisColumnCandidates(preferredTypes: Set<ColumnValueType>) -> [(index: Int, title: String)] {
        let summaries = columnStatisticsReport?.columns ?? []
        let indexes: [Int]
        if preferredTypes.isEmpty || summaries.isEmpty {
            indexes = Array(columnNames.indices)
        } else {
            let preferred = summaries.filter { preferredTypes.contains($0.inferredType) }.map(\.index)
            indexes = preferred.isEmpty ? Array(columnNames.indices) : preferred
        }
        return indexes.map { index in
            let type = columnStatisticsReport?.columns[safe: index]?.inferredType.rawValue
            let suffix = type.map { " [\($0)]" } ?? ""
            return (index, "\(columnNames[safe: index] ?? L.t("Column \(index + 1)", "\(index + 1)열"))\(suffix)")
        }
    }

    private func performAnalysis(_ request: AnalysisRequest) {
        guard let doc = csvDocument else { return }
        analysisCancellation?.cancel()
        let cancellation = CancellationFlag()
        analysisCancellation = cancellation
        let provenance = makeAnalysisProvenance(for: request)
        let header = request.kind.title
        let columns = columnNames
        let report = columnStatisticsReport
        let start = Date()

        setInspectorVisible(true, animated: true)
        detailHeaderLabel.stringValue = header
        detailTextView.string = L.t("Calculating analysis...", "분석을 계산 중입니다...")
        currentInspectorContentKind = .analysis
        updateInspectorCopyButtons()
        currentAnalysisReport = nil
        updateAnalysisActionBar(running: true)
        setBusy(true, message: L.t("Analyzing...", "분석 중..."))
        setProgressVisible(true)
        updateProgress(0)

        DispatchQueue.global(qos: .userInitiated).async { [weak self, weak doc] in
            guard let doc else { return }
            do {
                let built = try AnalysisReportBuilder.make(
                    request: request,
                    document: doc,
                    columnNames: columns,
                    columnStatisticsReport: report,
                    provenance: provenance,
                    cancellation: cancellation
                )
                let elapsed = Date().timeIntervalSince(start)
                let finalReport = AnalysisReport(
                    title: built.title,
                    summary: built.summary,
                    provenance: built.provenance.withElapsed(elapsed),
                    sections: built.sections
                )
                DispatchQueue.main.async {
                    guard let self, doc === self.csvDocument, self.analysisCancellation === cancellation, !cancellation.isCancelled else { return }
                    self.analysisCancellation = nil
                    self.currentAnalysisReport = finalReport
                    self.detailHeaderLabel.stringValue = finalReport.title
                    self.detailTextView.string = finalReport.markdown
                    self.currentInspectorContentKind = .analysis
                    self.updateInspectorCopyButtons()
                    self.updateAnalysisActionBar(running: false)
                    self.setProgressVisible(false)
                    self.setBusy(false)
                    self.statusLabel.stringValue = L.t("Analysis complete.", "분석이 완료되었습니다.")
                }
            } catch CsvError.cancelled {
                DispatchQueue.main.async {
                    guard let self, self.analysisCancellation === cancellation else { return }
                    self.analysisCancellation = nil
                    self.updateAnalysisActionBar(running: false)
                    self.setProgressVisible(false)
                    self.setBusy(false)
                    self.statusLabel.stringValue = L.t("Analysis cancelled.", "분석이 취소되었습니다.")
                }
            } catch {
                DispatchQueue.main.async {
                    guard let self, self.analysisCancellation === cancellation else { return }
                    self.analysisCancellation = nil
                    self.updateAnalysisActionBar(running: false)
                    self.setProgressVisible(false)
                    self.setBusy(false)
                    self.presentError(error)
                }
            }
        }
    }

    private func makeAnalysisProvenance(for request: AnalysisRequest) -> AnalysisProvenance {
        let sortDescription = sortKeys.isEmpty ? nil : sortKeys.map { key in
            "\(columnNames[safe: key.column] ?? L.t("Column \(key.column + 1)", "\(key.column + 1)열")) \(key.ascending ? "▲" : "▼")"
        }.joined(separator: " → ")
        return AnalysisProvenance(
            visibleRows: csvDocument?.displayRowCount ?? 0,
            totalRows: csvDocument?.dataRowsAvailable ?? 0,
            isFiltered: csvDocument?.isFiltered == true || hasAnyFilter,
            filters: filterDescriptions(),
            sortDescription: sortDescription,
            columnNames: request == .documentSummary
                ? [L.t("All columns (\(columnNames.count))", "전체 컬럼 (\(columnNames.count))")]
                : request.selectedColumns().compactMap { columnNames[safe: $0] },
            parameterLines: request.parameterLines(columnNames: columnNames),
            generatedAt: Date(),
            elapsedMilliseconds: nil,
            scannedRows: csvDocument.map { min($0.displayRowCount, VirtualCsvDocument.analysisRowLimit) }
        )
    }

    private func updateAnalysisActionBar(running: Bool) {
        let hasResult = currentAnalysisReport != nil
        analysisActionBar.isHidden = !running && !hasResult
        analysisCopyButton.isHidden = running
        analysisExportButton.isHidden = running
        analysisCancelButton.isHidden = !running
        analysisCopyButton.isEnabled = hasResult && !running
        analysisExportButton.isEnabled = hasResult && !running
        analysisCancelButton.isEnabled = running
    }

    @objc func cancelAnalysis(_ sender: Any?) {
        analysisCancellation?.cancel()
    }

    @objc func copyAnalysisResult(_ sender: Any?) {
        guard let report = currentAnalysisReport else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report.markdown, forType: .string)
        statusLabel.stringValue = L.t("Copied analysis result.", "분석 결과를 복사했습니다.")
    }

    @objc func exportAnalysisResult(_ sender: Any?) {
        guard let report = currentAnalysisReport else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [
            UTType(filenameExtension: "md") ?? .plainText,
            .commaSeparatedText,
            UTType(filenameExtension: "tsv") ?? .plainText,
            .json,
            .plainText
        ]
        panel.nameFieldStringValue = "analysis-result.md"
        panel.beginSheetModal(for: window!) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            do {
                let data: Data
                switch url.pathExtension.lowercased() {
                case "json":
                    data = try report.jsonData()
                case "csv":
                    data = Data(report.csv.utf8)
                case "tsv":
                    data = Data(report.tsv.utf8)
                default:
                    data = Data(report.markdown.utf8)
                }
                try data.write(to: url)
                self?.statusLabel.stringValue = L.t("Exported analysis result.", "분석 결과를 내보냈습니다.")
            } catch {
                self?.presentError(error)
            }
        }
    }

    @objc func changeEncoding(_ sender: Any?) {
        guard let doc = csvDocument, !busy else { return }
        let name = encodingPopup.titleOfSelectedItem ?? CsvEncodingName.utf8
        guard name != doc.encodingName else { return }
        do {
            try doc.changeEncoding(to: name)
            buildColumns(from: doc.header)
            resetViewState()
            doc.clearView()
            tableView.reloadData()
            statusLabel.stringValue = L.t("Encoding changed to \(name).", "인코딩을 \(name)(으)로 변경했습니다.")
        } catch {
            presentError(error)
        }
    }

    @objc func changeEncodingFromMenu(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        encodingPopup.selectItem(withTitle: name)
        changeEncoding(sender)
    }

    @objc func showUsage(_ sender: Any?) {
        let message = L.t(
            """
            Open a CSV or text file, then browse rows while indexing continues in the background.

            File: open multiple files as tabs, drag files in, or open CSV text from the clipboard.
            Toolbar: Open, sort, find, and detail panel.
            Find: use plain text, regex:pattern, /pattern/, or fuzzy:term.
            Filter bar: choose a column, enter text, apply or clear filters.
            View: save/restore the current view and inspect performance.
            Table: right-click a cell to copy it or filter by that value.
            Headers: click to sort, Shift-click to add another sort key.
            Export: CSV, Markdown, JSON, or HTML using the currently visible columns.
            """,
            """
            CSV 또는 텍스트 파일을 열면 백그라운드 인덱싱 중에도 행을 탐색할 수 있습니다.

            파일: 여러 파일을 탭으로 열거나, 파일을 드롭하거나, 클립보드의 CSV 텍스트를 열 수 있습니다.
            툴바: 열기, 정렬, 찾기, 상세 패널.
            찾기: 일반 텍스트, regex:패턴, /패턴/, fuzzy:검색어를 사용할 수 있습니다.
            필터 바: 열 선택, 텍스트 입력, 필터 적용/해제.
            보기: 현재 보기 저장/복원 및 성능 확인.
            표: 셀을 우클릭해 복사하거나 해당 값으로 필터.
            헤더: 클릭하면 정렬, Shift+클릭하면 정렬 기준 추가.
            내보내기: 현재 표시 중인 컬럼을 CSV, Markdown, JSON, HTML로 내보낼 수 있습니다.
            """
        )
        let alert = NSAlert()
        alert.messageText = L.t("How to Use", "사용법")
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.runModal()
    }

    @objc func copySelectedCellToPasteboard(_ sender: Any?) {
        guard let value = selectedGridCopyString() else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        statusLabel.stringValue = gridSelection.selectedCells.count > 1
            ? L.t("Copied selected cells.", "선택 셀들을 복사했습니다.")
            : L.t("Copied selected cell.", "선택 셀을 복사했습니다.")
    }

    @objc func copySelectedCellAsCsv(_ sender: Any?) {
        guard let value = selectedCellValue() else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(Self.csvEscaped(value), forType: .string)
        statusLabel.stringValue = L.t("Copied selected cell as CSV.", "선택 셀을 CSV로 복사했습니다.")
    }

    @objc func copySelectedCellAsJson(_ sender: Any?) {
        guard let value = selectedCellValue(),
              let data = try? JSONSerialization.data(withJSONObject: ["value": value], options: [.prettyPrinted, .sortedKeys]),
              let json = String(data: data, encoding: .utf8) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(json, forType: .string)
        statusLabel.stringValue = L.t("Copied selected cell as JSON.", "선택 셀을 JSON으로 복사했습니다.")
    }

    @objc func copyEntireCurrentRow(_ sender: Any?) {
        guard let text = rowCopyString(row: tableView.selectedRow) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        statusLabel.stringValue = L.t("Copied entire row.", "행 전체를 복사했습니다.")
    }

    @objc func copyEntireCurrentColumn(_ sender: Any?) {
        guard let text = columnCopyString(column: currentDataColumn, includeHeader: true) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        statusLabel.stringValue = L.t("Copied entire column.", "열 전체를 복사했습니다.")
    }

    @objc func copyInspectorText(_ sender: Any?) {
        let text = inspectorTextCopyString()
        guard !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        statusLabel.stringValue = L.t("Copied inspector text.", "인스펙터 텍스트를 복사했습니다.")
    }

    @objc func copyInspectorJson(_ sender: Any?) {
        guard let json = inspectorJsonCopyString() else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(json, forType: .string)
        statusLabel.stringValue = L.t("Copied inspector JSON.", "인스펙터 JSON을 복사했습니다.")
    }

    private func runViewOperation(
        message: String,
        operation: @escaping @Sendable (_ cancellation: CancellationFlag, _ progress: @escaping @Sendable (Int) -> Void) throws -> Void,
        completion: @escaping @MainActor () -> Void
    ) {
        operationCancellation?.cancel()
        let cancellation = CancellationFlag()
        operationCancellation = cancellation
        setBusy(true, message: message)
        setProgressVisible(true)
        updateProgress(0)

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                try operation(cancellation) { pct in
                    DispatchQueue.main.async {
                        guard let self, self.operationCancellation === cancellation else { return }
                        self.updateProgress(pct)
                    }
                }
                DispatchQueue.main.async {
                    guard let self, self.operationCancellation === cancellation else { return }
                    self.operationCancellation = nil
                    self.setProgressVisible(false)
                    self.setBusy(false)
                    self.refreshRowCount()
                    self.tableView.reloadData()
                    self.scheduleVisibleRowPrefetch()
                    completion()
                }
            } catch CsvError.cancelled {
                DispatchQueue.main.async {
                    guard let self, self.operationCancellation === cancellation else { return }
                    self.operationCancellation = nil
                    self.setProgressVisible(false)
                    self.setBusy(false)
                }
            } catch {
                DispatchQueue.main.async {
                    guard let self, self.operationCancellation === cancellation else { return }
                    self.operationCancellation = nil
                    self.setProgressVisible(false)
                    self.setBusy(false)
                    self.presentError(error)
                }
            }
        }
    }
}

extension MainWindowController: NSTableViewDataSource, NSTableViewDelegate {
    nonisolated func numberOfRows(in tableView: NSTableView) -> Int {
        MainActor.assumeIsolated {
            csvDocument?.displayRowCount ?? 0
        }
    }

    nonisolated func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        MainActor.assumeIsolated {
            let identifier = tableColumn?.identifier ?? NSUserInterfaceItemIdentifier("cell")
            let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView ?? makeCellView(identifier: identifier)

            guard let doc = csvDocument else {
                cell.textField?.stringValue = ""
                return cell
            }

            if identifier.rawValue == "rowNumber" {
                cell.textField?.stringValue = doc.getSourceRowNumber(row).formatted()
                cell.textField?.alignment = .right
                cell.textField?.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
                cell.textField?.textColor = .secondaryLabelColor
                cell.wantsLayer = true
                cell.layer?.backgroundColor = nil
                return cell
            }

            let column = columnIndex(from: identifier)
            do {
                let fields = try doc.getDisplayRow(row)
                cell.textField?.stringValue = column < fields.count ? tableCellPreview(fields[column]) : ""
            } catch {
                cell.textField?.stringValue = ""
            }
            cell.textField?.alignment = .left
            cell.textField?.font = .systemFont(ofSize: 13)
            cell.textField?.textColor = .labelColor
            cell.wantsLayer = true
            if isGridCellSelected(row: row, column: column) {
                cell.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.18).cgColor
                cell.layer?.cornerRadius = 3
            } else {
                cell.layer?.backgroundColor = nil
            }
            return cell
        }
    }

    nonisolated func tableViewSelectionDidChange(_ notification: Notification) {
        MainActor.assumeIsolated {
            if gridSelection.isEmpty, tableView.selectedRow >= 0 {
                gridSelection.replace(with: GridCellCoordinate(row: tableView.selectedRow, column: currentDataColumn))
            }
            updateSelectedValue()
            scheduleDetailPanelUpdate()
            reloadSelectedRowHighlight()
        }
    }

    func tableViewColumnDidResize(_ notification: Notification) {
        handleTableColumnDidResize(notification)
    }

    func tableViewColumnDidMove(_ notification: Notification) {
        updateTableDocumentWidthForViewport()
    }

    nonisolated func tableView(_ tableView: NSTableView, didClick tableColumn: NSTableColumn) {
        MainActor.assumeIsolated {
            let raw = tableColumn.identifier.rawValue
            guard raw.hasPrefix("c") else { return }
            let column = columnIndex(from: tableColumn.identifier)
            currentDataColumn = column
            let additive = NSEvent.modifierFlags.contains(.shift)
            toggleSort(column: column, additive: additive)
        }
    }

    private func handleTableColumnDidResize(_ notification: Notification) {
        guard !applyingGridLayout else { return }
        if let column = notification.userInfo?["NSTableColumn"] as? NSTableColumn {
            recordBaseWidth(for: column)
        } else {
            for column in tableView.tableColumns {
                recordBaseWidth(for: column)
            }
        }
        updateTableDocumentWidthForViewport()
    }

    private func makeColumnHeaderMenu(column: Int) -> NSMenu? {
        guard let report = columnStatisticsReport, let summary = report.columns[safe: column] else { return nil }
        let menu = NSMenu()
        menu.autoenablesItems = false
        let typeItem = NSMenuItem(title: L.t("Change Type", "타입 변경"), action: nil, keyEquivalent: "")
        let typeMenu = NSMenu()
        typeMenu.autoenablesItems = false
        for type in [ColumnValueType.integer, .float, .date, .boolean, .categorical, .string] {
            let item = NSMenuItem(title: type.rawValue, action: #selector(changeColumnType(_:)), keyEquivalent: "")
            item.target = self
            item.tag = column
            item.representedObject = type.rawValue
            item.state = summary.inferredType == type ? .on : .off
            typeMenu.addItem(item)
        }
        typeMenu.addItem(.separator())
        let auto = NSMenuItem(title: L.t("Revert to Auto-detected", "자동 감지로 되돌리기"), action: #selector(changeColumnType(_:)), keyEquivalent: "")
        auto.target = self
        auto.tag = column
        auto.representedObject = "auto"
        auto.isEnabled = columnTypeOverrides[column] != nil
        typeMenu.addItem(auto)
        typeItem.submenu = typeMenu
        menu.addItem(typeItem)
        return menu
    }

    @objc private func changeColumnType(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String else { return }
        let column = sender.tag
        if raw == "auto" {
            setColumnTypeOverride(column: column, type: nil)
            return
        }
        guard let target = ColumnValueType(rawValue: raw) else { return }
        requestColumnTypeChange(column: column, to: target)
    }

    func requestColumnTypeChange(column: Int, to target: ColumnValueType) {
        guard let current = columnStatisticsReport?.columns[safe: column]?.inferredType else { return }
        switch ColumnTypeConversion.classify(from: current, to: target) {
        case .block:
            statusLabel.stringValue = L.t(
                "Cannot convert \(current.rawValue) to \(target.rawValue) without data loss.",
                "\(current.rawValue) 타입은 데이터 손실 없이 \(target.rawValue)(으)로 바꿀 수 없습니다."
            )
        case .allow:
            setColumnTypeOverride(column: column, type: target)
        case .validateSample:
            validateAndApplyColumnType(column: column, target: target)
        }
    }

    private func validateAndApplyColumnType(column: Int, target: ColumnValueType) {
        guard let doc = csvDocument, doc.indexingComplete, !busy else { return }
        let cancellation = CancellationFlag()
        statusLabel.stringValue = L.t("Validating type change...", "타입 변경을 검증하는 중...")
        DispatchQueue.global(qos: .userInitiated).async { [weak self, doc] in
            let sample: [String]
            do {
                sample = try doc.distinctValues(column: column, withinCurrentView: false, limit: 2_000, progress: nil, cancellation: cancellation).map(\.value)
            } catch {
                DispatchQueue.main.async { self?.presentError(error) }
                return
            }
            let validation = ColumnTypeConversion.validateSample(values: sample, to: target)
            DispatchQueue.main.async {
                guard let self, doc === self.csvDocument else { return }
                if validation.passed {
                    self.setColumnTypeOverride(column: column, type: target)
                    return
                }
                let alert = NSAlert()
                alert.messageText = L.t("Some values do not match \(target.rawValue)", "일부 값이 \(target.rawValue) 타입과 맞지 않습니다")
                alert.informativeText = L.t(
                    "Examples: \(validation.failures.joined(separator: ", ")). Apply anyway?",
                    "예시: \(validation.failures.joined(separator: ", ")). 그래도 적용할까요?"
                )
                alert.addButton(withTitle: L.t("Apply", "적용"))
                alert.addButton(withTitle: L.t("Cancel", "취소"))
                guard let window = self.window else { return }
                alert.beginSheetModal(for: window) { [weak self] response in
                    guard let self else { return }
                    if response == .alertFirstButtonReturn {
                        self.setColumnTypeOverride(column: column, type: target)
                    } else {
                        self.statusLabel.stringValue = L.t("Type change cancelled.", "타입 변경을 취소했습니다.")
                    }
                }
            }
        }
    }

    func setColumnTypeOverride(column: Int, type: ColumnValueType?) {
        if let type {
            columnTypeOverrides[column] = type
        } else {
            columnTypeOverrides.removeValue(forKey: column)
        }
        columnStatisticsReport = baseColumnStatisticsReport?.applyingOverrides(columnTypeOverrides)
        updateSortHeaders()
        scheduleFacetRefresh()
        if case .columnStatistics(let shownColumn) = currentInspectorContentKind, shownColumn == column {
            renderColumnStatistics(column: column)
        }
        let name = columnNames[safe: column] ?? "\(column + 1)"
        if let type {
            statusLabel.stringValue = L.t("\(name) type set to \(type.rawValue).", "\(name) 컬럼 타입을 \(type.rawValue)(으)로 설정했습니다.")
        } else {
            statusLabel.stringValue = L.t("\(name) type reverted to auto-detected.", "\(name) 컬럼 타입을 자동 감지로 되돌렸습니다.")
        }
    }

    private func makeCellView(identifier: NSUserInterfaceItemIdentifier) -> NSTableCellView {
        let cell = NSTableCellView()
        cell.identifier = identifier
        let text = NSTextField(labelWithString: "")
        text.lineBreakMode = .byTruncatingTail
        text.maximumNumberOfLines = 1
        text.cell?.wraps = false
        text.cell?.isScrollable = false
        text.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(text)
        cell.textField = text
        NSLayoutConstraint.activate([
            text.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6),
            text.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
            text.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
        ])
        return cell
    }

    private func tableCellPreview(_ value: String) -> String {
        guard !value.isEmpty else { return value }
        var preview = ""
        preview.reserveCapacity(min(value.count, Self.tableCellPreviewLimit) + 3)

        for character in value {
            if preview.count >= Self.tableCellPreviewLimit {
                preview += "..."
                break
            }
            if character == "\n" || character == "\r" || character == "\t" {
                preview.append(" ")
            } else {
                preview.append(character)
            }
        }
        return preview
    }
}

extension MainWindowController {
    func columnIndex(from identifier: NSUserInterfaceItemIdentifier) -> Int {
        Int(identifier.rawValue.dropFirst()) ?? 0
    }

    func handleTableCellHit(_ hit: CsvTableCellHit) {
        guard hit.row >= 0, hit.column >= 0, hit.column < tableView.tableColumns.count else { return }
        let identifier = tableView.tableColumns[hit.column].identifier.rawValue
        guard identifier.hasPrefix("c"), let dataColumn = Int(identifier.dropFirst()) else { return }
        switch hit.phase {
        case .mouseDown, .rightMouseDown:
            selectGridCell(
                row: hit.row,
                column: dataColumn,
                extending: hit.modifiers.contains(.shift),
                toggling: hit.modifiers.contains(.command)
            )
        case .mouseDragged:
            extendGridSelection(toRow: hit.row, column: dataColumn)
        case .mouseUp:
            break
        }
    }

    func selectGridCell(row: Int, column: Int, extending: Bool = false, toggling: Bool = false) {
        guard row >= 0, column >= 0 else { return }
        let cell = GridCellCoordinate(row: row, column: column)
        currentDataColumn = column
        if extending {
            gridSelection.extend(to: cell)
        } else if toggling {
            gridSelection.toggle(cell)
        } else {
            gridSelection.replace(with: cell)
        }
        if gridSelection.isEmpty {
            tableView.deselectAll(nil)
        } else {
            tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }
        updateSelectedValue()
        scheduleDetailPanelUpdate()
        reloadSelectedRowHighlight()
    }

    func extendGridSelection(toRow row: Int, column: Int) {
        guard row >= 0, column >= 0 else { return }
        currentDataColumn = column
        gridSelection.extend(to: GridCellCoordinate(row: row, column: column))
        tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        updateSelectedValue()
        scheduleDetailPanelUpdate()
        reloadSelectedRowHighlight()
    }

    func clearGridSelection() {
        gridSelection.clear()
        lastHighlightedRows.removeAll()
        tableView.deselectAll(nil)
    }

    func primarySelectedGridCell() -> GridCellCoordinate? {
        gridSelection.anchor ?? (tableView.selectedRow >= 0 ? GridCellCoordinate(row: tableView.selectedRow, column: currentDataColumn) : nil)
    }

    func isGridCellSelected(row: Int, column: Int) -> Bool {
        if gridSelection.contains(row: row, column: column) { return true }
        return gridSelection.isEmpty && row == tableView.selectedRow && column == currentDataColumn
    }

    func selectedGridCopyString() -> String? {
        guard let doc = csvDocument else { return nil }
        let selection = gridSelection.isEmpty
            ? (primarySelectedGridCell().map { Set([$0]) } ?? [])
            : gridSelection.selectedCells
        guard let bounds = GridSelectionModel(selectedCells: selection).boundingRect() else { return nil }

        var rows: [[String]] = []
        rows.reserveCapacity(bounds.rows.upperBound + 1)
        for rowIndex in 0...bounds.rows.upperBound {
            if rowIndex < bounds.rows.lowerBound {
                rows.append([])
            } else {
                rows.append((try? doc.getDisplayRow(rowIndex)) ?? [])
            }
        }
        return GridCopyFormatter.tsv(rows: rows, selection: selection)
    }

    func rowCopyString(row: Int) -> String? {
        guard let doc = csvDocument, row >= 0, row < doc.displayRowCount else { return nil }
        let visibleColumns = columnNames.indices.filter { !hiddenColumnIndexes.contains($0) }
        guard let fields = try? doc.getDisplayRow(row) else { return nil }
        return GridCopyFormatter.tsv(row: fields, columns: visibleColumns)
    }

    func columnCopyString(column: Int, includeHeader: Bool) -> String? {
        guard let doc = csvDocument, column >= 0, column < columnNames.count else { return nil }
        let values = (0..<doc.displayRowCount).map { row -> String in
            guard let fields = try? doc.getDisplayRow(row), column < fields.count else { return "" }
            return fields[column]
        }
        if includeHeader {
            return GridCopyFormatter.tsv(columnName: columnNames[column], values: values)
        }
        return values.joined(separator: "\n") + "\n"
    }

    func inspectorTextCopyString() -> String {
        InspectorCopyFormatter.text(detailTextView.string)
    }

    func inspectorJsonCopyString() -> String? {
        guard case .row(let displayRow, _) = currentInspectorContentKind,
              let row = try? csvDocument?.getDisplayRow(displayRow) else {
            return nil
        }
        return InspectorCopyFormatter.jsonObject(headers: columnNames, row: row)
    }

    func updateInspectorCopyButtons() {
        inspectorCopyTextButton.isEnabled = !detailTextView.string.isEmpty
        if case .row = currentInspectorContentKind {
            inspectorCopyJsonButton.isEnabled = true
        } else {
            inspectorCopyJsonButton.isEnabled = false
        }
    }

    func updateSelectedValue() {
        guard let doc = csvDocument, let primary = primarySelectedGridCell() else {
            selectedValueBar.isHidden = true
            selectedAddressLabel.stringValue = ""
            selectedValueTextView.string = ""
            return
        }
        selectedValueBar.isHidden = false
        do {
            let fields = try doc.getDisplayRow(primary.row)
            let column = max(0, min(primary.column, max(0, columnNames.count - 1)))
            let value = column < fields.count ? fields[column] : ""
            selectedValueTextView.string = value
            let name = columnNames[safe: column] ?? ""
            selectedAddressLabel.stringValue = "\(doc.getSourceRowNumber(primary.row).formatted()) · \(name)"
        } catch {
            selectedValueTextView.string = ""
        }
    }

    func updateSelectedValueExpansionLayout() {
        selectedValueBarHeightConstraint?.constant = selectedValueExpanded ? 140 : 34
        selectedValueScrollHeightConstraint?.constant = selectedValueExpanded ? 130 : 24
        selectedValueScrollView.hasVerticalScroller = selectedValueExpanded
        selectedValueTextView.textContainer?.heightTracksTextView = !selectedValueExpanded
        updateSelectedValueExpansionButton()
        selectedValueBar.superview?.layoutSubtreeIfNeeded()
    }

    private func updateSelectedValueExpansionButton() {
        let symbol = selectedValueExpanded ? "chevron.down.circle" : "chevron.up.circle"
        let tooltip = selectedValueExpanded
            ? L.t("Collapse selected value", "선택값 접기")
            : L.t("Expand selected value", "선택값 펼치기")
        selectedValueExpandButton.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip)
        selectedValueExpandButton.toolTip = tooltip
    }

    func setFilterBarVisible(_ visible: Bool, focus: Bool = false) {
        filterBarView.isHidden = !visible
        filterToggleButton.state = visible ? .on : .off
        if visible && focus {
            window?.makeFirstResponder(filterField)
        }
    }

    @objc func visibleRowsDidChange(_ notification: Notification) {
        syncHeaderClipIfNeeded()
        scheduleVisibleRowPrefetch()
    }

    /// AppKit normally keeps the header clip view in sync with the content
    /// clip during interactive scrolling, but programmatic scrolls (and
    /// headless test runs) can leave it behind. No-op when already in sync.
    private func syncHeaderClipIfNeeded() {
        let contentX = scrollView.contentView.bounds.origin.x
        guard let headerClip = tableView.headerView?.superview as? NSClipView,
              abs(headerClip.bounds.origin.x - contentX) > 0.01 else { return }
        headerClip.scroll(to: NSPoint(x: contentX, y: headerClip.bounds.origin.y))
        scrollView.reflectScrolledClipView(headerClip)
    }

    @objc func tableViewportDidResize(_ notification: Notification) {
        updateTableDocumentWidthForViewport()
    }

    /// Restores user column widths, lets AppKit tile the table, and decides
    /// scroller visibility / viewport fill from the MEASURED natural width.
    /// Never forces table/header frames and never computes geometry from
    /// summed column widths — AppKit owns intercell spacing and style insets.
    func updateTableDocumentWidthForViewport() {
        guard !tableView.tableColumns.isEmpty, !applyingGridLayout else { return }
        let viewportWidth = scrollView.contentSize.width
        guard viewportWidth > 0 else { return }
        gridLayoutPassCount += 1

        applyingGridLayout = true
        defer { applyingGridLayout = false }

        for column in tableView.tableColumns where !column.isHidden {
            let base = baseWidth(for: column)
            if abs(column.width - base) > 0.5 {
                column.width = base
            }
        }
        tableView.tile()

        // tile() pads the table frame up to the clip width, so the frame
        // cannot reveal a shortfall; measure the actual right edge of the
        // last visible column plus the style's symmetric side inset instead.
        guard let extent = measuredColumnExtent() else { return }
        let decision = GridTableLayout.decide(
            naturalWidth: extent.contentMaxX + extent.leadingInset,
            viewportWidth: viewportWidth
        )
        if decision.fillDelta > 0.5,
           let fillColumn = tableView.tableColumns.last(where: { !$0.isHidden && $0.identifier.rawValue.hasPrefix("c") }) {
            fillColumn.width = baseWidth(for: fillColumn) + decision.fillDelta
            tableView.tile()
        }

        if scrollView.hasHorizontalScroller != decision.needsHorizontalScroller {
            scrollView.hasHorizontalScroller = decision.needsHorizontalScroller
            scrollView.tile()
        }
        if !decision.needsHorizontalScroller, scrollView.contentView.bounds.origin.x > 0.5 {
            let origin = NSPoint(x: 0, y: scrollView.contentView.bounds.origin.y)
            scrollView.contentView.scroll(to: origin)
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
    }

    private func measuredColumnExtent() -> (contentMaxX: CGFloat, leadingInset: CGFloat)? {
        var contentMaxX: CGFloat = 0
        var leadingInset = CGFloat.greatestFiniteMagnitude
        var hasVisibleColumn = false
        for index in 0..<tableView.tableColumns.count where !tableView.tableColumns[index].isHidden {
            let rect = tableView.rect(ofColumn: index)
            guard !rect.isNull, rect.width > 0 else { continue }
            hasVisibleColumn = true
            contentMaxX = max(contentMaxX, rect.maxX)
            leadingInset = min(leadingInset, rect.minX)
        }
        guard hasVisibleColumn else { return nil }
        return (contentMaxX, max(0, min(leadingInset, 32)))
    }

    private func baseWidth(for column: NSTableColumn) -> CGFloat {
        max(gridColumnBaseWidths[column.identifier] ?? column.width, column.minWidth)
    }

    private func recordBaseWidth(for column: NSTableColumn) {
        gridColumnBaseWidths[column.identifier] = max(column.width, column.minWidth)
    }

    func scheduleVisibleRowPrefetch() {
        guard let doc = csvDocument, tableView.numberOfRows > 0 else {
            prefetchCancellation?.cancel()
            return
        }
        let visible = tableView.rows(in: scrollView.contentView.bounds)
        guard visible.length > 0 else { return }

        let start = max(0, visible.location - 512)
        let end = min(doc.displayRowCount, visible.location + visible.length + 2_048)
        guard start < end else { return }

        let cancellation = CancellationFlag()
        prefetchCancellation?.cancel()
        prefetchCancellation = cancellation
        DispatchQueue.global(qos: .utility).async { [weak doc] in
            doc?.prefetchDisplayRows(in: start..<end, cancellation: cancellation)
        }
    }

    func updateEmptyState() {
        let hasDocument = csvDocument != nil
        emptyStateView.isHidden = hasDocument
        mainSplit.isHidden = !hasDocument
        if !hasDocument {
            setFilterBarVisible(false)
            selectedValueBar.isHidden = true
            selectedAddressLabel.stringValue = ""
            selectedValueTextView.string = ""
            detailTextView.string = ""
            gridSelection.clear()
            currentInspectorContentKind = .empty
            updateInspectorCopyButtons()
        }
    }

    func filterDescriptions() -> [String] {
        var descriptions: [String] = []
        if textCondition != nil {
            descriptions.append(textConditionDescription)
        }
        descriptions.append(contentsOf: columnFilterDescriptions())
        return descriptions
    }

    func columnFilterDescriptions() -> [String] {
        columnFilterState.descriptions(
            columnNames: columnNames,
            blankLabel: L.t("(Blank)", "(빈 값)")
        )
    }

    func refreshFilterTokens() {
        for view in filterTokensStack.arrangedSubviews {
            filterTokensStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        let total = filterDescriptions().count
        filterTokensStack.isHidden = total == 0
        guard total > 0 else { return }

        var visibleCount = 0
        if textCondition != nil, visibleCount < 4 {
            addFilterToken(
                textConditionDescription,
                editable: true,
                onEdit: { [weak self] in self?.editTextFilterToken() },
                onRemove: { [weak self] in self?.removeTextFilterToken() }
            )
            visibleCount += 1
        }

        let columnFilters = columnFilterState.filters
        let columnDescriptions = columnFilterDescriptions()
        for index in columnFilters.indices where visibleCount < 4 {
            let filter = columnFilters[index]
            addFilterToken(
                columnDescriptions[safe: index] ?? L.t("Column filter", "컬럼 필터"),
                editable: false,
                onEdit: nil,
                onRemove: { [weak self] in self?.removeColumnFilterToken(column: filter.column) }
            )
            visibleCount += 1
        }

        if total > visibleCount {
            let more = NSTextField(labelWithString: "+\(total - visibleCount)")
            more.font = .systemFont(ofSize: 11, weight: .medium)
            more.textColor = .secondaryLabelColor
            filterTokensStack.addArrangedSubview(more)
        }
    }

    private func addFilterToken(
        _ title: String,
        editable: Bool,
        onEdit: (() -> Void)?,
        onRemove: @escaping () -> Void
    ) {
        let token = FilterTokenView(title: title, editable: editable)
        token.onEdit = onEdit
        token.onRemove = onRemove
        token.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        filterTokensStack.addArrangedSubview(token)
    }

    private func editTextFilterToken() {
        guard textCondition != nil else { return }
        setFilterBarVisible(true)
        filterField.stringValue = textFilterTerm
        filterColumnPopup.selectItem(at: textFilterColumn < 0 ? 0 : textFilterColumn + 1)
        window?.makeFirstResponder(filterField)
        filterField.currentEditor()?.selectAll(nil)
    }

    private func removeTextFilterToken() {
        guard textCondition != nil else { return }
        textCondition = nil
        textConditionDescription = ""
        textFilterTerm = ""
        textFilterColumn = -1
        filterField.stringValue = ""
        rebuildFilter(message: L.t("Updating filter...", "필터 갱신 중..."))
    }

    private func removeColumnFilterToken(column: Int) {
        guard columnFilterState.filter(for: column) != nil else { return }
        clearColumnFilter(column: column)
    }

    func applyColumnFilter(_ filter: ColumnFilter) {
        switch filter {
        case .selectedValues(let column, let values, let includeBlanks):
            columnFilterState.setValues(column: column, values: values, includeBlanks: includeBlanks)
        case .dateRange(let column, let start, let end):
            columnFilterState.setDateRange(column: column, start: start, end: end)
        case .numericRange(let column, let lower, let upper, let includesUpperBound):
            columnFilterState.setNumericRange(column: column, lower: lower, upper: upper, includesUpperBound: includesUpperBound)
        }
        setFilterBarVisible(true)
        updateSortHeaders()
        rebuildFilter(message: L.t("Applying column filter...", "컬럼 필터 적용 중..."))
    }

    func clearColumnFilter(column: Int) {
        columnFilterState.remove(column: column)
        updateSortHeaders()
        rebuildFilter(message: L.t("Updating filter...", "필터 갱신 중..."))
    }

    func showColumnFilterPopover(column: Int, relativeTo frame: NSRect) {
        guard let doc = csvDocument, doc.indexingComplete, !busy else { return }
        guard let type = columnStatisticsReport?.columns[safe: column]?.inferredType,
              type == .categorical || type == .date else {
            statusLabel.stringValue = L.t("Column filters are available for categorical and date columns.", "컬럼 필터는 범주형 및 날짜 컬럼에서 사용할 수 있습니다.")
            return
        }

        if type == .date {
            presentColumnFilterPopover(column: column, type: type, values: [], relativeTo: frame)
            return
        }

        let cancellation = startColumnFilterValuesLoad()

        DispatchQueue.global(qos: .userInitiated).async { [weak self, doc] in
            do {
                let values = try doc.distinctValues(column: column, withinCurrentView: false, limit: nil, progress: { pct in
                    DispatchQueue.main.async {
                        guard let self, self.columnFilterValuesCancellation === cancellation else { return }
                        self.updateProgress(pct)
                    }
                }, cancellation: cancellation)
                DispatchQueue.main.async {
                    self?.finishColumnFilterValuesLoad(
                        cancellation: cancellation,
                        doc: doc,
                        column: column,
                        type: type,
                        values: values,
                        relativeTo: frame
                    )
                }
            } catch CsvError.cancelled {
                DispatchQueue.main.async {
                    self?.discardColumnFilterValuesLoad(cancellation: cancellation)
                }
            } catch {
                DispatchQueue.main.async {
                    self?.failColumnFilterValuesLoad(cancellation: cancellation, error: error)
                }
            }
        }
    }

    private var columnFilterValuesLoadingMessage: String {
        L.t("Loading filter values...", "필터 값을 불러오는 중...")
    }

    private func startColumnFilterValuesLoad() -> CancellationFlag {
        columnFilterValuesCancellation?.cancel()
        let cancellation = CancellationFlag()
        columnFilterValuesCancellation = cancellation
        setBusy(true, message: columnFilterValuesLoadingMessage)
        setProgressVisible(true)
        updateProgress(0)
        return cancellation
    }

    private func finishColumnFilterValuesLoad(
        cancellation: CancellationFlag,
        doc: VirtualCsvDocument,
        column: Int,
        type: ColumnValueType,
        values: [DistinctColumnValue],
        relativeTo frame: NSRect
    ) {
        guard clearCurrentColumnFilterValuesLoad(cancellation: cancellation) else { return }
        guard doc === csvDocument, !cancellation.isCancelled else { return }
        presentColumnFilterPopover(column: column, type: type, values: values, relativeTo: frame)
    }

    private func discardColumnFilterValuesLoad(cancellation: CancellationFlag) {
        _ = clearCurrentColumnFilterValuesLoad(cancellation: cancellation)
    }

    private func failColumnFilterValuesLoad(cancellation: CancellationFlag, error: Error) {
        guard clearCurrentColumnFilterValuesLoad(cancellation: cancellation) else { return }
        presentError(error)
    }

    private func clearCurrentColumnFilterValuesLoad(cancellation: CancellationFlag) -> Bool {
        guard columnFilterValuesCancellation === cancellation else { return false }
        columnFilterValuesCancellation = nil
        setProgressVisible(false)
        setBusy(false)
        clearColumnFilterValuesLoadingStatus()
        return true
    }

    private func clearColumnFilterValuesLoadingStatus() {
        if statusLabel.stringValue == columnFilterValuesLoadingMessage {
            statusLabel.stringValue = ""
        }
    }

    private func presentColumnFilterPopover(
        column: Int,
        type: ColumnValueType,
        values: [DistinctColumnValue],
        relativeTo frame: NSRect
    ) {
        guard let headerView = tableView.headerView else { return }
        columnFilterPopover?.close()
        let controller = ColumnFilterPopoverController(
            column: column,
            columnName: columnNames[safe: column] ?? L.t("Column \(column + 1)", "\(column + 1)열"),
            type: type,
            values: values,
            initialFilter: columnFilterState.filter(for: column)
        )
        controller.onApply = { [weak self] filter in
            guard let self else { return }
            if let filter {
                applyColumnFilter(filter)
            } else {
                clearColumnFilter(column: column)
            }
        }
        controller.onClose = { [weak self] in
            self?.columnFilterPopover?.close()
            self?.columnFilterPopover = nil
        }

        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = controller
        popover.show(relativeTo: frame, of: headerView, preferredEdge: .maxY)
        columnFilterPopover = popover
    }

    func reloadSelectedRowHighlight() {
        guard tableView.numberOfColumns > 1 else { return }
        var rows = lastHighlightedRows
        rows.formUnion(gridSelection.selectedRows)
        if tableView.selectedRow >= 0 { rows.insert(tableView.selectedRow) }
        lastHighlightedRows = gridSelection.selectedRows
        guard !rows.isEmpty else { return }
        tableView.reloadData(
            forRowIndexes: rows,
            columnIndexes: IndexSet(integersIn: 1..<tableView.numberOfColumns)
        )
    }

    func selectedCellValue() -> String? {
        guard let doc = csvDocument, let primary = primarySelectedGridCell() else { return nil }
        do {
            let row = try doc.getDisplayRow(primary.row)
            return primary.column < row.count ? row[primary.column] : ""
        } catch {
            return nil
        }
    }

    @objc func hideCurrentColumn(_ sender: Any?) {
        guard currentDataColumn >= 0,
              let column = tableView.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier("c\(currentDataColumn)")) else { return }
        hiddenColumnIndexes.insert(currentDataColumn)
        column.isHidden = true
        persistColumnVisibility()
        updateTableDocumentWidthForViewport()
        scheduleFacetRefresh()
        statusLabel.stringValue = L.t("Column hidden.", "컬럼을 숨겼습니다.")
    }

    @objc func showAllColumns(_ sender: Any?) {
        hiddenColumnIndexes.removeAll()
        for index in columnNames.indices {
            tableView.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier("c\(index)"))?.isHidden = false
        }
        persistColumnVisibility()
        updateTableDocumentWidthForViewport()
        scheduleFacetRefresh()
        statusLabel.stringValue = L.t("All columns shown.", "모든 컬럼을 표시했습니다.")
    }

    @objc func togglePersistentIndex(_ sender: Any?) {
        VirtualCsvDocument.persistentIndexEnabled.toggle()
        UserDefaults.standard.set(VirtualCsvDocument.persistentIndexEnabled, forKey: Self.persistentIndexDefaultsKey)
        statusLabel.stringValue = VirtualCsvDocument.persistentIndexEnabled
            ? L.t("Persistent index enabled.", "인덱스 저장을 켰습니다.")
            : L.t("Persistent index disabled.", "인덱스 저장을 껐습니다.")
    }

    @objc func toggleDeleteIndexCacheOnClose(_ sender: Any?) {
        VirtualCsvDocument.deletePersistentIndexOnClose.toggle()
        UserDefaults.standard.set(VirtualCsvDocument.deletePersistentIndexOnClose, forKey: Self.deleteIndexCacheOnCloseDefaultsKey)
        statusLabel.stringValue = VirtualCsvDocument.deletePersistentIndexOnClose
            ? L.t("Index cache will be deleted when a CSV is closed.", "CSV를 닫을 때 인덱스 캐시를 삭제합니다.")
            : L.t("Index cache will be kept after closing CSV files.", "CSV를 닫은 뒤에도 인덱스 캐시를 유지합니다.")
    }

    @objc func showIndexFolder(_ sender: Any?) {
        do {
            let directory = try VirtualCsvDocument.ensurePersistentIndexDirectory()
            NSWorkspace.shared.open(directory)
            statusLabel.stringValue = L.t("Opened index folder.", "인덱스 폴더를 열었습니다.")
        } catch {
            presentError(error)
        }
    }

    @objc func clearIndexFolder(_ sender: Any?) {
        do {
            try VirtualCsvDocument.clearPersistentIndexDirectory()
            statusLabel.stringValue = L.t("Index folder cleared.", "인덱스 폴더를 비웠습니다.")
        } catch {
            presentError(error)
        }
    }

    @objc func saveCurrentView(_ sender: Any?) {
        guard csvDocument != nil, let currentFilePath else { return }
        let existing = savedViewStore().names(forPath: currentFilePath)
        let suggestion = existing.isEmpty
            ? L.t("View 1", "보기 1")
            : L.t("View \(existing.count + 1)", "보기 \(existing.count + 1)")
        guard let name = promptForBookmarkName(default: suggestion, existing: existing) else { return }
        saveCurrentView(named: name, forPath: currentFilePath)
    }

    private func saveCurrentView(named name: String, forPath path: String) {
        let searchQuery = findField.stringValue.isEmpty ? nil : try? SearchFieldParser.parse(findField.stringValue, column: nil)
        let saved = SavedCsvView(
            name: name,
            filterText: textFilterTerm.isEmpty ? nil : textFilterTerm,
            filterColumn: textFilterColumn < 0 ? nil : textFilterColumn,
            sortKeys: sortKeys,
            hiddenColumnIndexes: Array(hiddenColumnIndexes),
            searchQuery: searchQuery,
            currentColumn: currentDataColumn,
            columnFilters: columnFilterState
        )
        var store = savedViewStore()
        store.save(saved, forPath: path)
        persistSavedViewStore(store)
        statusLabel.stringValue = L.t("Saved view \"\(name)\".", "\"\(name)\" 보기를 저장했습니다.")
    }

    @objc func restoreSavedView(_ sender: Any?) {
        guard csvDocument != nil, let currentFilePath, !busy else { return }
        let names = savedViewStore().names(forPath: currentFilePath)
        guard !names.isEmpty else {
            statusLabel.stringValue = L.t("No saved views for this file.", "이 파일에 저장된 보기가 없습니다.")
            return
        }
        guard let choice = promptForSavedViewChoice(names: names) else { return }
        switch choice {
        case .restore(let name):
            restoreSavedView(named: name, forPath: currentFilePath)
        case .delete(let name):
            var store = savedViewStore()
            store.remove(name: name, forPath: currentFilePath)
            persistSavedViewStore(store)
            statusLabel.stringValue = L.t("Deleted view \"\(name)\".", "\"\(name)\" 보기를 삭제했습니다.")
        }
    }

    @discardableResult
    private func restoreSavedView(named name: String, forPath path: String) -> Bool {
        guard let doc = csvDocument, !busy else { return false }
        guard let saved = savedViewStore().view(named: name, forPath: path) else {
            statusLabel.stringValue = L.t("No saved view named \"\(name)\".", "\"\(name)\" 보기가 없습니다.")
            return false
        }

        columnFilterState = saved.columnFilters
        textCondition = nil
        textConditionDescription = ""
        textFilterTerm = saved.filterText ?? ""
        textFilterColumn = saved.filterColumn ?? -1
        filterField.stringValue = textFilterTerm
        filterColumnPopup.selectItem(at: textFilterColumn < 0 ? 0 : textFilterColumn + 1)
        sortKeys = saved.sortKeys
        currentDataColumn = min(saved.currentColumn, max(0, columnNames.count - 1))
        hiddenColumnIndexes = Set(saved.hiddenColumnIndexes)
        applyColumnVisibility()
        if let query = saved.searchQuery {
            findField.stringValue = Self.displayText(for: query)
        }

        do {
            if let filterText = saved.filterText {
                _ = try configureTextCondition(term: filterText, column: textFilterColumn, document: doc)
            }
        } catch {
            presentError(error)
            return false
        }

        let keys = sortKeys
        let predicate = hasAnyFilter ? combinedPredicate() : nil
        let bookmarkName = saved.name
        runViewOperation(message: L.t("Restoring view...", "보기 복원 중...")) { flag, progress in
            doc.clearView()
            if let predicate {
                try doc.applyFilter(predicate, progress: progress, cancellation: flag)
            }
            if !keys.isEmpty {
                try doc.sort(keys: keys, progress: progress, cancellation: flag)
            }
            progress(100)
        } completion: { [weak self] in
            self?.updateSortHeaders()
            self?.refreshFilterTokens()
            self?.updateFilterStatus()
            self?.statusLabel.stringValue = L.t("Restored view \"\(bookmarkName)\".", "\"\(bookmarkName)\" 보기를 복원했습니다.")
        }
        return true
    }

    // MARK: - Saved view store (named bookmarks)

    private enum SavedViewChoice {
        case restore(String)
        case delete(String)
    }

    private func savedViewStore() -> SavedViewStore {
        if let data = UserDefaults.standard.data(forKey: Self.savedViewStoreDefaultsKey),
           let store = try? JSONDecoder().decode(SavedViewStore.self, from: data) {
            return store
        }
        // One-time migration from the v1.7 [path: base64] single-view map.
        let legacyMap = UserDefaults.standard.dictionary(forKey: Self.savedViewsDefaultsKey) as? [String: String] ?? [:]
        let migrated = SavedViewStore(migratingLegacyMap: legacyMap)
        if !legacyMap.isEmpty {
            persistSavedViewStore(migrated)
        }
        return migrated
    }

    private func persistSavedViewStore(_ store: SavedViewStore) {
        if let data = try? JSONEncoder().encode(store) {
            UserDefaults.standard.set(data, forKey: Self.savedViewStoreDefaultsKey)
        }
    }

    private func promptForBookmarkName(default suggestion: String, existing: [String]) -> String? {
        let alert = NSAlert()
        alert.messageText = L.t("Save View As", "다른 이름으로 보기 저장")
        alert.informativeText = L.t(
            "Name this view. Reusing a name overwrites that view.",
            "이 보기의 이름을 입력하세요. 같은 이름은 덮어씁니다."
        )
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = suggestion
        alert.accessoryView = field
        alert.addButton(withTitle: L.t("Save", "저장"))
        alert.addButton(withTitle: L.t("Cancel", "취소"))
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? suggestion : name
    }

    private func promptForSavedViewChoice(names: [String]) -> SavedViewChoice? {
        let alert = NSAlert()
        alert.messageText = L.t("Restore Saved View", "저장된 보기 복원")
        alert.informativeText = L.t("Choose a saved view to restore or delete.", "복원하거나 삭제할 저장된 보기를 선택하세요.")
        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 260, height: 25))
        popup.addItems(withTitles: names)
        alert.accessoryView = popup
        alert.addButton(withTitle: L.t("Restore", "복원"))
        alert.addButton(withTitle: L.t("Delete", "삭제"))
        alert.addButton(withTitle: L.t("Cancel", "취소"))
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return .restore(popup.titleOfSelectedItem ?? names[0])
        case .alertSecondButtonReturn:
            return .delete(popup.titleOfSelectedItem ?? names[0])
        default:
            return nil
        }
    }

    private var currentRowDensity: GridRowDensity {
        GridRowDensity(rawValue: UserDefaults.standard.string(forKey: Self.rowDensityDefaultsKey) ?? "") ?? .regular
    }

    @objc func changeRowDensity(_ sender: Any?) {
        guard let item = sender as? NSMenuItem,
              let density = item.representedObject as? String,
              let value = GridRowDensity(rawValue: density) else { return }
        UserDefaults.standard.set(value.rawValue, forKey: Self.rowDensityDefaultsKey)
        applyRowDensity()
    }

    private func applyRowDensity() {
        tableView.rowHeight = currentRowDensity.rowHeight
        tableView.reloadData()
        updateTableDocumentWidthForViewport()
    }

    @objc func toggleAutoRestoreView(_ sender: Any?) {
        let enabled = !UserDefaults.standard.bool(forKey: Self.autoRestoreViewDefaultsKey)
        UserDefaults.standard.set(enabled, forKey: Self.autoRestoreViewDefaultsKey)
        statusLabel.stringValue = enabled
            ? L.t("Saved views will restore on open.", "파일을 열 때 저장된 보기를 복원합니다.")
            : L.t("Saved views will not restore on open.", "파일을 열 때 저장된 보기를 복원하지 않습니다.")
    }

    private func autoRestoreSavedViewIfEnabled() {
        guard UserDefaults.standard.bool(forKey: Self.autoRestoreViewDefaultsKey),
              let currentFilePath,
              let recent = savedViewStore().mostRecent(forPath: currentFilePath) else { return }
        restoreSavedView(named: recent.name, forPath: currentFilePath)
    }

    private func applyColumnVisibility() {
        for index in columnNames.indices {
            tableView.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier("c\(index)"))?.isHidden = hiddenColumnIndexes.contains(index)
        }
        persistColumnVisibility()
        updateTableDocumentWidthForViewport()
    }

    private static func displayText(for query: CsvSearchQuery) -> String {
        switch query.mode {
        case .contains:
            return query.text
        case .regex:
            return "regex:\(query.text)"
        case .fuzzy:
            return "fuzzy:\(query.text)"
        }
    }

    func persistColumnVisibility() {
        UserDefaults.standard.set(Array(hiddenColumnIndexes).sorted(), forKey: Self.hiddenColumnsDefaultsKey)
    }

    func updateDetailPanel() {
        guard isInspectorVisible else { return }
        guard let doc = csvDocument, tableView.selectedRow >= 0 else {
            detailHeaderLabel.stringValue = L.t("Inspector", "인스펙터")
            detailTextView.string = ""
            currentInspectorContentKind = .empty
            updateInspectorCopyButtons()
            return
        }
        let row = tableView.selectedRow
        do {
            let fields = try doc.getDisplayRow(row)
            detailHeaderLabel.stringValue = L.t("Source Row \(doc.getSourceRowNumber(row).formatted())", "원본 \(doc.getSourceRowNumber(row).formatted())행")
            currentInspectorContentKind = .row(displayRow: row, sourceRow: doc.getSourceRowNumber(row))
            let text = NSMutableAttributedString()
            for index in 0..<doc.columnCount {
                let name = columnNames[safe: index] ?? L.t("Column \(index + 1)", "\(index + 1)열")
                let value = index < fields.count ? fields[index] : ""
                text.append(NSAttributedString(string: name + "\n", attributes: [
                    .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
                    .foregroundColor: NSColor.controlAccentColor
                ]))
                text.append(NSAttributedString(string: Self.prettyValue(value) + "\n\n", attributes: [
                    .font: NSFont.systemFont(ofSize: 13),
                    .foregroundColor: NSColor.labelColor
                ]))
            }
            detailTextView.textStorage?.setAttributedString(text)
            updateInspectorCopyButtons()
        } catch {
            detailTextView.string = ""
            currentInspectorContentKind = .empty
            updateInspectorCopyButtons()
        }
    }

    func refreshColumnStatistics(for doc: VirtualCsvDocument, final: Bool = true) {
        let priority = final ? 2 : 1
        if final {
            columnStatisticsCancellation?.cancel()
        }
        let cancellation = CancellationFlag()
        columnStatisticsCancellation = cancellation
        DispatchQueue.global(qos: .utility).async { [weak self, weak doc] in
            guard let doc else { return }
            do {
                let report = try doc.analyzeColumns(sampleLimit: 5_000, cancellation: cancellation)
                DispatchQueue.main.async {
                    guard doc === self?.csvDocument else { return }
                    guard !cancellation.isCancelled else { return }
                    guard priority >= (self?.acceptedColumnStatisticsPriority ?? 0) else { return }
                    self?.acceptedColumnStatisticsPriority = priority
                    self?.baseColumnStatisticsReport = report
                    self?.columnStatisticsReport = report.applyingOverrides(self?.columnTypeOverrides ?? [:])
                    self?.updateSortHeaders()
                    self?.scheduleFacetRefresh()
                }
            } catch {
                DispatchQueue.main.async {
                    guard doc === self?.csvDocument else { return }
                    guard !cancellation.isCancelled else { return }
                    guard priority >= (self?.acceptedColumnStatisticsPriority ?? 0) else { return }
                    self?.acceptedColumnStatisticsPriority = priority
                    self?.columnStatisticsReport = nil
                    self?.updateSortHeaders()
                }
            }
        }
    }

    func maybeRefreshEarlyColumnStatistics(for doc: VirtualCsvDocument) {
        guard Self.shouldStartEarlyColumnStatistics(
            availableRows: doc.dataRowsAvailable,
            indexingComplete: doc.indexingComplete,
            alreadyRequested: earlyColumnStatisticsRequested,
            hasReport: columnStatisticsReport != nil
        ) else { return }
        earlyColumnStatisticsRequested = true
        refreshColumnStatistics(for: doc, final: false)
    }

    static func shouldStartEarlyColumnStatistics(
        availableRows: Int,
        indexingComplete: Bool,
        alreadyRequested: Bool,
        hasReport: Bool
    ) -> Bool {
        !indexingComplete &&
            !alreadyRequested &&
            !hasReport &&
            availableRows >= earlyColumnStatisticsRowThreshold
    }

    func renderColumnStatistics(column: Int) {
        guard let doc = csvDocument else { return }
        detailHeaderLabel.stringValue = L.t("Column Statistics", "컬럼 통계")
        currentInspectorContentKind = .columnStatistics(column: column)
        guard let report = columnStatisticsReport else {
            detailTextView.string = L.t("Statistics are still being calculated.", "통계를 계산 중입니다.")
            updateInspectorCopyButtons()
            refreshColumnStatistics(for: doc)
            return
        }
        guard let summary = report.columns[safe: column] else {
            detailTextView.string = ""
            updateInspectorCopyButtons()
            return
        }

        var lines: [String] = [
            "\(summary.name)",
            "",
            L.t("Type: \(summary.inferredType.rawValue)", "타입: \(summary.inferredType.rawValue)"),
            L.t("Sampled rows: \(report.rowSampleCount.formatted())", "샘플 행: \(report.rowSampleCount.formatted())"),
            L.t("Null: \(summary.nullCount.formatted())", "Null: \(summary.nullCount.formatted())"),
            L.t("Non-null: \(summary.nonNullCount.formatted())", "Non-null: \(summary.nonNullCount.formatted())"),
            L.t("Unique: \(summary.uniqueCount.formatted())", "고유값: \(summary.uniqueCount.formatted())")
        ]

        if let numeric = summary.numeric {
            lines.append("")
            lines.append(L.t("Numeric", "숫자"))
            lines.append("Min: \(formatNumber(numeric.min))")
            lines.append("Max: \(formatNumber(numeric.max))")
            lines.append("Mean: \(formatNumber(numeric.mean))")
            lines.append("Median: \(formatNumber(numeric.median))")
            lines.append("Std: \(formatNumber(numeric.standardDeviation))")
        }

        if !summary.topValues.isEmpty {
            lines.append("")
            lines.append(L.t("Top values", "상위 값"))
            for value in summary.topValues.prefix(10) {
                lines.append("\(value.value): \(value.count.formatted())")
            }
        }

        detailTextView.string = lines.joined(separator: "\n")
        updateInspectorCopyButtons()
    }

    func clampedCurrentDataColumn() -> Int {
        max(0, min(currentDataColumn, max(0, columnNames.count - 1)))
    }

    func inferredType(column: Int) -> ColumnValueType? {
        columnStatisticsReport?.columns[safe: column]?.inferredType
    }

    func isNumericColumn(_ column: Int) -> Bool {
        guard let type = inferredType(column: column) else { return true }
        return [.integer, .float].contains(type)
    }

    func isDateColumn(_ column: Int) -> Bool {
        inferredType(column: column) == .date
    }

    func firstNumericColumn(excluding excluded: Int) -> Int? {
        columnStatisticsReport?.columns.first {
            $0.index != excluded && [.integer, .float].contains($0.inferredType)
        }?.index
    }

    func firstDateColumn(excluding excluded: Int) -> Int? {
        columnStatisticsReport?.columns.first {
            $0.index != excluded && $0.inferredType == .date
        }?.index
    }

    func firstNonNumericColumn(excluding excluded: Int) -> Int? {
        columnStatisticsReport?.columns.first {
            $0.index != excluded && ![.integer, .float].contains($0.inferredType)
        }?.index
    }

    func topGroups(column: Int, limit: Int) -> [String]? {
        columnStatisticsReport?.columns[safe: column]?.topValues.prefix(limit).map(\.value)
    }

    func formatNumericDistribution(_ distribution: NumericDistribution) -> String {
        let name = columnNames[safe: distribution.column] ?? L.t("Column \(distribution.column + 1)", "\(distribution.column + 1)열")
        var lines = [
            name,
            "",
            "Count: \(distribution.count.formatted())",
            "Min: \(formatNumber(distribution.min))",
            "Q1: \(formatNumber(distribution.q1))",
            "Median: \(formatNumber(distribution.median))",
            "Q3: \(formatNumber(distribution.q3))",
            "Max: \(formatNumber(distribution.max))",
            "Mean: \(formatNumber(distribution.mean))",
            "Std: \(formatNumber(distribution.standardDeviation))",
            "",
            L.t("Histogram", "히스토그램")
        ]
        for bin in distribution.bins {
            lines.append("\(formatNumber(bin.lowerBound)) - \(formatNumber(bin.upperBound)): \(bin.count.formatted())")
        }
        return lines.joined(separator: "\n")
    }

    func formatDateHistogram(_ histogram: DateHistogram) -> String {
        let dateName = columnNames[safe: histogram.dateColumn] ?? L.t("Column \(histogram.dateColumn + 1)", "\(histogram.dateColumn + 1)열")
        var lines = [
            dateName,
            L.t("Period: \(histogram.period.rawValue)", "단위: \(histogram.period.rawValue)"),
            ""
        ]
        for bin in histogram.bins {
            if let sum = bin.sum, let average = bin.average {
                lines.append("\(bin.label): count \(bin.count.formatted()), sum \(formatNumber(sum)), avg \(formatNumber(average))")
            } else {
                lines.append("\(bin.label): \(bin.count.formatted())")
            }
        }
        return lines.joined(separator: "\n")
    }

    func formatDuplicates(_ duplicates: [DuplicateGroup], columns: [Int]) -> String {
        let names = columns.map { columnNames[safe: $0] ?? L.t("Column \($0 + 1)", "\($0 + 1)열") }.joined(separator: " + ")
        var lines = [
            names,
            "",
            L.t("Duplicate groups: \(duplicates.count.formatted())", "중복 그룹: \(duplicates.count.formatted())")
        ]
        for group in duplicates.prefix(100) {
            lines.append("\(group.key.joined(separator: " | ")) -> rows \(group.sourceRows.map { $0.formatted() }.joined(separator: ", "))")
        }
        if duplicates.count > 100 {
            lines.append("...")
        }
        return lines.joined(separator: "\n")
    }

    func formatGroupBy(_ result: GroupByResult) -> String {
        let groupNames = result.groupColumns.map { columnNames[safe: $0] ?? L.t("Column \($0 + 1)", "\($0 + 1)열") }.joined(separator: " + ")
        let valueName = columnNames[safe: result.valueColumn] ?? L.t("Column \(result.valueColumn + 1)", "\(result.valueColumn + 1)열")
        var lines = [
            L.t("Group: \(groupNames)", "그룹: \(groupNames)"),
            L.t("Value: \(valueName)", "값: \(valueName)"),
            ""
        ]
        for row in result.rows.prefix(100) {
            let metrics = result.functions.map { function in
                "\(function.rawValue)=\(formatNumber(row.values[function] ?? 0))"
            }.joined(separator: ", ")
            lines.append("\(row.key.joined(separator: " | ")): \(metrics)")
        }
        if result.rows.count > 100 {
            lines.append("...")
        }
        return lines.joined(separator: "\n")
    }

    func formatPivotTable(_ pivot: PivotTableResult) -> String {
        let rowNames = pivot.rowColumns.map { columnNames[safe: $0] ?? L.t("Column \($0 + 1)", "\($0 + 1)열") }.joined(separator: " + ")
        let columnNamesText = pivot.columnColumns.map { columnNames[safe: $0] ?? L.t("Column \($0 + 1)", "\($0 + 1)열") }.joined(separator: " + ")
        let valueName = columnNames[safe: pivot.valueColumn] ?? L.t("Column \(pivot.valueColumn + 1)", "\(pivot.valueColumn + 1)열")
        var lines: [String] = [
            L.t("Rows: \(rowNames)", "행: \(rowNames)"),
            L.t("Columns: \(columnNamesText)", "열: \(columnNamesText)"),
            L.t("Values: \(pivot.function.rawValue)(\(valueName))", "값: \(pivot.function.rawValue)(\(valueName))"),
            ""
        ]
        lines.append(([rowNames] + pivot.columnKeys.map { $0.joined(separator: " | ") }).joined(separator: "\t"))

        for row in pivot.rowKeys.prefix(80) {
            let fields = [row.joined(separator: " | ")] + pivot.columnKeys.map { formatNumber(pivot.value(row: row, column: $0)) }
            lines.append(fields.joined(separator: "\t"))
        }
        if pivot.rowKeys.count > 80 {
            lines.append("...")
        }
        return lines.joined(separator: "\n")
    }

    func formatCorrelation(_ pearson: CorrelationResult, spearman: CorrelationResult, xColumn: Int, yColumn: Int) -> String {
        let xName = columnNames[safe: xColumn] ?? L.t("Column \(xColumn + 1)", "\(xColumn + 1)열")
        let yName = columnNames[safe: yColumn] ?? L.t("Column \(yColumn + 1)", "\(yColumn + 1)열")
        return [
            "\(xName) vs \(yName)",
            "",
            "Pearson r: \(formatNumber(pearson.coefficient))",
            "Pearson p-value: \(formatNumber(pearson.pValue))",
            pearson.interpretation,
            "",
            "Spearman rho: \(formatNumber(spearman.coefficient))",
            "Spearman p-value: \(formatNumber(spearman.pValue))",
            spearman.interpretation,
            "",
            "n: \(pearson.sampleSize.formatted())"
        ].joined(separator: "\n")
    }

    func formatIndependentTTest(_ result: IndependentTTestResult, groupColumn: Int, valueColumn: Int) -> String {
        let groupName = columnNames[safe: groupColumn] ?? L.t("Column \(groupColumn + 1)", "\(groupColumn + 1)열")
        let valueName = columnNames[safe: valueColumn] ?? L.t("Column \(valueColumn + 1)", "\(valueColumn + 1)열")
        return [
            "\(valueName) by \(groupName)",
            "",
            "\(result.groupA) mean: \(formatNumber(result.meanA))",
            "\(result.groupB) mean: \(formatNumber(result.meanB))",
            "t: \(formatNumber(result.tStatistic))",
            "df: \(formatNumber(result.degreesOfFreedom))",
            "p-value: \(formatNumber(result.pValue))",
            "95% CI: \(formatNumber(result.confidenceIntervalLow)) to \(formatNumber(result.confidenceIntervalHigh))",
            "Effect size: \(formatNumber(result.effectSize))",
            result.interpretation
        ].joined(separator: "\n")
    }

    func formatChiSquare(_ result: ChiSquareResult, rowColumn: Int, columnColumn: Int) -> String {
        let rowName = columnNames[safe: rowColumn] ?? L.t("Column \(rowColumn + 1)", "\(rowColumn + 1)열")
        let columnName = columnNames[safe: columnColumn] ?? L.t("Column \(columnColumn + 1)", "\(columnColumn + 1)열")
        var lines = [
            "\(rowName) x \(columnName)",
            "",
            "Chi-square: \(formatNumber(result.statistic))",
            "df: \(result.degreesOfFreedom)",
            "p-value: \(formatNumber(result.pValue))",
            result.interpretation,
            "",
            ([rowName] + result.columnLabels).joined(separator: "\t")
        ]
        for (index, rowLabel) in result.rowLabels.enumerated() {
            let fields = [rowLabel] + result.observed[index].map { formatNumber($0) }
            lines.append(fields.joined(separator: "\t"))
        }
        return lines.joined(separator: "\n")
    }

    func scheduleDetailPanelUpdate() {
        detailUpdateWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.updateDetailPanel()
        }
        detailUpdateWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04, execute: workItem)
    }

    func resetViewState() {
        textCondition = nil
        textConditionDescription = ""
        textFilterTerm = ""
        textFilterColumn = -1
        columnFilterState = ColumnFilterState()
        sortKeys.removeAll()
        currentDataColumn = 0
        lastHighlightedRows.removeAll()
        gridSelection.clear()
        findField.stringValue = ""
        filterField.stringValue = ""
        selectedValueBar.isHidden = true
        selectedAddressLabel.stringValue = ""
        selectedValueTextView.string = ""
        selectedValueExpanded = false
        updateSelectedValueExpansionLayout()
        updateSortHeaders()
        refreshFilterTokens()
        setFilterBarVisible(false)
    }

    func cancelAll() {
        indexCancellation?.cancel()
        operationCancellation?.cancel()
        findCancellation?.cancel()
        prefetchCancellation?.cancel()
        columnFilterValuesCancellation?.cancel()
        columnFilterValuesCancellation = nil
        columnStatisticsCancellation?.cancel()
        analysisCancellation?.cancel()
        chartCancellation?.cancel()
        chartCancellation = nil
        dataQualityCancellation?.cancel()
        dataQualityCancellation = nil
        facetsCancellation?.cancel()
        facetsCancellation = nil
        facetRefreshWorkItem?.cancel()
        rowTimer?.invalidate()
        detailUpdateWorkItem?.cancel()
        indexing = false
        setBusy(false)
        setProgressVisible(false)
        clearColumnFilterValuesLoadingStatus()
    }

    func setBusy(_ value: Bool, message: String? = nil) {
        busy = value
        if let message { statusLabel.stringValue = message }
        updateFeatureState()
    }

    func updateFeatureState() {
        let open = csvDocument != nil
        let ready = csvDocument?.indexingComplete == true && !busy
        findField.isEnabled = open && !busy
        findNextButton.isEnabled = open && !busy
        filterToggleButton.isEnabled = open && !busy
        detailToggleButton.isEnabled = open
        sortControl.isEnabled = ready
        filterField.isEnabled = ready
        filterColumnPopup.isEnabled = ready
        filterByCellButton.isEnabled = ready
        applyFilterButton.isEnabled = ready
        clearFilterButton.isEnabled = ready && hasAnyFilter
        encodingPopup.isEnabled = open && !busy
        closeToolbarItem?.isEnabled = open
        pivotToolbarItem?.isEnabled = ready && columnNames.count >= 2
        updateAnalysisActionBar(running: analysisCancellation != nil)
        refreshSignal()
        updateStatusMetrics()
    }

    func refreshSignal() {
        if csvDocument == nil {
            signalDot.color = .systemGray
            signalLabel.stringValue = L.t("Idle", "대기")
        } else if indexing {
            signalDot.color = .systemYellow
            signalLabel.stringValue = L.t("Loading", "로딩")
        } else if busy {
            signalDot.color = .systemOrange
            signalLabel.stringValue = L.t("Working", "작업 중")
        } else {
            signalDot.color = .systemGreen
            signalLabel.stringValue = L.t("Ready", "준비 완료")
        }
    }

    func updateStatusMetrics() {
        guard let doc = csvDocument else {
            documentInfoLabel.stringValue = L.t("No file", "파일 없음")
            storageModeLabel.stringValue = ""
            storageModeLabel.isHidden = true
            return
        }

        let totalRows = doc.dataRowsAvailable
        let visibleRows = doc.displayRowCount
        let rowsText: String
        if hasAnyFilter || visibleRows != totalRows {
            rowsText = L.t(
                "\(visibleRows.formatted()) / \(totalRows.formatted()) rows",
                "\(visibleRows.formatted()) / \(totalRows.formatted())행"
            )
        } else {
            rowsText = L.t("\(totalRows.formatted()) rows", "\(totalRows.formatted())행")
        }

        let storageMode = doc.indexingComplete ? (doc.inMemory ? "RAM" : "Disk") : (doc.willUseRam ? "RAM" : "Disk")
        var parts = [
            rowsText,
            L.t("\(doc.columnCount) columns", "\(doc.columnCount)열"),
            formatBytes(doc.fileLength),
            storageMode
        ]
        if let indexingElapsed {
            parts.append("\(String(format: "%.0f", indexingElapsed * 1000)) ms")
        }
        documentInfoLabel.stringValue = parts.joined(separator: " · ")
        storageModeLabel.stringValue = ""
        storageModeLabel.isHidden = true
    }

    func performanceSnapshot() -> PerformanceSnapshot? {
        guard let doc = csvDocument else { return nil }
        let storageMode = doc.indexingComplete ? (doc.inMemory ? "RAM" : "Disk") : (doc.willUseRam ? "RAM" : "Disk")
        return PerformanceSnapshot(
            fileBytes: doc.fileLength,
            totalRows: doc.dataRowsAvailable,
            visibleRows: doc.displayRowCount,
            columnCount: doc.columnCount,
            storageMode: storageMode,
            indexingElapsed: indexingElapsed,
            indexingComplete: doc.indexingComplete,
            memoryFootprintBytes: MemoryMetrics.currentFootprintBytes()
        )
    }

    func setProgressVisible(_ visible: Bool) {
        progressLabel.isHidden = !visible
        progressIndicator.isHidden = !visible
    }

    func updateProgress(_ percent: Int) {
        let pct = max(0, min(100, percent))
        progressIndicator.doubleValue = Double(pct)
        progressLabel.stringValue = "\(pct)%"
    }

    func syncEncodingPopup() {
        guard let doc = csvDocument else { return }
        encodingPopup.selectItem(withTitle: doc.encodingName)
    }

    func formatBytes(_ bytes: Int64) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var value = Double(bytes)
        var index = 0
        while value >= 1024, index < units.count - 1 {
            value /= 1024
            index += 1
        }
        return String(format: "%.1f %@", value, units[index])
    }

    func formatNumber(_ value: Double) -> String {
        if value.rounded(.towardZero) == value {
            return String(format: "%.0f", value)
        }
        return String(format: "%.3f", value)
    }

    static func csvEscaped(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r") {
            return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return value
    }

    static func prettyValue(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return value }
        if let data = trimmed.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data),
           JSONSerialization.isValidJSONObject(object),
           let prettyData = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
           let pretty = String(data: prettyData, encoding: .utf8) {
            return pretty
        }
        if trimmed.hasPrefix("<"),
           let data = trimmed.data(using: .utf8),
           let document = try? XMLDocument(data: data, options: [.nodePreserveWhitespace]) {
            return document.xmlString(options: [.nodePrettyPrint])
        }
        return value
    }

    func truncated(_ value: String) -> String {
        let oneLine = value.replacingOccurrences(of: "\r", with: " ").replacingOccurrences(of: "\n", with: " ")
        if oneLine.count <= 20 { return oneLine }
        return String(oneLine.prefix(20)) + "..."
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

#if DEBUG
extension MainWindowController {
    func openFileForTesting(_ url: URL) {
        openFile(url)
    }

    func makePivotBuilderForTesting() -> PivotBuilderWindowController? {
        makePivotBuilder()
    }

    func performAnalysisForTesting(_ request: AnalysisRequest) {
        performAnalysis(request)
    }

    func analysisPromptLayoutMetricsForTesting(_ kind: AnalysisKind) -> AnalysisPromptLayoutMetrics? {
        guard let request = defaultAnalysisRequest(for: kind) else { return nil }
        let sheet = makeAnalysisPromptSheet(kind: kind, defaultRequest: request)
        sheet.panel.contentView?.layoutSubtreeIfNeeded()
        let views = sheet.panel.contentView?.allDescendantsForTesting ?? []
        let rows = views.filter { $0.identifier == .analysisPromptRow }
        let popups = views.compactMap { $0 as? NSPopUpButton }
        let runButton = views.first { $0.identifier == .analysisPromptRunButton }
        let cancelButton = views.first { $0.identifier == .analysisPromptCancelButton }
        return AnalysisPromptLayoutMetrics(
            windowSize: sheet.panel.frame.size,
            rowCount: rows.count,
            minimumPopupWidth: popups.map(\.frame.width).min() ?? 0,
            runButtonSize: runButton?.frame.size ?? .zero,
            cancelButtonSize: cancelButton?.frame.size ?? .zero
        )
    }

    var analysisReportTextForTesting: String {
        currentAnalysisReport?.markdown ?? ""
    }

    var indexingCompleteForTesting: Bool {
        csvDocument?.indexingComplete == true
    }

    var busyForTesting: Bool {
        busy
    }

    var progressVisibleForTesting: Bool {
        !progressLabel.isHidden && !progressIndicator.isHidden
    }

    var statusTextForTesting: String {
        statusLabel.stringValue
    }

    var hasCurrentColumnFilterValuesLoadForTesting: Bool {
        columnFilterValuesCancellation != nil
    }

    var renderedRowCountForTesting: Int {
        tableView.numberOfRows
    }

    func renderedDataRowForTesting(_ row: Int) -> [String] {
        guard row >= 0, row < tableView.numberOfRows else { return [] }
        return (1..<tableView.numberOfColumns).map { columnIndex in
            let column = tableView.tableColumns[columnIndex]
            let view = tableView(tableView, viewFor: column, row: row) as? NSTableCellView
            return view?.textField?.stringValue ?? ""
        }
    }

    func materializedDataRowForTesting(_ row: Int) -> [String] {
        guard row >= 0, row < tableView.numberOfRows else { return [] }
        window?.contentView?.layoutSubtreeIfNeeded()
        tableView.scrollRowToVisible(row)
        tableView.layoutSubtreeIfNeeded()
        return (1..<tableView.numberOfColumns).map { columnIndex in
            let view = tableView.view(atColumn: columnIndex, row: row, makeIfNecessary: true) as? NSTableCellView
            return view?.textField?.stringValue ?? ""
        }
    }

    func selectCellForTesting(row: Int, column: Int) {
        selectGridCellForTesting(row: row, column: column)
    }

    func selectGridCellForTesting(row: Int, column: Int) {
        selectGridCell(row: row, column: column)
    }

    func extendGridSelectionForTesting(toRow row: Int, column: Int) {
        extendGridSelection(toRow: row, column: column)
    }

    func toggleGridCellSelectionForTesting(row: Int, column: Int) {
        selectGridCell(row: row, column: column, toggling: true)
    }

    var selectedGridCellsForTesting: Set<GridCellCoordinate> {
        gridSelection.selectedCells
    }

    func selectedGridCopyStringForTesting() -> String? {
        selectedGridCopyString()
    }

    func applyColumnFilterForTesting(_ filter: ColumnFilter) {
        applyColumnFilter(filter)
    }

    func startColumnFilterValuesLoadForTesting() -> CancellationFlag {
        startColumnFilterValuesLoad()
    }

    func finishColumnFilterValuesLoadForTesting(
        cancellation: CancellationFlag,
        values: [DistinctColumnValue]
    ) {
        guard let doc = csvDocument else { return }
        finishColumnFilterValuesLoad(
            cancellation: cancellation,
            doc: doc,
            column: 0,
            type: .categorical,
            values: values,
            relativeTo: .zero
        )
    }

    func isCurrentColumnFilterValuesLoadForTesting(_ cancellation: CancellationFlag) -> Bool {
        columnFilterValuesCancellation === cancellation
    }

    func rowCopyStringForTesting(row: Int) -> String? {
        rowCopyString(row: row)
    }

    func columnCopyStringForTesting(column: Int, includeHeader: Bool) -> String? {
        columnCopyString(column: column, includeHeader: includeHeader)
    }

    func setInspectorVisibleForTesting(_ visible: Bool) {
        setInspectorVisible(visible, rememberWidth: false, animated: false)
    }

    func showInspectorForTesting() {
        setInspectorVisible(true, animated: false)
    }

    func inspectorTextCopyStringForTesting() -> String {
        inspectorTextCopyString()
    }

    func inspectorJsonCopyStringForTesting() -> String {
        inspectorJsonCopyString() ?? ""
    }

    func toggleSelectedValueExpansionForTesting() {
        toggleSelectedValueExpansion(nil)
    }

    var selectedValueBarHeightForTesting: CGFloat {
        selectedValueBarHeightConstraint?.constant ?? 0
    }

    var selectedValueScrollsVerticallyForTesting: Bool {
        selectedValueScrollView.hasVerticalScroller
    }

    var selectedValueTextForTesting: String {
        selectedValueTextView.string
    }

    var detailHeaderTextForTesting: String {
        detailHeaderLabel.stringValue
    }

    var detailTextForTesting: String {
        detailTextView.string
    }

    func headerTypeTextForTesting(column: Int) -> String? {
        guard let header = tableView
            .tableColumn(withIdentifier: NSUserInterfaceItemIdentifier("c\(column)"))?
            .headerCell as? SortHeaderCell else { return nil }
        return header.typeText
    }

    func headerFilterAvailableForTesting(column: Int) -> Bool {
        guard let header = tableView
            .tableColumn(withIdentifier: NSUserInterfaceItemIdentifier("c\(column)"))?
            .headerCell as? SortHeaderCell else { return false }
        return header.filterAvailable
    }

    func headerFilterActiveForTesting(column: Int) -> Bool {
        guard let header = tableView
            .tableColumn(withIdentifier: NSUserInterfaceItemIdentifier("c\(column)"))?
            .headerCell as? SortHeaderCell else { return false }
        return header.filterActive
    }

    func headerFilterFrameForTesting(column: Int) -> NSRect? {
        guard let tableColumn = tableView.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier("c\(column)")),
              let tableColumnIndex = tableView.tableColumns.firstIndex(of: tableColumn),
              let headerView = tableView.headerView,
              let header = tableColumn.headerCell as? SortHeaderCell else {
            return nil
        }
        return header.filterButtonFrame(withFrame: headerView.headerRect(ofColumn: tableColumnIndex), in: headerView)
    }

    var headerVisibleRectForTesting: NSRect {
        tableView.headerView?.visibleRect ?? .zero
    }

    var tableVisibleRectForTesting: NSRect {
        tableView.visibleRect
    }

    func scrollGridHorizontallyForTesting(to x: CGFloat) {
        let maxX = max(0, tableView.frame.width - scrollView.contentSize.width)
        let origin = NSPoint(x: min(max(0, x), maxX), y: scrollView.contentView.bounds.origin.y)
        scrollView.contentView.scroll(to: origin)
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    func scrollColumnToVisibleForTesting(column: Int) {
        guard let tableColumn = tableView.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier("c\(column)")),
              let tableColumnIndex = tableView.tableColumns.firstIndex(of: tableColumn) else {
            return
        }
        tableView.scrollColumnToVisible(tableColumnIndex)
    }

    func headerDisplayTitleForTesting(column: Int) -> String? {
        tableView
            .tableColumn(withIdentifier: NSUserInterfaceItemIdentifier("c\(column)"))?
            .headerCell
            .stringValue
    }

    var tableHeaderHeightForTesting: CGFloat {
        tableView.headerView?.frame.height ?? 0
    }

    func layoutWindowForTesting() {
        window?.layoutIfNeeded()
        window?.contentView?.layoutSubtreeIfNeeded()
        updateTableDocumentWidthForViewport()
        tableView.layoutSubtreeIfNeeded()
    }

    var facetsPanelVisibleForTesting: Bool {
        isFacetsPanelVisible
    }

    var inspectorVisibleForTesting: Bool {
        isInspectorVisible
    }

    var chartWindowsForTesting: [ChartWindowController] {
        chartWindows
    }

    func openChartWindowForTesting(_ request: ChartRequest) {
        openChartWindow(request: request)
    }

    func defaultChartRequestForTesting(kind: ChartKind) -> ChartRequest? {
        defaultChartRequest(for: kind)
    }

    var dataQualityReportForTesting: DataQualityReport? {
        currentDataQualityReport
    }

    func saveViewForTesting(named name: String) {
        guard let currentFilePath = currentFilePathForTesting else { return }
        saveCurrentView(named: name, forPath: currentFilePath)
    }

    @discardableResult
    func restoreViewForTesting(named name: String) -> Bool {
        guard let currentFilePath = currentFilePathForTesting else { return false }
        return restoreSavedView(named: name, forPath: currentFilePath)
    }

    func deleteSavedViewForTesting(named name: String) {
        guard let currentFilePath = currentFilePathForTesting else { return }
        var store = savedViewStore()
        store.remove(name: name, forPath: currentFilePath)
        persistSavedViewStore(store)
    }

    var savedViewNamesForTesting: [String] {
        guard let currentFilePath = currentFilePathForTesting else { return [] }
        return savedViewStore().names(forPath: currentFilePath)
    }

    func isColumnHiddenForTesting(_ column: Int) -> Bool {
        hiddenColumnIndexes.contains(column)
    }

    var tableRowHeightForTesting: CGFloat {
        tableView.rowHeight
    }

    func setRowDensityForTesting(_ density: GridRowDensity) {
        UserDefaults.standard.set(density.rawValue, forKey: Self.rowDensityDefaultsKey)
        applyRowDensity()
    }

    func performanceSnapshotForTesting() -> PerformanceSnapshot? {
        performanceSnapshot()
    }

    var currentFilePathForTesting: String? {
        currentFilePath
    }

    func setAutoRestoreViewForTesting(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: Self.autoRestoreViewDefaultsKey)
    }

    var hasPendingDataQualityScanForTesting: Bool {
        dataQualityCancellation != nil
    }

    func setFacetsPanelVisibleForTesting(_ visible: Bool) {
        setFacetsPanelVisible(visible, persist: false)
    }

    var facetSectionsForTesting: [FacetPanelSection] {
        facetsPanel.renderedSections
    }

    var facetsPanelWidthForTesting: CGFloat {
        facetsWidthConstraint?.constant ?? 0
    }

    var hasPendingFacetLoadForTesting: Bool {
        facetsCancellation != nil
    }

    func handleFacetSelectionForTesting(column: Int, kind: FacetPanelEntry.Kind) {
        handleFacetSelection(column: column, kind: kind)
    }

    var columnFilterStateForTesting: ColumnFilterState {
        columnFilterState
    }

    var tableDocumentWidthForTesting: CGFloat {
        tableView.frame.width
    }

    var gridLayoutPassCountForTesting: Int {
        gridLayoutPassCount
    }

    var tableViewportWidthForTesting: CGFloat {
        scrollView.contentSize.width
    }

    var horizontalScrollerConfiguredForTesting: Bool {
        scrollView.hasHorizontalScroller && !scrollView.autohidesScrollers && scrollView.scrollerStyle == .legacy
    }

    func tableColumnWidthForTesting(column: Int) -> CGFloat {
        tableView.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier("c\(column)"))?.width ?? 0
    }

    func setTableColumnWidthForTesting(column: Int, width: CGFloat) {
        guard let tableColumn = tableView.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier("c\(column)")) else {
            return
        }
        let oldWidth = tableColumn.width
        tableColumn.width = width
        NotificationCenter.default.post(
            name: NSTableView.columnDidResizeNotification,
            object: tableView,
            userInfo: ["NSTableColumn": tableColumn, "NSOldWidth": oldWidth]
        )
    }

    func headerTooltipForTesting(column: Int) -> String? {
        tableView
            .tableColumn(withIdentifier: NSUserInterfaceItemIdentifier("c\(column)"))?
            .headerToolTip
    }

    func tableColumnRectForTesting(column: Int) -> NSRect {
        guard let tableColumn = tableView.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier("c\(column)")),
              let index = tableView.tableColumns.firstIndex(of: tableColumn) else {
            return .null
        }
        return tableView.rect(ofColumn: index)
    }

    var tableIntercellSpacingForTesting: NSSize {
        tableView.intercellSpacing
    }

    func setColumnTypeOverrideForTesting(column: Int, type: ColumnValueType?) {
        setColumnTypeOverride(column: column, type: type)
    }

    func requestColumnTypeChangeForTesting(column: Int, to target: ColumnValueType) {
        requestColumnTypeChange(column: column, to: target)
    }

    var columnTypeOverridesForTesting: [Int: String] {
        columnTypeOverrides.mapValues(\.rawValue)
    }

    func headerFilterHitDataColumnForTesting(column: Int) -> Int? {
        guard let headerView = tableView.headerView as? CsvTableHeaderView,
              let tableColumn = tableView.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier("c\(column)")),
              let index = tableView.tableColumns.firstIndex(of: tableColumn),
              let cell = tableColumn.headerCell as? SortHeaderCell,
              let frame = cell.filterHitFrame(headerFrame: headerView.headerRect(ofColumn: index), in: headerView) else {
            return nil
        }
        return headerView.filterHit(at: NSPoint(x: frame.midX, y: frame.midY))?.dataColumn
    }
}
#endif
