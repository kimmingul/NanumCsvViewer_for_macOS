# Pivot Builder Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the current opaque text-only Pivot Table action with a separate Excel-like Pivot Builder window that supports drag-and-drop fields, a grid preview, and a basic chart preview.

**Architecture:** Keep existing pivot aggregation in `CsvCore` and add focused AppKit UI files in `NanumCsvViewerMac`. A new window controller owns layout state, recomputes `PivotTableResult` from the current filtered `VirtualCsvDocument`, feeds an `NSTableView` preview, and projects simple pivot shapes into a custom bar chart view.

**Tech Stack:** Swift 6.3 package, Swift language mode 5, macOS 14 AppKit, existing `CsvCore`, XCTest. No new dependencies.

## Global Constraints

- The Pivot Builder is a separate native AppKit window.
- Drag-and-drop field list is included in the initial implementation.
- The feature remains entirely non-AI.
- Compute pivots from the current filtered view.
- Reuse existing `CsvCore` pivot calculation and export behavior where possible.
- First version supports one value field and one aggregation function at a time.
- Chart preview must be a real chart view, not a text summary.

---

## File Structure

- Create `NanumCsvViewerMac/Sources/NanumCsvViewerMac/PivotBuilderModel.swift`
  - Owns UI-only pivot fields, layout state, pasteboard type, and chart projection structs.
- Create `NanumCsvViewerMac/Sources/NanumCsvViewerMac/PivotDropZoneView.swift`
  - Native AppKit drag destination for `Rows`, `Columns`, `Values`, and `Filters`.
- Create `NanumCsvViewerMac/Sources/NanumCsvViewerMac/PivotChartView.swift`
  - Custom AppKit chart renderer for simple one-row-dimension pivot results.
- Create `NanumCsvViewerMac/Sources/NanumCsvViewerMac/PivotBuilderWindowController.swift`
  - Separate window, field list source, drag source, drop zones, aggregation popup, table preview, chart preview, and recompute orchestration.
- Modify `NanumCsvViewerMac/Sources/NanumCsvViewerMac/MainWindowController.swift`
  - Replace the current text-only `showPivotTable` behavior with window creation.
  - Retain `formatPivotTable` only if still used by tests or remove it if no longer referenced.
- Add `NanumCsvViewerMac/Tests/NanumCsvViewerMacTests/PivotBuilderTests.swift`
  - Regression coverage for layout assignment, recompute, preview headers/cells, and chart model projection.

---

### Task 1: Add Pivot Builder State And Chart Projection Types

**Files:**
- Create: `NanumCsvViewerMac/Sources/NanumCsvViewerMac/PivotBuilderModel.swift`
- Test: `NanumCsvViewerMac/Tests/NanumCsvViewerMacTests/PivotBuilderTests.swift`

**Interfaces:**
- Consumes: `CsvCore.AggregationFunction`, `CsvCore.PivotTableResult`
- Produces:
  - `struct PivotField: Equatable`
  - `enum PivotDropZone: String, CaseIterable`
  - `struct PivotBuilderLayout: Equatable`
  - `struct PivotChartSeries: Equatable`
  - `struct PivotChartModel: Equatable`
  - `extension NSPasteboard.PasteboardType.pivotFieldIndex`

- [ ] **Step 1: Write the failing chart projection test**

```swift
import AppKit
import XCTest
@testable import CsvCore
@testable import NanumCsvViewerMac

@MainActor
final class PivotBuilderTests: XCTestCase {
    func testChartModelProjectsSimplePivotIntoSeries() {
        let pivot = PivotTableResult(
            rowColumns: [0],
            rowColumnNames: ["site"],
            columnColumns: [1],
            valueColumn: 2,
            function: .sum,
            rowKeys: [["A"], ["B"]],
            columnKeys: [["Control"], ["Treatment"]],
            values: [
                PivotCellKey(row: ["A"], column: ["Control"]): 3,
                PivotCellKey(row: ["A"], column: ["Treatment"]): 7,
                PivotCellKey(row: ["B"], column: ["Control"]): 2,
                PivotCellKey(row: ["B"], column: ["Treatment"]): 5
            ]
        )

        let model = PivotChartModel.make(from: pivot)

        XCTAssertEqual(model.categories, ["A", "B"])
        XCTAssertEqual(model.series.map(\.name), ["Control", "Treatment"])
        XCTAssertEqual(model.series[0].values, [3, 2])
        XCTAssertEqual(model.series[1].values, [7, 5])
        XCTAssertNil(model.unsupportedReason)
    }
}
```

