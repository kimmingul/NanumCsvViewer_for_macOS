import AppKit
@preconcurrency import CsvCore
import XCTest
@testable import NanumCsvViewerMac

@MainActor
final class MainWindowControllerGridTests: XCTestCase {
    func testGridSelectionReplacesWithSingleCell() {
        var model = GridSelectionModel()
        model.replace(with: GridCellCoordinate(row: 2, column: 1))

        XCTAssertTrue(model.contains(row: 2, column: 1))
        XCTAssertEqual(model.anchor, GridCellCoordinate(row: 2, column: 1))
        XCTAssertEqual(model.selectedCells.count, 1)
        XCTAssertEqual(model.boundingRect(), ClosedRangeGrid(rows: 2...2, columns: 1...1))
    }

    func testGridSelectionExtendsFromAnchorToRectangle() {
        var model = GridSelectionModel()
        model.replace(with: GridCellCoordinate(row: 1, column: 1))
        model.extend(to: GridCellCoordinate(row: 3, column: 2))

        XCTAssertTrue(model.contains(row: 1, column: 1))
        XCTAssertTrue(model.contains(row: 3, column: 2))
        XCTAssertEqual(model.selectedCells.count, 6)
        XCTAssertEqual(model.selectedRows, IndexSet(integersIn: 1...3))
        XCTAssertEqual(model.selectedColumns, IndexSet(integersIn: 1...2))
    }

    func testGridSelectionTogglesCells() {
        var model = GridSelectionModel()
        let cell = GridCellCoordinate(row: 4, column: 2)

        model.toggle(cell)
        XCTAssertTrue(model.contains(row: 4, column: 2))

        model.toggle(cell)
        XCTAssertFalse(model.contains(row: 4, column: 2))
    }

    func testGridCopyFormatterCopiesRectangleAsTsv() {
        let rows = [
            ["A1", "B1", "C1"],
            ["A2", "B2", "C2"]
        ]
        let selection: Set<GridCellCoordinate> = [
            .init(row: 0, column: 1),
            .init(row: 0, column: 2),
            .init(row: 1, column: 1),
            .init(row: 1, column: 2)
        ]

        XCTAssertEqual(GridCopyFormatter.tsv(rows: rows, selection: selection), "B1\tC1\nB2\tC2\n")
    }

    func testGridCopyFormatterCopiesSparseSelectionInsideBoundingRect() {
        let rows = [
            ["A1", "B1", "C1"],
            ["A2", "B2", "C2"]
        ]
        let selection: Set<GridCellCoordinate> = [
            .init(row: 0, column: 0),
            .init(row: 1, column: 2)
        ]

        XCTAssertEqual(GridCopyFormatter.tsv(rows: rows, selection: selection), "A1\t\t\n\t\tC2\n")
    }

    func testControllerSelectsAndExtendsGridCells() throws {
        _ = NSApplication.shared
        let path = try temporaryCsvPath()
        try """
        a,b,c
        A1,B1,C1
        A2,B2,C2
        A3,B3,C3

        """.data(using: .utf8)!.write(to: URL(fileURLWithPath: path))
        defer { try? FileManager.default.removeItem(atPath: path) }

        let controller = MainWindowController()
        controller.showWindow(nil)
        defer { controller.close() }

        controller.openFileForTesting(URL(fileURLWithPath: path))
        try waitUntilIndexed(controller)

        controller.selectGridCellForTesting(row: 0, column: 1)
        XCTAssertEqual(controller.selectedGridCellsForTesting, [GridCellCoordinate(row: 0, column: 1)])
        XCTAssertEqual(controller.selectedValueTextForTesting, "B1")

        controller.extendGridSelectionForTesting(toRow: 2, column: 2)
        XCTAssertTrue(controller.selectedGridCellsForTesting.contains(GridCellCoordinate(row: 2, column: 2)))
        XCTAssertEqual(controller.selectedGridCellsForTesting.count, 6)

        controller.toggleGridCellSelectionForTesting(row: 2, column: 2)
        XCTAssertFalse(controller.selectedGridCellsForTesting.contains(GridCellCoordinate(row: 2, column: 2)))
    }

    func testControllerCopiesSelectedGridCellsAsTsv() throws {
        _ = NSApplication.shared
        let path = try temporaryCsvPath()
        try """
        a,b,c
        A1,B1,C1
        A2,B2,C2

        """.data(using: .utf8)!.write(to: URL(fileURLWithPath: path))
        defer { try? FileManager.default.removeItem(atPath: path) }

        let controller = MainWindowController()
        controller.showWindow(nil)
        defer { controller.close() }

        controller.openFileForTesting(URL(fileURLWithPath: path))
        try waitUntilIndexed(controller)

        controller.selectGridCellForTesting(row: 0, column: 1)
        controller.extendGridSelectionForTesting(toRow: 1, column: 2)

        XCTAssertEqual(controller.selectedGridCopyStringForTesting(), "B1\tC1\nB2\tC2\n")
    }

    func testControllerCopiesEntireVisibleRowAndColumnAsTsv() throws {
        _ = NSApplication.shared
        let path = try temporaryCsvPath()
        try """
        id,site,value
        1,A,10
        2,B,20

        """.data(using: .utf8)!.write(to: URL(fileURLWithPath: path))
        defer { try? FileManager.default.removeItem(atPath: path) }

        let controller = MainWindowController()
        controller.showWindow(nil)
        defer { controller.close() }

        controller.openFileForTesting(URL(fileURLWithPath: path))
        try waitUntilIndexed(controller)

        XCTAssertEqual(controller.rowCopyStringForTesting(row: 1), "2\tB\t20\n")
        XCTAssertEqual(controller.columnCopyStringForTesting(column: 1, includeHeader: true), "site\nA\nB\n")
    }

