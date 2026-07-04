import AppKit
import XCTest
@testable import NanumCsvViewerMac

final class ColumnManagementTests: XCTestCase {
    func testExportOrderIsNilWhenNaturalFullOrder() {
        XCTAssertNil(ColumnManagement.exportColumnOrder(visualDataColumns: [0, 1, 2], hidden: [], totalColumns: 3))
    }

    func testExportOrderReflectsReordering() {
        XCTAssertEqual(
            ColumnManagement.exportColumnOrder(visualDataColumns: [2, 0, 1], hidden: [], totalColumns: 3),
            [2, 0, 1]
        )
    }

    func testExportOrderExcludesHiddenColumnsInVisualOrder() {
        XCTAssertEqual(
            ColumnManagement.exportColumnOrder(visualDataColumns: [2, 0, 1], hidden: [0], totalColumns: 3),
            [2, 1]
        )
    }

    func testNormalizedOrderDropsInvalidAndAppendsMissing() {
        XCTAssertEqual(
            ColumnManagement.normalizedOrder(stored: [2, 9, 2, 0], totalColumns: 4),
            [2, 0, 1, 3],
            "invalid/duplicate indices dropped, columns absent from the stored order appended in source order"
        )
    }

    func testNormalizedOrderIdentityWhenComplete() {
        XCTAssertEqual(ColumnManagement.normalizedOrder(stored: [0, 1, 2], totalColumns: 3), [0, 1, 2])
    }
}

@MainActor
final class ColumnManagementControllerTests: XCTestCase {
    private let orderKey = "NanumCsvViewerMac.ColumnOrderByPath"
    private let hiddenKey = "NanumCsvViewerMac.HiddenColumnIndexes"
    private var savedDefaults: [String: Any?] = [:]

    override func setUp() {
        super.setUp()
        for key in [orderKey, hiddenKey] {
            savedDefaults[key] = UserDefaults.standard.object(forKey: key)
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    override func tearDown() {
        for (key, value) in savedDefaults {
            if let value { UserDefaults.standard.set(value, forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) }
        }
        super.tearDown()
    }

    func testReorderingColumnsChangesExportOrder() throws {
        let controller = try openController(csv: "a,b,c\n1,2,3\n")
        defer { controller.close() }

        XCTAssertNil(controller.exportColumnOrderForTesting(), "unchanged grid exports all columns in source order")

        controller.moveDataColumnForTesting(from: 2, to: 0)
        XCTAssertEqual(controller.exportColumnOrderForTesting(), [2, 0, 1])
    }

    func testColumnReorderPersistsAcrossReopen() throws {
        let path = try temporaryCsvPath()
        try "a,b,c\n1,2,3\n".data(using: .utf8)!.write(to: URL(fileURLWithPath: path))
        addTeardownBlock { try? FileManager.default.removeItem(atPath: path) }

        let first = MainWindowController()
        first.showWindow(nil)
        first.openFileForTesting(URL(fileURLWithPath: path))
        try waitUntilIndexed(first)
        first.moveDataColumnForTesting(from: 2, to: 0)
        first.close()

        let second = MainWindowController()
        second.showWindow(nil)
        defer { second.close() }
        second.openFileForTesting(URL(fileURLWithPath: path))
        try waitUntilIndexed(second)

        XCTAssertEqual(second.visualDataColumnOrderForTesting, [2, 0, 1], "reorder restored on reopen")
    }

    func testColumnChecklistTogglesVisibility() throws {
        let controller = try openController(csv: "a,b,c\n1,2,3\n")
        defer { controller.close() }

        let menu = NSMenu()
        controller.populateColumnsMenuForTesting(menu)
        XCTAssertEqual(menu.items.map(\.title), ["a", "b", "c"])
        XCTAssertTrue(menu.items.allSatisfy { $0.state == .on })

        controller.toggleColumnVisibilityForTesting(1)
        XCTAssertTrue(controller.isColumnHiddenForTesting(1))

        let refreshed = NSMenu()
        controller.populateColumnsMenuForTesting(refreshed)
        XCTAssertEqual(refreshed.items[1].state, .off)
    }

    // MARK: - Helpers

    private func openController(csv: String) throws -> MainWindowController {
        let path = try temporaryCsvPath()
        try csv.data(using: .utf8)!.write(to: URL(fileURLWithPath: path))
        addTeardownBlock { try? FileManager.default.removeItem(atPath: path) }
        let controller = MainWindowController()
        controller.showWindow(nil)
        controller.openFileForTesting(URL(fileURLWithPath: path))
        try waitUntilIndexed(controller)
        return controller
    }

    private func waitUntilIndexed(_ controller: MainWindowController, file: StaticString = #filePath, line: UInt = #line) throws {
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
            if controller.indexingCompleteForTesting, controller.renderedRowCountForTesting > 0 { return }
        }
        XCTFail("Timed out waiting for indexing", file: file, line: line)
    }

    private func temporaryCsvPath() throws -> String {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return directory.appendingPathComponent("nanumcsv_colmgmt_\(UUID().uuidString).csv").path
    }
}
