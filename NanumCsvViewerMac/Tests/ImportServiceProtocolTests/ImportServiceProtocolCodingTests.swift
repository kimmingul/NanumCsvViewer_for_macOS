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

    func testImportKindRoundTripsForAllFormats() throws {
        let kinds: [ImportKind] = [
            .echo, .xls, .xlsx, .sqlite, .sav, .sas7bdat,
            .xlsSheet("Sheet 1"),
            .xlsxSheet("두번째"),
            .sqliteTable("people")
        ]
        for kind in kinds {
            XCTAssertEqual(try roundTrip(kind), kind, "\(kind.rawValue) must survive secure coding")
        }
    }

    func testImportKindPartNameAccessors() {
        XCTAssertEqual(ImportKind.xlsxSheet("Sales").xlsxSheetName, "Sales")
        XCTAssertNil(ImportKind.xlsxSheet("Sales").xlsSheetName)
        XCTAssertNil(ImportKind.xlsxSheet("Sales").sqliteTableName)

        XCTAssertEqual(ImportKind.sqliteTable("orders").sqliteTableName, "orders")
        XCTAssertNil(ImportKind.sqliteTable("orders").xlsxSheetName)

        XCTAssertNil(ImportKind.xlsx.xlsxSheetName)
        XCTAssertNil(ImportKind.sqlite.sqliteTableName)
    }

    private func roundTrip<T: NSObject & NSSecureCoding>(_ value: T) throws -> T {
        let data = try NSKeyedArchiver.archivedData(withRootObject: value, requiringSecureCoding: true)
        let decoded = try XCTUnwrap(NSKeyedUnarchiver.unarchivedObject(ofClass: T.self, from: data))
        return decoded
    }
}
