import AppKit
@preconcurrency import CsvCore

@MainActor
final class MainWindowController: NSWindowController {
    private static let persistentIndexDefaultsKey = "NanumCsvViewerMac.PersistentIndexEnabled"
    private static let hiddenColumnsDefaultsKey = "NanumCsvViewerMac.HiddenColumnIndexes"

    private let tableView = CsvTableView()
    private let scrollView = NSScrollView()
    private let selectedValueBar = NSVisualEffectView()
    private let selectedAddressLabel = NSTextField(labelWithString: "")
    private let selectedValueTextView = NSTextView()
    private let selectedValueScrollView = NSScrollView()
    private let detailHeaderLabel = NSTextField(labelWithString: L.t("Inspector", "인스펙터"))
    private let detailTextView = NSTextView()
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
    private let mainSplit = NSSplitView()
    private let contentContainer = NSView()
    private let filterBarView = FilterBarView()
    private let filterTokensStack = NSStackView()
    private let emptyStateView = NSView()
    private let detailPanel = NSView()
    private var didSetInitialSplit = false
    private var preferredInspectorWidth: CGFloat = 360

    private var csvDocument: VirtualCsvDocument?
    private var indexCancellation: CancellationFlag?
    private var operationCancellation: CancellationFlag?
    private var findCancellation: CancellationFlag?
    private var prefetchCancellation: CancellationFlag?
    private var rowTimer: Timer?
    private var lastKnownRowCount = 0
    private var lastHighlightedRow: Int?
    private var busy = false
    private var indexing = false
    private var indexingElapsed: TimeInterval?
    private var currentDataColumn = 0
    private var columnNames: [String] = []
    private var sortKeys: [SortKey] = []
    private var textCondition: (([String]) -> Bool)?
    private var textConditionDescription = ""
    private var textFilterTerm = ""
    private var textFilterColumn = -1
    private var valueConditions: [(description: String, predicate: ([String]) -> Bool)] = []
    private var detailUpdateWorkItem: DispatchWorkItem?
    private var columnStatisticsReport: ColumnStatisticsReport?
    private var hiddenColumnIndexes: Set<Int> = []

