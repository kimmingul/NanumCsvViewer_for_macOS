import Foundation
import XCTest
@testable import CsvCore

final class CsvDataQualityTests: XCTestCase {
    private func openIndexed(_ content: String) throws -> (VirtualCsvDocument, String) {
        let directory = NSTemporaryDirectory()
        let path = (directory as NSString).appendingPathComponent("quality-\(UUID().uuidString).csv")
        try content.data(using: .utf8)!.write(to: URL(fileURLWithPath: path))
        let doc = try VirtualCsvDocument.open(path: path)
        try doc.runIndexing(progress: { _ in }, cancellation: CancellationFlag())
        return (doc, path)
    }

    func testProfileCountsBlanksSentinelsAndTypes() throws {
        let (doc, path) = try openIndexed("""
        amount,city
        10,Seoul
        NA,Busan
        20,
        -9999,Jeonju
        30,Seoul

        """)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let report = try doc.dataQualityReport(cancellation: CancellationFlag())

        XCTAssertEqual(report.rowCount, 5)
        XCTAssertEqual(report.scannedRowCount, 5)
        XCTAssertEqual(report.scope, .full)

        let amount = report.columnProfiles[0]
        XCTAssertEqual(amount.name, "amount")
        XCTAssertEqual(amount.blankCount, 0)
        XCTAssertEqual(amount.sentinelCount, 2, "NA and -9999 are sentinel tokens")
        XCTAssertEqual(amount.numericCount, 3)

        let city = report.columnProfiles[1]
        XCTAssertEqual(city.blankCount, 1)
        XCTAssertEqual(city.sentinelCount, 0)
    }

    func testTypeValidityIssueListsCounterexamples() throws {
        let (doc, path) = try openIndexed("""
        value
        1
        2
        3
        4
        5
        6
        7
        oops
        8
        9

        """)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let report = try doc.dataQualityReport(cancellation: CancellationFlag())
        let validity = report.issues.first { $0.rule == .typeValidity && $0.column == 0 }

        XCTAssertNotNil(validity, "a mostly-numeric column with stray text should raise a validity issue")
        XCTAssertEqual(validity?.count, 1)
        XCTAssertEqual(validity?.examples.first, "oops")
    }

    func testKeyUniquenessRuleFlagsDuplicateIds() throws {
        let (doc, path) = try openIndexed("""
        user_id,name
        u1,Alice
        u2,Bob
        u1,Carol
        u3,Dan

        """)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let report = try doc.dataQualityReport(cancellation: CancellationFlag())
        let issue = report.issues.first { $0.rule == .keyUniqueness && $0.column == 0 }

        XCTAssertNotNil(issue, "an id-named column with duplicates should raise a key issue")
        XCTAssertEqual(issue?.count, 1, "one duplicated key value (u1)")
        XCTAssertEqual(issue?.examples.first, "u1")
    }

    func testRaggedRowsAreReported() throws {
        let (doc, path) = try openIndexed("""
        a,b,c
        1,2,3
        4,5
        6,7,8,9
        10,11,12

        """)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let report = try doc.dataQualityReport(cancellation: CancellationFlag())
        let issue = report.issues.first { $0.rule == .raggedRow }

        XCTAssertNotNil(issue)
        XCTAssertEqual(issue?.count, 2, "one short row and one long row")
    }

    func testCodebookListsSmallCategoricalDomains() throws {
        let (doc, path) = try openIndexed("""
        status,note
        open,alpha
        closed,beta
        open,gamma
        pending,delta
        open,epsilon

        """)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let report = try doc.dataQualityReport(cancellation: CancellationFlag())
        let statusCodebook = report.codebook.first { $0.column == 0 }

        XCTAssertNotNil(statusCodebook)
        XCTAssertEqual(statusCodebook?.entries.first?.value, "open")
        XCTAssertEqual(statusCodebook?.entries.first?.count, 3)
        XCTAssertNil(report.codebook.first { $0.column == 1 }, "all-unique text column is not a codebook domain")
    }

    func testFullScanIgnoresActiveFilter() throws {
        let (doc, path) = try openIndexed("""
        city
        Seoul
        Busan
        Seoul

        """)
        defer { try? FileManager.default.removeItem(atPath: path) }

        try doc.applyFilter({ $0.first == "Busan" }, progress: nil, cancellation: CancellationFlag())
        XCTAssertEqual(doc.displayRowCount, 1)

        let report = try doc.dataQualityReport(cancellation: CancellationFlag())
        XCTAssertEqual(report.scannedRowCount, 3, "data quality always profiles the whole file")
    }

    func testDuplicateRowsCounted() throws {
        let (doc, path) = try openIndexed("""
        a,b
        1,x
        2,y
        1,x
        1,x

        """)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let report = try doc.dataQualityReport(cancellation: CancellationFlag())
        XCTAssertEqual(report.duplicateRowCount, 2, "two extra copies of the (1,x) row")
    }

    func testQualityScoreDropsWithIssues() throws {
        let (clean, cleanPath) = try openIndexed("id,v\na,1\nb,2\nc,3\n")
        defer { try? FileManager.default.removeItem(atPath: cleanPath) }
        let (dirty, dirtyPath) = try openIndexed("id,v\na,1\na,NA\n,oops\na,\n")
        defer { try? FileManager.default.removeItem(atPath: dirtyPath) }

        let cleanReport = try clean.dataQualityReport(cancellation: CancellationFlag())
        let dirtyReport = try dirty.dataQualityReport(cancellation: CancellationFlag())

        XCTAssertEqual(cleanReport.score, 100)
        XCTAssertLessThan(dirtyReport.score, cleanReport.score)
        XCTAssertGreaterThanOrEqual(dirtyReport.score, 0)
    }

    func testReportEncodesToJson() throws {
        let (doc, path) = try openIndexed("a\n1\n2\n")
        defer { try? FileManager.default.removeItem(atPath: path) }

        let report = try doc.dataQualityReport(cancellation: CancellationFlag())
        let data = try JSONEncoder().encode(report)
        let decoded = try JSONDecoder().decode(DataQualityReport.self, from: data)

        XCTAssertEqual(decoded, report)
    }

    func testCancellationThrows() throws {
        let (doc, path) = try openIndexed("a\n1\n2\n")
        defer { try? FileManager.default.removeItem(atPath: path) }

        let cancellation = CancellationFlag()
        cancellation.cancel()
        XCTAssertThrowsError(try doc.dataQualityReport(cancellation: cancellation)) { error in
            guard case CsvError.cancelled = error else {
                return XCTFail("expected CsvError.cancelled, got \(error)")
            }
        }
    }

    func testKeyColumnHeuristicIgnoresPlainWordsEndingInId() {
        XCTAssertTrue(DataQualityRules.looksLikeKeyColumn(name: "id"))
        XCTAssertTrue(DataQualityRules.looksLikeKeyColumn(name: "user_id"))
        XCTAssertTrue(DataQualityRules.looksLikeKeyColumn(name: "userId"))
        XCTAssertTrue(DataQualityRules.looksLikeKeyColumn(name: "customerID"))
        XCTAssertTrue(DataQualityRules.looksLikeKeyColumn(name: "고객번호"))

        for word in ["grid", "valid", "void", "rapid", "squid", "aphid"] {
            XCTAssertFalse(DataQualityRules.looksLikeKeyColumn(name: word), word)
        }
    }
}
