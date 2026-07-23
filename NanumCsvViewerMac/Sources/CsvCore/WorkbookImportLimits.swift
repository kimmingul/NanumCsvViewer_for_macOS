import Foundation

/// Resource ceilings enforced while converting a binary workbook (XLSX / SQLite)
/// to CSV. Mirrors the fields of the XPC `ImportLimits` but lives in CsvCore so
/// the readers stay decoupled from the import-service protocol. `.unlimited`
/// preserves the historical (uncapped) behavior for callers that don't opt in.
public struct WorkbookImportLimits: Sendable, Equatable {
    public let maxRows: Int
    public let maxColumns: Int
    public let maxCells: Int
    /// Per-cell character ceiling (a shared/inline XLSX string, a SQLite value).
    /// Bounds a single ~100MB crafted value, independent of row/cell counts.
    public let maxCellChars: Int
    /// Ceiling on a single inflated ZIP entry (one worksheet/sharedStrings part).
    public let maxUncompressedEntryBytes: Int
    /// Ceiling on the sum of all inflated ZIP entries read for one workbook.
    public let maxTotalUncompressedBytes: Int
    public let deadline: Date?

    public init(
        maxRows: Int,
        maxColumns: Int,
        maxCells: Int,
        maxCellChars: Int = .max,
        maxUncompressedEntryBytes: Int = .max,
        maxTotalUncompressedBytes: Int = .max,
        deadline: Date? = nil
    ) {
        self.maxRows = maxRows
        self.maxColumns = maxColumns
        self.maxCells = maxCells
        self.maxCellChars = maxCellChars
        self.maxUncompressedEntryBytes = maxUncompressedEntryBytes
        self.maxTotalUncompressedBytes = maxTotalUncompressedBytes
        self.deadline = deadline
    }

    public static let unlimited = WorkbookImportLimits(
        maxRows: .max,
        maxColumns: .max,
        maxCells: .max,
        maxCellChars: .max,
        maxUncompressedEntryBytes: .max,
        maxTotalUncompressedBytes: .max,
        deadline: nil
    )

    /// Throws if `value` exceeds the per-cell character ceiling.
    func checkCell(_ value: String) throws {
        if maxCellChars != .max, value.count > maxCellChars {
            throw WorkbookImportError.maxCellCharsExceeded
        }
    }

    /// Throws once the wall-clock deadline (if any) has passed. Cheap enough to
    /// call inside per-row loops.
    func checkDeadline() throws {
        if let deadline, Date() > deadline {
            throw WorkbookImportError.timedOut
        }
    }

    /// Throws if writing `row` more output rows — each `columnCount` cells wide —
    /// would breach the row or cell ceiling. Call before writing each row.
    func checkRowBudget(alreadyWritten rows: Int, columnCount: Int) throws {
        if rows >= maxRows {
            throw WorkbookImportError.maxRowsExceeded
        }
        let width = Swift.max(1, columnCount)
        if maxCells != .max, (rows + 1) > maxCells / width {
            throw WorkbookImportError.maxCellsExceeded
        }
    }
}

public enum WorkbookImportError: Error, Equatable {
    case maxRowsExceeded
    case maxColumnsExceeded
    case maxCellsExceeded
    case maxCellCharsExceeded
    case maxUncompressedBytesExceeded
    case timedOut
}
