import AppKit
@preconcurrency import CsvCore
import XCTest
@testable import NanumCsvViewerMac

@MainActor
final class FacetsPanelTests: XCTestCase {
    func testFacetsPanelHiddenByDefaultAndTogglesWidth() throws {
        let controller = try openController(csv: "city,amount\nNY,1\nLA,2\n")

        XCTAssertFalse(controller.facetsPanelVisibleForTesting)
        XCTAssertEqual(controller.facetsPanelWidthForTesting, 0)

        controller.setFacetsPanelVisibleForTesting(true)
        XCTAssertTrue(controller.facetsPanelVisibleForTesting)
        XCTAssertEqual(controller.facetsPanelWidthForTesting, FacetsPanelView.preferredWidth)

        controller.setFacetsPanelVisibleForTesting(false)
        XCTAssertFalse(controller.facetsPanelVisibleForTesting)
        XCTAssertEqual(controller.facetsPanelWidthForTesting, 0)
    }

    func testFacetsPanelRendersValueSectionsForVisibleColumns() throws {
        let controller = try openController(csv: """
        city,status
        NY,open
        LA,open
        NY,closed

        """)

        controller.setFacetsPanelVisibleForTesting(true)
        try waitUntilFacetsRendered(controller)

        let sections = controller.facetSectionsForTesting
        XCTAssertEqual(sections.map(\.title), ["city", "status"])

        let citySection = sections[0]
        XCTAssertEqual(citySection.entries.map(\.label), ["NY", "LA"])
        XCTAssertEqual(citySection.entries.map(\.count), [2, 1])
    }

    func testFacetsPanelRendersHistogramForNumericColumn() throws {
        let values = (0...20).map(String.init).joined(separator: "\n")
        let controller = try openController(csv: "amount\n\(values)\n")

        controller.setFacetsPanelVisibleForTesting(true)
        try waitUntilColumnTypesReady(controller)
        try waitUntilFacetsRendered(controller, where: { sections in
            if case .numericRange = sections.first?.entries.first?.kind { return true }
            return false
        })

        guard let section = controller.facetSectionsForTesting.first else {
            return XCTFail("expected a facet section")
        }
        XCTAssertEqual(section.entries.count, 6)
        guard case .numericRange(let lower, _, let includesUpperBound) = section.entries[0].kind else {
            return XCTFail("expected numeric range entries, got \(section.entries[0].kind)")
        }
        XCTAssertEqual(lower, 0)
        XCTAssertFalse(includesUpperBound)
        guard case .numericRange(_, let lastUpper, let lastIncludes) = section.entries[5].kind else {
            return XCTFail("expected numeric range entries")
        }
        XCTAssertEqual(lastUpper, 20)
        XCTAssertTrue(lastIncludes)
    }

    func testFacetValueClickAppliesFilterAndSecondClickRemovesIt() throws {
        let controller = try openController(csv: """
        city,status
        NY,open
        LA,open
        NY,closed

        """)

        controller.setFacetsPanelVisibleForTesting(true)
        try waitUntilFacetsRendered(controller)

        controller.handleFacetSelectionForTesting(column: 0, kind: .value("NY"))
        try waitUntilNotBusy(controller)
        XCTAssertEqual(controller.renderedRowCountForTesting, 2)
        guard case .selectedValues(let column, let values, let includeBlanks)? = controller.columnFilterStateForTesting.filter(for: 0) else {
            return XCTFail("expected selectedValues filter")
        }
        XCTAssertEqual(column, 0)
        XCTAssertEqual(values, ["NY"])
        XCTAssertFalse(includeBlanks)

        controller.handleFacetSelectionForTesting(column: 0, kind: .value("NY"))
        try waitUntilNotBusy(controller)
        XCTAssertNil(controller.columnFilterStateForTesting.filter(for: 0))
        XCTAssertEqual(controller.renderedRowCountForTesting, 3)
    }

    func testFacetValueClicksUnionWithinColumn() throws {
        let controller = try openController(csv: """
        city
        NY
        LA
        SF

        """)

        controller.setFacetsPanelVisibleForTesting(true)
        try waitUntilFacetsRendered(controller)

        controller.handleFacetSelectionForTesting(column: 0, kind: .value("NY"))
        try waitUntilNotBusy(controller)
        controller.handleFacetSelectionForTesting(column: 0, kind: .value("LA"))
        try waitUntilNotBusy(controller)

        guard case .selectedValues(_, let values, _)? = controller.columnFilterStateForTesting.filter(for: 0) else {
            return XCTFail("expected selectedValues filter")
        }
        XCTAssertEqual(values, ["NY", "LA"])
        XCTAssertEqual(controller.renderedRowCountForTesting, 2)
    }