    func testInspectorCopiesSelectedRowAsTextAndJsonWithUniqueKeys() throws {
        _ = NSApplication.shared
        let path = try temporaryCsvPath()
        try """
        id,id,note
        1,alpha,hello

        """.data(using: .utf8)!.write(to: URL(fileURLWithPath: path))
        defer { try? FileManager.default.removeItem(atPath: path) }

        let controller = MainWindowController()
        controller.showWindow(nil)
        defer { controller.close() }

        controller.openFileForTesting(URL(fileURLWithPath: path))
        try waitUntilIndexed(controller)
        controller.selectGridCellForTesting(row: 0, column: 1)
        controller.showInspectorForTesting()
        controller.updateDetailPanel()

        XCTAssertTrue(controller.inspectorTextCopyStringForTesting().contains("alpha"))

        let json = controller.inspectorJsonCopyStringForTesting()
        XCTAssertTrue(json.contains(#""id" : "1""#))
        XCTAssertTrue(json.contains(#""id_2" : "alpha""#))
        XCTAssertTrue(json.contains(#""note" : "hello""#))
    }

    func testControllerAppliesCategoricalColumnFilterState() throws {
        _ = NSApplication.shared
        let path = try temporaryCsvPath()
        try """
        site,value
        A,10
        B,20
        A,30

        """.data(using: .utf8)!.write(to: URL(fileURLWithPath: path))
        defer { try? FileManager.default.removeItem(atPath: path) }

        let controller = MainWindowController()
        controller.showWindow(nil)
        defer { controller.close() }

        controller.openFileForTesting(URL(fileURLWithPath: path))
        try waitUntilIndexed(controller)

        controller.applyColumnFilterForTesting(.selectedValues(column: 0, values: ["A"], includeBlanks: false))
        try waitUntilNotBusy(controller)

        XCTAssertEqual(controller.renderedRowCountForTesting, 2)
        XCTAssertEqual(controller.renderedDataRowForTesting(0), ["A", "10"])
        XCTAssertEqual(controller.renderedDataRowForTesting(1), ["A", "30"])
        XCTAssertTrue(controller.headerFilterActiveForTesting(column: 0))
    }

    func testCancelledColumnFilterValueCompletionClearsLoadingState() throws {
        _ = NSApplication.shared
        let path = try temporaryCsvPath()
        try """
        site,value
        A,10
        B,20

        """.data(using: .utf8)!.write(to: URL(fileURLWithPath: path))
        defer { try? FileManager.default.removeItem(atPath: path) }

        let controller = MainWindowController()
        controller.showWindow(nil)
        defer { controller.close() }

        controller.openFileForTesting(URL(fileURLWithPath: path))
        try waitUntilIndexed(controller)

        let cancellation = controller.startColumnFilterValuesLoadForTesting()
        XCTAssertTrue(controller.busyForTesting)
        XCTAssertTrue(controller.progressVisibleForTesting)
        XCTAssertEqual(controller.statusTextForTesting, L.t("Loading filter values...", "필터 값을 불러오는 중..."))

        cancellation.cancel()
        controller.finishColumnFilterValuesLoadForTesting(cancellation: cancellation, values: [
            DistinctColumnValue(value: "A", count: 1),
            DistinctColumnValue(value: "B", count: 1)
        ])

        XCTAssertFalse(controller.busyForTesting)
        XCTAssertFalse(controller.progressVisibleForTesting)
        XCTAssertNotEqual(controller.statusTextForTesting, L.t("Loading filter values...", "필터 값을 불러오는 중..."))
        XCTAssertFalse(controller.hasCurrentColumnFilterValuesLoadForTesting)
    }

    func testStaleColumnFilterValueCompletionDoesNotClearNewerLoad() throws {
        _ = NSApplication.shared
        let path = try temporaryCsvPath()
        try """
        site,value
        A,10
        B,20

        """.data(using: .utf8)!.write(to: URL(fileURLWithPath: path))
        defer { try? FileManager.default.removeItem(atPath: path) }

        let controller = MainWindowController()
        controller.showWindow(nil)
        defer { controller.close() }

        controller.openFileForTesting(URL(fileURLWithPath: path))
        try waitUntilIndexed(controller)

        let staleCancellation = controller.startColumnFilterValuesLoadForTesting()
        let currentCancellation = controller.startColumnFilterValuesLoadForTesting()

        staleCancellation.cancel()
        controller.finishColumnFilterValuesLoadForTesting(cancellation: staleCancellation, values: [
            DistinctColumnValue(value: "A", count: 1)
        ])

        XCTAssertTrue(controller.busyForTesting)
        XCTAssertTrue(controller.progressVisibleForTesting)
        XCTAssertTrue(controller.isCurrentColumnFilterValuesLoadForTesting(currentCancellation))

        currentCancellation.cancel()
        controller.finishColumnFilterValuesLoadForTesting(cancellation: currentCancellation, values: [
            DistinctColumnValue(value: "B", count: 1)
        ])
        XCTAssertFalse(controller.busyForTesting)
    }

    func testControllerAppliesDateRangeColumnFilterState() throws {
        _ = NSApplication.shared
        let path = try temporaryCsvPath()
        try """
        date,value
        20260101,10
        20260102,20
        20260104,30

        """.data(using: .utf8)!.write(to: URL(fileURLWithPath: path))
        defer { try? FileManager.default.removeItem(atPath: path) }

        let controller = MainWindowController()
        controller.showWindow(nil)
        defer { controller.close() }

        controller.openFileForTesting(URL(fileURLWithPath: path))
        try waitUntilIndexed(controller)

        let calendar = Calendar(identifier: .gregorian)
        let start = DateComponents(calendar: calendar, timeZone: TimeZone(secondsFromGMT: 0), year: 2026, month: 1, day: 2).date
        let end = DateComponents(calendar: calendar, timeZone: TimeZone(secondsFromGMT: 0), year: 2026, month: 1, day: 3, hour: 23, minute: 59, second: 59).date
        controller.applyColumnFilterForTesting(.dateRange(column: 0, start: start, end: end))
        try waitUntilNotBusy(controller)

        XCTAssertEqual(controller.renderedRowCountForTesting, 1)
        XCTAssertEqual(controller.renderedDataRowForTesting(0), ["20260102", "20"])
    }

    func testSavedViewRestoresColumnFilterState() throws {
        _ = NSApplication.shared
        UserDefaults.standard.removeObject(forKey: "NanumCsvViewerMac.SavedViewsByPath")
        let path = try temporaryCsvPath()
        try """
        site,value
        A,10
        B,20
        A,30

        """.data(using: .utf8)!.write(to: URL(fileURLWithPath: path))
        defer {
            try? FileManager.default.removeItem(atPath: path)
            UserDefaults.standard.removeObject(forKey: "NanumCsvViewerMac.SavedViewsByPath")
        }

        let controller = MainWindowController()
        controller.showWindow(nil)
        defer { controller.close() }

        controller.openFileForTesting(URL(fileURLWithPath: path))
        try waitUntilIndexed(controller)

        controller.applyColumnFilterForTesting(.selectedValues(column: 0, values: ["A"], includeBlanks: false))
        try waitUntilNotBusy(controller)
        controller.saveCurrentView(nil)

        controller.clearFilter(nil)
        XCTAssertEqual(controller.renderedRowCountForTesting, 3)

        controller.restoreSavedView(nil)
        try waitUntilNotBusy(controller)

        XCTAssertEqual(controller.renderedRowCountForTesting, 2)
        XCTAssertEqual(controller.renderedDataRowForTesting(0), ["A", "10"])
        XCTAssertTrue(controller.headerFilterActiveForTesting(column: 0))
    }

    func testRepeatedSmallFileOpenRendersEveryGridRow() throws {
        _ = NSApplication.shared
        let path = try temporaryCsvPath()
        let expectedRows = (0..<300).map { index in
            [
                String(format: "r%03d", index),
                String(format: "payload-%03d-abcdefghijklmnopqrstuvwxyz", index),
                String(format: "%03d", index)
            ]
        }
        let content = "id,payload,n\n" + expectedRows.map { $0.joined(separator: ",") }.joined(separator: "\n") + "\n"
        try content.data(using: .utf8)!.write(to: URL(fileURLWithPath: path))
        defer { try? FileManager.default.removeItem(atPath: path) }

        for iteration in 0..<40 {
            let controller = MainWindowController()
            defer { controller.close() }

            controller.openFileForTesting(URL(fileURLWithPath: path))
            try waitUntilIndexed(controller)

            XCTAssertEqual(controller.renderedRowCountForTesting, expectedRows.count, "iteration \(iteration)")
            for row in expectedRows.indices {
                let rendered = controller.renderedDataRowForTesting(row)
                XCTAssertEqual(rendered, expectedRows[row], "iteration \(iteration), row \(row)")
            }
        }
    }

    func testRepeatedSmallFileOpenMaterializesEveryGridRow() throws {
        _ = NSApplication.shared
        let path = try temporaryCsvPath()
        let expectedRows = (0..<300).map { index in
            [
                String(format: "r%03d", index),
                String(format: "payload-%03d-abcdefghijklmnopqrstuvwxyz", index),
                String(format: "%03d", index)
            ]
        }
        let content = "id,payload,n\n" + expectedRows.map { $0.joined(separator: ",") }.joined(separator: "\n") + "\n"
        try content.data(using: .utf8)!.write(to: URL(fileURLWithPath: path))
        defer { try? FileManager.default.removeItem(atPath: path) }

        for iteration in 0..<20 {
            let controller = MainWindowController()
            controller.showWindow(nil)
            defer { controller.close() }

            controller.openFileForTesting(URL(fileURLWithPath: path))
            try waitUntilIndexed(controller)

            XCTAssertEqual(controller.renderedRowCountForTesting, expectedRows.count, "iteration \(iteration)")
            for row in expectedRows.indices {
                let rendered = controller.materializedDataRowForTesting(row)
                XCTAssertEqual(rendered, expectedRows[row], "iteration \(iteration), row \(row)")
            }
        }
    }

    func testRepeatedSmallFileOpenInSameWindowMaterializesEveryGridRow() throws {
        _ = NSApplication.shared
        let path = try temporaryCsvPath()
        let expectedRows = (0..<300).map { index in
            [
                String(format: "r%03d", index),
                String(format: "payload-%03d-abcdefghijklmnopqrstuvwxyz", index),
                String(format: "%03d", index)
            ]
        }
        let content = "id,payload,n\n" + expectedRows.map { $0.joined(separator: ",") }.joined(separator: "\n") + "\n"
        try content.data(using: .utf8)!.write(to: URL(fileURLWithPath: path))
        defer { try? FileManager.default.removeItem(atPath: path) }

        let controller = MainWindowController()
        controller.showWindow(nil)
        defer { controller.close() }

        for iteration in 0..<40 {
            controller.openFileForTesting(URL(fileURLWithPath: path))
            try waitUntilIndexed(controller)

            XCTAssertEqual(controller.renderedRowCountForTesting, expectedRows.count, "iteration \(iteration)")
            for row in expectedRows.indices {
                let rendered = controller.materializedDataRowForTesting(row)
                XCTAssertEqual(rendered, expectedRows[row], "iteration \(iteration), row \(row)")
            }
        }
    }

    func testRapidSmallFileReopenInSameWindowMaterializesEveryGridRow() throws {
        _ = NSApplication.shared
        let path = try temporaryCsvPath()
        let expectedRows = (0..<300).map { index in
            [
                String(format: "r%03d", index),
                String(format: "payload-%03d-abcdefghijklmnopqrstuvwxyz", index),
                String(format: "%03d", index)
            ]
        }
        let content = "id,payload,n\n" + expectedRows.map { $0.joined(separator: ",") }.joined(separator: "\n") + "\n"
        try content.data(using: .utf8)!.write(to: URL(fileURLWithPath: path))
        defer { try? FileManager.default.removeItem(atPath: path) }

        let controller = MainWindowController()
        controller.showWindow(nil)
        defer { controller.close() }

        for iteration in 0..<80 {
            controller.openFileForTesting(URL(fileURLWithPath: path))
            if iteration & 1 == 0 {
                RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.001))
            }
        }

        try waitUntilIndexed(controller)
        XCTAssertEqual(controller.renderedRowCountForTesting, expectedRows.count)
        for row in expectedRows.indices {
            let rendered = controller.materializedDataRowForTesting(row)
            XCTAssertEqual(rendered, expectedRows[row], "row \(row)")
        }
    }

    func testLongMultilineCellsRenderAsBoundedPreview() throws {
        _ = NSApplication.shared
        let path = try temporaryCsvPath()
        let longValue = String(repeating: "abcdefghij\n", count: 80)
        let escaped = longValue.replacingOccurrences(of: "\"", with: "\"\"")
        try "id,note\n1,\"\(escaped)\"\n".data(using: .utf8)!.write(to: URL(fileURLWithPath: path))
        defer { try? FileManager.default.removeItem(atPath: path) }

        let controller = MainWindowController()
        controller.showWindow(nil)
        defer { controller.close() }

        controller.openFileForTesting(URL(fileURLWithPath: path))
        try waitUntilIndexed(controller)

        let rendered = controller.materializedDataRowForTesting(0)
        XCTAssertEqual(rendered.first, "1")
        XCTAssertEqual(rendered[1].count, 515)
        XCTAssertFalse(rendered[1].contains("\n"))
        XCTAssertTrue(rendered[1].hasSuffix("..."))
    }

    func testSelectedValueBarExpandsForMultilineValues() throws {
        _ = NSApplication.shared
        let path = try temporaryCsvPath()
        try "id,note\n1,\"line one\nline two\nline three\"\n".data(using: .utf8)!.write(to: URL(fileURLWithPath: path))
        defer { try? FileManager.default.removeItem(atPath: path) }

        let controller = MainWindowController()
        controller.showWindow(nil)
        defer { controller.close() }

        controller.openFileForTesting(URL(fileURLWithPath: path))
        try waitUntilIndexed(controller)
        controller.selectCellForTesting(row: 0, column: 1)

        XCTAssertEqual(controller.selectedValueBarHeightForTesting, 34)
        XCTAssertFalse(controller.selectedValueScrollsVerticallyForTesting)

        controller.toggleSelectedValueExpansionForTesting()

        XCTAssertGreaterThanOrEqual(controller.selectedValueBarHeightForTesting, 132)
        XCTAssertTrue(controller.selectedValueScrollsVerticallyForTesting)
        XCTAssertEqual(controller.selectedValueTextForTesting, "line one\nline two\nline three")
    }

    func testGridHeadersShowInferredColumnTypes() throws {
        _ = NSApplication.shared
        let path = try temporaryCsvPath()
        try """
        visit_date,amount,site
        2026.01.02,10.5,A
        2026.01.03,12.0,B

        """.data(using: .utf8)!.write(to: URL(fileURLWithPath: path))
        defer { try? FileManager.default.removeItem(atPath: path) }

        let controller = MainWindowController()
        controller.showWindow(nil)
        defer { controller.close() }

        controller.openFileForTesting(URL(fileURLWithPath: path))
        try waitUntilColumnTypesReady(controller)

        XCTAssertEqual(controller.headerTypeTextForTesting(column: 0), "Date")
        XCTAssertEqual(controller.headerTypeTextForTesting(column: 1), "Float")
        XCTAssertEqual(controller.headerTypeTextForTesting(column: 2), "Categorical")
        XCTAssertTrue(controller.headerDisplayTitleForTesting(column: 0)?.contains("Date") == true)
        XCTAssertTrue(controller.headerDisplayTitleForTesting(column: 1)?.contains("Float") == true)
        XCTAssertTrue(controller.headerDisplayTitleForTesting(column: 2)?.contains("Categorical") == true)
        XCTAssertTrue(controller.headerFilterAvailableForTesting(column: 0))
        XCTAssertFalse(controller.headerFilterAvailableForTesting(column: 1))
        XCTAssertTrue(controller.headerFilterAvailableForTesting(column: 2))
        XCTAssertEqual(controller.headerTooltipForTesting(column: 0), "visit_date\n\(L.t("Type: Date", "타입: Date"))")
    }

    func testLastCategoricalHeaderShowsFilterButtonWhenColumnsFillViewport() throws {
        _ = NSApplication.shared
        let path = try temporaryCsvPath()
        try """
        id,amount,site
        1,10,A
        2,20,B

        """.data(using: .utf8)!.write(to: URL(fileURLWithPath: path))
        defer { try? FileManager.default.removeItem(atPath: path) }

        let controller = MainWindowController()
        controller.showWindow(nil)
        defer { controller.close() }

        controller.openFileForTesting(URL(fileURLWithPath: path))
        try waitUntilColumnTypesReady(controller, column: 2)
        controller.layoutWindowForTesting()

        let filterFrame = try XCTUnwrap(controller.headerFilterFrameForTesting(column: 2))
        XCTAssertTrue(controller.headerFilterAvailableForTesting(column: 2))
        XCTAssertTrue(
            controller.headerVisibleRectForTesting.intersects(filterFrame),
            "filterFrame=\(filterFrame), visibleRect=\(controller.headerVisibleRectForTesting)"
        )
        XCTAssertLessThanOrEqual(
            filterFrame.maxX,
            controller.tableViewportWidthForTesting + 1,
            "filterFrame=\(filterFrame), viewportWidth=\(controller.tableViewportWidthForTesting)"
        )
        XCTAssertLessThan(
            filterFrame.minX,
            540,
            "filterFrame=\(filterFrame), viewportWidth=\(controller.tableViewportWidthForTesting), lastWidth=\(controller.tableColumnWidthForTesting(column: 2))"
        )
    }

    func testLastDateHeaderShowsFilterButtonAfterHorizontalScroll() throws {
        _ = NSApplication.shared
        let path = try temporaryCsvPath()
        let headers = ((0..<12).map { "field_\($0)" } + ["last_date"]).joined(separator: ",")
        let row1 = ((0..<12).map { "value_\($0)" } + ["2026-01-01"]).joined(separator: ",")
        let row2 = ((0..<12).map { "value_\($0 + 12)" } + ["2026-01-02"]).joined(separator: ",")
        try "\(headers)\n\(row1)\n\(row2)\n".data(using: .utf8)!.write(to: URL(fileURLWithPath: path))
        defer { try? FileManager.default.removeItem(atPath: path) }

        let controller = MainWindowController()
        controller.showWindow(nil)
        defer { controller.close() }

        controller.openFileForTesting(URL(fileURLWithPath: path))
        try waitUntilColumnTypesReady(controller, column: 12)
        controller.scrollColumnToVisibleForTesting(column: 12)
        controller.layoutWindowForTesting()

        let filterFrame = try XCTUnwrap(
            controller.headerFilterFrameForTesting(column: 12),
            "visibleRect=\(controller.headerVisibleRectForTesting), type=\(String(describing: controller.headerTypeTextForTesting(column: 12))), available=\(controller.headerFilterAvailableForTesting(column: 12))"
        )
        XCTAssertTrue(controller.headerFilterAvailableForTesting(column: 12))
        XCTAssertTrue(
            controller.headerVisibleRectForTesting.intersects(filterFrame),
            "filterFrame=\(filterFrame), visibleRect=\(controller.headerVisibleRectForTesting), documentWidth=\(controller.tableDocumentWidthForTesting), viewportWidth=\(controller.tableViewportWidthForTesting), lastWidth=\(controller.tableColumnWidthForTesting(column: 12))"
        )
    }

    func testGridHeaderViewStaysVisibleAfterOpeningFile() throws {
        _ = NSApplication.shared
        let path = try temporaryCsvPath()
        try """
        id,name,value
        1,Alice,10
        2,Bob,20

        """.data(using: .utf8)!.write(to: URL(fileURLWithPath: path))
        defer { try? FileManager.default.removeItem(atPath: path) }

        let controller = MainWindowController()
        controller.showWindow(nil)
        defer { controller.close() }

        controller.openFileForTesting(URL(fileURLWithPath: path))
        try waitUntilIndexed(controller)
        controller.layoutWindowForTesting()

        XCTAssertGreaterThan(controller.tableHeaderHeightForTesting, 0)
        XCTAssertEqual(controller.headerDisplayTitleForTesting(column: 0), "id")
    }

    func testGridColumnsExpandToFillViewportWhenFewColumns() throws {
        _ = NSApplication.shared
        let path = try temporaryCsvPath()
        try """
        id,name
        1,Alice

        """.data(using: .utf8)!.write(to: URL(fileURLWithPath: path))
        defer { try? FileManager.default.removeItem(atPath: path) }

        let controller = MainWindowController()
        controller.showWindow(nil)
        defer { controller.close() }

        controller.openFileForTesting(URL(fileURLWithPath: path))
        try waitUntilIndexed(controller)
        controller.layoutWindowForTesting()

        XCTAssertGreaterThanOrEqual(controller.tableDocumentWidthForTesting, controller.tableViewportWidthForTesting - 1)
        XCTAssertGreaterThan(controller.tableColumnWidthForTesting(column: 1), 150)
    }

    func testGridColumnsContinueExpandingAfterWindowResize() throws {
        _ = NSApplication.shared
        let path = try temporaryCsvPath()
        try """
        id,name
        1,Alice

        """.data(using: .utf8)!.write(to: URL(fileURLWithPath: path))
        defer { try? FileManager.default.removeItem(atPath: path) }

        let controller = MainWindowController()
        controller.showWindow(nil)
        defer { controller.close() }

        controller.openFileForTesting(URL(fileURLWithPath: path))
        try waitUntilIndexed(controller)
        controller.layoutWindowForTesting()

        let initialViewportWidth = controller.tableViewportWidthForTesting
        let initialDocumentWidth = controller.tableDocumentWidthForTesting
        guard let window = controller.window else {
            return XCTFail("Expected a window")
        }

        var frame = window.frame
        frame.size.width += 480
        window.setFrame(frame, display: true)
        window.layoutIfNeeded()
        window.contentView?.layoutSubtreeIfNeeded()
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))

        XCTAssertGreaterThan(controller.tableViewportWidthForTesting, initialViewportWidth + 300)
        XCTAssertGreaterThan(controller.tableDocumentWidthForTesting, initialDocumentWidth + 300)
        XCTAssertGreaterThanOrEqual(controller.tableDocumentWidthForTesting, controller.tableViewportWidthForTesting - 1)
        XCTAssertGreaterThanOrEqual(
            controller.tableColumnRectForTesting(column: 1).maxX,
            controller.tableViewportWidthForTesting - 33,
            "last data column must stretch to the viewport edge (minus the style's side inset)"
        )
    }

    func testLastColumnContinuesFillingViewportAfterWideResizeWithSeveralColumns() throws {
        _ = NSApplication.shared
        let path = try temporaryCsvPath()
        try """
        id,birth,mtb,ntm,sex,address
        A,1942-02-08,77.9,,M,광주광역시 서구

        """.data(using: .utf8)!.write(to: URL(fileURLWithPath: path))
        defer { try? FileManager.default.removeItem(atPath: path) }

        let controller = MainWindowController()
        controller.showWindow(nil)
        defer { controller.close() }

        controller.openFileForTesting(URL(fileURLWithPath: path))
        try waitUntilIndexed(controller)
        controller.layoutWindowForTesting()

        guard let window = controller.window else {
            return XCTFail("Expected a window")
        }
        var frame = window.frame
        frame.size.width += 820
        window.setFrame(frame, display: true)
        window.layoutIfNeeded()
        window.contentView?.layoutSubtreeIfNeeded()
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))

        XCTAssertGreaterThanOrEqual(
            controller.tableColumnRectForTesting(column: 5).maxX,
            controller.tableViewportWidthForTesting - 33,
            "lastRect=\(controller.tableColumnRectForTesting(column: 5)), viewport=\(controller.tableViewportWidthForTesting), lastWidth=\(controller.tableColumnWidthForTesting(column: 5))"
        )
    }

