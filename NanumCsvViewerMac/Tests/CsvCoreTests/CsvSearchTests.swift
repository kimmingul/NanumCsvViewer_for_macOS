import Foundation
import XCTest
@testable import CsvCore

final class CsvSearchTests: XCTestCase {
    func testRejectsNestedQuantifierPatterns() {
        for pattern in ["(a+)+", "(a*)*", "(.*)+", "((a+))+", "(a+)*$", "(\\d+)+"] {
            XCTAssertTrue(CsvSearchQuery.hasNestedQuantifier(pattern), pattern)
        }
    }

    func testAllowsSafePatterns() {
        for pattern in ["a+", "(ab)+", "abc", "\\(a+\\)+", "[a+]+", "a+b+", "(ab)+(cd)+", "\\d{3}"] {
            XCTAssertFalse(CsvSearchQuery.hasNestedQuantifier(pattern), pattern)
        }
    }

    func testQueryInitRejectsCatastrophicRegex() {
        XCTAssertThrowsError(try CsvSearchQuery(text: "(a+)+", mode: .regex, column: nil)) { error in
            XCTAssertEqual(error as? CsvSearchError, .unsafeRegularExpression("(a+)+"))
        }
    }

    func testQueryInitAllowsSafeRegex() throws {
        _ = try CsvSearchQuery(text: "(ab)+\\d{3}", mode: .regex, column: nil)
    }

    func testRegexSearchFindsMatchingCellAndSourceRow() throws {
        let (doc, path) = try openIndexed("""
        id,note
        A01,negative
        B22,pending
        A99,positive

        """)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let query = try CsvSearchQuery(text: #"^A\d{2}$"#, mode: .regex, column: 0)
        let match = try doc.findNext(query: query, start: 0, wrap: true, cancellation: CancellationFlag())

        XCTAssertEqual(match, CsvSearchMatch(viewRow: 0, sourceRowNumber: 1, column: 0, value: "A01"))
    }

    func testFuzzySearchMatchesCharactersInOrderAcrossAllColumns() throws {
        let (doc, path) = try openIndexed("""
        name,note
        Alice,baseline visit
        Bob,follow up
        Carol,adverse event

        """)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let query = try CsvSearchQuery(text: "bsln", mode: .fuzzy, column: nil)
        let match = try doc.findNext(query: query, start: 0, wrap: true, cancellation: CancellationFlag())

        XCTAssertEqual(match?.viewRow, 0)
        XCTAssertEqual(match?.sourceRowNumber, 1)
        XCTAssertEqual(match?.column, 1)
        XCTAssertEqual(match?.value, "baseline visit")
    }

    func testSearchWrapsAfterStartRow() throws {
        let (doc, path) = try openIndexed("""
        name,note
        Alice,target
        Bob,other
        Carol,target

        """)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let query = try CsvSearchQuery(text: "target", mode: .contains, column: 1)
        let match = try doc.findNext(query: query, start: 2, wrap: true, cancellation: CancellationFlag())

        XCTAssertEqual(match?.viewRow, 2)
        XCTAssertEqual(match?.sourceRowNumber, 3)
    }

    func testSearchStartingAtEndWrapsToFirstMatch() throws {
        let (doc, path) = try openIndexed("""
        name,note
        Alice,target
        Bob,other
        Carol,target

        """)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let query = try CsvSearchQuery(text: "target", mode: .contains, column: 1)
        let match = try doc.findNext(query: query, start: doc.displayRowCount, wrap: true, cancellation: CancellationFlag())

        XCTAssertEqual(match?.viewRow, 0)
        XCTAssertEqual(match?.sourceRowNumber, 1)
    }

    func testInvalidRegexThrowsClearSearchError() {
        XCTAssertThrowsError(try CsvSearchQuery(text: #"("#, mode: .regex, column: nil)) { error in
            guard case CsvSearchError.invalidRegularExpression = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    private func openIndexed(_ content: String) throws -> (VirtualCsvDocument, String) {
        let path = try temporaryPath()
        try content.data(using: .utf8)!.write(to: URL(fileURLWithPath: path))
        let doc = try VirtualCsvDocument.open(path: path)
        try doc.runIndexing(progress: { _ in }, cancellation: CancellationFlag())
        return (doc, path)
    }
}
