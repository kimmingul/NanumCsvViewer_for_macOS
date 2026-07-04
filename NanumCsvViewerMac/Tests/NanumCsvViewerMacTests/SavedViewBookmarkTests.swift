import AppKit
@preconcurrency import CsvCore
import XCTest
@testable import NanumCsvViewerMac

@MainActor
final class SavedViewBookmarkTests: XCTestCase {
    private let storeKey = "NanumCsvViewerMac.SavedViewStore"
    private let legacyKey = "NanumCsvViewerMac.SavedViewsByPath"
    private let autoKey = "NanumCsvViewerMac.AutoRestoreView"
    private let hiddenColumnsKey = "NanumCsvViewerMac.HiddenColumnIndexes"
    private var savedDefaults: [String: Any?] = [:]

    override func setUp() {
        super.setUp()
        // hiddenColumnsKey included: hideCurrentColumn persists it and would
        // otherwise leak a hidden column across the whole suite run.
        for key in [storeKey, legacyKey, autoKey, hiddenColumnsKey] {
            savedDefaults[key] = UserDefaults.standard.object(forKey: key)
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    override func tearDown() {
        for (key, value) in savedDefaults {
            if let value {
                UserDefaults.standard.set(value, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        super.tearDown()
    }

    func testMultipleNamedViewsPersistPerFile() throws {
        let controller = try openController(csv: "city,amount\nNY,1\nLA,2\nNY,3\n")
        defer { controller.close() }

        controller.saveViewForTesting(named: "all")
        controller.selectCellForTesting(row: 0, column: 0)
        controller.saveViewForTesting(named: "focus")

        XCTAssertEqual(controller.savedViewNamesForTesting, ["all", "focus"])
    }

    func testRestoreByNameAppliesSavedHiddenColumns() throws {
        let controller = try openController(csv: "city,status\nNY,open\nLA,closed\n")
        defer { controller.close() }

        controller.selectCellForTesting(row: 0, column: 1)
        controller.hideCurrentColumn(nil)
        controller.saveViewForTesting(named: "hide-status")

        controller.showAllColumns(nil)
        XCTAssertFalse(controller.isColumnHiddenForTesting(1))

        XCTAssertTrue(controller.restoreViewForTesting(named: "hide-status"))
        try waitUntilNotBusy(controller)
        XCTAssertTrue(controller.isColumnHiddenForTesting(1), "restore reapplies the saved hidden column")
    }

    func testDeleteRemovesOneBookmark() throws {
        let controller = try openController(csv: "a\n1\n2\n")
        defer { controller.close() }

        controller.saveViewForTesting(named: "one")
        controller.saveViewForTesting(named: "two")
        controller.deleteSavedViewForTesting(named: "one")

        XCTAssertEqual(controller.savedViewNamesForTesting, ["two"])
    }

    func testAutoRestoreAppliesMostRecentOnOpen() throws {
        let path = try temporaryCsvPath()
        try "city,amount\nNY,1\nLA,2\nNY,3\n".data(using: .utf8)!.write(to: URL(fileURLWithPath: path))
        addTeardownBlock { try? FileManager.default.removeItem(atPath: path) }

        let controller = MainWindowController()
        controller.showWindow(nil)
        controller.openFileForTesting(URL(fileURLWithPath: path))
        try waitUntilIndexed(controller)

        controller.applyColumnFilterForTesting(.selectedValues(column: 0, values: ["NY"], includeBlanks: false))
        try waitUntilNotBusy(controller)
        controller.saveViewForTesting(named: "NY only")
        XCTAssertEqual(controller.renderedRowCountForTesting, 2)

        controller.setAutoRestoreViewForTesting(true)

        // Reopen the same file; the most-recent bookmark should reapply.
        let reopened = MainWindowController()
        reopened.showWindow(nil)
        defer { reopened.close(); controller.close() }
        reopened.openFileForTesting(URL(fileURLWithPath: path))
        try waitUntilIndexed(reopened)
        try waitUntilNotBusy(reopened)
        try waitUntil(reopened) { $0.renderedRowCountForTesting == 2 }
        XCTAssertEqual(reopened.renderedRowCountForTesting, 2, "auto-restore reapplied the NY filter")
    }

    func testLegacySingleViewMigratesToStore() throws {
        let path = try temporaryCsvPath()
        try "a\n1\n2\n".data(using: .utf8)!.write(to: URL(fileURLWithPath: path))
        addTeardownBlock { try? FileManager.default.removeItem(atPath: path) }

        let legacyView = SavedCsvView(
            name: "legacy",
            filterText: nil,
            filterColumn: nil,
            sortKeys: [],
            hiddenColumnIndexes: [],
            searchQuery: nil,
            currentColumn: 0
        )
        let encoded = try JSONEncoder().encode(legacyView).base64EncodedString()
        UserDefaults.standard.set([path: encoded], forKey: legacyKey)

        let controller = MainWindowController()
        controller.showWindow(nil)
        defer { controller.close() }
        controller.openFileForTesting(URL(fileURLWithPath: path))
        try waitUntilIndexed(controller)

        XCTAssertEqual(controller.savedViewNamesForTesting, ["legacy"], "legacy single view surfaces as a bookmark")
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
        try waitUntil(controller, file: file, line: line) {
            $0.indexingCompleteForTesting && $0.renderedRowCountForTesting > 0
        }
    }

    private func waitUntilNotBusy(_ controller: MainWindowController, file: StaticString = #filePath, line: UInt = #line) throws {
        try waitUntil(controller, file: file, line: line) { !$0.busyForTesting }
    }

    private func waitUntil(
        _ controller: MainWindowController,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ condition: @MainActor (MainWindowController) -> Bool
    ) throws {
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
            if condition(controller) { return }
        }
        XCTFail("Timed out waiting for condition", file: file, line: line)
    }

    private func temporaryCsvPath() throws -> String {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return directory.appendingPathComponent("nanumcsv_bookmark_\(UUID().uuidString).csv").path
    }
}
