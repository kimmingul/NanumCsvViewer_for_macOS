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

    func testChartModelBuildsPointEncodingForSwiftCharts() {
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

        XCTAssertEqual(model.recommendedKind, .groupedBar)
        XCTAssertEqual(model.xAxisTitle, "site")
        XCTAssertEqual(model.seriesTitle, L.t("Columns", "열"))
        XCTAssertEqual(model.valueTitle, "Sum")
        XCTAssertEqual(model.points, [
            PivotChartPoint(category: "A", series: "Control", value: 3),
            PivotChartPoint(category: "A", series: "Treatment", value: 7),
            PivotChartPoint(category: "B", series: "Control", value: 2),
            PivotChartPoint(category: "B", series: "Treatment", value: 5)
        ])
    }

    func testChartModelSupportsMultipleRowDimensionsForSwiftCharts() {
        let pivot = PivotTableResult(
            rowColumns: [0, 1],
            rowColumnNames: ["year", "month"],
            columnColumns: [],
            valueColumn: 2,
            function: .count,
            rowKeys: [["2026", "01"], ["2026", "02"]],
            columnKeys: [],
            values: [
                PivotCellKey(row: ["2026", "01"], column: []): 3,
                PivotCellKey(row: ["2026", "02"], column: []): 7
            ]
        )

        let model = PivotChartModel.make(from: pivot)

        XCTAssertNil(model.unsupportedReason)
        XCTAssertEqual(model.recommendedKind, .bar)
        XCTAssertEqual(model.xAxisTitle, "year | month")
        XCTAssertEqual(model.categories, ["2026 | 01", "2026 | 02"])
        XCTAssertEqual(model.points, [
            PivotChartPoint(category: "2026 | 01", series: "Count", value: 3),
            PivotChartPoint(category: "2026 | 02", series: "Count", value: 7)
        ])
    }

    func testChartModelRecommendsLineForDateGroupedCategories() {
        let pivot = PivotTableResult(
            rowColumns: [0],
            rowColumnNames: ["birth_date (\(L.t("Month", "월")))" ],
            columnColumns: [],
            valueColumn: 1,
            function: .count,
            rowKeys: [["2026-01"], ["2026-02"]],
            columnKeys: [],
            values: [
                PivotCellKey(row: ["2026-01"], column: []): 3,
                PivotCellKey(row: ["2026-02"], column: []): 7
            ]
        )

        let model = PivotChartModel.make(from: pivot)

        XCTAssertEqual(model.recommendedKind, .line)
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
        XCTAssertTrue(chart.usesSwiftChartsSurfaceForTesting)
    }

    func testChartHoverTooltipUsesChartCoordinatesAndDoesNotStealHover() throws {
        let source = try String(contentsOfFile: "Sources/NanumCsvViewerMac/PivotChartView.swift")

        XCTAssertTrue(source.contains(".chartOverlay"))
        XCTAssertTrue(source.contains(".allowsHitTesting(false)"))
        XCTAssertTrue(source.contains("proxy.position(forY: tooltipValue"))
        XCTAssertTrue(source.contains(".fixedSize(horizontal: true, vertical: true)"))
        XCTAssertTrue(source.contains("Color(nsColor: .controlBackgroundColor)"))
        XCTAssertFalse(source.contains(".background(.regularMaterial"))
        XCTAssertFalse(source.contains("ZStack(alignment: .topTrailing)"))
        XCTAssertFalse(source.contains("y: plotFrame.minY + 46"))
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
        XCTAssertEqual(builder.previewHeadersForTesting, ["site", "Control", "Treatment", L.t("Total", "합계")])
        XCTAssertEqual(builder.previewRowForTesting(0), ["A", "3", "7", "10"])
        XCTAssertEqual(builder.previewRowForTesting(1), ["B", "2", "5", "7"])
        XCTAssertEqual(builder.previewRowForTesting(2), [L.t("Total", "합계"), "5", "12", "17"])
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

        XCTAssertEqual(builder.previewHeadersForTesting, ["site", "Count"])
        XCTAssertEqual(builder.previewRowForTesting(0), ["A", "2"])
        XCTAssertEqual(builder.previewRowForTesting(1), ["B", "2"])
        XCTAssertEqual(builder.previewRowForTesting(2), [L.t("Total", "합계"), "4"])
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

        XCTAssertEqual(builder.previewHeadersForTesting, ["", "Control", "Treatment", L.t("Total", "합계")])
        XCTAssertEqual(builder.previewRowForTesting(0), ["Count", "2", "2", "4"])
        XCTAssertEqual(builder.chartModelForTesting?.categories, ["Control", "Treatment"])
    }

    func testBuilderSupportsMultipleMeasuresWithIndependentAggregations() throws {
        _ = NSApplication.shared
        let (doc, path) = try openIndexed("""
        site,visits,cost
        A,1,3
        A,2,7
        B,3,11

        """)
        defer { try? FileManager.default.removeItem(atPath: path) }
        let builder = PivotBuilderWindowController(document: doc, columnNames: doc.header)

        builder.assignFieldForTesting(0, to: .rows)
        builder.assignFieldForTesting(1, to: .values)
        builder.assignFieldForTesting(2, to: .values)
        builder.setMeasureAggregationForTesting(column: 1, function: .count)
        builder.setMeasureAggregationForTesting(column: 2, function: .sum)
        try waitForPreview(builder) {
            $0.previewSectionCountForTesting == 2
                && $0.previewRowForTesting(section: 1, row: 0) == ["A", "10"]
        }

        XCTAssertEqual(builder.layoutForTesting.measures, [
            PivotMeasure(fieldIndex: 1, function: .count),
            PivotMeasure(fieldIndex: 2, function: .sum)
        ])
        XCTAssertEqual(builder.measureAggregationControlCountForTesting, 2)
        XCTAssertEqual(builder.previewSectionTitlesForTesting, ["Count of visits", "Sum of cost"])
        XCTAssertEqual(builder.previewHeadersForTesting(section: 0), ["site", "Count"])
        XCTAssertEqual(builder.previewRowForTesting(section: 0, row: 0), ["A", "2"])
        XCTAssertEqual(builder.previewRowForTesting(section: 0, row: 1), ["B", "1"])
        XCTAssertEqual(builder.previewRowForTesting(section: 0, row: 2), [L.t("Total", "합계"), "3"])
        XCTAssertEqual(builder.previewHeadersForTesting(section: 1), ["site", "Sum"])
        XCTAssertEqual(builder.previewRowForTesting(section: 1, row: 0), ["A", "10"])
        XCTAssertEqual(builder.previewRowForTesting(section: 1, row: 1), ["B", "11"])
        XCTAssertEqual(builder.previewRowForTesting(section: 1, row: 2), [L.t("Total", "합계"), "21"])
    }

    func testBuilderPacksMultipleMeasureResultSectionsNearTop() throws {
        _ = NSApplication.shared
        let (doc, path) = try openIndexed("""
        id,sex,age,score
        A,F,10,3
        B,M,20,7
        C,F,30,11
        D,M,40,13

        """)
        defer { try? FileManager.default.removeItem(atPath: path) }
        let builder = PivotBuilderWindowController(document: doc, columnNames: doc.header)
        builder.showWindow(nil)
        defer { builder.close() }

        builder.assignFieldForTesting(1, to: .columns)
        builder.assignFieldForTesting(0, to: .values)
        builder.assignFieldForTesting(2, to: .values)
        builder.setMeasureAggregationForTesting(column: 2, function: .sum)
        try waitForPreview(builder) {
            $0.previewSectionCountForTesting == 2
        }
        builder.layoutWindowForTesting()

        XCTAssertGreaterThanOrEqual(builder.previewTableSectionGapForTesting, 36)
        XCTAssertLessThanOrEqual(builder.previewTableSectionGapForTesting, 64)
        XCTAssertLessThanOrEqual(builder.previewTableFirstSectionCenterDeltaForTesting, 2)
        XCTAssertLessThan(builder.previewTableDocumentHeightForTesting, builder.previewPaneHeightForTesting * 0.5)
    }

    func testBuilderSizesChartSectionsToResultPaneWidth() throws {
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
        builder.showWindow(nil)
        defer { builder.close() }

        builder.assignFieldForTesting(0, to: .rows)
        builder.assignFieldForTesting(1, to: .columns)
        builder.assignFieldForTesting(2, to: .values)
        try waitForPreview(builder)
        builder.layoutWindowForTesting()

        XCTAssertGreaterThanOrEqual(
            builder.previewChartFirstSectionWidthForTesting,
            builder.resultPaneWidthForTesting * 0.85
        )
        XCTAssertGreaterThanOrEqual(builder.previewChartFirstSectionHeightForTesting, 300)
    }

    func testBuilderSizesChartViewToMostOfResultPaneWidth() throws {
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
        builder.showWindow(nil)
        defer { builder.close() }

        builder.assignFieldForTesting(0, to: .rows)
        builder.assignFieldForTesting(1, to: .columns)
        builder.assignFieldForTesting(2, to: .values)
        try waitForPreview(builder)
        builder.selectResultTab(.chart)
        builder.layoutWindowForTesting()

        let chartView = try XCTUnwrap(firstSubview(ofType: PivotChartView.self, in: builder.window?.contentView))
        XCTAssertGreaterThanOrEqual(
            chartView.frame.width,
            builder.resultPaneWidthForTesting * 0.8
        )
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

        XCTAssertEqual(builder.previewHeadersForTesting, ["site", "Sum"])
        XCTAssertEqual(builder.previewRowForTesting(0), ["A", "3"])
        XCTAssertEqual(builder.previewRowForTesting(1), ["B", "2"])
    }

    func testBuilderShowsFilterDropdownsInResultPane() throws {
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

        builder.assignFieldForTesting(1, to: .filters)
        builder.layoutWindowForTesting()

        XCTAssertEqual(builder.resultFilterControlCountForTesting, 1)
        XCTAssertTrue(builder.resultPaneContainsFilterControlsForTesting)
        XCTAssertFalse(builder.controlPaneContainsFilterControlsForTesting)
    }

    func testBuilderKeepsEachFieldAssignedToOnlyOneZone() throws {
        _ = NSApplication.shared
        let (doc, path) = try openIndexed("""
        site,arm,value
        A,Control,3
        A,Treatment,7

        """)
        defer { try? FileManager.default.removeItem(atPath: path) }
        let builder = PivotBuilderWindowController(document: doc, columnNames: doc.header)

        builder.assignFieldForTesting(0, to: .rows)
        builder.assignFieldForTesting(0, to: .columns)
        XCTAssertEqual(builder.layoutForTesting.rows, [])
        XCTAssertEqual(builder.layoutForTesting.columns, [0])

        builder.assignFieldForTesting(0, to: .filters)
        XCTAssertEqual(builder.layoutForTesting.columns, [])
        XCTAssertEqual(builder.layoutForTesting.filters, [0])

        builder.assignFieldForTesting(0, to: .values)
        XCTAssertEqual(builder.layoutForTesting.filters, [])
        XCTAssertEqual(builder.layoutForTesting.value, 0)

        builder.assignFieldForTesting(0, to: .rows)
        XCTAssertNil(builder.layoutForTesting.value)
        XCTAssertEqual(builder.layoutForTesting.rows, [0])
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
        let monthHeader = "visit_date (\(L.t("Month", "월")))"
        let yearHeader = "visit_date (\(L.t("Year", "연")))"
        try waitForPreview(builder) {
            $0.previewHeadersForTesting == [monthHeader, "Sum"]
        }

        XCTAssertEqual(builder.dateDimensionGroupingControlCountForTesting, 1)
        XCTAssertEqual(builder.previewHeadersForTesting, [monthHeader, "Sum"])
        XCTAssertEqual(builder.previewRowForTesting(0), ["2026-01", "10"])
        XCTAssertEqual(builder.previewRowForTesting(1), ["2026-02", "2"])

        builder.selectDateGroupingPopupForTesting(column: 0, period: .year)
        try waitForPreview(builder) {
            $0.previewHeadersForTesting == [yearHeader, "Sum"]
        }

        XCTAssertEqual(builder.previewHeadersForTesting, [yearHeader, "Sum"])
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
            $0.previewHeadersForTesting == ["", "2026-01", "2026-02", L.t("Total", "합계")]
        }

        XCTAssertEqual(builder.dateDimensionGroupingControlCountForTesting, 1)
        XCTAssertEqual(builder.previewRowForTesting(0), ["Sum", "10", "2", "12"])

        builder.selectDateGroupingPopupForTesting(column: 0, period: .year)
        try waitForPreview(builder) {
            $0.previewHeadersForTesting == ["", "2026", L.t("Total", "합계")]
        }

        XCTAssertEqual(builder.previewRowForTesting(0), ["Sum", "12", "12"])
    }

    func testBuilderKeepsHighCardinalityDateRowPreviewVirtualized() throws {
        _ = NSApplication.shared
        let rows = (0..<420).map { index in
            let year = 1900 + (index / 12)
            let month = (index % 12) + 1
            return String(format: "P%03d,%04d-%02d-15", index, year, month)
        }
        let (doc, path) = try openIndexed("id,birth_date\n" + rows.joined(separator: "\n") + "\n")
        defer { try? FileManager.default.removeItem(atPath: path) }
        let statistics = try doc.analyzeColumns(sampleLimit: 1_000, cancellation: CancellationFlag())
        let builder = PivotBuilderWindowController(
            document: doc,
            columnNames: doc.header,
            columnStatisticsReport: statistics
        )
        builder.showWindow(nil)
        defer { builder.close() }

        builder.assignFieldForTesting(1, to: .rows)
        builder.assignFieldForTesting(0, to: .values)
        try waitForPreview(builder) {
            $0.previewHeadersForTesting == ["birth_date (\(L.t("Month", "월")))", "Count"]
                && $0.previewRowForTesting(0) == ["1900-01", "1"]
        }
        builder.layoutWindowForTesting()

        XCTAssertLessThanOrEqual(builder.previewTableDocumentHeightForTesting, 700)
    }

    func testBuilderShowsDateGroupingControlForFilterDimensions() throws {
        _ = NSApplication.shared
        let (doc, path) = try openIndexed("""
        birth_date,id
        2026-01-02,A
        2026-02-01,B

        """)
        defer { try? FileManager.default.removeItem(atPath: path) }
        let statistics = try doc.analyzeColumns(sampleLimit: 5, cancellation: CancellationFlag())
        let builder = PivotBuilderWindowController(
            document: doc,
            columnNames: doc.header,
            columnStatisticsReport: statistics
        )

        builder.assignFieldForTesting(0, to: .filters)
        builder.assignFieldForTesting(1, to: .values)

        XCTAssertEqual(builder.dateDimensionGroupingControlCountForTesting, 1)
        builder.selectDateGroupingPopupForTesting(column: 0, period: .year)
        XCTAssertEqual(builder.layoutForTesting.dateGroupings[0], .year)
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

        XCTAssertEqual(builder.previewHeadersForTesting, ["site", "Sum"])
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

    func testBuilderFieldActionButtonsOrderFiltersBeforeValues() throws {
        _ = NSApplication.shared
        let (doc, path) = try openIndexed("""
        site,arm,value
        A,Control,3
        A,Treatment,7

        """)
        defer { try? FileManager.default.removeItem(atPath: path) }
        let builder = PivotBuilderWindowController(document: doc, columnNames: doc.header)

        XCTAssertEqual(builder.fieldActionButtonTitlesForTesting, [
            L.t("Rows", "행"),
            L.t("Columns", "열"),
            L.t("Filters", "필터"),
            L.t("Values", "값")
        ])
    }

    func testBuilderUsesFieldTypeSpecificAggregationOptions() throws {
        _ = NSApplication.shared
        let (doc, path) = try openIndexed("""
        group,height,name
        A,170,Kim
        B,180,Lee

        """)
        defer { try? FileManager.default.removeItem(atPath: path) }
        let statistics = try doc.analyzeColumns(sampleLimit: 5, cancellation: CancellationFlag())
        let builder = PivotBuilderWindowController(
            document: doc,
            columnNames: doc.header,
            columnStatisticsReport: statistics
        )

        builder.assignFieldForTesting(1, to: .values)
        XCTAssertEqual(builder.measureAggregationOptionTitlesForTesting(measureAt: 0), [
            "Count", "Sum", "Mean", "Median", "Min", "Max", "Std", "Unique Count"
        ])

        builder.assignFieldForTesting(2, to: .values)
        XCTAssertEqual(builder.measureAggregationOptionTitlesForTesting(measureAt: 1), [
            "Count", "Unique Count"
        ])

        builder.setMeasureAggregationForTesting(measureAt: 1, function: .sum)
        XCTAssertEqual(builder.layoutForTesting.measures[1].function, .count)
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

    func testBuilderGroupsBlankDimensionValuesAsNull() throws {
        _ = NSApplication.shared
        let (doc, path) = try openIndexed("""
        id,sex
        A,F
        B,M
        C,

        """)
        defer { try? FileManager.default.removeItem(atPath: path) }
        let builder = PivotBuilderWindowController(document: doc, columnNames: doc.header)

        builder.assignFieldForTesting(1, to: .columns)
        builder.assignFieldForTesting(0, to: .values)
        try waitForPreview(builder) {
            $0.previewHeadersForTesting.contains("null")
        }

        XCTAssertEqual(builder.previewHeadersForTesting, ["", "F", "M", "null", L.t("Total", "합계")])
        XCTAssertEqual(builder.previewRowForTesting(0), ["Count", "1", "1", "1", "3"])
    }

    func testBuilderReordersMeasuresWithoutResettingAggregations() throws {
        _ = NSApplication.shared
        let (doc, path) = try openIndexed("""
        site,visits,cost
        A,1,3
        A,2,7

        """)
        defer { try? FileManager.default.removeItem(atPath: path) }
        let builder = PivotBuilderWindowController(document: doc, columnNames: doc.header)

        builder.assignFieldForTesting(1, to: .values)
        builder.assignFieldForTesting(2, to: .values)
        builder.setMeasureAggregationForTesting(column: 1, function: .sum)
        builder.setMeasureAggregationForTesting(column: 2, function: .count)
        builder.moveAssignedFieldForTesting(1, from: .values, to: .values, targetPosition: 2)

        XCTAssertEqual(builder.layoutForTesting.measures, [
            PivotMeasure(fieldIndex: 2, function: .count),
            PivotMeasure(fieldIndex: 1, function: .sum)
        ])
    }

    func testBuilderAllowsSameFieldAsMultipleMeasures() throws {
        _ = NSApplication.shared
        let (doc, path) = try openIndexed("""
        group,height
        A,170
        A,180
        B,160
        B,190

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
        builder.assignFieldForTesting(1, to: .values)
        builder.setMeasureAggregationForTesting(measureAt: 0, function: .mean)
        builder.setMeasureAggregationForTesting(measureAt: 1, function: .standardDeviation)
        try waitForPreview(builder) {
            $0.previewSectionCountForTesting == 2
                && $0.previewSectionTitlesForTesting == ["Mean of height", "Std of height"]
        }

        XCTAssertEqual(builder.layoutForTesting.measures.map(\.fieldIndex), [1, 1])
        XCTAssertEqual(builder.layoutForTesting.measures.map(\.function), [.mean, .standardDeviation])
        XCTAssertEqual(builder.previewRowForTesting(section: 0, row: 0), ["A", "175"])
        XCTAssertEqual(builder.previewRowForTesting(section: 1, row: 0), ["A", "5"])
    }

    func testBuilderMeasureRowsExposeMoveControlsAndCanMoveByButton() throws {
        _ = NSApplication.shared
        let (doc, path) = try openIndexed("""
        site,visits,cost
        A,1,3
        A,2,7

        """)
        defer { try? FileManager.default.removeItem(atPath: path) }
        let builder = PivotBuilderWindowController(document: doc, columnNames: doc.header)
        builder.showWindow(nil)
        defer { builder.close() }

        builder.assignFieldForTesting(1, to: .values)
        builder.assignFieldForTesting(2, to: .values)
        builder.layoutWindowForTesting()

        XCTAssertEqual(builder.measureMoveControlCountForTesting, 4)
        XCTAssertTrue(builder.measureRowControlsAreOrderedForTesting(measureAt: 0))

        builder.moveMeasureDownForTesting(measureAt: 0)
        XCTAssertEqual(builder.layoutForTesting.measures.map(\.fieldIndex), [2, 1])
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

    func testBuilderKeepsFilterZoneCompactAndMeasureZoneTaller() throws {
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

        XCTAssertLessThanOrEqual(
            abs(builder.dropZoneHeightForTesting(.filters) - builder.dropZoneHeightForTesting(.rows)),
            8
        )
        XCTAssertGreaterThan(
            builder.dropZoneHeightForTesting(.values),
            builder.dropZoneHeightForTesting(.filters) + 36
        )
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

    private func firstSubview<T: NSView>(ofType type: T.Type, in root: NSView?) -> T? {
        guard let root else { return nil }
        if let view = root as? T {
            return view
        }
        for subview in root.subviews {
            if let match = firstSubview(ofType: type, in: subview) {
                return match
            }
        }
        return nil
    }
}
