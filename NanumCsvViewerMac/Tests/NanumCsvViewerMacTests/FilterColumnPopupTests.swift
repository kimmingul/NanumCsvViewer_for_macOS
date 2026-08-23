import XCTest
import AppKit
@testable import NanumCsvViewerMac

/// `NSPopUpButton.addItem(withTitle:)` removes any existing item carrying the same
/// title, so a CSV whose headers repeat used to collapse the filter column list and
/// shift every position-derived column index. These tests pin the popup to the real
/// column indexes instead of item positions.
@MainActor
final class FilterColumnPopupTests: XCTestCase {
    private func temporaryCsvPath() throws -> String {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return directory.appendingPathComponent("nanumcsv_filtercol_\(UUID().uuidString).csv").path
    }

    private func waitUntilIndexed(_ controller: MainWindowController, file: StaticString = #filePath, line: UInt = #line) throws {
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
            if controller.indexingCompleteForTesting, controller.renderedRowCountForTesting > 0 { return }
        }
        XCTFail("Timed out waiting for indexing", file: file, line: line)
    }

    private func makeController(headers: String, rows: String) throws -> (MainWindowController, String) {
        _ = NSApplication.shared
        let path = try temporaryCsvPath()
        try "\(headers)\n\(rows)\n".data(using: .utf8)!.write(to: URL(fileURLWithPath: path))
        let controller = MainWindowController()
        controller.showWindow(nil)
        controller.openFileForTesting(URL(fileURLWithPath: path))
        try waitUntilIndexed(controller)
        return (controller, path)
    }

    func testDuplicateHeadersKeepOneFilterItemPerColumn() throws {
        let (controller, path) = try makeController(
            headers: "id,name,id,value,name",
            rows: "1,a,2,x,b"
        )
        defer {
            controller.close()
            try? FileManager.default.removeItem(atPath: path)
        }

        let titles = controller.filterColumnTitlesForTesting
        XCTAssertEqual(
            titles.count, 6,
            "one item per column plus All Columns; duplicate titles must not collapse the list"
        )
        XCTAssertEqual(Array(titles.dropFirst()), ["id", "name", "id", "value", "name"])
    }

    func testEveryFilterItemResolvesToItsOwnColumn() throws {
        let (controller, path) = try makeController(
            headers: "id,name,id,value,name",
            rows: "1,a,2,x,b"
        )
        defer {
            controller.close()
            try? FileManager.default.removeItem(atPath: path)
        }

        // Item 0 is "All Columns" and means "no specific column".
        XCTAssertEqual(controller.filterColumnForTesting(itemIndex: 0), -1)

        for column in 0..<5 {
            XCTAssertEqual(
                controller.filterColumnForTesting(itemIndex: column + 1), column,
                "item \(column + 1) must select column \(column)"
            )
        }
    }

    func testSelectingAColumnRoundTripsThroughThePopup() throws {
        let (controller, path) = try makeController(
            headers: "id,name,id,value,name",
            rows: "1,a,2,x,b"
        )
        defer {
            controller.close()
            try? FileManager.default.removeItem(atPath: path)
        }

        for column in 0..<5 {
            controller.selectFilterColumnForTesting(column)
            XCTAssertEqual(
                controller.selectedFilterColumnForTesting, column,
                "selecting column \(column) must read back as column \(column)"
            )
        }

        controller.selectFilterColumnForTesting(-1)
        XCTAssertEqual(controller.selectedFilterColumnForTesting, -1)
    }

    func testOutOfRangeColumnFallsBackToAllColumns() throws {
        let (controller, path) = try makeController(headers: "a,b", rows: "1,2")
        defer {
            controller.close()
            try? FileManager.default.removeItem(atPath: path)
        }

        // A saved view recorded against a wider file must not select a stale item.
        controller.selectFilterColumnForTesting(9)
        XCTAssertEqual(controller.selectedFilterColumnForTesting, -1)
    }

    func testClosingTheDocumentLeavesOnlyAllColumns() throws {
        let (controller, path) = try makeController(headers: "a,b", rows: "1,2")
        defer {
            controller.close()
            try? FileManager.default.removeItem(atPath: path)
        }

        controller.closeCurrentDocument(nil)
        XCTAssertEqual(controller.filterColumnTitlesForTesting.count, 1)
        XCTAssertEqual(controller.selectedFilterColumnForTesting, -1)
    }
}