    private var hasAnyFilter: Bool {
        textCondition != nil || !valueConditions.isEmpty
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
        super.init(window: window)
        VirtualCsvDocument.persistentIndexEnabled = UserDefaults.standard.object(forKey: Self.persistentIndexDefaultsKey) as? Bool ?? true
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
        setFilterBarVisible(false)
        setInspectorVisible(false, rememberWidth: false, animated: false)
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
        left.addArrangedSubview(scrollView)

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
        bar.heightAnchor.constraint(equalToConstant: 34).isActive = true

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
        selectedValueScrollView.documentView = selectedValueTextView
        selectedValueScrollView.hasVerticalScroller = false
        selectedValueScrollView.autohidesScrollers = true
        selectedValueScrollView.drawsBackground = false
        selectedValueScrollView.borderType = .noBorder
        selectedValueScrollView.translatesAutoresizingMaskIntoConstraints = false

        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false

        bar.addSubview(selectedAddressLabel)
        bar.addSubview(selectedValueScrollView)
        bar.addSubview(separator)
        NSLayoutConstraint.activate([
            selectedAddressLabel.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 10),
            selectedAddressLabel.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            selectedAddressLabel.widthAnchor.constraint(equalToConstant: 170),
            selectedValueScrollView.leadingAnchor.constraint(equalTo: selectedAddressLabel.trailingAnchor, constant: 10),
            selectedValueScrollView.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -10),
            selectedValueScrollView.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            selectedValueScrollView.heightAnchor.constraint(equalToConstant: 24),
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
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = false
        tableView.delegate = self
        tableView.dataSource = self
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.gridStyleMask = [.solidHorizontalGridLineMask, .solidVerticalGridLineMask]
        tableView.rowSizeStyle = .medium
        tableView.allowsMultipleSelection = false
        tableView.allowsColumnResizing = true
        tableView.allowsColumnReordering = true
        tableView.columnAutoresizingStyle = .noColumnAutoresizing
        tableView.doubleAction = #selector(copySelectedCellToPasteboard(_:))
        tableView.target = self
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(visibleRowsDidChange(_:)),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )
        tableView.cellClickHandler = { [weak self] row, column in
            guard let self else { return }
            if column > 0 {
                currentDataColumn = column - 1
            }
            if row >= 0 {
                tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            }
            updateSelectedValue()
            scheduleDetailPanelUpdate()
            reloadSelectedRowHighlight()
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

        detailTextView.isEditable = false
        detailTextView.isSelectable = true
        detailTextView.textContainerInset = NSSize(width: 14, height: 12)
        detailTextView.font = .systemFont(ofSize: 13)
        detailTextView.backgroundColor = .windowBackgroundColor
        let detailScroll = NSScrollView()
        detailScroll.documentView = detailTextView
        detailScroll.hasVerticalScroller = true
        detailScroll.drawsBackground = false
        stack.addArrangedSubview(detailScroll)
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
    static let sortGroup = NSToolbarItem.Identifier("sortGroup")
    static let findGroup = NSToolbarItem.Identifier("findGroup")
    static let filterToggle = NSToolbarItem.Identifier("filterToggle")
    static let detail = NSToolbarItem.Identifier("detail")
}

extension MainWindowController: NSToolbarDelegate {
    nonisolated func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.openFile, .sortGroup, .findGroup, .filterToggle, .detail, .flexibleSpace, .space]
    }

    nonisolated func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.openFile, .sortGroup, .findGroup, .filterToggle, .flexibleSpace, .detail]
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

            case .sortGroup:
                configureSortControl()
                return viewToolbarItem(identifier: itemIdentifier, label: L.t("Sort", "정렬"), view: sortControl, minWidth: 104, maxWidth: 104)

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
    nonisolated func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        MainActor.assumeIsolated {
            let hasDocument = csvDocument != nil
            let ready = csvDocument?.indexingComplete == true && !busy
            let hasSelection = tableView.selectedRow >= 0

            switch menuItem.action {
            case #selector(openDocument(_:)), #selector(showUsage(_:)):
                return true
            case #selector(exportCurrentView(_:)):
                return ready
            case #selector(focusFindField(_:)), #selector(findNext(_:)):
                return hasDocument && !busy
            case #selector(goToRow(_:)):
                return hasDocument && !busy
            case #selector(copySelectedCellToPasteboard(_:)), #selector(copySelectedCellAsCsv(_:)), #selector(copySelectedCellAsJson(_:)):
                return hasDocument && hasSelection
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
            case #selector(showColumnStatistics(_:)):
                return ready
            case #selector(showAllColumns(_:)):
                return hasDocument && !hiddenColumnIndexes.isEmpty
            case #selector(hideCurrentColumn(_:)):
                return hasDocument && currentDataColumn >= 0
            case #selector(togglePersistentIndex(_:)):
                menuItem.state = VirtualCsvDocument.persistentIndexEnabled ? .on : .off
                return true
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
        panel.allowedContentTypes = [.commaSeparatedText, .plainText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.beginSheetModal(for: window!) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                self?.openFile(url)
            }
        }
    }

    @objc func exportCurrentView(_ sender: Any?) {
        guard let doc = csvDocument, doc.indexingComplete, !busy else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "export.csv"
        panel.beginSheetModal(for: window!) { [weak self, weak doc] response in
            guard response == .OK, let url = panel.url, let doc else { return }
            Task { @MainActor in
                self?.runViewOperation(message: L.t("Exporting...", "내보내는 중...")) { flag, progress in
                    try doc.exportCurrentView(to: url.path, cancellation: flag)
                    progress(100)
                } completion: { [weak self] in
                    self?.statusLabel.stringValue = L.t("Exported current view.", "현재 보기를 내보냈습니다.")
                }
            }
        }
    }

    private func openFile(_ url: URL) {
        cancelAll()
        do {
            let doc = try VirtualCsvDocument.open(path: url.path)
            csvDocument = doc
            indexingElapsed = nil
            columnStatisticsReport = nil
            window?.title = "Nanum CSV Viewer - \(url.lastPathComponent)"
            resetViewState()
            buildColumns(from: doc.header)
            syncEncodingPopup()
            tableView.reloadData()
            lastKnownRowCount = 0
            updateEmptyState()
            startIndexing(csvDocument: doc)
            updateFeatureState()
        } catch {
            indexingElapsed = nil
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
        refreshColumnStatistics(for: doc)
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
    }

    private func buildColumns(from header: [String]) {
        while tableView.tableColumns.count > 0 {
            tableView.removeTableColumn(tableView.tableColumns[0])
        }

        columnNames = header.enumerated().map { index, name in
            name.isEmpty ? L.t("Column \(index + 1)", "\(index + 1)열") : name
        }

        let rowColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("rowNumber"))
        rowColumn.title = "#"
        rowColumn.headerCell = NSTableHeaderCell(textCell: "#")
        rowColumn.width = 76
        rowColumn.minWidth = 56
        tableView.addTableColumn(rowColumn)

        for (index, name) in columnNames.enumerated() {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("c\(index)"))
            column.title = name
            column.headerCell = SortHeaderCell(textCell: name)
            column.width = 150
            column.minWidth = 60
            column.isHidden = hiddenColumnIndexes.contains(index)
            tableView.addTableColumn(column)
        }

        filterColumnPopup.removeAllItems()
        filterColumnPopup.addItem(withTitle: L.t("All Columns", "전체 열"))
        filterColumnPopup.addItems(withTitles: columnNames)
        filterColumnPopup.selectItem(at: 0)
        updateSortHeaders()
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

        findCancellation?.cancel()
        let cancellation = CancellationFlag()
        findCancellation = cancellation
        let start = tableView.selectedRow >= 0 ? tableView.selectedRow + 1 : 0
        setBusy(true, message: L.t("Searching...", "검색 중..."))

        DispatchQueue.global(qos: .userInitiated).async { [weak self, weak doc] in
            guard let doc else { return }
            let found: Int?
            do {
                found = try Self.searchForward(csvDocument: doc, term: term, start: start, total: total, cancellation: cancellation)
            } catch {
                return
            }
            DispatchQueue.main.async {
                guard doc === self?.csvDocument else { return }
                self?.setBusy(false)
                if let found {
                    self?.tableView.selectRowIndexes(IndexSet(integer: found), byExtendingSelection: false)
                    self?.tableView.scrollRowToVisible(found)
                    self?.statusLabel.stringValue = L.t("Found \"\(term)\" at row \((found + 1).formatted()).", "\"\(term)\" 검색 결과: \((found + 1).formatted())행")
                } else {
                    self?.statusLabel.stringValue = L.t("No match for \"\(term)\".", "\"\(term)\" 검색 결과가 없습니다.")
                }
            }
        }
    }

    private nonisolated static func searchForward(csvDocument: VirtualCsvDocument, term: String, start: Int, total: Int, cancellation: CancellationFlag) throws -> Int? {
        if start < total {
            for row in start..<total {
                if row & 0x3FFF == 0 { try cancellation.check() }
                if try rowContains(csvDocument: csvDocument, viewRow: row, term: term) { return row }
            }
        }
        if start > 0 {
            for row in 0..<min(start, total) {
                if row & 0x3FFF == 0 { try cancellation.check() }
                if try rowContains(csvDocument: csvDocument, viewRow: row, term: term) { return row }
            }
        }
        return nil
    }

    private nonisolated static func rowContains(csvDocument: VirtualCsvDocument, viewRow: Int, term: String) throws -> Bool {
        let row = try csvDocument.getDisplayRow(viewRow)
        return row.contains { $0.range(of: term, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
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
        let compiledExpression: CompiledAdvancedFilter?
        if Self.looksLikeExpression(term) {
            do {
                compiledExpression = try AdvancedFilterExpression.compile(term, headers: doc.header)
            } catch {
                presentError(error)
                return
            }
        } else {
            compiledExpression = nil
        }

        let activePredicate: ([String]) -> Bool
        if let compiledExpression {
            activePredicate = compiledExpression.predicate
            textCondition = activePredicate
            textConditionDescription = L.t("expression: \(truncated(term))", "표현식: \(truncated(term))")
        } else {
            let predicate = Self.containsPredicate(term: term, column: column)
            activePredicate = predicate
            let columnName = column < 0 ? L.t("all columns", "전체 열") : columnNames[safe: column] ?? L.t("column \(column + 1)", "\(column + 1)열")
            textCondition = activePredicate
            textConditionDescription = L.t("\(columnName) contains \"\(truncated(term))\"", "\(columnName)에 \"\(truncated(term))\" 포함")
        }
        textFilterTerm = term
        textFilterColumn = column
        setFilterBarVisible(true)
        let canUseColumnFastPath = compiledExpression == nil && column >= 0 && (!hadTextCondition || valueConditions.isEmpty)
        if canUseColumnFastPath {
            let withinCurrentView = !hadTextCondition && !valueConditions.isEmpty
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
            let name = columnNames[safe: column] ?? L.t("column \(column + 1)", "\(column + 1)열")
            valueConditions.append((
                description: L.t("\(name) = \"\(truncated(value))\"", "\(name) = \"\(truncated(value))\""),
                predicate: { fields in column < fields.count && fields[column] == value }
            ))
            setFilterBarVisible(true)
            runViewOperation(message: L.t("Applying cell filter...", "셀값 필터 적용 중...")) { flag, progress in
                try doc.filterColumnEquals(column: column, value: value, withinCurrentView: true, progress: progress, cancellation: flag)
            } completion: { [weak self] in
                self?.updateFilterStatus()
            }
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
        valueConditions.removeAll()
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

    private func combinedPredicate() -> ([String]) -> Bool {
        let text = textCondition
        let predicates = valueConditions.map(\.predicate)
        return { row in
            if let text, !text(row) { return false }
            return predicates.allSatisfy { $0(row) }
        }
    }

    private nonisolated static func containsPredicate(term: String, column: Int) -> ([String]) -> Bool {
        if column < 0 {
            return { row in row.contains { $0.range(of: term, options: [.caseInsensitive, .diacriticInsensitive]) != nil } }
        }
        return { row in
            column < row.count && row[column].range(of: term, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }

    private nonisolated static func looksLikeExpression(_ text: String) -> Bool {
        let lowered = text.lowercased()
        return lowered.contains(" and ")
            || lowered.contains(" or ")
            || lowered.contains(" contains ")
            || lowered.contains("==")
            || lowered.contains("!=")
            || lowered.contains(">=")
            || lowered.contains("<=")
            || lowered.contains(" > ")
            || lowered.contains(" < ")
    }

    private func updateFilterStatus() {
        guard csvDocument != nil else { return }
        refreshFilterTokens()
        if !hasAnyFilter {
            statusLabel.stringValue = ""
            updateFeatureState()
            return
        }
        var parts: [String] = []
        if textCondition != nil { parts.append(textConditionDescription) }
        parts.append(contentsOf: valueConditions.map(\.description))
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
            column?.title = name
            if let sortIndex = sortKeys.firstIndex(where: { $0.column == index }) {
                let key = sortKeys[sortIndex]
                let priority = sortKeys.count > 1 ? sortIndex + 1 : nil
                if let header = column?.headerCell as? SortHeaderCell {
                    header.stringValue = name
                    header.sortPriority = priority
                    header.ascending = key.ascending
                }
                column?.headerToolTip = L.t(
                    "Sorted \(key.ascending ? "ascending" : "descending")\(priority.map { ", priority \($0)" } ?? "")",
                    "\(key.ascending ? "오름차순" : "내림차순") 정렬\(priority.map { ", \($0)순위" } ?? "")"
                )
            } else {
                if let header = column?.headerCell as? SortHeaderCell {
                    header.stringValue = name
                    header.sortPriority = nil
                    header.ascending = nil
                }
                column?.headerToolTip = nil
            }
        }
        tableView.headerView?.needsDisplay = true
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
    }

    @objc func toggleFilterBar(_ sender: Any?) {
        setFilterBarVisible(filterBarView.isHidden, focus: true)
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

            Toolbar: Open, sort, find, and detail panel.
            Filter bar: choose a column, enter text, apply or clear filters.
            Table: right-click a cell to copy it or filter by that value.
            Headers: click to sort, Shift-click to add another sort key.
            Encoding: use the status-bar popup or View > Encoding.
            """,
            """
            CSV 또는 텍스트 파일을 열면 백그라운드 인덱싱 중에도 행을 탐색할 수 있습니다.

            툴바: 열기, 정렬, 찾기, 상세 패널.
            필터 바: 열 선택, 텍스트 입력, 필터 적용/해제.
            표: 셀을 우클릭해 복사하거나 해당 값으로 필터.
            헤더: 클릭하면 정렬, Shift+클릭하면 정렬 기준 추가.
            인코딩: 상태바 팝업 또는 보기 > 인코딩.
            """
        )
        let alert = NSAlert()
        alert.messageText = L.t("How to Use", "사용법")
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.runModal()
    }

    @objc func copySelectedCellToPasteboard(_ sender: Any?) {
        guard let value = selectedCellValue() else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        statusLabel.stringValue = L.t("Copied selected cell.", "선택 셀을 복사했습니다.")
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

    private func runViewOperation(
        message: String,
        operation: @escaping (_ cancellation: CancellationFlag, _ progress: @escaping (Int) -> Void) throws -> Void,
        completion: @escaping () -> Void
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
                        self?.updateProgress(pct)
                    }
                }
                DispatchQueue.main.async {
                    self?.setProgressVisible(false)
                    self?.setBusy(false)
                    self?.refreshRowCount()
                    self?.tableView.reloadData()
                    self?.scheduleVisibleRowPrefetch()
                    completion()
                }
            } catch CsvError.cancelled {
                DispatchQueue.main.async {
                    self?.setProgressVisible(false)
                    self?.setBusy(false)
                }
            } catch {
                DispatchQueue.main.async {
                    self?.setProgressVisible(false)
                    self?.setBusy(false)
                    self?.presentError(error)
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
                cell.textField?.stringValue = column < fields.count ? fields[column] : ""
            } catch {
                cell.textField?.stringValue = ""
            }
            cell.textField?.alignment = .left
            cell.textField?.font = .systemFont(ofSize: 13)
            cell.textField?.textColor = .labelColor
            cell.wantsLayer = true
            if row == tableView.selectedRow && column == currentDataColumn {
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
            updateSelectedValue()
            scheduleDetailPanelUpdate()
            reloadSelectedRowHighlight()
        }
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

    private func makeCellView(identifier: NSUserInterfaceItemIdentifier) -> NSTableCellView {
        let cell = NSTableCellView()
        cell.identifier = identifier
        let text = NSTextField(labelWithString: "")
        text.lineBreakMode = .byTruncatingTail
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
}

extension MainWindowController {
    func columnIndex(from identifier: NSUserInterfaceItemIdentifier) -> Int {
        Int(identifier.rawValue.dropFirst()) ?? 0
    }

    func updateSelectedValue() {
        guard let doc = csvDocument, tableView.selectedRow >= 0 else {
            selectedValueBar.isHidden = true
            selectedAddressLabel.stringValue = ""
            selectedValueTextView.string = ""
            return
        }
        selectedValueBar.isHidden = false
        let row = tableView.selectedRow
        do {
            let fields = try doc.getDisplayRow(row)
            let column = max(0, min(currentDataColumn, max(0, columnNames.count - 1)))
            let value = column < fields.count ? fields[column] : ""
            selectedValueTextView.string = value
            let name = columnNames[safe: column] ?? ""
            selectedAddressLabel.stringValue = "\(doc.getSourceRowNumber(row).formatted()) · \(name)"
        } catch {
            selectedValueTextView.string = ""
        }
    }

    func setFilterBarVisible(_ visible: Bool, focus: Bool = false) {
        filterBarView.isHidden = !visible
        filterToggleButton.state = visible ? .on : .off
        if visible && focus {
            window?.makeFirstResponder(filterField)
        }
    }

    @objc func visibleRowsDidChange(_ notification: Notification) {
        scheduleVisibleRowPrefetch()
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
        }
    }

    func filterDescriptions() -> [String] {
        var descriptions: [String] = []
        if textCondition != nil {
            descriptions.append(textConditionDescription)
        }
        descriptions.append(contentsOf: valueConditions.map(\.description))
        return descriptions
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

        for (index, condition) in valueConditions.enumerated() where visibleCount < 4 {
            addFilterToken(
                condition.description,
                editable: false,
                onEdit: nil,
                onRemove: { [weak self] in self?.removeValueFilterToken(at: index) }
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

    private func removeValueFilterToken(at index: Int) {
        guard valueConditions.indices.contains(index) else { return }
        valueConditions.remove(at: index)
        rebuildFilter(message: L.t("Updating filter...", "필터 갱신 중..."))
    }

    func reloadSelectedRowHighlight() {
        let row = tableView.selectedRow
        guard tableView.numberOfColumns > 1 else { return }
        var rows = IndexSet()
        if let lastHighlightedRow, lastHighlightedRow >= 0 {
            rows.insert(lastHighlightedRow)
        }
        if row >= 0 {
            rows.insert(row)
        }
        lastHighlightedRow = row >= 0 ? row : nil
        guard !rows.isEmpty else { return }
        tableView.reloadData(
            forRowIndexes: rows,
            columnIndexes: IndexSet(integersIn: 1..<tableView.numberOfColumns)
        )
    }

    func selectedCellValue() -> String? {
        guard let doc = csvDocument, tableView.selectedRow >= 0 else { return nil }
        do {
            let row = try doc.getDisplayRow(tableView.selectedRow)
            return currentDataColumn < row.count ? row[currentDataColumn] : ""
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
        statusLabel.stringValue = L.t("Column hidden.", "컬럼을 숨겼습니다.")
    }

    @objc func showAllColumns(_ sender: Any?) {
        hiddenColumnIndexes.removeAll()
        for index in columnNames.indices {
            tableView.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier("c\(index)"))?.isHidden = false
        }
        persistColumnVisibility()
        statusLabel.stringValue = L.t("All columns shown.", "모든 컬럼을 표시했습니다.")
    }

    @objc func togglePersistentIndex(_ sender: Any?) {
        VirtualCsvDocument.persistentIndexEnabled.toggle()
        UserDefaults.standard.set(VirtualCsvDocument.persistentIndexEnabled, forKey: Self.persistentIndexDefaultsKey)
        statusLabel.stringValue = VirtualCsvDocument.persistentIndexEnabled
            ? L.t("Persistent index enabled.", "인덱스 저장을 켰습니다.")
            : L.t("Persistent index disabled.", "인덱스 저장을 껐습니다.")
    }

    func persistColumnVisibility() {
        UserDefaults.standard.set(Array(hiddenColumnIndexes).sorted(), forKey: Self.hiddenColumnsDefaultsKey)
    }

    func updateDetailPanel() {
        guard isInspectorVisible else { return }
        guard let doc = csvDocument, tableView.selectedRow >= 0 else {
            detailHeaderLabel.stringValue = L.t("Inspector", "인스펙터")
            detailTextView.string = ""
            return
        }
        let row = tableView.selectedRow
        do {
            let fields = try doc.getDisplayRow(row)
            detailHeaderLabel.stringValue = L.t("Source Row \(doc.getSourceRowNumber(row).formatted())", "원본 \(doc.getSourceRowNumber(row).formatted())행")
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
        } catch {
            detailTextView.string = ""
        }
    }

    func refreshColumnStatistics(for doc: VirtualCsvDocument) {
        let cancellation = CancellationFlag()
        DispatchQueue.global(qos: .utility).async { [weak self, weak doc] in
            guard let doc else { return }
            do {
                let report = try doc.analyzeColumns(sampleLimit: 5_000, cancellation: cancellation)
                DispatchQueue.main.async {
                    guard doc === self?.csvDocument else { return }
                    self?.columnStatisticsReport = report
                }
            } catch {
                DispatchQueue.main.async {
                    guard doc === self?.csvDocument else { return }
                    self?.columnStatisticsReport = nil
                }
            }
        }
    }

    func renderColumnStatistics(column: Int) {
        guard let doc = csvDocument else { return }
        detailHeaderLabel.stringValue = L.t("Column Statistics", "컬럼 통계")
        guard let report = columnStatisticsReport else {
            detailTextView.string = L.t("Statistics are still being calculated.", "통계를 계산 중입니다.")
            refreshColumnStatistics(for: doc)
            return
        }
        guard let summary = report.columns[safe: column] else {
            detailTextView.string = ""
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
        valueConditions.removeAll()
        sortKeys.removeAll()
        currentDataColumn = 0
        lastHighlightedRow = nil
        findField.stringValue = ""
        filterField.stringValue = ""
        selectedValueBar.isHidden = true
        selectedAddressLabel.stringValue = ""
        selectedValueTextView.string = ""
        updateSortHeaders()
        refreshFilterTokens()
        setFilterBarVisible(false)
    }

    func cancelAll() {
        indexCancellation?.cancel()
        operationCancellation?.cancel()
        findCancellation?.cancel()
        prefetchCancellation?.cancel()
        rowTimer?.invalidate()
        detailUpdateWorkItem?.cancel()
        indexing = false
        busy = false
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

    var indexingCompleteForTesting: Bool {
        csvDocument?.indexingComplete == true
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
}
#endif
