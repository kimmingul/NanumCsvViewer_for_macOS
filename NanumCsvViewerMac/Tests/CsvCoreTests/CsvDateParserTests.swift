import Foundation
import XCTest
@testable import CsvCore

final class CsvDateParserTests: XCTestCase {
    override func tearDown() {
        CsvDateSettings.order = .monthFirst
        super.tearDown()
    }

    func testAmbiguousDateUsesMonthFirstByDefault() {
        CsvDateSettings.order = .monthFirst
        XCTAssertEqual(ymd(CsvDateParser.parse("03/04/2020"))?.month, 3)
        XCTAssertEqual(ymd(CsvDateParser.parse("03/04/2020"))?.day, 4)
    }

    func testAmbiguousDateUsesDayFirstWhenConfigured() {
        CsvDateSettings.order = .dayFirst
        XCTAssertEqual(ymd(CsvDateParser.parse("03/04/2020"))?.month, 4)
        XCTAssertEqual(ymd(CsvDateParser.parse("03/04/2020"))?.day, 3)
    }

    func testDayGreaterThanTwelveFallsThroughRegardlessOfOrder() {
        for order in [CsvDateOrder.monthFirst, .dayFirst] {
            CsvDateSettings.order = order
            let parsed = ymd(CsvDateParser.parse("25/12/2020"))
            XCTAssertEqual(parsed?.month, 12, "\(order)")
            XCTAssertEqual(parsed?.day, 25, "\(order)")
        }
    }

    func testIsoAndYearFirstDatesAreUnaffectedByOrder() {
        CsvDateSettings.order = .dayFirst
        XCTAssertEqual(ymd(CsvDateParser.parse("2020-01-02"))?.month, 1)
        XCTAssertEqual(ymd(CsvDateParser.parse("2020-01-02"))?.day, 2)
    }

    private func ymd(_ date: Date?) -> (year: Int, month: Int, day: Int)? {
        guard let date else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = components.year, let month = components.month, let day = components.day else { return nil }
        return (year, month, day)
    }
}
