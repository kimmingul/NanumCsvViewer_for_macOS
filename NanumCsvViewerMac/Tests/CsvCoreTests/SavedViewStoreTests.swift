import Foundation
import XCTest
@testable import CsvCore

final class SavedViewStoreTests: XCTestCase {
    private func view(_ name: String, currentColumn: Int = 0) -> SavedCsvView {
        SavedCsvView(
            name: name,
            filterText: nil,
            filterColumn: nil,
            sortKeys: [],
            hiddenColumnIndexes: [],
            searchQuery: nil,
            currentColumn: currentColumn
        )
    }

    func testSaveAppendsNewNamesInOrder() {
        var store = SavedViewStore()
        store.save(view("first"), forPath: "/a.csv")
        store.save(view("second"), forPath: "/a.csv")

        XCTAssertEqual(store.names(forPath: "/a.csv"), ["first", "second"])
        XCTAssertEqual(store.views(forPath: "/b.csv"), [])
    }

    func testSaveUpsertsSameNameInPlace() {
        var store = SavedViewStore()
        store.save(view("bookmark", currentColumn: 1), forPath: "/a.csv")
        store.save(view("other"), forPath: "/a.csv")
        store.save(view("bookmark", currentColumn: 9), forPath: "/a.csv")

        XCTAssertEqual(store.names(forPath: "/a.csv"), ["bookmark", "other"], "upsert keeps position")
        XCTAssertEqual(store.view(named: "bookmark", forPath: "/a.csv")?.currentColumn, 9)
    }

    func testRemoveByName() {
        var store = SavedViewStore()
        store.save(view("keep"), forPath: "/a.csv")
        store.save(view("drop"), forPath: "/a.csv")

        store.remove(name: "drop", forPath: "/a.csv")
        XCTAssertEqual(store.names(forPath: "/a.csv"), ["keep"])

        store.remove(name: "keep", forPath: "/a.csv")
        XCTAssertTrue(store.views(forPath: "/a.csv").isEmpty, "empty path entry is pruned")
        XCTAssertFalseOrNil(store.mostRecent(forPath: "/a.csv"))
    }

    func testMostRecentIsLastSaved() {
        var store = SavedViewStore()
        store.save(view("one"), forPath: "/a.csv")
        store.save(view("two"), forPath: "/a.csv")
        store.save(view("one", currentColumn: 5), forPath: "/a.csv")

        XCTAssertEqual(store.mostRecent(forPath: "/a.csv")?.name, "one", "re-saving marks it most recent")
        XCTAssertEqual(store.mostRecent(forPath: "/a.csv")?.currentColumn, 5)
    }

    func testDeletingRecentFallsBackToNextMostRecentNotInsertionOrder() {
        var store = SavedViewStore()
        store.save(view("A"), forPath: "/a.csv")
        store.save(view("B"), forPath: "/a.csv")
        store.save(view("A", currentColumn: 3), forPath: "/a.csv") // A now most recent
        store.save(view("C"), forPath: "/a.csv")                    // C most recent

        store.remove(name: "C", forPath: "/a.csv")
        XCTAssertEqual(store.mostRecent(forPath: "/a.csv")?.name, "A", "A was saved more recently than B")
        XCTAssertEqual(store.names(forPath: "/a.csv"), ["A", "B"], "display order still upsert-in-place")
    }

    func testRoundTripsThroughCodable() throws {
        var store = SavedViewStore()
        store.save(view("alpha"), forPath: "/a.csv")
        store.save(view("beta", currentColumn: 3), forPath: "/a.csv")
        store.save(view("gamma"), forPath: "/b.csv")

        let data = try JSONEncoder().encode(store)
        let decoded = try JSONDecoder().decode(SavedViewStore.self, from: data)
        XCTAssertEqual(decoded, store)
    }

    func testRemovePathsWhereDropsMatchingEntries() {
        var store = SavedViewStore()
        store.save(view("keep"), forPath: "/a.csv")
        store.save(view("gone"), forPath: "/b.csv")
        store.save(view("gone2"), forPath: "/b.csv")

        store.removePaths { $0 == "/b.csv" }
        XCTAssertEqual(store.names(forPath: "/a.csv"), ["keep"])
        XCTAssertTrue(store.views(forPath: "/b.csv").isEmpty)
        XCTAssertNil(store.mostRecent(forPath: "/b.csv"))
    }

    func testMigratesLegacySingleViewMap() throws {
        // The v1.7 format stored [path: base64(SavedCsvView)] with one view per file.
        let legacyA = try JSONEncoder().encode(view("legacyA", currentColumn: 2)).base64EncodedString()
        let legacyB = try JSONEncoder().encode(view("legacyB")).base64EncodedString()
        let legacyMap = ["/a.csv": legacyA, "/b.csv": legacyB, "/bad.csv": "not-base64!!"]

        let store = SavedViewStore(migratingLegacyMap: legacyMap)
        XCTAssertEqual(store.names(forPath: "/a.csv"), ["legacyA"])
        XCTAssertEqual(store.view(named: "legacyA", forPath: "/a.csv")?.currentColumn, 2)
        XCTAssertEqual(store.names(forPath: "/b.csv"), ["legacyB"])
        XCTAssertTrue(store.views(forPath: "/bad.csv").isEmpty, "undecodable legacy entries are skipped")
    }
}

private func XCTAssertFalseOrNil(_ value: Any?, file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertNil(value, file: file, line: line)
}