- [ ] **Step 2: Run the new test to verify it fails**

Run: `env CLANG_MODULE_CACHE_PATH=/Users/min/Projects/nanum-csv-viewer/.clang-cache swift test --filter PivotBuilderTests/testChartModelProjectsSimplePivotIntoSeries`

Expected: FAIL because `PivotChartModel` is not defined.

- [ ] **Step 3: Add the model implementation**

```swift
import AppKit
@preconcurrency import CsvCore

struct PivotField: Equatable {
    let index: Int
    let name: String
    let typeHint: String?

    var displayName: String {
        typeHint.map { "\(name)  \($0)" } ?? name
    }
}

enum PivotDropZone: String, CaseIterable {
    case rows
    case columns
    case values
    case filters

    var title: String {
        switch self {
        case .rows: return L.t("Rows", "행")
        case .columns: return L.t("Columns", "열")
        case .values: return L.t("Values", "값")
        case .filters: return L.t("Filters", "필터")
        }
    }
}

struct PivotBuilderLayout: Equatable {
    var rows: [Int] = []
    var columns: [Int] = []
    var value: Int?
    var filters: [Int] = []
    var function: AggregationFunction = .sum

    var isRunnable: Bool {
        !rows.isEmpty && !columns.isEmpty && value != nil
    }
}

struct PivotChartSeries: Equatable {
    let name: String
    let values: [Double]
}

struct PivotChartModel: Equatable {
    let categories: [String]
    let series: [PivotChartSeries]
    let unsupportedReason: String?

    static func make(from pivot: PivotTableResult) -> PivotChartModel {
        guard pivot.rowColumns.count == 1 else {
            return PivotChartModel(
                categories: [],
                series: [],
                unsupportedReason: L.t("Charts currently support one row field.", "차트는 현재 하나의 행 필드만 지원합니다.")
            )
        }

        let categories = pivot.rowKeys.map { $0.joined(separator: " | ") }
        let series = pivot.columnKeys.map { columnKey in
            PivotChartSeries(
                name: columnKey.joined(separator: " | "),
                values: pivot.rowKeys.map { rowKey in
                    pivot.value(row: rowKey, column: columnKey)
                }
            )
        }
        return PivotChartModel(categories: categories, series: series, unsupportedReason: nil)
    }
}

extension NSPasteboard.PasteboardType {
    static let pivotFieldIndex = NSPasteboard.PasteboardType("com.nanum.csvviewer.pivot-field-index")
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `env CLANG_MODULE_CACHE_PATH=/Users/min/Projects/nanum-csv-viewer/.clang-cache swift test --filter PivotBuilderTests/testChartModelProjectsSimplePivotIntoSeries`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add NanumCsvViewerMac/Sources/NanumCsvViewerMac/PivotBuilderModel.swift NanumCsvViewerMac/Tests/NanumCsvViewerMacTests/PivotBuilderTests.swift
git commit -m "feat: add pivot builder model"
```

---

### Task 2: Add Native Pivot Drop Zones

**Files:**
- Create: `NanumCsvViewerMac/Sources/NanumCsvViewerMac/PivotDropZoneView.swift`
- Test: `NanumCsvViewerMac/Tests/NanumCsvViewerMacTests/PivotBuilderTests.swift`

**Interfaces:**
- Consumes: `PivotDropZone`, `.pivotFieldIndex`
- Produces: `final class PivotDropZoneView: NSView`
  - `init(zone: PivotDropZone, onDrop: @escaping (Int, PivotDropZone) -> Void)`
  - `func setFieldNames(_ names: [String])`
  - `var fieldNamesForTesting: [String]`

- [ ] **Step 1: Write the failing drop zone test**

