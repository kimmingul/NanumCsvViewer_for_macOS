import Foundation
import XCTest
@testable import NanumCsvViewerMac

final class DocumentOpenRoutingTests: XCTestCase {
    func testFirstSelectedUrlOpensInEmptyCurrentWindowAndRestOpenAsAdditionalDocuments() {
        let urls = [
            URL(fileURLWithPath: "/tmp/a.csv"),
            URL(fileURLWithPath: "/tmp/b.csv"),
            URL(fileURLWithPath: "/tmp/c.csv")
        ]

        let route = DocumentOpenRouting.route(urls: urls, currentWindowHasDocument: false)

        XCTAssertEqual(route.currentWindowURL, urls[0])
        XCTAssertEqual(route.additionalWindowURLs, Array(urls.dropFirst()))
    }

    func testAllSelectedUrlsOpenAsAdditionalDocumentsWhenCurrentWindowAlreadyHasDocument() {
        let urls = [
            URL(fileURLWithPath: "/tmp/a.csv"),
            URL(fileURLWithPath: "/tmp/b.csv")
        ]

        let route = DocumentOpenRouting.route(urls: urls, currentWindowHasDocument: true)

        XCTAssertNil(route.currentWindowURL)
        XCTAssertEqual(route.additionalWindowURLs, urls)
    }
}
