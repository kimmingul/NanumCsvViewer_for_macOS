import Foundation
import SQLite3

public enum SqliteWorkbookError: Error, Equatable {
    case cannotOpen(String)
    case queryFailed(String)
    case tableNotFound(String)
}

/// Read-only access to SQLite database files. Tables and views are exported
/// to temporary CSV files so the existing CSV engine (indexing, filters,
/// sort, analytics, export) works unchanged — the same strategy the Windows
/// twin uses for Excel/SAS/SQLite sources. The source database is never
/// written to.
public enum SqliteWorkbook {
    private static let magic: [UInt8] = Array("SQLite format 3\0".utf8)

    public static func isSqliteFile(path: String) -> Bool {
        guard let handle = FileHandle(forReadingAtPath: path) else { return false }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: magic.count) else { return false }
        return Array(data) == magic
    }

    public static func hasSqliteExtension(_ path: String) -> Bool {
        let ext = (path as NSString).pathExtension.lowercased()
        return ["db", "sqlite", "sqlite3"].contains(ext)
    }

    /// Names of tables and views, tables first, each sorted alphabetically.
    public static func tableNames(path: String) throws -> [String] {
        let db = try openReadOnly(path: path)
        defer { sqlite3_close_v2(db) }
        let sql = """
        SELECT name, type FROM sqlite_master
        WHERE type IN ('table', 'view') AND name NOT LIKE 'sqlite_%'
        ORDER BY CASE type WHEN 'table' THEN 0 ELSE 1 END, name
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SqliteWorkbookError.queryFailed(lastErrorMessage(db))
        }
        defer { sqlite3_finalize(statement) }

        var names: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let name = sqlite3_column_text(statement, 0) {
                names.append(String(cString: name))
            }
        }
        return names
    }

    /// Exports one table/view to a CSV file and returns the row count.
    @discardableResult
    public static func exportTableToCsv(
        path: String,
        table: String,
        destination: URL,
        limits: WorkbookImportLimits = .unlimited,
        cancellation: CancellationFlag = CancellationFlag()
    ) throws -> Int {
        try? FileManager.default.removeItem(at: destination)
        FileManager.default.createFile(atPath: destination.path, contents: nil)
        guard let output = FileHandle(forWritingAtPath: destination.path) else {
            throw SqliteWorkbookError.queryFailed("cannot write \(destination.path)")
        }
        do {
            let count = try exportTableToCsv(path: path, table: table, output: output, limits: limits, cancellation: cancellation)
            try output.close()
            return count
        } catch {
            try? output.close()
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
    }

    /// Exports one table/view into an already-open handle (e.g. an XPC-provided
    /// descriptor) and returns the row count. The caller owns the handle and any
    /// cleanup on failure.
    @discardableResult
    public static func exportTableToCsv(
        path: String,
        table: String,
        output: FileHandle,
        limits: WorkbookImportLimits = .unlimited,
        cancellation: CancellationFlag = CancellationFlag()
    ) throws -> Int {
        let db = try openReadOnly(path: path)
        defer { sqlite3_close_v2(db) }

        // A crafted view (e.g. a full cross join with ORDER BY) can spin inside a
        // single sqlite3_step past the deadline, which the per-row checks below
        // can't interrupt. A progress handler can.
        let guardBox = QueryProgressGuard(deadline: limits.deadline, cancellation: cancellation)
        let guardPtr = Unmanaged.passRetained(guardBox).toOpaque()
        defer { Unmanaged<QueryProgressGuard>.fromOpaque(guardPtr).release() }
        sqlite3_progress_handler(db, 10_000, { raw in
            guard let raw else { return 0 }
            return Unmanaged<QueryProgressGuard>.fromOpaque(raw).takeUnretainedValue().shouldAbort() ? 1 : 0
        }, guardPtr)

        guard try tableNames(path: path).contains(table) else {
            throw SqliteWorkbookError.tableNotFound(table)
        }

        var statement: OpaquePointer?
        let sql = "SELECT * FROM \"\(table.replacingOccurrences(of: "\"", with: "\"\""))\""
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SqliteWorkbookError.queryFailed(lastErrorMessage(db))
        }
        defer { sqlite3_finalize(statement) }

        let columnCount = Int(sqlite3_column_count(statement))
        guard columnCount <= limits.maxColumns else {
            throw WorkbookImportError.maxColumnsExceeded
        }
        let headers = (0..<columnCount).map { index -> String in
            sqlite3_column_name(statement, Int32(index)).map { String(cString: $0) } ?? "column\(index + 1)"
        }

        var buffer = csvLine(headers)
        var rowCount = 0
        var stepResult = sqlite3_step(statement)
        while stepResult == SQLITE_ROW {
            if rowCount & 0xFFF == 0 {
                try cancellation.check()
                try limits.checkDeadline()
            }
            try limits.checkRowBudget(alreadyWritten: rowCount, columnCount: columnCount)
            let fields = (0..<columnCount).map { index -> String in
                columnText(statement, Int32(index))
            }
            buffer += csvLine(fields)
            rowCount += 1
            if buffer.utf8.count >= 1_048_576 {
                try output.write(contentsOf: Data(buffer.utf8))
                buffer = ""
            }
            stepResult = sqlite3_step(statement)
        }
        guard stepResult == SQLITE_DONE else {
            if stepResult == SQLITE_INTERRUPT {
                throw cancellation.isCancelled ? CsvError.cancelled : WorkbookImportError.timedOut
            }
            throw SqliteWorkbookError.queryFailed(lastErrorMessage(db))
        }
        if !buffer.isEmpty {
            try output.write(contentsOf: Data(buffer.utf8))
        }
        return rowCount
    }

    private static func openReadOnly(path: String) throws -> OpaquePointer {
        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY
        guard sqlite3_open_v2(path, &db, flags, nil) == SQLITE_OK, let db else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
            sqlite3_close_v2(db)
            throw SqliteWorkbookError.cannotOpen(message)
        }
        return db
    }

    private static func columnText(_ statement: OpaquePointer?, _ index: Int32) -> String {
        switch sqlite3_column_type(statement, index) {
        case SQLITE_NULL:
            return ""
        case SQLITE_BLOB:
            let bytes = sqlite3_column_bytes(statement, index)
            return "<blob \(bytes) bytes>"
        default:
            return sqlite3_column_text(statement, index).map { String(cString: $0) } ?? ""
        }
    }

    private static func csvLine(_ fields: [String]) -> String {
        fields.map { field in
            if field.contains(",") || field.contains("\"") || field.contains("\n") || field.contains("\r") {
                return "\"\(field.replacingOccurrences(of: "\"", with: "\"\""))\""
            }
            return field
        }.joined(separator: ",") + "\n"
    }

    private static func lastErrorMessage(_ db: OpaquePointer?) -> String {
        db.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
    }
}

/// Backing context for the SQLite progress handler: aborts a query once the
/// import deadline passes or the operation is cancelled. Held via `Unmanaged`
/// for the lifetime of the export so the C callback can read it.
private final class QueryProgressGuard {
    private let deadline: Date?
    private let cancellation: CancellationFlag

    init(deadline: Date?, cancellation: CancellationFlag) {
        self.deadline = deadline
        self.cancellation = cancellation
    }

    func shouldAbort() -> Bool {
        if cancellation.isCancelled { return true }
        if let deadline, Date() > deadline { return true }
        return false
    }
}
