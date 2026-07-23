import Foundation
import SQLite3
import XCTest
@testable import CsvCore

final class SqliteWorkbookTests: XCTestCase {
    private func makeSampleDatabase() throws -> String {
        let path = NSTemporaryDirectory() + "/sqlite-test-\(UUID().uuidString).db"
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(path, &db), SQLITE_OK)
        defer { sqlite3_close_v2(db) }
        let statements = [
            "CREATE TABLE people (id INTEGER PRIMARY KEY, name TEXT, score REAL)",
            "INSERT INTO people VALUES (1, 'Alice', 91.5)",
            "INSERT INTO people VALUES (2, '김민걸', 88.0)",
            "INSERT INTO people VALUES (3, 'Comma, \"Quoted\"', NULL)",
            "CREATE TABLE empty_table (a TEXT)",
            "CREATE VIEW high_scores AS SELECT name FROM people WHERE score > 90"
        ]
        for sql in statements {
            XCTAssertEqual(sqlite3_exec(db, sql, nil, nil, nil), SQLITE_OK, sql)
        }
        return path
    }

    func testDetectsSqliteFilesByMagicAndExtension() throws {
        let path = try makeSampleDatabase()
        defer { try? FileManager.default.removeItem(atPath: path) }

        XCTAssertTrue(SqliteWorkbook.isSqliteFile(path: path))
        XCTAssertTrue(SqliteWorkbook.hasSqliteExtension(path))
        XCTAssertTrue(SqliteWorkbook.hasSqliteExtension("/tmp/x.sqlite3"))
        XCTAssertFalse(SqliteWorkbook.hasSqliteExtension("/tmp/x.csv"))

        let csvPath = NSTemporaryDirectory() + "/not-a-db-\(UUID().uuidString).csv"
        try "a,b\n1,2\n".data(using: .utf8)!.write(to: URL(fileURLWithPath: csvPath))
        defer { try? FileManager.default.removeItem(atPath: csvPath) }
        XCTAssertFalse(SqliteWorkbook.isSqliteFile(path: csvPath))
    }

    func testListsTablesAndViews() throws {
        let path = try makeSampleDatabase()
        defer { try? FileManager.default.removeItem(atPath: path) }

        XCTAssertEqual(try SqliteWorkbook.tableNames(path: path), ["empty_table", "people", "high_scores"])
    }

    func testExportsTableToCsvAndOpensThroughCsvEngine() throws {
        let path = try makeSampleDatabase()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let csvURL = URL(fileURLWithPath: NSTemporaryDirectory() + "/sqlite-export-\(UUID().uuidString).csv")
        defer { try? FileManager.default.removeItem(at: csvURL) }

        let rowCount = try SqliteWorkbook.exportTableToCsv(path: path, table: "people", destination: csvURL)
        XCTAssertEqual(rowCount, 3)

        let doc = try VirtualCsvDocument.open(path: csvURL.path)
        try doc.runIndexing(progress: { _ in }, cancellation: CancellationFlag())
        XCTAssertEqual(doc.header, ["id", "name", "score"])
        XCTAssertEqual(doc.dataRowsAvailable, 3)
        XCTAssertEqual(try doc.getDisplayRow(1), ["2", "김민걸", "88.0"])
        XCTAssertEqual(try doc.getDisplayRow(2), ["3", "Comma, \"Quoted\"", ""])
    }

    func testExportRejectsUnknownTable() throws {
        let path = try makeSampleDatabase()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let csvURL = URL(fileURLWithPath: NSTemporaryDirectory() + "/sqlite-nope-\(UUID().uuidString).csv")

        XCTAssertThrowsError(try SqliteWorkbook.exportTableToCsv(path: path, table: "missing; DROP TABLE people", destination: csvURL))
    }

    func testExportEnforcesRowLimit() throws {
        let path = try makeSampleDatabase()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let csvURL = URL(fileURLWithPath: NSTemporaryDirectory() + "/sqlite-rowcap-\(UUID().uuidString).csv")
        defer { try? FileManager.default.removeItem(at: csvURL) }

        // people has 3 rows; cap at 2.
        let limits = WorkbookImportLimits(maxRows: 2, maxColumns: .max, maxCells: .max)
        XCTAssertThrowsError(try SqliteWorkbook.exportTableToCsv(path: path, table: "people", destination: csvURL, limits: limits)) { error in
            XCTAssertEqual(error as? WorkbookImportError, .maxRowsExceeded)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: csvURL.path), "partial output removed on failure")
    }

    func testExportEnforcesColumnLimit() throws {
        let path = try makeSampleDatabase()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let csvURL = URL(fileURLWithPath: NSTemporaryDirectory() + "/sqlite-colcap-\(UUID().uuidString).csv")
        defer { try? FileManager.default.removeItem(at: csvURL) }

        // people has 3 columns; cap at 2.
        let limits = WorkbookImportLimits(maxRows: .max, maxColumns: 2, maxCells: .max)
        XCTAssertThrowsError(try SqliteWorkbook.exportTableToCsv(path: path, table: "people", destination: csvURL, limits: limits)) { error in
            XCTAssertEqual(error as? WorkbookImportError, .maxColumnsExceeded)
        }
    }

    func testExportEnforcesCellLimit() throws {
        let path = try makeSampleDatabase()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let csvURL = URL(fileURLWithPath: NSTemporaryDirectory() + "/sqlite-cellcap-\(UUID().uuidString).csv")
        defer { try? FileManager.default.removeItem(at: csvURL) }

        // people is 3 columns wide; 5-cell cap admits one row, then trips.
        let limits = WorkbookImportLimits(maxRows: .max, maxColumns: .max, maxCells: 5)
        XCTAssertThrowsError(try SqliteWorkbook.exportTableToCsv(path: path, table: "people", destination: csvURL, limits: limits)) { error in
            XCTAssertEqual(error as? WorkbookImportError, .maxCellsExceeded)
        }
    }

    func testExportEnforcesDeadline() throws {
        let path = try makeSampleDatabase()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let csvURL = URL(fileURLWithPath: NSTemporaryDirectory() + "/sqlite-deadline-\(UUID().uuidString).csv")
        defer { try? FileManager.default.removeItem(at: csvURL) }

        let limits = WorkbookImportLimits(maxRows: .max, maxColumns: .max, maxCells: .max, deadline: Date(timeIntervalSince1970: 0))
        XCTAssertThrowsError(try SqliteWorkbook.exportTableToCsv(path: path, table: "people", destination: csvURL, limits: limits)) { error in
            XCTAssertEqual(error as? WorkbookImportError, .timedOut)
        }
    }

    func testExportToFileHandleMatchesUrlVariant() throws {
        let path = try makeSampleDatabase()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let urlOut = URL(fileURLWithPath: NSTemporaryDirectory() + "/sqlite-url-\(UUID().uuidString).csv")
        let fhOut = URL(fileURLWithPath: NSTemporaryDirectory() + "/sqlite-fh-\(UUID().uuidString).csv")
        defer {
            try? FileManager.default.removeItem(at: urlOut)
            try? FileManager.default.removeItem(at: fhOut)
        }

        _ = try SqliteWorkbook.exportTableToCsv(path: path, table: "people", destination: urlOut)

        FileManager.default.createFile(atPath: fhOut.path, contents: nil)
        let handle = try FileHandle(forWritingTo: fhOut)
        _ = try SqliteWorkbook.exportTableToCsv(path: path, table: "people", output: handle)
        try handle.close()

        XCTAssertEqual(try String(contentsOf: urlOut, encoding: .utf8), try String(contentsOf: fhOut, encoding: .utf8))
    }
}