    func testGridKeepsHorizontalScrollerAvailableWhenManyColumnsOverflow() throws {
        _ = NSApplication.shared
        let path = try temporaryCsvPath()
        let headers = (0..<24).map { "field_\($0)" }.joined(separator: ",")
        let row = (0..<24).map(String.init).joined(separator: ",")
        try "\(headers)\n\(row)\n".data(using: .utf8)!.write(to: URL(fileURLWithPath: path))
        defer { try? FileManager.default.removeItem(atPath: path) }

        let controller = MainWindowController()
        controller.showWindow(nil)
        defer { controller.close() }

        controller.openFileForTesting(URL(fileURLWithPath: path))
        try waitUntilIndexed(controller)
        controller.layoutWindowForTesting()

        XCTAssertTrue(controller.horizontalScrollerConfiguredForTesting)
        XCTAssertGreaterThan(controller.tableDocumentWidthForTesting, controller.tableViewportWidthForTesting + 1)
    }

    func testHorizontalScrollMovesHeaderAndBodyTogetherWhenColumnsOverflow() throws {
        _ = NSApplication.shared
        let path = try temporaryCsvPath()
        let headers = (0..<24).map { "field_\($0)" }.joined(separator: ",")
        let row = (0..<24).map(String.init).joined(separator: ",")
        try "\(headers)\n\(row)\n".data(using: .utf8)!.write(to: URL(fileURLWithPath: path))
        defer { try? FileManager.default.removeItem(atPath: path) }

        let controller = MainWindowController()
        controller.showWindow(nil)
        defer { controller.close() }

        controller.openFileForTesting(URL(fileURLWithPath: path))
        try waitUntilIndexed(controller)
        controller.layoutWindowForTesting()
        XCTAssertTrue(controller.horizontalScrollerConfiguredForTesting)

        controller.scrollGridHorizontallyForTesting(to: 480)
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))

        XCTAssertGreaterThan(controller.tableVisibleRectForTesting.minX, 300)
        XCTAssertEqual(
            controller.headerVisibleRectForTesting.minX,
            controller.tableVisibleRectForTesting.minX,
            accuracy: 0.5,
            "headerVisible=\(controller.headerVisibleRectForTesting), tableVisible=\(controller.tableVisibleRectForTesting)"
        )
    }

    func testHorizontalScrollDoesNotRecomputeGridLayoutWhenColumnsOverflow() throws {
        _ = NSApplication.shared
        let path = try temporaryCsvPath()
        let headers = (0..<24).map { "field_\($0)" }.joined(separator: ",")
        let row = (0..<24).map(String.init).joined(separator: ",")
        try "\(headers)\n\(row)\n".data(using: .utf8)!.write(to: URL(fileURLWithPath: path))
        defer { try? FileManager.default.removeItem(atPath: path) }

        let controller = MainWindowController()
        controller.showWindow(nil)
        defer { controller.close() }

        controller.openFileForTesting(URL(fileURLWithPath: path))
        try waitUntilIndexed(controller)
        controller.layoutWindowForTesting()
        XCTAssertTrue(controller.horizontalScrollerConfiguredForTesting)

        let layoutPassCount = controller.gridLayoutPassCountForTesting
        let documentWidth = controller.tableDocumentWidthForTesting
        let firstColumnWidth = controller.tableColumnWidthForTesting(column: 0)

        controller.scrollGridHorizontallyForTesting(to: 480)
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))

        XCTAssertEqual(controller.gridLayoutPassCountForTesting, layoutPassCount)
        XCTAssertEqual(controller.tableDocumentWidthForTesting, documentWidth, accuracy: 0.5)
        XCTAssertEqual(controller.tableColumnWidthForTesting(column: 0), firstColumnWidth, accuracy: 0.5)
    }

    func testGridShowsHorizontalScrollerWhenColumnResizeCreatesOverflow() throws {
        _ = NSApplication.shared
        let path = try temporaryCsvPath()
        try """
        id,name
        1,Alice

        """.data(using: .utf8)!.write(to: URL(fileURLWithPath: path))
        defer { try? FileManager.default.removeItem(atPath: path) }

        let controller = MainWindowController()
        controller.showWindow(nil)
        defer { controller.close() }

        controller.openFileForTesting(URL(fileURLWithPath: path))
        try waitUntilIndexed(controller)
        controller.layoutWindowForTesting()
        XCTAssertFalse(controller.horizontalScrollerConfiguredForTesting)

        controller.setTableColumnWidthForTesting(column: 0, width: controller.tableViewportWidthForTesting)
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))

        XCTAssertTrue(controller.horizontalScrollerConfiguredForTesting)
        XCTAssertGreaterThan(controller.tableDocumentWidthForTesting, controller.tableViewportWidthForTesting + 1)
    }

    func testGridHidesHorizontalScrollerWhenColumnsFitViewport() throws {
        _ = NSApplication.shared
        let path = try temporaryCsvPath()
        try """
        id,name
        1,Alice

        """.data(using: .utf8)!.write(to: URL(fileURLWithPath: path))
        defer { try? FileManager.default.removeItem(atPath: path) }

        let controller = MainWindowController()
        controller.showWindow(nil)
        defer { controller.close() }

        controller.openFileForTesting(URL(fileURLWithPath: path))
        try waitUntilIndexed(controller)
        controller.layoutWindowForTesting()

        XCTAssertFalse(controller.horizontalScrollerConfiguredForTesting)
        XCTAssertGreaterThanOrEqual(controller.tableDocumentWidthForTesting, controller.tableViewportWidthForTesting - 1)
    }

    func testGridHidesHorizontalScrollerAfterResizeMakesColumnsFit() throws {
        _ = NSApplication.shared
        let path = try temporaryCsvPath()
        let headers = (0..<8).map { "field_\($0)" }.joined(separator: ",")
        let row = (0..<8).map(String.init).joined(separator: ",")
        try "\(headers)\n\(row)\n".data(using: .utf8)!.write(to: URL(fileURLWithPath: path))
        defer { try? FileManager.default.removeItem(atPath: path) }

        let controller = MainWindowController()
        controller.showWindow(nil)
        defer { controller.close() }

        controller.openFileForTesting(URL(fileURLWithPath: path))
        try waitUntilIndexed(controller)
        guard let window = controller.window else {
            return XCTFail("Expected a window")
        }

        var narrowFrame = window.frame
        narrowFrame.size.width = 720
        window.setFrame(narrowFrame, display: true)
        window.layoutIfNeeded()
        window.contentView?.layoutSubtreeIfNeeded()
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        XCTAssertTrue(controller.horizontalScrollerConfiguredForTesting)

        var wideFrame = window.frame
        wideFrame.size.width = 1_720
        window.setFrame(wideFrame, display: true)
        window.layoutIfNeeded()
        window.contentView?.layoutSubtreeIfNeeded()
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))

        XCTAssertFalse(controller.horizontalScrollerConfiguredForTesting)
        XCTAssertGreaterThanOrEqual(controller.tableDocumentWidthForTesting, controller.tableViewportWidthForTesting - 1)
    }

    func testGridHeaderTypesClearWhenOpeningAnotherFile() throws {
        _ = NSApplication.shared
        let firstPath = try temporaryCsvPath()
        let secondPath = try temporaryCsvPath()
        try "visit_date,amount\n2026.01.02,10\n".data(using: .utf8)!.write(to: URL(fileURLWithPath: firstPath))
        try "name,note\nAlice,hello\n".data(using: .utf8)!.write(to: URL(fileURLWithPath: secondPath))
        defer {
            try? FileManager.default.removeItem(atPath: firstPath)
            try? FileManager.default.removeItem(atPath: secondPath)
        }

        let controller = MainWindowController()
        controller.showWindow(nil)
        defer { controller.close() }

        controller.openFileForTesting(URL(fileURLWithPath: firstPath))
        try waitUntilColumnTypesReady(controller)
        XCTAssertEqual(controller.headerTypeTextForTesting(column: 0), "Date")

        controller.openFileForTesting(URL(fileURLWithPath: secondPath))

        XCTAssertNil(controller.headerTypeTextForTesting(column: 0))
        XCTAssertEqual(controller.headerDisplayTitleForTesting(column: 0), "name")
        XCTAssertNil(controller.headerTooltipForTesting(column: 0))
    }

    func testCloseCurrentDocumentClearsGridAndDisablesDocumentActions() throws {
        _ = NSApplication.shared
        let path = try temporaryCsvPath()
        try """
        id,name
        1,Alice
        2,Bob

        """.data(using: .utf8)!.write(to: URL(fileURLWithPath: path))
        defer { try? FileManager.default.removeItem(atPath: path) }

        let controller = MainWindowController()
        controller.showWindow(nil)
        defer { controller.close() }

        controller.openFileForTesting(URL(fileURLWithPath: path))
        try waitUntilIndexed(controller)
        XCTAssertEqual(controller.renderedRowCountForTesting, 2)

        let selector = NSSelectorFromString("closeCurrentDocument:")
        guard controller.responds(to: selector) else {
            XCTFail("MainWindowController should expose closeCurrentDocument:")
            return
        }
        controller.perform(selector, with: nil)

        XCTAssertFalse(controller.indexingCompleteForTesting)
        XCTAssertEqual(controller.renderedRowCountForTesting, 0)
        XCTAssertNil(controller.headerDisplayTitleForTesting(column: 0))
        XCTAssertNil(controller.makePivotBuilderForTesting())

        let exportItem = NSMenuItem(title: "", action: #selector(MainWindowController.exportCurrentView(_:)), keyEquivalent: "")
        let pivotItem = NSMenuItem(title: "", action: #selector(MainWindowController.showPivotTable(_:)), keyEquivalent: "")
        XCTAssertFalse(controller.validateMenuItem(exportItem))
        XCTAssertFalse(controller.validateMenuItem(pivotItem))
    }

    func testCloseCurrentDocumentDeletesIndexCacheWhenEnabled() throws {
        _ = NSApplication.shared
        let path = try temporaryCsvPath()
        let cacheDirectory = try temporaryDirectory()
        VirtualCsvDocument.persistentIndexDirectoryOverride = URL(fileURLWithPath: cacheDirectory, isDirectory: true)
        try """
        id,name
        1,Alice
        2,Bob

        """.data(using: .utf8)!.write(to: URL(fileURLWithPath: path))
        defer {
            VirtualCsvDocument.persistentIndexDirectoryOverride = nil
            VirtualCsvDocument.deletePersistentIndexOnClose = false
            try? FileManager.default.removeItem(atPath: path)
            try? FileManager.default.removeItem(atPath: cacheDirectory)
        }

        let controller = MainWindowController()
        VirtualCsvDocument.deletePersistentIndexOnClose = true
        controller.showWindow(nil)
        defer { controller.close() }

        controller.openFileForTesting(URL(fileURLWithPath: path))
        try waitUntilIndexed(controller)

        let sidecarURL = VirtualCsvDocument.persistentIndexURL(forCSVAt: path)
        try waitUntilFileExists(atPath: sidecarURL.path)

        controller.closeCurrentDocument(nil)

        XCTAssertFalse(FileManager.default.fileExists(atPath: sidecarURL.path))
    }

    func testToolbarContainsCloseAndPivotCommands() throws {
        _ = NSApplication.shared
        let controller = MainWindowController()
        controller.showWindow(nil)
        defer { controller.close() }

        let toolbar = try XCTUnwrap(controller.window?.toolbar)
        let identifiers = controller.toolbarDefaultItemIdentifiers(toolbar)
        let closeIdentifier = NSToolbarItem.Identifier("closeDocument")
        let pivotIdentifier = NSToolbarItem.Identifier("pivot")

        XCTAssertTrue(identifiers.contains(closeIdentifier))
        XCTAssertTrue(identifiers.contains(pivotIdentifier))

        let closeItem = try XCTUnwrap(controller.toolbar(toolbar, itemForItemIdentifier: closeIdentifier, willBeInsertedIntoToolbar: true))
        XCTAssertEqual(closeItem.action, NSSelectorFromString("closeCurrentDocument:"))
        XCTAssertNotNil(closeItem.image)

        let pivotItem = try XCTUnwrap(controller.toolbar(toolbar, itemForItemIdentifier: pivotIdentifier, willBeInsertedIntoToolbar: true))
        XCTAssertEqual(pivotItem.action, #selector(MainWindowController.showPivotTable(_:)))
        XCTAssertNotNil(pivotItem.image)
    }

    func testAnalysisParameterSheetsHaveRoomForFieldsAndButtons() throws {
        _ = NSApplication.shared
        let path = try temporaryCsvPath()
        try """
        group,visit_date,amount,score
        A,2026.01.02,10,1
        B,2026.02.03,12,2
        A,2026.03.04,14,3
        B,2026.04.05,16,4

        """.data(using: .utf8)!.write(to: URL(fileURLWithPath: path))
        defer { try? FileManager.default.removeItem(atPath: path) }

        let controller = MainWindowController()
        controller.showWindow(nil)
        defer { controller.close() }

        controller.openFileForTesting(URL(fileURLWithPath: path))
        try waitUntilColumnTypesReady(controller, column: 1)

        let expectedRows: [AnalysisKind: Int] = [
            .numericDistribution: 2,
            .dateHistogram: 3,
            .duplicateRows: 2,
            .groupBy: 3,
            .correlation: 2,
            .independentTTest: 4,
            .chiSquare: 2
        ]

        for kind in expectedRows.keys {
            let metrics = try XCTUnwrap(controller.analysisPromptLayoutMetricsForTesting(kind))
            XCTAssertGreaterThanOrEqual(metrics.windowSize.width, 560, "\(kind)")
            XCTAssertGreaterThanOrEqual(metrics.windowSize.height, 280, "\(kind)")
            XCTAssertEqual(metrics.rowCount, expectedRows[kind], "\(kind)")
            XCTAssertGreaterThanOrEqual(metrics.minimumPopupWidth, 320, "\(kind)")
            XCTAssertGreaterThanOrEqual(metrics.runButtonSize.width, 88, "\(kind)")
            XCTAssertGreaterThanOrEqual(metrics.cancelButtonSize.width, 88, "\(kind)")
        }
    }

    func testDateHistogramUsesInferredDateColumnWhenSelectionIsNotDate() throws {
        _ = NSApplication.shared
        let path = try temporaryCsvPath()
        try """
        site,visit_date,amount
        A,2026.01.02,10
        B,2026.02.03,12

        """.data(using: .utf8)!.write(to: URL(fileURLWithPath: path))
        defer { try? FileManager.default.removeItem(atPath: path) }

        let controller = MainWindowController()
        controller.showWindow(nil)
        defer { controller.close() }

        controller.openFileForTesting(URL(fileURLWithPath: path))
        try waitUntilColumnTypesReady(controller, column: 1)

        controller.selectCellForTesting(row: 0, column: 0)
        controller.showDateHistogram(nil)
        try waitUntilAnalysisReady(controller)

        XCTAssertEqual(controller.detailHeaderTextForTesting, L.t("Date Histogram", "날짜 히스토그램"))
        XCTAssertTrue(controller.detailTextForTesting.contains("visit_date"))
        XCTAssertTrue(controller.detailTextForTesting.contains("2026-01"))
        XCTAssertTrue(controller.detailTextForTesting.contains("2026-02"))
    }

    func testAnalysisReportIncludesProvenanceAndCanBeCopied() throws {
        _ = NSApplication.shared
        let path = try temporaryCsvPath()
        try """
        site,amount
        A,10
        B,20
        C,30

        """.data(using: .utf8)!.write(to: URL(fileURLWithPath: path))
        defer { try? FileManager.default.removeItem(atPath: path) }

        let controller = MainWindowController()
        controller.showWindow(nil)
        defer { controller.close() }

        controller.openFileForTesting(URL(fileURLWithPath: path))
        try waitUntilIndexed(controller)

        controller.performAnalysisForTesting(.numericDistribution(column: 1, binCount: 2))
        try waitUntilAnalysisReady(controller)

        XCTAssertEqual(controller.detailHeaderTextForTesting, L.t("Numeric Distribution", "숫자 분포"))
        XCTAssertTrue(controller.analysisReportTextForTesting.contains(L.t("Rows: 3 / 3", "행: 3 / 3")))
        XCTAssertTrue(controller.analysisReportTextForTesting.contains(L.t("Columns: amount", "컬럼: amount")))
        XCTAssertTrue(controller.analysisReportTextForTesting.contains(L.t("Column: amount", "컬럼: amount")))
        XCTAssertTrue(controller.analysisReportTextForTesting.contains(L.t("Histogram", "히스토그램")))

        NSPasteboard.general.clearContents()
        controller.copyAnalysisResult(nil)
        let copied = try XCTUnwrap(NSPasteboard.general.string(forType: .string))
        XCTAssertTrue(copied.contains(L.t("Numeric Distribution", "숫자 분포")))
        XCTAssertTrue(copied.contains("amount"))
    }

    func testQuickStatsAnalysisShowsDocumentSummaryInsteadOfSelectedColumnStats() throws {
        _ = NSApplication.shared
        let path = try temporaryCsvPath()
        try """
        site,visit_date,amount
        A,2026.01.02,10
        B,2026.02.03,12

        """.data(using: .utf8)!.write(to: URL(fileURLWithPath: path))
        defer { try? FileManager.default.removeItem(atPath: path) }

        let controller = MainWindowController()
        controller.showWindow(nil)
        defer { controller.close() }

        controller.openFileForTesting(URL(fileURLWithPath: path))
        try waitUntilColumnTypesReady(controller, column: 1)

        controller.performAnalysisForTesting(.documentSummary)
        try waitUntilAnalysisReady(controller)

        XCTAssertEqual(controller.detailHeaderTextForTesting, L.t("Quick Stats", "빠른 통계"))
        XCTAssertTrue(controller.analysisReportTextForTesting.contains(L.t("Rows: 2 / 2", "행: 2 / 2")))
        XCTAssertTrue(controller.analysisReportTextForTesting.contains(L.t("Columns: All columns (3)", "컬럼: 전체 컬럼 (3)")))
        XCTAssertTrue(controller.analysisReportTextForTesting.contains(L.t("Columns: 3", "컬럼: 3")))
        XCTAssertTrue(controller.analysisReportTextForTesting.contains("visit_date"))
        XCTAssertFalse(controller.analysisReportTextForTesting.hasPrefix("site\n\n"))
    }

    func testAnalysisReportCsvTsvJsonAndMarkdownExportsUseDistinctFormats() throws {
        let provenance = AnalysisProvenance(
            visibleRows: 2,
            totalRows: 2,
            isFiltered: false,
            filters: [],
            sortDescription: nil,
            columnNames: ["amount"],
            parameterLines: [L.t("Column: amount", "컬럼: amount")],
            generatedAt: Date(timeIntervalSince1970: 0),
            elapsedMilliseconds: 4
        )
        let report = AnalysisReport(
            title: "Export Test",
            summary: "Values",
            provenance: provenance,
            sections: [
                .table(AnalysisTable(
                    title: "Rows",
                    headers: ["name", "value"],
                    rows: [["A,B", "10"], ["Quote \"Q\"", "20"]],
                    truncated: false
                ))
            ]
        )

        XCTAssertTrue(report.markdown.contains("| name | value |"))
        XCTAssertTrue(report.tsv.contains("A,B\t10"))
        XCTAssertTrue(report.csv.contains("\"A,B\",10"))
        XCTAssertTrue(report.csv.contains("\"Quote \"\"Q\"\"\",20"))

        let json = try JSONSerialization.jsonObject(with: report.jsonData()) as? [String: Any]
        XCTAssertEqual(json?["title"] as? String, "Export Test")
    }

    func testEarlyColumnStatisticsStartsAfterRowsArriveBeforeIndexingCompletes() {
        XCTAssertFalse(MainWindowController.shouldStartEarlyColumnStatistics(
            availableRows: 199,
            indexingComplete: false,
            alreadyRequested: false,
            hasReport: false
        ))
        XCTAssertTrue(MainWindowController.shouldStartEarlyColumnStatistics(
            availableRows: 200,
            indexingComplete: false,
            alreadyRequested: false,
            hasReport: false
        ))
        XCTAssertFalse(MainWindowController.shouldStartEarlyColumnStatistics(
            availableRows: 200,
            indexingComplete: true,
            alreadyRequested: false,
            hasReport: false
        ))
        XCTAssertFalse(MainWindowController.shouldStartEarlyColumnStatistics(
            availableRows: 200,
            indexingComplete: false,
            alreadyRequested: true,
            hasReport: false
        ))
        XCTAssertFalse(MainWindowController.shouldStartEarlyColumnStatistics(
            availableRows: 200,
            indexingComplete: false,
            alreadyRequested: false,
            hasReport: true
        ))
    }

    func testTableFrameContainsLastColumnUnderDefaultIntercellSpacing() throws {
        _ = NSApplication.shared
        let controller = try openWideGridController()
        defer { controller.close() }

        let lastRect = controller.tableColumnRectForTesting(column: 7)
        XCTAssertFalse(lastRect.isNull)
        XCTAssertLessThanOrEqual(
            lastRect.maxX,
            controller.tableDocumentWidthForTesting + 0.5,
            "last data column extends past the table frame by \(lastRect.maxX - controller.tableDocumentWidthForTesting)pt with intercellSpacing \(controller.tableIntercellSpacingForTesting); horizontal scrolling cannot reach the end of the grid"
        )
    }

    func testHeaderFilterHitResolvesCorrectDataColumnUnderDefaultIntercellSpacing() throws {
        _ = NSApplication.shared
        let controller = try openWideGridController()
        defer { controller.close() }
        try waitUntilColumnTypesReady(controller, column: 6)
        controller.layoutWindowForTesting()

        XCTAssertEqual(
            controller.headerFilterHitDataColumnForTesting(column: 6), 6,
            "clicking the filter icon of data column 6 must resolve to column 6 under intercellSpacing \(controller.tableIntercellSpacingForTesting)"
        )
        XCTAssertEqual(controller.headerFilterHitDataColumnForTesting(column: 2), 2)
    }

    func testHorizontalScrollerEnabledWhenNaturalWidthOverflowsViewport() throws {
        _ = NSApplication.shared
        let controller = try openWideGridController()
        defer { controller.close() }

        XCTAssertTrue(
            controller.horizontalScrollerConfiguredForTesting,
            "8 columns x 220pt exceed the viewport; the horizontal scroller must be enabled"
        )
        XCTAssertGreaterThanOrEqual(
            controller.tableDocumentWidthForTesting,
            controller.tableColumnRectForTesting(column: 7).maxX - 0.5,
            "scrollable range must cover the last data column"
        )
    }

    func testColumnTypeOverrideUpdatesHeaderBadgeAndReverts() throws {
        _ = NSApplication.shared
        let path = try temporaryCsvPath()
        try """
        id,name
        1,Alice
        2,Bob
        3,Cara

        """.data(using: .utf8)!.write(to: URL(fileURLWithPath: path))
        defer { try? FileManager.default.removeItem(atPath: path) }

        let controller = MainWindowController()
        controller.showWindow(nil)
        defer { controller.close() }

        controller.openFileForTesting(URL(fileURLWithPath: path))
        try waitUntilColumnTypesReady(controller, column: 0)
        XCTAssertEqual(controller.headerTypeTextForTesting(column: 0), "Integer")

        controller.setColumnTypeOverrideForTesting(column: 0, type: .string)
        XCTAssertEqual(controller.headerTypeTextForTesting(column: 0), "String")
        XCTAssertEqual(controller.columnTypeOverridesForTesting, [0: "String"])

        controller.setColumnTypeOverrideForTesting(column: 0, type: nil)
        XCTAssertEqual(controller.headerTypeTextForTesting(column: 0), "Integer")
        XCTAssertTrue(controller.columnTypeOverridesForTesting.isEmpty)
    }

    func testColumnTypeChangeBlocksLossyFloatToInteger() throws {
        _ = NSApplication.shared
        let path = try temporaryCsvPath()
        try """
        score,name
        1.5,Alice
        2.25,Bob

        """.data(using: .utf8)!.write(to: URL(fileURLWithPath: path))
        defer { try? FileManager.default.removeItem(atPath: path) }

        let controller = MainWindowController()
        controller.showWindow(nil)
        defer { controller.close() }

        controller.openFileForTesting(URL(fileURLWithPath: path))
        try waitUntilColumnTypesReady(controller, column: 0)
        XCTAssertEqual(controller.headerTypeTextForTesting(column: 0), "Float")

        controller.requestColumnTypeChangeForTesting(column: 0, to: .integer)
        XCTAssertEqual(controller.headerTypeTextForTesting(column: 0), "Float", "lossy Float→Integer must be blocked")
        XCTAssertTrue(controller.columnTypeOverridesForTesting.isEmpty)
    }

    private func openWideGridController() throws -> MainWindowController {
        let path = try temporaryCsvPath()
        let header = (0..<8).map { "col\($0)" }.joined(separator: ",")
        let row = (0..<8).map { "value\($0)" }.joined(separator: ",")
        try "\(header)\n\(row)\n\(row)\n".data(using: .utf8)!.write(to: URL(fileURLWithPath: path))
        defer { try? FileManager.default.removeItem(atPath: path) }

        let controller = MainWindowController()
        controller.showWindow(nil)
        controller.openFileForTesting(URL(fileURLWithPath: path))
        try waitUntilIndexed(controller)

        for column in 0..<8 {
            controller.setTableColumnWidthForTesting(column: column, width: 220)
        }
        controller.layoutWindowForTesting()
        return controller
    }

    private func waitUntilIndexed(_ controller: MainWindowController, file: StaticString = #filePath, line: UInt = #line) throws {
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
            if controller.indexingCompleteForTesting, controller.renderedRowCountForTesting > 0 {
                return
            }
        }
        XCTFail("Timed out waiting for indexing", file: file, line: line)
    }

    private func waitUntilNotBusy(_ controller: MainWindowController, file: StaticString = #filePath, line: UInt = #line) throws {
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
            if !controller.busyForTesting {
                return
            }
        }
        XCTFail("Timed out waiting for operation", file: file, line: line)
    }

    private func waitUntilColumnTypesReady(_ controller: MainWindowController, column: Int = 0, file: StaticString = #filePath, line: UInt = #line) throws {
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
            if controller.headerTypeTextForTesting(column: column) != nil {
                return
            }
        }
        XCTFail("Timed out waiting for column types", file: file, line: line)
    }

    private func waitUntilAnalysisReady(_ controller: MainWindowController, file: StaticString = #filePath, line: UInt = #line) throws {
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
            if controller.analysisReportTextForTesting.isEmpty == false {
                return
            }
        }
        XCTFail("Timed out waiting for analysis result", file: file, line: line)
    }

    private func temporaryCsvPath() throws -> String {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return directory.appendingPathComponent("nanumcsv_grid_\(UUID().uuidString).csv").path
    }

    private func temporaryDirectory() throws -> String {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("nanumcsv_grid_dir_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.path
    }

    private func waitUntilFileExists(atPath path: String, file: StaticString = #filePath, line: UInt = #line) throws {
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
            if FileManager.default.fileExists(atPath: path) {
                return
            }
        }
        XCTFail("Timed out waiting for file at \(path)", file: file, line: line)
    }
}
