import AppKit
import XCTest
@testable import NanumCsvViewerMac

final class AppearanceSettingsTests: XCTestCase {
    func testAppearanceMapping() {
        XCTAssertNil(AppearancePreference.system.nsAppearance)
        XCTAssertEqual(AppearancePreference.light.nsAppearance?.name, .aqua)
        XCTAssertEqual(AppearancePreference.dark.nsAppearance?.name, .darkAqua)
    }

    func testAppearanceFromRawValueFallsBackToSystem() {
        XCTAssertEqual(AppearancePreference.from(rawValue: "dark"), .dark)
        XCTAssertEqual(AppearancePreference.from(rawValue: nil), .system)
        XCTAssertEqual(AppearancePreference.from(rawValue: "bogus"), .system)
    }

    func testFontSizeOrdering() {
        XCTAssertLessThan(GridFontSize.small.pointSize, GridFontSize.medium.pointSize)
        XCTAssertLessThan(GridFontSize.medium.pointSize, GridFontSize.large.pointSize)
        XCTAssertEqual(GridFontSize.large.gutterPointSize, GridFontSize.large.pointSize - 1)
    }

    func testFontSizeFromRawValueFallsBackToMedium() {
        XCTAssertEqual(GridFontSize.from(rawValue: "large"), .large)
        XCTAssertEqual(GridFontSize.from(rawValue: nil), .medium)
        XCTAssertEqual(GridFontSize.from(rawValue: "bogus"), .medium)
    }
}
