import AppKit
import XCTest
@testable import CsvCore
@testable import NanumCsvViewerMac

@MainActor
final class PivotBuilderTests: XCTestCase {
    func testPivotResultTableModelSortsNumericCellsAndKeepsTotalLast() {
        var model = PivotResultTableModel(
            headers: ["site", "Sum"],
            rows: [
                ["A", "2"],
                ["B", "10"],
                [L.t("Total", "합계"), "12"]
            ]
        )

        model.sort(column: 1, ascending: false)

        XCTAssertEqual(model.visibleRows, [
            ["B", "10"],
            ["A", "2"],
            [L.t("Total", "합계"), "12"]
        ])
    }

    func testPivotResultTableModelFiltersAcrossVisibleColumns() {
        var model = PivotResultTableModel(
            headers: ["site", "Sum"],
            rows: [
                ["Control", "2"],
                ["Treatment", "10"],
                [L.t("Total", "합계"), "12"]
            ]
        )

        model.setFilter(column: nil, query: "treat")

        XCTAssertEqual(model.visibleRows, [
            ["Treatment", "10"]
        ])
    }

    func testPivotResultTableModelExportsVisibleRowsAsTsvAndCsv() {
        var model = PivotResultTableModel(
            headers: ["site", "Sum"],
            rows: [
                ["A, quoted", "2"],
                ["B", "10"]
            ]
        )
        model.setFilter(column: nil, query: "quoted")

        XCTAssertEqual(model.exportString(format: .tsv), "site\tSum\nA, quoted\t2\n")
        XCTAssertEqual(model.exportString(format: .csv), "site,Sum\n\"A, quoted\",2\n")
    }

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


    func testChartModelRefusesLargeSparsePivotsWithoutBuildingDenseSeries() {
        let dimensions = [
            (rows: 201, columns: 0),
            (rows: 1, columns: 21),
            (rows: 200, columns: 11),
            (rows: 0, columns: 201)
        ]
        for dimension in dimensions {
            let pivot = PivotTableResult(
                rowColumns: dimension.rows == 0 ? [] : [0],
                rowColumnNames: dimension.rows == 0 ? [] : ["category"],
                columnColumns: dimension.columns == 0 ? [] : [1],
                valueColumn: 2,
                function: .sum,
                rowKeys: (0..<dimension.rows).map { ["R\($0)"] },
                columnKeys: (0..<dimension.columns).map { ["C\($0)"] },
                values: [:]
            )

            let model = PivotChartModel.make(from: pivot)

            XCTAssertNotNil(model.unsupportedReason, "\(dimension)")
            XCTAssertEqual(model.series, [], "\(dimension)")
            XCTAssertEqual(model.points, [], "\(dimension)")
        }
    }

