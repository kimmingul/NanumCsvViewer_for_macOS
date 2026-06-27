import AppKit
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

        XCTAssertEqual(controller.detailHeaderTextForTesting, L.t("Date Histogram", "날짜 히스토그램"))
        XCTAssertTrue(controller.detailTextForTesting.contains("visit_date"))
        XCTAssertTrue(controller.detailTextForTesting.contains("2026-01"))
        XCTAssertTrue(controller.detailTextForTesting.contains("2026-02"))
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

    private func temporaryCsvPath() throws -> String {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return directory.appendingPathComponent("nanumcsv_grid_\(UUID().uuidString).csv").path
    }
}