```swift
func testDropZoneStoresVisibleFieldNames() {
    let zone = PivotDropZoneView(zone: .rows) { _, _ in }

    zone.setFieldNames(["site", "visit"])

    XCTAssertEqual(zone.fieldNamesForTesting, ["site", "visit"])
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `env CLANG_MODULE_CACHE_PATH=/Users/min/Projects/nanum-csv-viewer/.clang-cache swift test --filter PivotBuilderTests/testDropZoneStoresVisibleFieldNames`

Expected: FAIL because `PivotDropZoneView` is not defined.

- [ ] **Step 3: Implement the drop zone view**

```swift
import AppKit

@MainActor
final class PivotDropZoneView: NSView {
    private let zone: PivotDropZone
    private let onDrop: (Int, PivotDropZone) -> Void
    private let titleLabel = NSTextField(labelWithString: "")
    private let stack = NSStackView()
    private var names: [String] = []

    init(zone: PivotDropZone, onDrop: @escaping (Int, PivotDropZone) -> Void) {
        self.zone = zone
        self.onDrop = onDrop
        super.init(frame: .zero)
        configure()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var fieldNamesForTesting: [String] { names }

    func setFieldNames(_ names: [String]) {
        self.names = names
        stack.arrangedSubviews.forEach { view in
            stack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        for name in names {
            let label = NSTextField(labelWithString: name)
            label.font = .systemFont(ofSize: 12)
            label.lineBreakMode = .byTruncatingTail
            stack.addArrangedSubview(label)
        }
        if names.isEmpty {
            let empty = NSTextField(labelWithString: L.t("Drop fields here", "여기에 필드 놓기"))
            empty.font = .systemFont(ofSize: 12)
            empty.textColor = .secondaryLabelColor
            stack.addArrangedSubview(empty)
        }
    }

    private func configure() {
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor
        registerForDraggedTypes([.pivotFieldIndex])

        titleLabel.stringValue = zone.title
        titleLabel.font = .systemFont(ofSize: 12, weight: .semibold)

        let root = NSStackView(views: [titleLabel, stack])
        root.orientation = .vertical
        root.spacing = 6
        root.edgeInsets = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        root.translatesAutoresizingMaskIntoConstraints = false
        addSubview(root)

        stack.orientation = .vertical
        stack.spacing = 4
        setFieldNames([])

        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: leadingAnchor),
            root.trailingAnchor.constraint(equalTo: trailingAnchor),
            root.topAnchor.constraint(equalTo: topAnchor),
            root.bottomAnchor.constraint(equalTo: bottomAnchor),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 92)
        ])
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        sender.draggingPasteboard.string(forType: .pivotFieldIndex) == nil ? [] : .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let raw = sender.draggingPasteboard.string(forType: .pivotFieldIndex),
              let index = Int(raw) else { return false }
        onDrop(index, zone)
        return true
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `env CLANG_MODULE_CACHE_PATH=/Users/min/Projects/nanum-csv-viewer/.clang-cache swift test --filter PivotBuilderTests/testDropZoneStoresVisibleFieldNames`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add NanumCsvViewerMac/Sources/NanumCsvViewerMac/PivotDropZoneView.swift NanumCsvViewerMac/Tests/NanumCsvViewerMacTests/PivotBuilderTests.swift
git commit -m "feat: add pivot drop zones"
```

---

### Task 3: Add Pivot Chart Rendering View

**Files:**
- Create: `NanumCsvViewerMac/Sources/NanumCsvViewerMac/PivotChartView.swift`
- Test: `NanumCsvViewerMac/Tests/NanumCsvViewerMacTests/PivotBuilderTests.swift`

**Interfaces:**
- Consumes: `PivotChartModel`
- Produces: `final class PivotChartView: NSView`
  - `func update(model: PivotChartModel?)`
  - `var modelForTesting: PivotChartModel?`

- [ ] **Step 1: Write the failing chart view test**

```swift
func testChartViewStoresModelForRendering() {
    let chart = PivotChartView()
    let model = PivotChartModel(
        categories: ["A"],
        series: [PivotChartSeries(name: "Treatment", values: [4])],
        unsupportedReason: nil
    )

    chart.update(model: model)

    XCTAssertEqual(chart.modelForTesting, model)
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `env CLANG_MODULE_CACHE_PATH=/Users/min/Projects/nanum-csv-viewer/.clang-cache swift test --filter PivotBuilderTests/testChartViewStoresModelForRendering`

Expected: FAIL because `PivotChartView` is not defined.

- [ ] **Step 3: Implement the chart view**

```swift
import AppKit

@MainActor
final class PivotChartView: NSView {
    private var model: PivotChartModel?

    var modelForTesting: PivotChartModel? { model }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(model: PivotChartModel?) {
        self.model = model
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let model else {
            drawCentered(L.t("Configure rows, columns, and values to preview a chart.", "행, 열, 값을 설정하면 차트를 미리 볼 수 있습니다."))
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
        text.draw(at: NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2), withAttributes: attributes)
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
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `env CLANG_MODULE_CACHE_PATH=/Users/min/Projects/nanum-csv-viewer/.clang-cache swift test --filter PivotBuilderTests/testChartViewStoresModelForRendering`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add NanumCsvViewerMac/Sources/NanumCsvViewerMac/PivotChartView.swift NanumCsvViewerMac/Tests/NanumCsvViewerMacTests/PivotBuilderTests.swift
git commit -m "feat: add pivot chart view"
```

---

### Task 4: Add Pivot Builder Window Controller

**Files:**
- Create: `NanumCsvViewerMac/Sources/NanumCsvViewerMac/PivotBuilderWindowController.swift`
- Test: `NanumCsvViewerMac/Tests/NanumCsvViewerMacTests/PivotBuilderTests.swift`

**Interfaces:**
- Consumes: `VirtualCsvDocument`, `PivotBuilderLayout`, `PivotDropZoneView`, `PivotChartView`
- Produces: `final class PivotBuilderWindowController: NSWindowController`
  - `init(document: VirtualCsvDocument, columnNames: [String])`
  - `func assignFieldForTesting(_ index: Int, to zone: PivotDropZone)`
  - `func setAggregationForTesting(_ function: AggregationFunction)`
  - `var layoutForTesting: PivotBuilderLayout`
  - `var previewHeadersForTesting: [String]`
  - `func previewRowForTesting(_ row: Int) -> [String]`
  - `var chartModelForTesting: PivotChartModel?`

- [ ] **Step 1: Write the failing builder recompute test**

```swift
func testBuilderAssignsFieldsAndBuildsPreview() throws {
    _ = NSApplication.shared
    let (doc, path) = try openIndexed("""
    site,arm,value
    A,Control,3
    A,Treatment,7
    B,Control,2
    B,Treatment,5

    """)
    defer { try? FileManager.default.removeItem(atPath: path) }
    let builder = PivotBuilderWindowController(document: doc, columnNames: doc.header)

    builder.assignFieldForTesting(0, to: .rows)
    builder.assignFieldForTesting(1, to: .columns)
    builder.assignFieldForTesting(2, to: .values)
    builder.setAggregationForTesting(.sum)

    XCTAssertEqual(builder.layoutForTesting.rows, [0])
    XCTAssertEqual(builder.layoutForTesting.columns, [1])
    XCTAssertEqual(builder.layoutForTesting.value, 2)
    XCTAssertEqual(builder.previewHeadersForTesting, ["site", "Control", "Treatment"])
    XCTAssertEqual(builder.previewRowForTesting(0), ["A", "3", "7"])
    XCTAssertEqual(builder.previewRowForTesting(1), ["B", "2", "5"])
    XCTAssertEqual(builder.chartModelForTesting?.categories, ["A", "B"])
}
```

Add this helper to `PivotBuilderTests`:

```swift
private func openIndexed(_ content: String) throws -> (VirtualCsvDocument, String) {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
    let path = directory.appendingPathComponent("nanumcsv_pivot_\(UUID().uuidString).csv").path
    try content.data(using: .utf8)!.write(to: URL(fileURLWithPath: path))
    let doc = try VirtualCsvDocument.open(path: path)
    try doc.runIndexing(progress: { _ in }, cancellation: CancellationFlag())
    return (doc, path)
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `env CLANG_MODULE_CACHE_PATH=/Users/min/Projects/nanum-csv-viewer/.clang-cache swift test --filter PivotBuilderTests/testBuilderAssignsFieldsAndBuildsPreview`

Expected: FAIL because `PivotBuilderWindowController` is not defined.

- [ ] **Step 3: Implement the builder window**

Create a native AppKit controller with these concrete implementation points:

```swift
import AppKit
@preconcurrency import CsvCore

@MainActor
final class PivotBuilderWindowController: NSWindowController {
    private let document: VirtualCsvDocument
    private let fields: [PivotField]
    private var layout = PivotBuilderLayout()
    private var pivot: PivotTableResult?
    private var previewRows: [[String]] = []
    private var previewHeaders: [String] = []

    private let fieldTable = NSTableView()
    private let tablePreview = NSTableView()
    private let tableScroll = NSScrollView()
    private let chartView = PivotChartView()
    private let aggregationPopup = NSPopUpButton()
    private var zoneViews: [PivotDropZone: PivotDropZoneView] = [:]

    init(document: VirtualCsvDocument, columnNames: [String]) {
        self.document = document
        self.fields = columnNames.enumerated().map { index, name in
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
}
```

The controller must:

- Configure `fieldTable` as an `NSTableViewDataSource`, `NSTableViewDelegate`, and dragging source.
- Write the dragged field index with `.pivotFieldIndex`.
- Build four `PivotDropZoneView` instances and call `assignField(_:to:)` from their drop handlers.
- Build `aggregationPopup` from `AggregationFunction.allCases`.
- Recompute by calling:

```swift
let result = try document.pivotTable(
    rowColumns: layout.rows,
    columnColumns: layout.columns,
    valueColumn: value,
    function: layout.function,
    cancellation: CancellationFlag()
)
```

- Convert preview output with:

```swift
previewHeaders = [layout.rows.map { fields[$0].name }.joined(separator: " | ")] + result.columnKeys.map { $0.joined(separator: " | ") }
previewRows = result.rowKeys.map { rowKey in
    [rowKey.joined(separator: " | ")] + result.columnKeys.map { MainWindowController.formatPivotNumberForSharedUse(result.value(row: rowKey, column: $0)) }
}
```

- Rebuild `tablePreview` columns after every recompute.
- Update `chartView` with `PivotChartModel.make(from: result)`.
- Expose the testing methods and properties listed in the interface block.

- [ ] **Step 4: Run the builder test to verify it passes**

Run: `env CLANG_MODULE_CACHE_PATH=/Users/min/Projects/nanum-csv-viewer/.clang-cache swift test --filter PivotBuilderTests/testBuilderAssignsFieldsAndBuildsPreview`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add NanumCsvViewerMac/Sources/NanumCsvViewerMac/PivotBuilderWindowController.swift NanumCsvViewerMac/Tests/NanumCsvViewerMacTests/PivotBuilderTests.swift
git commit -m "feat: add pivot builder window"
```

---

### Task 5: Wire Analysis Menu To Pivot Builder

**Files:**
- Modify: `NanumCsvViewerMac/Sources/NanumCsvViewerMac/MainWindowController.swift`
- Test: `NanumCsvViewerMac/Tests/NanumCsvViewerMacTests/PivotBuilderTests.swift`

**Interfaces:**
- Consumes: `PivotBuilderWindowController`
- Produces:
  - `private var pivotBuilderWindow: PivotBuilderWindowController?`
  - `func makePivotBuilderForTesting() -> PivotBuilderWindowController?`
  - `static func formatPivotNumberForSharedUse(_ value: Double) -> String`

- [ ] **Step 1: Write the failing integration test**

```swift
func testMainWindowCreatesPivotBuilderForIndexedDocument() throws {
    _ = NSApplication.shared
    let path = try temporaryCsvPath("""
    site,arm,value
    A,Control,3
    A,Treatment,7

    """)
    defer { try? FileManager.default.removeItem(atPath: path) }
    let controller = MainWindowController()
    controller.showWindow(nil)
    defer { controller.close() }

    controller.openFileForTesting(URL(fileURLWithPath: path))
    try waitUntilIndexed(controller)

    let builder = controller.makePivotBuilderForTesting()

    XCTAssertNotNil(builder)
}
```

Add helper functions:

```swift
private func temporaryCsvPath(_ content: String) throws -> String {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
    let path = directory.appendingPathComponent("nanumcsv_pivot_main_\(UUID().uuidString).csv").path
    try content.data(using: .utf8)!.write(to: URL(fileURLWithPath: path))
    return path
}

private func waitUntilIndexed(_ controller: MainWindowController, file: StaticString = #filePath, line: UInt = #line) throws {
    let deadline = Date().addingTimeInterval(5)
    while Date() < deadline {
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        if controller.indexingCompleteForTesting {
            return
        }
    }
    XCTFail("Timed out waiting for indexing", file: file, line: line)
}
```

- [ ] **Step 2: Run the integration test to verify it fails**

Run: `env CLANG_MODULE_CACHE_PATH=/Users/min/Projects/nanum-csv-viewer/.clang-cache swift test --filter PivotBuilderTests/testMainWindowCreatesPivotBuilderForIndexedDocument`

Expected: FAIL because `makePivotBuilderForTesting` is not defined.

- [ ] **Step 3: Modify `MainWindowController`**

Add a retained window property near the other controller state:

```swift
private var pivotBuilderWindow: PivotBuilderWindowController?
```

Replace `showPivotTable(_:)` with:

```swift
@objc func showPivotTable(_ sender: Any?) {
    guard let builder = makePivotBuilder() else { return }
    pivotBuilderWindow = builder
    builder.showWindow(sender)
    builder.window?.makeKeyAndOrderFront(sender)
}

private func makePivotBuilder() -> PivotBuilderWindowController? {
    guard let doc = csvDocument, doc.indexingComplete, !busy, columnNames.count >= 2 else { return nil }
    return PivotBuilderWindowController(document: doc, columnNames: columnNames)
}
```

Add the shared formatter:

```swift
static func formatPivotNumberForSharedUse(_ value: Double) -> String {
    if value.rounded(.towardZero) == value {
        return String(format: "%.0f", value)
    }
    return String(format: "%.3f", value)
}
```

Update `formatNumber(_:)` to call the shared formatter if needed.

Expose this under `#if DEBUG`:

```swift
func makePivotBuilderForTesting() -> PivotBuilderWindowController? {
    makePivotBuilder()
}
```

- [ ] **Step 4: Run the integration test to verify it passes**

Run: `env CLANG_MODULE_CACHE_PATH=/Users/min/Projects/nanum-csv-viewer/.clang-cache swift test --filter PivotBuilderTests/testMainWindowCreatesPivotBuilderForIndexedDocument`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add NanumCsvViewerMac/Sources/NanumCsvViewerMac/MainWindowController.swift NanumCsvViewerMac/Tests/NanumCsvViewerMacTests/PivotBuilderTests.swift
git commit -m "feat: open pivot builder from analysis menu"
```

---

### Task 6: Full Verification And Documentation

**Files:**
- Modify: `README.md`
- Modify: `RELEASE_NOTES.md`

**Interfaces:**
- Consumes: completed Pivot Builder behavior.
- Produces: user-facing documentation for the new pivot workflow.

- [ ] **Step 1: Update docs**

Add a release-note bullet:

```markdown
- Replaced the text-only Pivot Table analysis action with a separate drag-and-drop Pivot Builder window, including table and chart previews.
```

Update README analytics wording from text-summary pivot tables to interactive Pivot Builder wording.

- [ ] **Step 2: Run targeted tests**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=/Users/min/Projects/nanum-csv-viewer/.clang-cache swift test --filter PivotBuilderTests
```

Expected: all `PivotBuilderTests` pass.

- [ ] **Step 3: Run full test suite**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=/Users/min/Projects/nanum-csv-viewer/.clang-cache swift test
```

Expected: all tests pass.

- [ ] **Step 4: Inspect git status**

Run:

```bash
git status --short
```

Expected: only intentional code/docs changes are present before final commit.

- [ ] **Step 5: Commit**

```bash
git add README.md RELEASE_NOTES.md
git commit -m "docs: document pivot builder"
```

---

## Self-Review

- Spec coverage: separate window, drag-and-drop field list, table preview, chart preview, current filtered view, non-AI scope, and testing are each mapped to tasks.
- Placeholder scan: no `TBD`, `TODO`, or unspecified implementation steps are intentionally left.
- Type consistency: `PivotField`, `PivotDropZone`, `PivotBuilderLayout`, `PivotChartModel`, `PivotDropZoneView`, `PivotChartView`, and `PivotBuilderWindowController` are introduced before use.
