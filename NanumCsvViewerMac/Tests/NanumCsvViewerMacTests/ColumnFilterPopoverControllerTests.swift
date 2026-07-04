import AppKit
@preconcurrency import CsvCore
import XCTest
@testable import NanumCsvViewerMac

@MainActor
final class ColumnFilterPopoverControllerTests: XCTestCase {
    func testCategoricalPopoverDisplaysValueCheckboxes() {
        let controller = ColumnFilterPopoverController(
            column: 0,
            columnName: "site",
            type: .categorical,
            values: [
                DistinctColumnValue(value: "A", count: 2),
                DistinctColumnValue(value: "", count: 1)
            ],
            initialFilter: nil
        )

        controller.loadViewIfNeeded()
        controller.view.layoutSubtreeIfNeeded()

        XCTAssertEqual(controller.valueCheckboxTitlesForTesting, ["A (2)", L.t("(Blank) 1", "(빈 값) 1")])
        XCTAssertGreaterThan(controller.valueListContentHeightForTesting, 40)
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
