import XCTest
@testable import NanumCsvViewerMac

final class FilterExpressionRoutingTests: XCTestCase {
    func testRecognizesCompactComparisonExpressions() {
        XCTAssertTrue(MainWindowController.looksLikeExpression("age>65"))
        XCTAssertTrue(MainWindowController.looksLikeExpression("age=65"))
        XCTAssertTrue(MainWindowController.looksLikeExpression("score<=10"))
        XCTAssertTrue(MainWindowController.looksLikeExpression("visit_date contains 2026"))
        XCTAssertTrue(MainWindowController.looksLikeExpression("age>65 AND sex=M"))
    }

    func testPlainTextFilterTermsRemainContainsSearches() {
        XCTAssertFalse(MainWindowController.looksLikeExpression("positive"))
        XCTAssertFalse(MainWindowController.looksLikeExpression("baseline visit"))
    }
}
