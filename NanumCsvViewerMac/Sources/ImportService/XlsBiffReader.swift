import CLibXLS
import Foundation
import ImportServiceProtocol

public enum XlsBiffReader {
    public enum Error: Swift.Error, Equatable {
        case maxBytesExceeded
        case maxRowsExceeded
        case maxColumnsExceeded
        case maxCellsExceeded
        case timeoutExceeded
        case noSheets
        case parseFailed(String)
    }

    private static let ole2Magic: [UInt8] = [0xD0, 0xCF, 0x11, 0xE0]

    public static func hasXlsExtension(_ path: String) -> Bool {
        (path as NSString).pathExtension.lowercased() == "xls"
    }

    public static func isXlsFile(path: String) -> Bool {
        guard let handle = FileHandle(forReadingAtPath: path) else { return false }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: ole2Magic.count), data.count == ole2Magic.count else {
            return false
        }
        return Array(data) == ole2Magic
    }

    public static func exportFirstSheetToCsv(
        source: FileHandle,
        output: FileHandle,
        outputURL: URL,
        limits: ImportLimits
    ) throws -> ImportResult {
        try exportSheetToCsv(source: source, sheetName: nil, output: output, outputURL: outputURL, limits: limits)
    }

    public static func sheetNames(source: FileHandle, limits: ImportLimits) throws -> [String] {
        let deadline = Date().addingTimeInterval(limits.timeoutSeconds)
        let data = try readSource(source, limits: limits, deadline: deadline)
        return try data.withUnsafeBytes { rawBuffer -> [String] in
            guard let baseAddress = rawBuffer.bindMemory(to: UInt8.self).baseAddress else {
                throw Error.parseFailed("The workbook is empty.")
            }

            var openError = LIBXLS_OK
            guard let workbook = xls_open_buffer(baseAddress, data.count, "UTF-8", &openError) else {
                throw Error.parseFailed(String(cString: xls_getError(openError)))
            }
            defer { xls_close_WB(workbook) }

            let count = Int(workbook.pointee.sheets.count)
            guard count > 0 else {
                throw Error.noSheets
            }
            return (0..<count).map { index in
                guard let rawName = workbook.pointee.sheets.sheet[index].name else {
                    return ""
                }
                return String(cString: rawName)
            }
        }
    }

    public static func exportSheetToCsv(
        source: FileHandle,
        sheetName: String?,
        output: FileHandle,
        outputURL: URL,
        limits: ImportLimits
    ) throws -> ImportResult {
        do {
            try output.truncate(atOffset: 0)
            let deadline = Date().addingTimeInterval(limits.timeoutSeconds)
            let data = try readSource(source, limits: limits, deadline: deadline)
            let result = try data.withUnsafeBytes { rawBuffer -> ImportResult in
                guard let baseAddress = rawBuffer.bindMemory(to: UInt8.self).baseAddress else {
                    throw Error.parseFailed("The workbook is empty.")
                }

                var openError = LIBXLS_OK
                guard let workbook = xls_open_buffer(baseAddress, data.count, "UTF-8", &openError) else {
                    throw Error.parseFailed(String(cString: xls_getError(openError)))
                }
                defer { xls_close_WB(workbook) }

                guard workbook.pointee.sheets.count > 0 else {
                    throw Error.noSheets
                }
                let sheetIndex = try sheetIndex(in: workbook, named: sheetName)
                guard let worksheet = xls_getWorkSheet(workbook, Int32(sheetIndex)) else {
                    throw Error.parseFailed("The worksheet could not be opened.")
                }
                defer { xls_close_WS(worksheet) }

                let parseError = xls_parseWorkSheet(worksheet)
                guard parseError == LIBXLS_OK else {
                    throw Error.parseFailed(String(cString: xls_getError(parseError)))
                }

                let rowCount = Int(worksheet.pointee.rows.lastrow) + 1
                let columnCount = Int(worksheet.pointee.rows.lastcol) + 1
                try enforceShape(rowCount: rowCount, columnCount: columnCount, limits: limits)

                for row in 0..<rowCount {
                    if Date() > deadline {
                        throw Error.timeoutExceeded
                    }
                    if row > 0 {
                        try output.write(contentsOf: Data("\n".utf8))
                    }
                    for column in 0..<columnCount {
                        if column > 0 {
                            try output.write(contentsOf: Data(",".utf8))
                        }
                        let cell = xls_cell(worksheet, WORD(row), WORD(column))
                        let value = csvValue(for: cell)
                        try output.write(contentsOf: Data(value.utf8))
                    }
                }

                return ImportResult(
                    csvURL: outputURL,
                    metadataURL: nil,
                    warnings: [],
                    rowCount: Int64(rowCount),
                    columnCount: columnCount
                )
            }
            return result
        } catch {
            try? output.truncate(atOffset: 0)
            throw error
        }
    }

    private static func sheetIndex(in workbook: UnsafeMutablePointer<xlsWorkBook>, named sheetName: String?) throws -> Int {
        guard let sheetName else {
            return 0
        }
        let count = Int(workbook.pointee.sheets.count)
        for index in 0..<count {
            guard let rawName = workbook.pointee.sheets.sheet[index].name else { continue }
            if String(cString: rawName) == sheetName {
                return index
            }
        }
        throw Error.parseFailed("Sheet \"\(sheetName)\" was not found.")
    }

    private static func readSource(
        _ source: FileHandle,
        limits: ImportLimits,
        deadline: Date
    ) throws -> Data {
        try source.seek(toOffset: 0)
        var data = Data()
        while true {
            if Date() > deadline {
                throw Error.timeoutExceeded
            }
            let chunk = try source.read(upToCount: 64 * 1024) ?? Data()
            if chunk.isEmpty {
                break
            }
            data.append(chunk)
            if data.count > limits.maxBytes {
                throw Error.maxBytesExceeded
            }
        }
        return data
    }

    private static func enforceShape(rowCount: Int, columnCount: Int, limits: ImportLimits) throws {
        if rowCount > limits.maxRows {
            throw Error.maxRowsExceeded
        }
        if columnCount > limits.maxColumns {
            throw Error.maxColumnsExceeded
        }
        if Int64(rowCount) * Int64(columnCount) > limits.maxCells {
            throw Error.maxCellsExceeded
        }
    }

    private static func csvValue(for cellPointer: UnsafeMutablePointer<xlsCell>?) -> String {
        guard let cellPointer else {
            return ""
        }
        let cell = cellPointer.pointee
        if cell.isHidden != 0 {
            return ""
        }

        switch Int32(cell.id) {
        case XLS_RECORD_RK, XLS_RECORD_MULRK, XLS_RECORD_NUMBER:
            return numberString(cell.d)
        case XLS_RECORD_FORMULA, XLS_RECORD_FORMULA_ALT:
            if cell.l == 0 {
                return numberString(cell.d)
            }
            return formulaString(cell.str, numericValue: cell.d)
        default:
            guard let rawString = cell.str else {
                return ""
            }
            return csvEscaped(String(cString: rawString))
        }
    }

    private static func formulaString(_ rawString: UnsafeMutablePointer<CChar>?, numericValue: Double) -> String {
        guard let rawString else {
            return ""
        }
        let string = String(cString: rawString)
        if string == "bool" {
            return csvEscaped(numericValue > 0 ? "true" : "false")
        }
        if string == "error" {
            return csvEscaped("*error*")
        }
        return csvEscaped(string)
    }

    private static func numberString(_ number: Double) -> String {
        String(format: "%.15g", locale: Locale(identifier: "en_US_POSIX"), number)
    }

    private static func csvEscaped(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r") {
            return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return value
    }
}
