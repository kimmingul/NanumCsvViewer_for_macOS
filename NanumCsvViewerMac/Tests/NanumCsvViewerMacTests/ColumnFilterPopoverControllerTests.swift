import AppKit
@preconcurrency import CsvCore
import XCTest
@testable import NanumCsvViewerMac

@MainActor
final class ColumnFilterPopoverControllerTests: XCTestCase {
    func testLargeCategorySearchPreservesHiddenSelectionsWithoutConstructingEveryCheckbox() throws {
        _ = NSApplication.shared
        let lastValue = "value-99998"
        let controller = ColumnFilterPopoverController(
            column: 3,
            columnName: "category",
            type: .categorical,
            values: (0..<99_999).map { DistinctColumnValue(value: "value-\($0)", count: 1) }
                + [DistinctColumnValue(value: "", count: 2)],
            initialFilter: .selectedValues(column: 3, values: ["value-0"], includeBlanks: true)
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 420),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentViewController = controller
        window.orderFront(nil)
        defer { window.close() }
        controller.view.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        let table = controller.valueTableForTesting
        XCTAssertEqual(table.numberOfRows, 100_000)
        XCTAssertGreaterThan(controller.constructedValueCheckboxCountForTesting, 0)
        XCTAssertLessThan(controller.constructedValueCheckboxCountForTesting, 100)

        controller.searchValuesForTesting(lastValue)
        XCTAssertEqual(table.numberOfRows, 1)
        let lastCheckbox = try checkbox(in: table, row: 0)
        lastCheckbox.performClick(nil)
        XCTAssertEqual(lastCheckbox.state, .on)

        controller.searchValuesForTesting("")
        XCTAssertEqual(table.numberOfRows, 100_000)
        XCTAssertEqual(try checkbox(in: table, row: 0).state, .on)
        XCTAssertEqual(try checkbox(in: table, row: 99_998).state, .on)
        XCTAssertEqual(try checkbox(in: table, row: 99_999).state, .on)
        XCTAssertLessThan(controller.constructedValueCheckboxCountForTesting, 100)

        var appliedFilter: ColumnFilter?
        controller.onApply = { appliedFilter = $0 }
        controller.applyForTesting()
        guard case .selectedValues(let column, let values, let includeBlanks) = appliedFilter else {
            return XCTFail("Expected selected values")
        }
        XCTAssertEqual(column, 3)
        XCTAssertEqual(values, ["value-0", lastValue])
        XCTAssertTrue(includeBlanks)
    }

    func testSelectAllAndClearAffectValuesHiddenBySearchIncludingBlanks() throws {
        _ = NSApplication.shared
        let controller = ColumnFilterPopoverController(
            column: 0,
            columnName: "category",
            type: .categorical,
            values: [
                DistinctColumnValue(value: "Café", count: 2),
                DistinctColumnValue(value: "Other", count: 1),
                DistinctColumnValue(value: "", count: 1)
            ],
            initialFilter: nil
        )
        controller.loadViewIfNeeded()
        controller.view.layoutSubtreeIfNeeded()
        controller.searchValuesForTesting(" cafe ")
        XCTAssertEqual(controller.valueTableForTesting.numberOfRows, 1)
        let visibleCheckbox = try checkbox(in: controller.valueTableForTesting, row: 0)
        XCTAssertEqual(visibleCheckbox.state, .off)
        controller.selectAllValuesForTesting()
        XCTAssertEqual(visibleCheckbox.state, .on)
        var appliedFilter: ColumnFilter?
        controller.onApply = { appliedFilter = $0 }
        controller.applyForTesting()
        guard case .selectedValues(_, let values, let includeBlanks) = appliedFilter else {
            return XCTFail("Expected all values, including hidden values")
        }
        XCTAssertEqual(values, ["Café", "Other"])
        XCTAssertTrue(includeBlanks)

        controller.clearValuesForTesting()
        controller.searchValuesForTesting("")
        XCTAssertEqual(controller.valueTableForTesting.numberOfRows, 3)
        XCTAssertEqual(try checkbox(in: controller.valueTableForTesting, row: 2).state, .off)
        controller.applyForTesting()
        XCTAssertNil(appliedFilter)
    }

    private func checkbox(in table: NSTableView, row: Int) throws -> NSButton {
        table.scrollRowToVisible(row)
        table.layoutSubtreeIfNeeded()
        return try XCTUnwrap(table.view(atColumn: 0, row: row, makeIfNecessary: true) as? NSButton)
    }

    func testDatePickerChangeChecksMatchingBound() {
        let controller = ColumnFilterPopoverController(
            column: 0,
            columnName: "검사일자",
            type: .date,
            values: [],
            initialFilter: nil
        )

        controller.loadViewIfNeeded()
        controller.setStartDateForTesting(Date(timeIntervalSince1970: 1_767_225_600))
        controller.setEndDateForTesting(Date(timeIntervalSince1970: 1_767_312_000))

        XCTAssertTrue(controller.startDateEnabledForTesting)
        XCTAssertTrue(controller.endDateEnabledForTesting)
    }

    func testApplyRequestsCloseAndEmitsDateRangeFilter() throws {
        let controller = ColumnFilterPopoverController(
            column: 0,
            columnName: "검사일자",
            type: .date,
            values: [],
            initialFilter: nil
        )
        var appliedFilter: ColumnFilter?
        var didRequestClose = false
        controller.onApply = { appliedFilter = $0 }
        controller.onClose = { didRequestClose = true }

        controller.loadViewIfNeeded()
        controller.setStartDateForTesting(Date(timeIntervalSince1970: 1_767_225_600))
        controller.applyForTesting()

        XCTAssertTrue(didRequestClose)
        guard case .dateRange(let column, let start?, nil) = appliedFilter else {
            return XCTFail("Expected a date range filter")
        }
        XCTAssertEqual(column, 0)
        XCTAssertEqual(start, ColumnFilterPopoverController.startOfDayForTesting(Date(timeIntervalSince1970: 1_767_225_600)))
    }
}