    func testFacetNumericRangeClickAppliesAndTogglesFilter() throws {
        let values = (0...20).map(String.init).joined(separator: "\n")
        let controller = try openController(csv: "amount\n\(values)\n")

        controller.setFacetsPanelVisibleForTesting(true)
        try waitUntilColumnTypesReady(controller)
        try waitUntilFacetsRendered(controller)

        controller.handleFacetSelectionForTesting(
            column: 0,
            kind: .numericRange(lower: 0, upper: 5, includesUpperBound: false)
        )
        try waitUntilNotBusy(controller)
        XCTAssertEqual(controller.renderedRowCountForTesting, 5, "0,1,2,3,4 fall in [0,5)")

        controller.handleFacetSelectionForTesting(
            column: 0,
            kind: .numericRange(lower: 0, upper: 5, includesUpperBound: false)
        )
        try waitUntilNotBusy(controller)
        XCTAssertNil(controller.columnFilterStateForTesting.filter(for: 0))
        XCTAssertEqual(controller.renderedRowCountForTesting, 21)
    }

    func testFacetSectionsExcludeOwnFilterAndMarkActiveEntries() throws {
        let controller = try openController(csv: """
        city,status
        NY,open
        LA,open
        NY,closed

        """)

        controller.setFacetsPanelVisibleForTesting(true)
        try waitUntilFacetsRendered(controller)

        controller.handleFacetSelectionForTesting(column: 0, kind: .value("NY"))
        try waitUntilNotBusy(controller)
        try waitUntilFacetsRendered(controller, requiredSections: 2, where: { sections in
            sections.first(where: { $0.column == 0 })?.entries.contains(where: \.isActive) == true
        })

        let sections = controller.facetSectionsForTesting
        guard let citySection = sections.first(where: { $0.column == 0 }) else {
            return XCTFail("expected city section")
        }
        XCTAssertEqual(
            citySection.entries.map(\.label).sorted(),
            ["LA", "NY"],
            "city facet should keep showing all cities while its own filter is active"
        )
        XCTAssertEqual(citySection.entries.first(where: { $0.label == "NY" })?.isActive, true)
        XCTAssertEqual(citySection.entries.first(where: { $0.label == "LA" })?.isActive, false)

        guard let statusSection = sections.first(where: { $0.column == 1 }) else {
            return XCTFail("expected status section")
        }
        XCTAssertEqual(statusSection.entries.map(\.count).reduce(0, +), 2, "status facet should reflect the city filter")
    }

    func testHiddenColumnsAreExcludedFromFacets() throws {
        // hideCurrentColumn persists to UserDefaults; restore it so later
        // tests (and later suite runs) start with no hidden columns.
        let hiddenColumnsKey = "NanumCsvViewerMac.HiddenColumnIndexes"
        let previousHiddenColumns = UserDefaults.standard.object(forKey: hiddenColumnsKey)
        addTeardownBlock {
            if let previousHiddenColumns {
                UserDefaults.standard.set(previousHiddenColumns, forKey: hiddenColumnsKey)
            } else {
                UserDefaults.standard.removeObject(forKey: hiddenColumnsKey)
            }
        }

        let controller = try openController(csv: """
        city,status
        NY,open
        LA,closed

        """)

        controller.setFacetsPanelVisibleForTesting(true)
        try waitUntilFacetsRendered(controller)
        XCTAssertEqual(controller.facetSectionsForTesting.count, 2)

        controller.selectCellForTesting(row: 0, column: 0)
        controller.hideCurrentColumn(nil)
        try waitUntilFacetsRendered(controller, where: { $0.count == 1 })

        XCTAssertEqual(controller.facetSectionsForTesting.map(\.title), ["status"])
    }

    private func openController(csv: String) throws -> MainWindowController {
        let path = try temporaryCsvPath()
        try csv.data(using: .utf8)!.write(to: URL(fileURLWithPath: path))
        addTeardownBlock {
            try? FileManager.default.removeItem(atPath: path)
        }
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

    private func waitUntilFacetsRendered(
        _ controller: MainWindowController,
        requiredSections: Int = 1,
        where condition: (@MainActor ([FacetPanelSection]) -> Bool)? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
            let sections = controller.facetSectionsForTesting
            if sections.count >= requiredSections,
               !controller.hasPendingFacetLoadForTesting,
               condition?(sections) ?? true {
                return
            }
        }
        XCTFail("Timed out waiting for facet sections", file: file, line: line)
    }

    private func temporaryCsvPath() throws -> String {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return directory.appendingPathComponent("nanumcsv_facets_\(UUID().uuidString).csv").path
    }
}
