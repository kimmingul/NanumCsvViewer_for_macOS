import Foundation
import XCTest
@testable import ImportServiceProtocol

final class ImportServiceProtocolCodingTests: XCTestCase {
    func testDTOsRoundTripThroughSecureArchiver() throws {
        let limits = ImportLimits(maxBytes: 1024, maxRows: 10, maxColumns: 4, maxCells: 40, timeoutSeconds: 2)
        let warning = ImportWarning(code: "echo", message: "copied")
        let result = ImportResult(
            csvURL: URL(fileURLWithPath: "/tmp/echo.csv"),
            metadataURL: URL(fileURLWithPath: "/tmp/echo.json"),
            warnings: [warning],
            rowCount: 3,
            columnCount: 2
        )
        let inspection = ImportInspection(sheetNames: ["µ", "∂"])
        let error = ImportError(code: "capExceeded", message: "too large")

        XCTAssertEqual(try roundTrip(limits), limits)
        XCTAssertEqual(try roundTrip(warning), warning)
        XCTAssertEqual(try roundTrip(result), result)
        XCTAssertEqual(try roundTrip(inspection), inspection)
        XCTAssertEqual(try roundTrip(error), error)
    }

    private func roundTrip<T: NSObject & NSSecureCoding>(_ value: T) throws -> T {
        let data = try NSKeyedArchiver.archivedData(withRootObject: value, requiringSecureCoding: true)
        let decoded = try XCTUnwrap(NSKeyedUnarchiver.unarchivedObject(ofClass: T.self, from: data))
        return decoded
    }
}