    func testChartModelAllowsExactPointLimitWithoutDroppingCategories() {
        let pivot = PivotTableResult(
            rowColumns: [0],
            rowColumnNames: ["category"],
            columnColumns: [1],
            valueColumn: 2,
            function: .sum,
            rowKeys: (0..<200).map { ["R\($0)"] },
            columnKeys: (0..<10).map { ["C\($0)"] },
            values: [PivotCellKey(row: ["R199"], column: ["C9"]): 42]
        )

        let model = PivotChartModel.make(from: pivot)

        XCTAssertNil(model.unsupportedReason)
        XCTAssertEqual(model.points.count, 2_000)
        XCTAssertEqual(model.points.last, PivotChartPoint(category: "R199", series: "C9", value: 42))
    }
    func testDropZoneStoresVisibleFieldNames() {
        let zone = PivotDropZoneView(zone: .rows) { _, _ in }

        zone.setFieldNames(["site", "visit"])

        XCTAssertEqual(zone.fieldNamesForTesting, ["site", "visit"])
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

    func testBuilderSortsPivotResultRowsAfterAggregation() throws {
        _ = NSApplication.shared
        let (doc, path) = try openIndexed("""
        site,value
        A,2
        B,10

        """)
        defer { try? FileManager.default.removeItem(atPath: path) }
        let builder = PivotBuilderWindowController(document: doc, columnNames: doc.header)

        builder.assignFieldForTesting(0, to: .rows)
        builder.assignFieldForTesting(1, to: .values)
        builder.setAggregationForTesting(.sum)
        try waitForPreview(builder) {
            $0.previewRowForTesting(0) == ["A", "2"]
        }

        builder.sortPreviewSectionForTesting(section: 0, column: 1, ascending: false)

        XCTAssertEqual(builder.previewRowForTesting(0), ["B", "10"])
        XCTAssertEqual(builder.previewRowForTesting(1), ["A", "2"])
        XCTAssertEqual(builder.previewRowForTesting(2), [L.t("Total", "합계"), "12"])
    }

    func testBuilderPivotResultTablesUseClippedHeaderViewToAvoidRepeatedTrailingHeaders() throws {
        _ = NSApplication.shared
        let (doc, path) = try openIndexed("""
        site,value
        A,2
        B,10

        """)
        defer { try? FileManager.default.removeItem(atPath: path) }
        let builder = PivotBuilderWindowController(document: doc, columnNames: doc.header)
        builder.showWindow(nil)
        defer { builder.close() }

        builder.assignFieldForTesting(0, to: .rows)
        builder.assignFieldForTesting(1, to: .values)
        builder.setAggregationForTesting(.sum)
        try waitForPreview(builder)
        builder.layoutWindowForTesting()

        XCTAssertNotNil(firstSubview(ofType: CsvTableHeaderView.self, in: builder.window?.contentView))
    }

    func testBuilderPivotResultTableHeaderRemainsVisible() throws {
        _ = NSApplication.shared
        let (doc, path) = try openIndexed("""
        site,value
        A,2
        B,10

        """)
        defer { try? FileManager.default.removeItem(atPath: path) }
        let builder = PivotBuilderWindowController(document: doc, columnNames: doc.header)
        builder.showWindow(nil)
        defer { builder.close() }

        builder.assignFieldForTesting(0, to: .rows)
        builder.assignFieldForTesting(1, to: .values)
        builder.setAggregationForTesting(.sum)
        try waitForPreview(builder)
        builder.layoutWindowForTesting()

        let header = try XCTUnwrap(firstSubview(ofType: CsvTableHeaderView.self, in: builder.window?.contentView))
        XCTAssertGreaterThanOrEqual(header.frame.height, 20)
    }

    func testBuilderValueOnlyPivotResultDoesNotLeaveLargeBlankAreaAfterTotalRow() throws {
        _ = NSApplication.shared
        let (doc, path) = try openIndexed("""
        site,value
        A,2
        B,10

        """)
        defer { try? FileManager.default.removeItem(atPath: path) }
        let builder = PivotBuilderWindowController(document: doc, columnNames: doc.header)
        builder.showWindow(nil)
        defer { builder.close() }

        builder.assignFieldForTesting(1, to: .values)
        builder.setAggregationForTesting(.sum)
        try waitForPreview(builder)
        builder.layoutWindowForTesting()

        XCTAssertLessThanOrEqual(builder.previewTableDocumentHeightForTesting, 80)
    }

    func testBuilderPivotResultColumnsFillVisibleHeaderWidth() throws {
        _ = NSApplication.shared
        let (doc, path) = try openIndexed("""
        site,value
        A,2
        B,10

        """)
        defer { try? FileManager.default.removeItem(atPath: path) }
        let builder = PivotBuilderWindowController(document: doc, columnNames: doc.header)
        builder.showWindow(nil)
        defer { builder.close() }

        builder.assignFieldForTesting(0, to: .rows)
        builder.assignFieldForTesting(1, to: .values)
        builder.setAggregationForTesting(.sum)
        try waitForPreview(builder)
        builder.layoutWindowForTesting()

        XCTAssertGreaterThan(builder.previewTableSectionVisibleWidthForTesting(section: 0), 320)
        XCTAssertGreaterThanOrEqual(
            builder.previewTableHeaderColumnsMaxXForTesting(section: 0),
            builder.previewTableSectionVisibleWidthForTesting(section: 0) - 1
        )
    }

    func testBuilderKeepsPivotResultColumnWidthWhenSorting() throws {
        _ = NSApplication.shared
        let (doc, path) = try openIndexed("""
        site,value
        A,2
        B,10

        """)
        defer { try? FileManager.default.removeItem(atPath: path) }
        let builder = PivotBuilderWindowController(document: doc, columnNames: doc.header)
        builder.showWindow(nil)
        defer { builder.close() }

        builder.assignFieldForTesting(0, to: .rows)
        builder.assignFieldForTesting(1, to: .values)
        builder.setAggregationForTesting(.sum)
        try waitForPreview(builder)
        builder.layoutWindowForTesting()

        let sectionIdentity = builder.previewTableSectionIdentityForTesting(section: 0)
        builder.setPreviewTableColumnWidthForTesting(section: 0, column: 0, width: 260)
        builder.layoutWindowForTesting()

        builder.sortPreviewSectionForTesting(section: 0, column: 1, ascending: false)
        builder.layoutWindowForTesting()

        XCTAssertEqual(builder.previewTableSectionIdentityForTesting(section: 0), sectionIdentity)
        let columnWidth = try XCTUnwrap(builder.previewTableColumnWidthsForTesting(section: 0).first)
        XCTAssertEqual(columnWidth, 260, accuracy: 0.5)
        XCTAssertEqual(builder.previewRowForTesting(0), ["B", "10"])
    }

    func testBuilderKeepsPivotResultColumnWidthWhenFilteringResults() throws {
        _ = NSApplication.shared
        let (doc, path) = try openIndexed("""
        site,value
        Control,2
        Treatment,10

        """)
        defer { try? FileManager.default.removeItem(atPath: path) }
        let builder = PivotBuilderWindowController(document: doc, columnNames: doc.header)
        builder.showWindow(nil)
        defer { builder.close() }

        builder.assignFieldForTesting(0, to: .rows)
        builder.assignFieldForTesting(1, to: .values)
        builder.setAggregationForTesting(.sum)
        try waitForPreview(builder)
        builder.layoutWindowForTesting()

        let sectionIdentity = builder.previewTableSectionIdentityForTesting(section: 0)
        builder.setPreviewTableColumnWidthForTesting(section: 0, column: 0, width: 260)
        builder.layoutWindowForTesting()

        builder.setResultFilterForTesting("treat")
        builder.layoutWindowForTesting()

        XCTAssertEqual(builder.previewTableSectionIdentityForTesting(section: 0), sectionIdentity)
        let columnWidth = try XCTUnwrap(builder.previewTableColumnWidthsForTesting(section: 0).first)
        XCTAssertEqual(columnWidth, 260, accuracy: 0.5)
        XCTAssertEqual(builder.previewVisibleRowCountForTesting(section: 0), 1)
        XCTAssertEqual(builder.previewRowForTesting(0), ["Treatment", "10"])
    }

    func testBuilderFiltersPivotResultRowsAfterAggregation() throws {
        _ = NSApplication.shared
        let (doc, path) = try openIndexed("""
        site,value
        Control,2
        Treatment,10

        """)
        defer { try? FileManager.default.removeItem(atPath: path) }
        let builder = PivotBuilderWindowController(document: doc, columnNames: doc.header)

        builder.assignFieldForTesting(0, to: .rows)
        builder.assignFieldForTesting(1, to: .values)
        builder.setAggregationForTesting(.sum)
        try waitForPreview(builder)

        builder.setResultFilterForTesting("treat")

        XCTAssertEqual(builder.previewVisibleRowCountForTesting(section: 0), 1)
        XCTAssertEqual(builder.previewRowForTesting(0), ["Treatment", "10"])
    }

    func testBuilderCopiesVisiblePivotResultAsTsv() throws {
        _ = NSApplication.shared
        let (doc, path) = try openIndexed("""
        site,value
        A,2
        B,10

        """)
        defer { try? FileManager.default.removeItem(atPath: path) }
        let builder = PivotBuilderWindowController(document: doc, columnNames: doc.header)

        builder.assignFieldForTesting(0, to: .rows)
        builder.assignFieldForTesting(1, to: .values)
        builder.setAggregationForTesting(.sum)
        try waitForPreview(builder)

        builder.setResultFilterForTesting("B")

        XCTAssertEqual(builder.copyPivotResultForTesting(), "site\tSum\nB\t10\n")
    }

    func testBuilderExportsVisiblePivotResultAsCsv() throws {
        _ = NSApplication.shared
        let (doc, path) = try openIndexed("""
        site,value
        A,2
        B,10

        """)
        defer { try? FileManager.default.removeItem(atPath: path) }
        let builder = PivotBuilderWindowController(document: doc, columnNames: doc.header)

        builder.assignFieldForTesting(0, to: .rows)
        builder.assignFieldForTesting(1, to: .values)
        builder.setAggregationForTesting(.sum)
        try waitForPreview(builder)

        builder.setResultFilterForTesting("B")

        XCTAssertEqual(builder.pivotResultExportForTesting(format: .csv), "site,Sum\nB,10\n")
    }


    func testBuilderKeepsIndependentSectionSortsWhenClearingResultFilter() throws {
        _ = NSApplication.shared
        let (doc, path) = try openIndexed("site,visits,cost\nA,2,30\nB,10,5\nC,3,20\n")
        defer { try? FileManager.default.removeItem(atPath: path) }
        let builder = PivotBuilderWindowController(document: doc, columnNames: doc.header)
        defer { builder.close() }
        builder.assignFieldForTesting(0, to: .rows)
        builder.assignFieldForTesting(1, to: .values)
        builder.assignFieldForTesting(2, to: .values)
        builder.setMeasureAggregationForTesting(column: 1, function: .sum)
        builder.setMeasureAggregationForTesting(column: 2, function: .sum)
        try waitForPreview(builder)

        builder.sortPreviewSectionForTesting(section: 0, column: 1, ascending: false)
        builder.sortPreviewSectionForTesting(section: 1, column: 1, ascending: true)
        builder.setResultFilterForTesting("C")
        XCTAssertEqual(builder.previewRowForTesting(section: 0, row: 0), ["C", "3"])
        XCTAssertEqual(builder.previewRowForTesting(section: 1, row: 0), ["C", "20"])
        XCTAssertEqual(builder.previewVisibleRowCountForTesting(section: 0), 1)

        builder.setResultFilterForTesting("")
        XCTAssertEqual((0..<4).map { builder.previewRowForTesting(section: 0, row: $0) }, [
            ["B", "10"], ["C", "3"], ["A", "2"], [L.t("Total", "합계"), "15"]
        ])
        XCTAssertEqual((0..<4).map { builder.previewRowForTesting(section: 1, row: $0) }, [
            ["B", "5"], ["C", "20"], ["A", "30"], [L.t("Total", "합계"), "55"]
        ])
        XCTAssertEqual(builder.pivotResultExportForTesting(format: .tsv),
            "Sum of visits\nsite\tSum\nB\t10\nC\t3\nA\t2\n\(L.t("Total", "합계"))\t15\n\n"
                + "Sum of cost\nsite\tSum\nB\t5\nC\t20\nA\t30\n\(L.t("Total", "합계"))\t55\n")
    }

    func testBuilderRefusesCombinedDensePreviewAndRecoversAfterRemovingDimension() throws {
        _ = NSApplication.shared
        let rows = (0..<2_500).map { "R\($0),C\($0 % 200),1,2" }
        let (doc, path) = try openIndexed("row,column,first,second\n" + rows.joined(separator: "\n") + "\n")
        defer { try? FileManager.default.removeItem(atPath: path) }
        let builder = PivotBuilderWindowController(document: doc, columnNames: doc.header)
        defer { builder.close() }
        builder.assignFieldForTesting(0, to: .rows)
        builder.assignFieldForTesting(1, to: .columns)
        builder.assignFieldForTesting(2, to: .values)
        builder.assignFieldForTesting(3, to: .values)
        try waitForPreviewCompletion(builder)

        XCTAssertEqual(builder.previewSectionCountForTesting, 0)
        XCTAssertEqual(builder.pivotResultExportForTesting(format: .csv), "")
        XCTAssertFalse(builder.previewMessageForTesting.isEmpty)

        builder.removeFieldForTesting(1, from: .columns)
        try waitForPreview(builder)
        XCTAssertEqual(builder.previewSectionCountForTesting, 2)
        XCTAssertEqual(builder.previewVisibleRowCountForTesting(section: 0), 2_501)
        XCTAssertEqual(builder.previewRowForTesting(section: 1, row: 2_500), [L.t("Total", "합계"), "2500"])
    }

    func testBuilderLoadsBoundedFilterMenuAndAppliesExactValueFromSheet() throws {
        _ = NSApplication.shared
        let rows = (0...1_000).map { "Category\($0),1" }
        let (doc, path) = try openIndexed("category,value\n" + rows.joined(separator: "\n") + "\n")
        defer { try? FileManager.default.removeItem(atPath: path) }
        let builder = PivotBuilderWindowController(document: doc, columnNames: doc.header)
        builder.showWindow(nil)
        defer { builder.close() }
        builder.assignFieldForTesting(0, to: .filters)
        XCTAssertTrue(builder.filterOptionsAreLoadingForTesting(column: 0))
        builder.assignFieldForTesting(1, to: .values)
        try waitForFilterOptions(builder, column: 0)

        XCTAssertNotNil(builder.filterOptionsFailureForTesting(column: 0))
        XCTAssertEqual(builder.filterOptionValuesForTesting(column: 0), [])
        builder.beginExactFilterEntryForTesting(column: 0)
        let sheet = try XCTUnwrap(builder.window?.attachedSheet)
        let input = try XCTUnwrap(sheet.initialFirstResponder as? NSTextField)
        input.stringValue = "Category1000"
        builder.window?.endSheet(sheet, returnCode: .alertFirstButtonReturn)
        try waitForPreview(builder) {
            $0.layoutForTesting.filterSelections[0] == "Category1000"
                && $0.previewRowForTesting(0) == [L.t("Total", "합계"), "1"]
        }
        XCTAssertEqual(builder.filterOptionValuesForTesting(column: 0), ["Category1000"])
    }

    func testBuilderDiscardsStaleFilterLoadsAcrossDateGroupingAndClose() throws {
        _ = NSApplication.shared
        let (doc, path) = try openIndexed("date,value\n2026-01-02,1\n2027-02-03,2\n")
        defer { try? FileManager.default.removeItem(atPath: path) }
        let report = try doc.analyzeColumns(sampleLimit: 10, cancellation: CancellationFlag())
        let builder = PivotBuilderWindowController(document: doc, columnNames: doc.header, columnStatisticsReport: report)
        defer { builder.close() }
        builder.assignFieldForTesting(0, to: .filters)
        builder.setDateGroupingForTesting(column: 0, period: .year)
        builder.close()
        builder.setDateGroupingForTesting(column: 0, period: .day)
        builder.showWindow(nil)
        try waitForFilterOptions(builder, column: 0)

        XCTAssertEqual(builder.filterOptionValuesForTesting(column: 0), ["2026-01-02", "2027-02-03"])
        builder.setDateGroupingForTesting(column: 0, period: .month)
        builder.setDateGroupingForTesting(column: 0, period: .year)
        try waitForFilterOptions(builder, column: 0)
        XCTAssertEqual(builder.filterOptionValuesForTesting(column: 0), ["2026", "2027"])
    }

    func testBuilderFilterMenuPreservesValuesMatchingAllAndBlankLabels() throws {
        _ = NSApplication.shared
        let (doc, path) = try openIndexed("category,value\n\(L.t("All", "전체")),1\n\(L.t("(Blank)", "(빈 값)")),2\n,3\n")
        defer { try? FileManager.default.removeItem(atPath: path) }
        let builder = PivotBuilderWindowController(document: doc, columnNames: doc.header)
        defer { builder.close() }
        builder.assignFieldForTesting(0, to: .filters)
        try waitForFilterOptions(builder, column: 0)
        XCTAssertEqual(Set(builder.filterOptionValuesForTesting(column: 0)), [L.t("All", "전체"), L.t("(Blank)", "(빈 값)"), "null"])
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

    private func waitForFilterOptions(
        _ builder: PivotBuilderWindowController,
        column: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
            if !builder.filterOptionsAreLoadingForTesting(column: column) {
                return
            }
        }
        XCTFail("Timed out waiting for pivot filter values", file: file, line: line)
    }

    func testResultFilterEnteredDuringCalculationAppliesToNewPreview() throws {
        _ = NSApplication.shared
        let (doc, path) = try openIndexed("category,value\nA,1\nB,2\n")
        defer { try? FileManager.default.removeItem(atPath: path) }
        let builder = PivotBuilderWindowController(document: doc, columnNames: doc.header)
        defer { builder.close() }
        builder.assignFieldForTesting(0, to: .rows)
        builder.assignFieldForTesting(1, to: .values)
        builder.setResultFilterForTesting("B")
        try waitForPreview(builder)
        XCTAssertEqual(builder.copyPivotResultForTesting(), "category\tCount\nB\t1\n")
    }

    private func waitForPreviewCompletion(
        _ builder: PivotBuilderWindowController,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
            if !builder.previewIsComputingForTesting { return }
        }
        XCTFail("Timed out waiting for pivot calculation", file: file, line: line)
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
            if !builder.previewIsComputingForTesting,
               !builder.previewHeadersForTesting.isEmpty,
               condition?(builder) ?? true {
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
