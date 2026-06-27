import AppKit
@preconcurrency import CsvCore
import XCTest
@testable import NanumCsvViewerMac

@MainActor
final class MainWindowControllerGridTests: XCTestCase {
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
        XCTAssertEqual(controller.headerTooltipForTesting(column: 0), "visit_date\n\(L.t("Type: Date", "타입: Date"))")
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
