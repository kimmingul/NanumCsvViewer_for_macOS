import Foundation
import XCTest
@testable import CsvCore

final class SavedCsvViewTests: XCTestCase {
    func testSavedViewRoundTripsFilterSortHiddenColumnsAndSearchMode() throws {
        let saved = SavedCsvView(
            name: "NY positive",
            filterText: #"city == "NY" AND note contains "positive""#,
            filterColumn: nil,
            sortKeys: [SortKey(column: 2, ascending: false), SortKey(column: 0, ascending: true)],
            hiddenColumnIndexes: [4, 1],
            searchQuery: try CsvSearchQuery(text: "positive", mode: .contains, column: nil),
            currentColumn: 2,
            columnFilters: ColumnFilterState(filters: [
                .selectedValues(column: 1, values: ["NY"], includeBlanks: false)
            ])
        )

        let data = try JSONEncoder().encode(saved)
        let decoded = try JSONDecoder().decode(SavedCsvView.self, from: data)

        XCTAssertEqual(decoded, saved)
        XCTAssertEqual(decoded.hiddenColumnIndexes, [1, 4])
    }

    func testSavedViewDecodesLegacyPayloadWithoutColumnFilters() throws {
        let data = """
        {
          "name": "legacy",
          "filterText": null,
          "filterColumn": null,
          "sortKeys": [],
          "hiddenColumnIndexes": [2, 1],
          "searchQuery": null,
          "currentColumn": 0
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(SavedCsvView.self, from: data)

        XCTAssertEqual(decoded.columnFilters, ColumnFilterState())
        XCTAssertEqual(decoded.hiddenColumnIndexes, [1, 2])
    }
}
