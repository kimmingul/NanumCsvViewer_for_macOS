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
            currentColumn: 2
        )

        let data = try JSONEncoder().encode(saved)
        let decoded = try JSONDecoder().decode(SavedCsvView.self, from: data)

        XCTAssertEqual(decoded, saved)
        XCTAssertEqual(decoded.hiddenColumnIndexes, [1, 4])
    }
}
