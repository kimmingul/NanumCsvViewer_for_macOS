import CsvCore
import Foundation
import ImportServiceProtocol

/// Runs the XLSX / SQLite → CSV conversion inside the sandboxed import service.
/// The untrusted source arrives as a file descriptor; it is copied into the
/// service's own temp container (bounded by `maxBytes`) so the path-based
/// CsvCore readers can parse it, and every conversion is capped by `ImportLimits`.
enum WorkbookImporter {
    enum Failure: Error {
        case maxBytesExceeded
        case timedOut
        case noParts
    }

    static func inspectXlsx(source: FileHandle, limits: ImportLimits) throws -> [String] {
        let deadline = Date().addingTimeInterval(limits.timeoutSeconds)
        let sourceURL = try materialize(source, limits: limits, deadline: deadline)
        defer { try? FileManager.default.removeItem(at: sourceURL) }
        let names = try XlsxWorkbook.sheetNames(path: sourceURL.path)
        guard !names.isEmpty else { throw Failure.noParts }
        return names
    }

    static func inspectSqlite(source: FileHandle, limits: ImportLimits) throws -> [String] {
        let deadline = Date().addingTimeInterval(limits.timeoutSeconds)
        let sourceURL = try materialize(source, limits: limits, deadline: deadline)
        defer { try? FileManager.default.removeItem(at: sourceURL) }
        let names = try SqliteWorkbook.tableNames(path: sourceURL.path)
        guard !names.isEmpty else { throw Failure.noParts }
        return names
    }

    static func importXlsx(
        source: FileHandle,
        sheetName: String?,
        output: FileHandle,
        outputURL: URL,
        limits: ImportLimits
    ) throws -> ImportResult {
        let deadline = Date().addingTimeInterval(limits.timeoutSeconds)
        let sourceURL = try materialize(source, limits: limits, deadline: deadline)
        defer { try? FileManager.default.removeItem(at: sourceURL) }

        let sheet: String
        if let sheetName {
            sheet = sheetName
        } else {
            guard let first = try XlsxWorkbook.sheetNames(path: sourceURL.path).first else {
                throw Failure.noParts
            }
            sheet = first
        }

        try output.truncate(atOffset: 0)
        let rows = try XlsxWorkbook.exportSheetToCsv(
            path: sourceURL.path,
            sheet: sheet,
            output: output,
            limits: workbookLimits(limits, deadline: deadline)
        )
        return ImportResult(csvURL: outputURL, metadataURL: nil, warnings: [], rowCount: Int64(rows), columnCount: 0)
    }

    static func importSqlite(
        source: FileHandle,
        tableName: String?,
        output: FileHandle,
        outputURL: URL,
        limits: ImportLimits
    ) throws -> ImportResult {
        let deadline = Date().addingTimeInterval(limits.timeoutSeconds)
        let sourceURL = try materialize(source, limits: limits, deadline: deadline)
        defer { try? FileManager.default.removeItem(at: sourceURL) }

        let table: String
        if let tableName {
            table = tableName
        } else {
            guard let first = try SqliteWorkbook.tableNames(path: sourceURL.path).first else {
                throw Failure.noParts
            }
            table = first
        }

        try output.truncate(atOffset: 0)
        let rows = try SqliteWorkbook.exportTableToCsv(
            path: sourceURL.path,
            table: table,
            output: output,
            limits: workbookLimits(limits, deadline: deadline)
        )
        return ImportResult(csvURL: outputURL, metadataURL: nil, warnings: [], rowCount: Int64(rows), columnCount: 0)
    }

    // MARK: - Helpers

    private static func materialize(_ source: FileHandle, limits: ImportLimits, deadline: Date) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("NanumImportService", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(UUID().uuidString)
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let out = try FileHandle(forWritingTo: url)
        defer { try? out.close() }

        do {
            try source.seek(toOffset: 0)
            var total: Int64 = 0
            while true {
                if Date() > deadline { throw Failure.timedOut }
                let chunk = try source.read(upToCount: 256 * 1024) ?? Data()
                if chunk.isEmpty { break }
                total += Int64(chunk.count)
                if total > limits.maxBytes { throw Failure.maxBytesExceeded }
                try out.write(contentsOf: chunk)
            }
            return url
        } catch {
            try? out.close()
            try? FileManager.default.removeItem(at: url)
            throw error
        }
    }

    private static func workbookLimits(_ limits: ImportLimits, deadline: Date) -> WorkbookImportLimits {
        WorkbookImportLimits(
            maxRows: clampToInt(limits.maxRows),
            maxColumns: limits.maxColumns,
            maxCells: clampToInt(limits.maxCells),
            deadline: deadline
        )
    }

    private static func clampToInt(_ value: Int64) -> Int {
        value >= Int64(Int.max) ? Int.max : Int(value)
    }
}
