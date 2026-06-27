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

    func testDropZoneStoresVisibleFieldNames() {
        let zone = PivotDropZoneView(zone: .rows) { _, _ in }

        zone.setFieldNames(["site", "visit"])

        XCTAssertEqual(zone.fieldNamesForTesting, ["site", "visit"])
    }

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
        try waitForPreview(builder)

        XCTAssertEqual(builder.layoutForTesting.rows, [0])
        XCTAssertEqual(builder.layoutForTesting.columns, [1])
        XCTAssertEqual(builder.layoutForTesting.value, 2)
        XCTAssertEqual(builder.previewHeadersForTesting, ["site", "Control", "Treatment"])
        XCTAssertEqual(builder.previewRowForTesting(0), ["A", "3", "7"])
        XCTAssertEqual(builder.previewRowForTesting(1), ["B", "2", "5"])
        XCTAssertEqual(builder.chartModelForTesting?.categories, ["A", "B"])
    }

    func testBuilderRemovesFieldsFromZones() throws {
        _ = NSApplication.shared
        let (doc, path) = try openIndexed("""
        site,arm,value
        A,Control,3
        A,Treatment,7

        """)
        defer { try? FileManager.default.removeItem(atPath: path) }
        let builder = PivotBuilderWindowController(document: doc, columnNames: doc.header)

        builder.assignFieldForTesting(0, to: .rows)
        builder.assignFieldForTesting(1, to: .columns)
        builder.assignFieldForTesting(2, to: .values)
        try waitForPreview(builder)
        builder.removeFieldForTesting(2, from: .values)

        XCTAssertNil(builder.layoutForTesting.value)
        XCTAssertEqual(builder.previewHeadersForTesting, [])
        XCTAssertNil(builder.chartModelForTesting)
    }

    func testBuilderSupportsValueOnlyPivot() throws {
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

        builder.assignFieldForTesting(2, to: .values)
        try waitForPreview(builder)

        XCTAssertEqual(builder.previewHeadersForTesting, [L.t("Metric", "지표"), "Count of value"])
        XCTAssertEqual(builder.previewRowForTesting(0), [L.t("Total", "합계"), "4"])
        XCTAssertEqual(builder.chartModelForTesting?.categories, [L.t("Total", "합계")])
    }

    func testBuilderDefaultsAggregationToCount() throws {
        _ = NSApplication.shared
        let (doc, path) = try openIndexed("""
        site,arm,value
        A,Control,3
        A,Treatment,7

        """)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let builder = PivotBuilderWindowController(document: doc, columnNames: doc.header)

        XCTAssertEqual(builder.layoutForTesting.function, .count)
    }

    func testBuilderSupportsRowsAndValuesWithoutColumns() throws {
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
        builder.assignFieldForTesting(2, to: .values)
        try waitForPreview(builder)

        XCTAssertEqual(builder.previewHeadersForTesting, ["site", "Count of value"])
        XCTAssertEqual(builder.previewRowForTesting(0), ["A", "2"])
        XCTAssertEqual(builder.previewRowForTesting(1), ["B", "2"])
        XCTAssertEqual(builder.chartModelForTesting?.categories, ["A", "B"])
    }

    func testBuilderSupportsColumnsAndValuesWithoutRows() throws {
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

        builder.assignFieldForTesting(1, to: .columns)
        builder.assignFieldForTesting(2, to: .values)
        try waitForPreview(builder)

        XCTAssertEqual(builder.previewHeadersForTesting, [L.t("Total", "합계"), "Control", "Treatment"])
        XCTAssertEqual(builder.previewRowForTesting(0), [L.t("Total", "합계"), "2", "2"])
        XCTAssertEqual(builder.chartModelForTesting?.categories, ["Control", "Treatment"])
    }

    func testBuilderFilterSelectionAffectsPreview() throws {
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
        builder.assignFieldForTesting(1, to: .filters)
        builder.assignFieldForTesting(2, to: .values)
        builder.setAggregationForTesting(.sum)
        builder.setFilterSelectionForTesting(column: 1, value: "Control")
        try waitForPreview(builder) {
            $0.previewRowForTesting(0) == ["A", "3"]
        }

        XCTAssertEqual(builder.previewHeadersForTesting, ["site", "Sum of value"])
        XCTAssertEqual(builder.previewRowForTesting(0), ["A", "3"])
        XCTAssertEqual(builder.previewRowForTesting(1), ["B", "2"])
    }

    func testBuilderGroupsDateRowsByMonthAndCanSwitchToYear() throws {
        _ = NSApplication.shared
        let (doc, path) = try openIndexed("""
        visit_date,value
        2026-01-02,3
        2026-01-20,7
        2026-02-01,2

        """)
        defer { try? FileManager.default.removeItem(atPath: path) }
        let statistics = try doc.analyzeColumns(sampleLimit: 5, cancellation: CancellationFlag())
        let builder = PivotBuilderWindowController(
            document: doc,
            columnNames: doc.header,
            columnStatisticsReport: statistics
        )

        builder.assignFieldForTesting(0, to: .rows)
        builder.assignFieldForTesting(1, to: .values)
        builder.setAggregationForTesting(.sum)
        try waitForPreview(builder) {
            $0.previewHeadersForTesting == ["visit_date (Month)", "Sum of value"]
        }

        XCTAssertEqual(builder.dateDimensionGroupingControlCountForTesting, 1)
        XCTAssertEqual(builder.previewHeadersForTesting, ["visit_date (Month)", "Sum of value"])
        XCTAssertEqual(builder.previewRowForTesting(0), ["2026-01", "10"])
        XCTAssertEqual(builder.previewRowForTesting(1), ["2026-02", "2"])

        builder.selectDateGroupingPopupForTesting(column: 0, period: .year)
        try waitForPreview(builder) {
            $0.previewHeadersForTesting == ["visit_date (Year)", "Sum of value"]
        }

        XCTAssertEqual(builder.previewHeadersForTesting, ["visit_date (Year)", "Sum of value"])
        XCTAssertEqual(builder.previewRowForTesting(0), ["2026", "12"])
    }

    func testBuilderGroupsDateColumnsByMonthAndCanSwitchToYear() throws {
        _ = NSApplication.shared
        let (doc, path) = try openIndexed("""
        visit_date,value
        2026-01-02,3
        2026-01-20,7
        2026-02-01,2

        """)
        defer { try? FileManager.default.removeItem(atPath: path) }
        let statistics = try doc.analyzeColumns(sampleLimit: 5, cancellation: CancellationFlag())
        let builder = PivotBuilderWindowController(
            document: doc,
            columnNames: doc.header,
            columnStatisticsReport: statistics
        )

        builder.assignFieldForTesting(0, to: .columns)
        builder.assignFieldForTesting(1, to: .values)
        builder.setAggregationForTesting(.sum)
        try waitForPreview(builder) {
            $0.previewHeadersForTesting == [L.t("Total", "합계"), "2026-01", "2026-02"]
        }

        XCTAssertEqual(builder.dateDimensionGroupingControlCountForTesting, 1)
        XCTAssertEqual(builder.previewRowForTesting(0), [L.t("Total", "합계"), "10", "2"])

        builder.selectDateGroupingPopupForTesting(column: 0, period: .year)
        try waitForPreview(builder) {
            $0.previewHeadersForTesting == [L.t("Total", "합계"), "2026"]
        }

        XCTAssertEqual(builder.previewRowForTesting(0), [L.t("Total", "합계"), "12"])
    }

    func testBuilderAppliesDateGroupedFilterSelection() throws {
        _ = NSApplication.shared
        let (doc, path) = try openIndexed("""
        visit_date,site,value
        2026-01-02,A,3
        2026-02-01,A,7
        2027-01-01,A,11

        """)
        defer { try? FileManager.default.removeItem(atPath: path) }
        let statistics = try doc.analyzeColumns(sampleLimit: 5, cancellation: CancellationFlag())
        let builder = PivotBuilderWindowController(
            document: doc,
            columnNames: doc.header,
            columnStatisticsReport: statistics
        )

        builder.assignFieldForTesting(1, to: .rows)
        builder.assignFieldForTesting(0, to: .filters)
        builder.assignFieldForTesting(2, to: .values)
        builder.setAggregationForTesting(.sum)
        builder.selectDateGroupingPopupForTesting(column: 0, period: .year)
        builder.setFilterSelectionForTesting(column: 0, value: "2026")
        try waitForPreview(builder) {
            $0.previewRowForTesting(0) == ["A", "10"]
        }

        XCTAssertEqual(builder.previewHeadersForTesting, ["site", "Sum of value"])
        XCTAssertEqual(builder.previewRowForTesting(0), ["A", "10"])
    }

    func testBuilderReservesMajorityOfWindowForPivotResults() throws {
        _ = NSApplication.shared
        let (doc, path) = try openIndexed("""
        site,arm,value
        A,Control,3
        A,Treatment,7

        """)
        defer { try? FileManager.default.removeItem(atPath: path) }
        let builder = PivotBuilderWindowController(document: doc, columnNames: doc.header)
        builder.showWindow(nil)
        defer { builder.close() }

        builder.layoutWindowForTesting()

        XCTAssertGreaterThanOrEqual(builder.resultPaneWidthForTesting, builder.windowContentWidthForTesting * 0.56)
        XCTAssertLessThan(builder.controlPaneWidthForTesting, builder.resultPaneWidthForTesting)
        XCTAssertGreaterThanOrEqual(builder.previewPaneHeightForTesting, builder.resultPaneHeightForTesting * 0.82)
    }

    func testBuilderShowsCsvColumnsInFieldList() throws {
        _ = NSApplication.shared
        let (doc, path) = try openIndexed("""
        site,arm,value
        A,Control,3
        A,Treatment,7

        """)
        defer { try? FileManager.default.removeItem(atPath: path) }
        let builder = PivotBuilderWindowController(document: doc, columnNames: doc.header)
        builder.showWindow(nil)
        defer { builder.close() }

        builder.layoutWindowForTesting()

        XCTAssertEqual(builder.fieldListRowCountForTesting, 3)
        XCTAssertGreaterThanOrEqual(builder.fieldListScrollWidthForTesting, 280)
        XCTAssertGreaterThanOrEqual(builder.fieldListTableWidthForTesting, 260)
        XCTAssertGreaterThanOrEqual(builder.fieldListScrollHeightForTesting, 160)
        XCTAssertLessThanOrEqual(builder.fieldListScrollHeightForTesting, 340)
        XCTAssertLessThanOrEqual(builder.fieldListScrollMinXForTesting, 24)
        XCTAssertLessThanOrEqual(builder.fieldListToLayoutGapForTesting, 40)
        XCTAssertGreaterThanOrEqual(builder.fieldListTableHeightForTesting, 84)
        XCTAssertGreaterThan(builder.fieldListVisibleRowsForTesting.length, 0)
        XCTAssertEqual(builder.fieldListVisibleTextForTesting(row: 0), "site")
        XCTAssertEqual(builder.fieldListVisibleTextForTesting(row: 1), "arm")
        XCTAssertEqual(builder.fieldListVisibleTextForTesting(row: 2), "value")
    }

    func testBuilderDisplaysFieldTypeTagsAndAutohidesFieldScroller() throws {
        _ = NSApplication.shared
        let (doc, path) = try openIndexed("""
        site,active,value
        A,true,3
        B,false,7

        """)
        defer { try? FileManager.default.removeItem(atPath: path) }
        let statistics = try doc.analyzeColumns(sampleLimit: 5, cancellation: CancellationFlag())
        let builder = PivotBuilderWindowController(
            document: doc,
            columnNames: doc.header,
            columnStatisticsReport: statistics
        )
        builder.showWindow(nil)
        defer { builder.close() }

        builder.layoutWindowForTesting()

        XCTAssertEqual(builder.fieldListVisibleTextForTesting(row: 0), "site")
        XCTAssertEqual(builder.fieldListTypeTextForTesting(row: 0), "Categorical")
        XCTAssertEqual(builder.fieldListTypeTextForTesting(row: 1), "Boolean")
        XCTAssertEqual(builder.fieldListTypeTextForTesting(row: 2), "Integer")
        XCTAssertTrue(builder.fieldListAutohidesScrollersForTesting)
    }

    func testBuilderDisplaysDateTypeTagForCommonCsvDateFormats() throws {
        _ = NSApplication.shared
        let (doc, path) = try openIndexed("""
        visit_date,value
        2026.01.02,3
        2026.01.03,7

        """)
        defer { try? FileManager.default.removeItem(atPath: path) }
        let statistics = try doc.analyzeColumns(sampleLimit: 5, cancellation: CancellationFlag())
        let builder = PivotBuilderWindowController(
            document: doc,
            columnNames: doc.header,
            columnStatisticsReport: statistics
        )
        builder.showWindow(nil)
        defer { builder.close() }

        builder.layoutWindowForTesting()

        XCTAssertEqual(builder.fieldListVisibleTextForTesting(row: 0), "visit_date")
        XCTAssertEqual(builder.fieldListTypeTextForTesting(row: 0), "Date")
    }

    func testBuilderSupportsSelectionBasedFieldAssignmentActions() throws {
        _ = NSApplication.shared
        let (doc, path) = try openIndexed("""
        site,arm,value
        A,Control,3
        A,Treatment,7

        """)
        defer { try? FileManager.default.removeItem(atPath: path) }
        let statistics = try doc.analyzeColumns(sampleLimit: 5, cancellation: CancellationFlag())
        let builder = PivotBuilderWindowController(
            document: doc,
            columnNames: doc.header,
            columnStatisticsReport: statistics
        )

        builder.selectFieldForTesting(row: 2)
        builder.addSelectedFieldToDefaultZoneForTesting()
        builder.selectFieldForTesting(row: 1)
        builder.addSelectedFieldForTesting(to: .columns)

        XCTAssertEqual(builder.layoutForTesting.value, 2)
        XCTAssertEqual(builder.layoutForTesting.columns, [1])
    }

    func testBuilderMovesAssignedFieldsBetweenZones() throws {
        _ = NSApplication.shared
        let (doc, path) = try openIndexed("""
        site,arm,value
        A,Control,3
        A,Treatment,7

        """)
        defer { try? FileManager.default.removeItem(atPath: path) }
        let builder = PivotBuilderWindowController(document: doc, columnNames: doc.header)

        builder.assignFieldForTesting(0, to: .rows)
        builder.assignFieldForTesting(1, to: .columns)
        builder.assignFieldForTesting(2, to: .values)
        builder.moveAssignedFieldForTesting(0, from: .rows, to: .filters, targetPosition: 0)
        builder.moveAssignedFieldForTesting(2, from: .values, to: .rows, targetPosition: 0)

        XCTAssertEqual(builder.layoutForTesting.rows, [2])
        XCTAssertEqual(builder.layoutForTesting.columns, [1])
        XCTAssertEqual(builder.layoutForTesting.filters, [0])
        XCTAssertNil(builder.layoutForTesting.value)
    }

    func testBuilderReordersAssignedDimensionFields() throws {
        _ = NSApplication.shared
        let (doc, path) = try openIndexed("""
        site,arm,visit,value
        A,Control,Day 1,3
        A,Treatment,Day 2,7

        """)
        defer { try? FileManager.default.removeItem(atPath: path) }
        let builder = PivotBuilderWindowController(document: doc, columnNames: doc.header)

        builder.assignFieldForTesting(0, to: .rows)
        builder.assignFieldForTesting(1, to: .rows)
        builder.assignFieldForTesting(2, to: .rows)
        builder.moveAssignedFieldForTesting(0, from: .rows, to: .rows, targetPosition: 3)
        builder.moveAssignedFieldForTesting(2, from: .rows, to: .rows, targetPosition: 0)

        XCTAssertEqual(builder.layoutForTesting.rows, [2, 1, 0])
    }

    func testBuilderSearchesFieldListAndAssignsVisibleMatches() throws {
        _ = NSApplication.shared
        let (doc, path) = try openIndexed("""
        site,arm,value
        A,Control,3
        A,Treatment,7

        """)
        defer { try? FileManager.default.removeItem(atPath: path) }
        let statistics = try doc.analyzeColumns(sampleLimit: 5, cancellation: CancellationFlag())
        let builder = PivotBuilderWindowController(
            document: doc,
            columnNames: doc.header,
            columnStatisticsReport: statistics
        )
        builder.showWindow(nil)
        defer { builder.close() }

        builder.setFieldSearchTextForTesting("val")
        builder.layoutWindowForTesting()
        builder.selectFieldForTesting(row: 0)
        builder.addSelectedFieldToDefaultZoneForTesting()

        XCTAssertEqual(builder.fieldListRowCountForTesting, 1)
        XCTAssertEqual(builder.fieldListVisibleTextForTesting(row: 0), "value")
        XCTAssertEqual(builder.layoutForTesting.value, 2)

        builder.setFieldSearchTextForTesting("")
        XCTAssertEqual(builder.fieldListRowCountForTesting, 3)
    }

    func testBuilderSeparatesDimensionsFromMeasuresInControlLayout() throws {
        _ = NSApplication.shared
        let (doc, path) = try openIndexed("""
        site,arm,value
        A,Control,3
        A,Treatment,7

        """)
        defer { try? FileManager.default.removeItem(atPath: path) }
        let builder = PivotBuilderWindowController(document: doc, columnNames: doc.header)

        XCTAssertEqual(builder.controlSectionTitlesForTesting, [
            L.t("Fields", "필드"),
            L.t("Dimensions", "차원"),
            L.t("Measures", "측정값")
        ])
        XCTAssertFalse(builder.isMeasureZoneForTesting(.rows))
        XCTAssertFalse(builder.isMeasureZoneForTesting(.columns))
        XCTAssertFalse(builder.isMeasureZoneForTesting(.filters))
        XCTAssertTrue(builder.isMeasureZoneForTesting(.values))
    }

    func testBuilderResultTableDoesNotStripeEmptyPreviewArea() throws {
        _ = NSApplication.shared
        let (doc, path) = try openIndexed("""
        site,arm,value
        A,Control,3
        A,Treatment,7

        """)
        defer { try? FileManager.default.removeItem(atPath: path) }
        let builder = PivotBuilderWindowController(document: doc, columnNames: doc.header)

        XCTAssertFalse(builder.pivotTableUsesAlternatingRowsForTesting)
    }

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

    private func openIndexed(_ content: String) throws -> (VirtualCsvDocument, String) {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let path = directory.appendingPathComponent("nanumcsv_pivot_\(UUID().uuidString).csv").path
        try content.data(using: .utf8)!.write(to: URL(fileURLWithPath: path))
        let doc = try VirtualCsvDocument.open(path: path)
        try doc.runIndexing(progress: { _ in }, cancellation: CancellationFlag())
        return (doc, path)
    }

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

    private func waitForPreview(
        _ builder: PivotBuilderWindowController,
        file: StaticString = #filePath,
        line: UInt = #line,
        until condition: ((PivotBuilderWindowController) -> Bool)? = nil
    ) throws {
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
            if !builder.previewHeadersForTesting.isEmpty, condition?(builder) ?? true {
                return
            }
        }
        XCTFail("Timed out waiting for pivot preview", file: file, line: line)
    }
}
