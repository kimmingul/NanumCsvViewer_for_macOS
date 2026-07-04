import AppKit
@preconcurrency import CsvCore

final class ColumnFilterPopoverController: NSViewController {
    var onApply: ((ColumnFilter?) -> Void)?
    var onClose: (() -> Void)?

    private let column: Int
    private let columnName: String
    private let type: ColumnValueType
    private let values: [DistinctColumnValue]
    private let initialFilter: ColumnFilter?

    private let searchField = NSSearchField()
    private let valuesStack = NSStackView()
    private let valueListContainer = NSView()
    private let valueScrollView = NSScrollView()
    private let startEnabledButton = NSButton(checkboxWithTitle: L.t("Start", "시작"), target: nil, action: nil)
    private let endEnabledButton = NSButton(checkboxWithTitle: L.t("End", "종료"), target: nil, action: nil)
    private let startPicker = NSDatePicker()
    private let endPicker = NSDatePicker()
    private var selectedValues = Set<String>()
    private var includeBlanks = false

    init(
        column: Int,
        columnName: String,
        type: ColumnValueType,
        values: [DistinctColumnValue],
        initialFilter: ColumnFilter?
    ) {
        self.column = column
        self.columnName = columnName
        self.type = type
        self.values = values
        self.initialFilter = initialFilter
        super.init(nibName: nil, bundle: nil)
        if case .selectedValues(_, let values, let includeBlanks) = initialFilter {
            selectedValues = values
            self.includeBlanks = includeBlanks
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: type == .date ? 210 : 420))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildInterface()
    }

    private func buildInterface() {
        let root = NSStackView()
        root.orientation = .vertical
        root.spacing = 10
        root.edgeInsets = NSEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)
        root.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(root)

        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            root.topAnchor.constraint(equalTo: view.topAnchor),
            root.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        let title = NSTextField(labelWithString: columnName)
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        title.lineBreakMode = .byTruncatingTail
        root.addArrangedSubview(title)

        if type == .date {
            buildDateControls(in: root)
        } else {
            buildValueControls(in: root)
        }

        let actions = NSStackView()
        actions.orientation = .horizontal
        actions.spacing = 8
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        actions.addArrangedSubview(spacer)

        let cancel = NSButton(title: L.t("Cancel", "취소"), target: self, action: #selector(cancel(_:)))
        cancel.bezelStyle = .rounded
        actions.addArrangedSubview(cancel)

        let apply = NSButton(title: L.t("Apply", "적용"), target: self, action: #selector(apply(_:)))
        apply.bezelStyle = .rounded
        apply.keyEquivalent = "\r"
        actions.addArrangedSubview(apply)
        root.addArrangedSubview(actions)
    }

    private func buildValueControls(in root: NSStackView) {
        searchField.placeholderString = L.t("Search values", "값 검색")
        searchField.target = self
        searchField.action = #selector(searchChanged(_:))
        root.addArrangedSubview(searchField)

        let quickActions = NSStackView()
        quickActions.orientation = .horizontal
        quickActions.spacing = 8
        let selectAll = NSButton(title: L.t("Select All", "전체 선택"), target: self, action: #selector(selectAllValues(_:)))
        let clear = NSButton(title: L.t("Clear", "해제"), target: self, action: #selector(clearValues(_:)))
        selectAll.bezelStyle = .rounded
        clear.bezelStyle = .rounded
        quickActions.addArrangedSubview(selectAll)
        quickActions.addArrangedSubview(clear)
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        quickActions.addArrangedSubview(spacer)
        root.addArrangedSubview(quickActions)

        valuesStack.orientation = .vertical
        valuesStack.spacing = 4
        valuesStack.alignment = .leading
        valuesStack.autoresizingMask = [.width, .height]
        valueListContainer.addSubview(valuesStack)
        valueScrollView.hasVerticalScroller = true
        valueScrollView.drawsBackground = false
        valueScrollView.documentView = valueListContainer
        valueScrollView.heightAnchor.constraint(equalToConstant: 250).isActive = true
        root.addArrangedSubview(valueScrollView)
        rebuildValueList()
    }

    private func buildDateControls(in root: NSStackView) {
        configureDatePicker(startPicker)
        configureDatePicker(endPicker)

        if case .dateRange(_, let start, let end) = initialFilter {
            if let start {
                startEnabledButton.state = .on
                startPicker.dateValue = start
            }
            if let end {
                endEnabledButton.state = .on
                endPicker.dateValue = end
            }
        }

        root.addArrangedSubview(dateRow(label: startEnabledButton, picker: startPicker))
        root.addArrangedSubview(dateRow(label: endEnabledButton, picker: endPicker))
    }

    private func configureDatePicker(_ picker: NSDatePicker) {
        picker.datePickerStyle = .textFieldAndStepper
        picker.datePickerElements = [.yearMonthDay]
        picker.dateValue = Date()
        picker.target = self
        picker.action = #selector(datePickerChanged(_:))
        picker.sendAction(on: [.keyUp, .leftMouseUp])
    }

    private func dateRow(label: NSButton, picker: NSDatePicker) -> NSStackView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 8
        row.addArrangedSubview(label)
        row.addArrangedSubview(picker)
        picker.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return row
    }

    @objc private func searchChanged(_ sender: Any?) {
        rebuildValueList()
    }

    @objc private func datePickerChanged(_ sender: NSDatePicker) {
        if sender === startPicker {
            startEnabledButton.state = .on
        } else if sender === endPicker {
            endEnabledButton.state = .on
        }
    }

    private func rebuildValueList() {
        for arranged in valuesStack.arrangedSubviews {
            valuesStack.removeArrangedSubview(arranged)
            arranged.removeFromSuperview()
        }

        let term = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        for item in values where term.isEmpty || item.value.range(of: term, options: [.caseInsensitive, .diacriticInsensitive]) != nil {
            let title = item.value.isEmpty
                ? L.t("(Blank) \(item.count.formatted())", "(빈 값) \(item.count.formatted())")
                : "\(item.value) (\(item.count.formatted()))"
            let button = ValueCheckbox(checkboxWithTitle: title, target: self, action: #selector(valueCheckboxChanged(_:)))
            button.value = item.value
            button.state = item.value.isEmpty
                ? (includeBlanks ? .on : .off)
                : (selectedValues.contains(item.value) ? .on : .off)
            valuesStack.addArrangedSubview(button)
        }
        updateValueListDocumentFrame()
    }

    private func updateValueListDocumentFrame() {
        let rowHeight: CGFloat = 24
        let height = max(250, CGFloat(max(valuesStack.arrangedSubviews.count, 1)) * rowHeight + 8)
        let width = max(292, view.bounds.width - 28)
        valueListContainer.frame = NSRect(x: 0, y: 0, width: width, height: height)
        valuesStack.frame = valueListContainer.bounds.insetBy(dx: 0, dy: 4)
        valuesStack.needsLayout = true
        valuesStack.layoutSubtreeIfNeeded()
    }

    @objc private func valueCheckboxChanged(_ sender: NSButton) {
        guard let sender = sender as? ValueCheckbox else { return }
        let value = sender.value
        if value.isEmpty {
            includeBlanks = sender.state == .on
        } else if sender.state == .on {
            selectedValues.insert(value)
        } else {
            selectedValues.remove(value)
        }
    }

    @objc private func selectAllValues(_ sender: Any?) {
        selectedValues = Set(values.map(\.value).filter { !$0.isEmpty })
        includeBlanks = values.contains { $0.value.isEmpty }
        rebuildValueList()
    }

    @objc private func clearValues(_ sender: Any?) {
        selectedValues.removeAll()
        includeBlanks = false
        rebuildValueList()
    }

    @objc private func apply(_ sender: Any?) {
        if type == .date {
            let start = startEnabledButton.state == .on ? Self.startOfDay(startPicker.dateValue) : nil
            let end = endEnabledButton.state == .on ? Self.endOfDay(endPicker.dateValue) : nil
            onApply?((start == nil && end == nil) ? nil : .dateRange(column: column, start: start, end: end))
        } else {
            onApply?((selectedValues.isEmpty && !includeBlanks) ? nil : .selectedValues(column: column, values: selectedValues, includeBlanks: includeBlanks))
        }
        onClose?()
        dismiss(nil)
    }

    @objc private func cancel(_ sender: Any?) {
        onClose?()
        dismiss(nil)
    }

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private static func startOfDay(_ date: Date) -> Date {
        calendar.startOfDay(for: date)
    }

    private static func endOfDay(_ date: Date) -> Date {
        let start = calendar.startOfDay(for: date)
        return calendar.date(byAdding: DateComponents(day: 1, second: -1), to: start) ?? start
    }
}

private final class ValueCheckbox: NSButton {
    var value = ""
}

#if DEBUG
extension ColumnFilterPopoverController {
    var valueCheckboxTitlesForTesting: [String] {
        valuesStack.arrangedSubviews.compactMap { ($0 as? ValueCheckbox)?.title }
    }

    var valueListContentHeightForTesting: CGFloat {
        valueListContainer.frame.height
    }

    var startDateEnabledForTesting: Bool {
        startEnabledButton.state == .on
    }

    var endDateEnabledForTesting: Bool {
        endEnabledButton.state == .on
    }

    func setStartDateForTesting(_ date: Date) {
        startPicker.dateValue = date
        datePickerChanged(startPicker)
    }

    func setEndDateForTesting(_ date: Date) {
        endPicker.dateValue = date
        datePickerChanged(endPicker)
    }

    func applyForTesting() {
        apply(nil)
    }

    static func startOfDayForTesting(_ date: Date) -> Date {
        startOfDay(date)
    }
}
#endif
