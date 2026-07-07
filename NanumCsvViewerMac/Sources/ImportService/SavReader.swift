import CReadStat
import Darwin
import Foundation
import ImportServiceProtocol

public enum SavReader {
    public enum Error: Swift.Error, Equatable {
        case maxBytesExceeded
        case maxRowsExceeded
        case maxColumnsExceeded
        case maxCellsExceeded
        case timeoutExceeded
        case parseFailed(String)
    }

    public static func exportToCsv(
        source: FileHandle,
        output: FileHandle,
        metadataOutput: FileHandle? = nil,
        outputURL: URL,
        limits: ImportLimits
    ) throws -> ImportResult {
        try ReadStatTabularReader.exportToCsv(
            source: source,
            output: output,
            metadataOutput: metadataOutput,
            outputURL: outputURL,
            limits: limits,
            parse: readstat_parse_sav,
            bestEffortWarning: nil
        ).mapError { error in
            switch error {
            case .maxBytesExceeded: return SavReader.Error.maxBytesExceeded
            case .maxRowsExceeded: return SavReader.Error.maxRowsExceeded
            case .maxColumnsExceeded: return SavReader.Error.maxColumnsExceeded
            case .maxCellsExceeded: return SavReader.Error.maxCellsExceeded
            case .timeoutExceeded: return SavReader.Error.timeoutExceeded
            case .parseFailed(let message): return SavReader.Error.parseFailed(message)
            }
        }
    }
}

public enum Sas7bdatReader {
    public enum Error: Swift.Error, Equatable {
        case maxBytesExceeded
        case maxRowsExceeded
        case maxColumnsExceeded
        case maxCellsExceeded
        case timeoutExceeded
        case parseFailed(String)
    }

    public static let bestEffortWarning = ImportWarning(
        code: "sas-best-effort",
        message: "SAS import is best-effort; verify critical data against SAS."
    )

    public static func exportToCsv(
        source: FileHandle,
        output: FileHandle,
        metadataOutput: FileHandle? = nil,
        outputURL: URL,
        limits: ImportLimits
    ) throws -> ImportResult {
        try ReadStatTabularReader.exportToCsv(
            source: source,
            output: output,
            metadataOutput: metadataOutput,
            outputURL: outputURL,
            limits: limits,
            parse: readstat_parse_sas7bdat,
            bestEffortWarning: bestEffortWarning
        ).mapError { error in
            switch error {
            case .maxBytesExceeded: return Sas7bdatReader.Error.maxBytesExceeded
            case .maxRowsExceeded: return Sas7bdatReader.Error.maxRowsExceeded
            case .maxColumnsExceeded: return Sas7bdatReader.Error.maxColumnsExceeded
            case .maxCellsExceeded: return Sas7bdatReader.Error.maxCellsExceeded
            case .timeoutExceeded: return Sas7bdatReader.Error.timeoutExceeded
            case .parseFailed(let message): return Sas7bdatReader.Error.parseFailed(message)
            }
        }
    }
}

private enum ReadStatTabularReader {
    enum ReaderError: Swift.Error, Equatable {
        case maxBytesExceeded
        case maxRowsExceeded
        case maxColumnsExceeded
        case maxCellsExceeded
        case timeoutExceeded
        case parseFailed(String)
    }

    typealias ParserFunction = (
        UnsafeMutablePointer<readstat_parser_t>?,
        UnsafePointer<CChar>?,
        UnsafeMutableRawPointer?
    ) -> readstat_error_t

    static func exportToCsv(
        source: FileHandle,
        output: FileHandle,
        metadataOutput: FileHandle?,
        outputURL: URL,
        limits: ImportLimits,
        parse: ParserFunction,
        bestEffortWarning: ImportWarning?
    ) throws -> Result<ImportResult, ReaderError> {
        do {
            try output.truncate(atOffset: 0)
            let metadataURL = outputURL.appendingPathExtension("metadata.json")
            let ownedMetadataOutput: FileHandle?
            let resolvedMetadataOutput: FileHandle
            if let metadataOutput {
                resolvedMetadataOutput = metadataOutput
                ownedMetadataOutput = nil
            } else {
                try? FileManager.default.removeItem(at: metadataURL)
                FileManager.default.createFile(atPath: metadataURL.path, contents: nil)
                resolvedMetadataOutput = try FileHandle(forWritingTo: metadataURL)
                ownedMetadataOutput = resolvedMetadataOutput
            }
            defer { try? ownedMetadataOutput?.close() }
            try resolvedMetadataOutput.truncate(atOffset: 0)

            let byteCount = try source.seekToEnd()
            guard byteCount <= UInt64(limits.maxBytes) else {
                throw ReaderError.maxBytesExceeded
            }
            try source.seek(toOffset: 0)

            guard let parser = readstat_parser_init() else {
                throw ReaderError.parseFailed("ReadStat parser could not be initialized.")
            }
            defer { readstat_parser_free(parser) }

            let context = ReadStatImportContext(
                output: output,
                outputURL: outputURL,
                metadataOutput: resolvedMetadataOutput,
                metadataURL: metadataURL,
                limits: limits,
                deadline: Date().addingTimeInterval(limits.timeoutSeconds),
                bestEffortWarning: bestEffortWarning
            )
            let opaqueContext = Unmanaged.passUnretained(context).toOpaque()

            readstat_set_metadata_handler(parser, metadataHandler)
            readstat_set_variable_handler(parser, variableHandler)
            readstat_set_value_label_handler(parser, valueLabelHandler)
            readstat_set_value_handler(parser, valueHandler)
            readstat_set_error_handler(parser, errorHandler)
            readstat_set_progress_handler(parser, progressHandler)
            readstat_set_handler_character_encoding(parser, "UTF-8")
            let ioContext = ReadStatFileDescriptorIOContext(fileDescriptor: source.fileDescriptor, fileSize: byteCount)
            let opaqueIOContext = Unmanaged.passUnretained(ioContext).toOpaque()
            try configureFileDescriptorIO(parser: parser, ioContext: opaqueIOContext)

            let path = "xpc-import"
            let parseError = path.withCString { cPath in
                parse(parser, cPath, opaqueContext)
            }
            if let error = context.error {
                throw error
            }
            guard parseError == READSTAT_OK else {
                let message = context.errorMessage ?? String(cString: readstat_error_message(parseError))
                throw ReaderError.parseFailed(message)
            }

            try context.finish()
            return .success(context.result())
        } catch let error as ReaderError {
            try? output.truncate(atOffset: 0)
            try? metadataOutput?.truncate(atOffset: 0)
            try? FileManager.default.removeItem(at: outputURL.appendingPathExtension("metadata.json"))
            return .failure(error)
        } catch {
            try? output.truncate(atOffset: 0)
            try? metadataOutput?.truncate(atOffset: 0)
            try? FileManager.default.removeItem(at: outputURL.appendingPathExtension("metadata.json"))
            return .failure(.parseFailed("The file could not be read."))
        }
    }

    private static func configureFileDescriptorIO(
        parser: UnsafeMutablePointer<readstat_parser_t>,
        ioContext: UnsafeMutableRawPointer
    ) throws {
        let setResults = [
            readstat_set_open_handler(parser, fdOpenHandler),
            readstat_set_close_handler(parser, fdCloseHandler),
            readstat_set_seek_handler(parser, fdSeekHandler),
            readstat_set_read_handler(parser, fdReadHandler),
            readstat_set_update_handler(parser, fdUpdateHandler),
            readstat_set_io_ctx(parser, ioContext)
        ]
        guard setResults.allSatisfy({ $0 == READSTAT_OK }) else {
            throw ReaderError.parseFailed("ReadStat file descriptor I/O could not be initialized.")
        }
    }

    private static let fdOpenHandler: readstat_open_handler = { _, rawContext in
        guard let rawContext else { return -1 }
        let context = Unmanaged<ReadStatFileDescriptorIOContext>.fromOpaque(rawContext).takeUnretainedValue()
        let fd = dup(context.sourceFileDescriptor)
        guard fd >= 0 else { return -1 }
        _ = lseek(fd, 0, SEEK_SET)
        context.activeFileDescriptor = fd
        return fd
    }

    private static let fdCloseHandler: readstat_close_handler = { rawContext in
        guard let rawContext else { return 0 }
        let context = Unmanaged<ReadStatFileDescriptorIOContext>.fromOpaque(rawContext).takeUnretainedValue()
        guard context.activeFileDescriptor >= 0 else { return 0 }
        let result = close(context.activeFileDescriptor)
        context.activeFileDescriptor = -1
        return result
    }

    private static let fdSeekHandler: readstat_seek_handler = { offset, whence, rawContext in
        guard let rawContext else { return -1 }
        let context = Unmanaged<ReadStatFileDescriptorIOContext>.fromOpaque(rawContext).takeUnretainedValue()
        guard context.activeFileDescriptor >= 0 else { return -1 }
        let flag: Int32
        switch whence {
        case READSTAT_SEEK_SET:
            flag = SEEK_SET
        case READSTAT_SEEK_CUR:
            flag = SEEK_CUR
        case READSTAT_SEEK_END:
            flag = SEEK_END
        default:
            return -1
        }
        return lseek(context.activeFileDescriptor, offset, flag)
    }

    private static let fdReadHandler: readstat_read_handler = { buffer, byteCount, rawContext in
        guard let rawContext else { return -1 }
        let context = Unmanaged<ReadStatFileDescriptorIOContext>.fromOpaque(rawContext).takeUnretainedValue()
        guard context.activeFileDescriptor >= 0 else { return -1 }
        return read(context.activeFileDescriptor, buffer, byteCount)
    }

    private static let fdUpdateHandler: readstat_update_handler = { _, progressHandler, userContext, rawContext in
        guard let rawContext else { return READSTAT_OK }
        guard let progressHandler else { return READSTAT_OK }
        let context = Unmanaged<ReadStatFileDescriptorIOContext>.fromOpaque(rawContext).takeUnretainedValue()
        guard context.activeFileDescriptor >= 0 else { return READSTAT_ERROR_SEEK }
        let currentOffset = lseek(context.activeFileDescriptor, 0, SEEK_CUR)
        guard currentOffset >= 0 else { return READSTAT_ERROR_SEEK }
        let progress = context.fileSize == 0 ? 1.0 : Double(currentOffset) / Double(context.fileSize)
        return progressHandler(progress, userContext) == 0 ? READSTAT_OK : READSTAT_ERROR_USER_ABORT
    }

    private static let metadataHandler: readstat_metadata_handler = { metadata, rawContext in
        guard let metadata else { return Int32(READSTAT_HANDLER_ABORT) }
        let context = ReadStatImportContext.from(rawContext)
        context.rowCountHint = Int64(readstat_get_row_count(metadata))
        context.encoding = readstat_get_file_encoding(metadata).map { String(cString: $0) }
        let varCount = Int(readstat_get_var_count(metadata))
        if !context.enforceShape(rowCount: context.rowCountHint, columnCount: varCount) {
            return Int32(READSTAT_HANDLER_ABORT)
        }
        return Int32(READSTAT_HANDLER_OK)
    }

    private static let variableHandler: readstat_variable_handler = { _, variable, labelSetName, rawContext in
        guard let variable else { return Int32(READSTAT_HANDLER_ABORT) }
        let context = ReadStatImportContext.from(rawContext)
        let name = readstat_variable_get_name(variable).map { String(cString: $0) } ?? ""
        let label = readstat_variable_get_label(variable).flatMap { rawLabel -> String? in
            let value = String(cString: rawLabel)
            return value.isEmpty ? nil : value
        }
        let format = readstat_variable_get_format(variable).map { String(cString: $0) } ?? ""
        let labelSet = labelSetName.map { String(cString: $0) }.flatMap { $0.isEmpty ? nil : $0 }
        let declaredType = context.declaredType(for: variable, format: format)
        context.columns.append(ReadStatImportContext.Column(name: name, label: label, declaredType: declaredType, labelSetName: labelSet))
        if context.columns.count > context.limits.maxColumns {
            context.error = .maxColumnsExceeded
            return Int32(READSTAT_HANDLER_ABORT)
        }
        return Int32(READSTAT_HANDLER_OK)
    }

    private static let valueLabelHandler: readstat_value_label_handler = { labelSetName, value, label, rawContext in
        guard let labelSetName, let label else { return Int32(READSTAT_HANDLER_OK) }
        let context = ReadStatImportContext.from(rawContext)
        let setName = String(cString: labelSetName)
        context.valueLabels[setName, default: [:]][context.string(for: value)] = String(cString: label)
        return Int32(READSTAT_HANDLER_OK)
    }

    private static let valueHandler: readstat_value_handler = { obsIndex, variable, value, rawContext in
        guard let variable else { return Int32(READSTAT_HANDLER_ABORT) }
        let context = ReadStatImportContext.from(rawContext)
        do {
            try context.appendValue(obsIndex: Int(obsIndex), variable: variable, value: value)
            return Int32(READSTAT_HANDLER_OK)
        } catch let error as ReaderError {
            context.error = error
            return Int32(READSTAT_HANDLER_ABORT)
        } catch {
            context.error = .parseFailed("The parsed value could not be written.")
            return Int32(READSTAT_HANDLER_ABORT)
        }
    }

    private static let errorHandler: readstat_error_handler = { message, rawContext in
        guard let message else { return }
        ReadStatImportContext.from(rawContext).errorMessage = String(cString: message)
    }

    private static let progressHandler: readstat_progress_handler = { _, rawContext in
        let context = ReadStatImportContext.from(rawContext)
        if Date() > context.deadline {
            context.error = .timeoutExceeded
            return 1
        }
        return 0
    }
}

private final class ReadStatFileDescriptorIOContext {
    let sourceFileDescriptor: Int32
    let fileSize: UInt64
    var activeFileDescriptor: Int32 = -1

    init(fileDescriptor: Int32, fileSize: UInt64) {
        sourceFileDescriptor = fileDescriptor
        self.fileSize = fileSize
    }
}

private final class ReadStatImportContext {
    struct Column {
        let name: String
        let label: String?
        let declaredType: String
        let labelSetName: String?
    }

    struct Metadata: Codable {
        let columns: [MetadataColumn]
        let rowCount: Int64
        let encoding: String?
        let warnings: [MetadataWarning]
    }

    struct MetadataColumn: Codable {
        let name: String
        let label: String?
        let declaredType: String
        let valueLabels: [String: String]
    }

    struct MetadataWarning: Codable {
        let code: String
        let message: String
    }

    let output: FileHandle
    let outputURL: URL
    let metadataOutput: FileHandle
    let metadataURL: URL
    let limits: ImportLimits
    let deadline: Date

    var columns: [Column] = []
    var valueLabels: [String: [String: String]] = [:]
    var rowCountHint: Int64 = -1
    var encoding: String?
    var warnings: [ImportWarning]
    var error: ReadStatTabularReader.ReaderError?
    var errorMessage: String?

    private var wroteHeader = false
    private var currentObsIndex: Int?
    private var currentRow: [String] = []
    private var rowsWritten: Int64 = 0

    init(
        output: FileHandle,
        outputURL: URL,
        metadataOutput: FileHandle,
        metadataURL: URL,
        limits: ImportLimits,
        deadline: Date,
        bestEffortWarning: ImportWarning?
    ) {
        self.output = output
        self.outputURL = outputURL
        self.metadataOutput = metadataOutput
        self.metadataURL = metadataURL
        self.limits = limits
        self.deadline = deadline
        warnings = bestEffortWarning.map { [$0] } ?? []
    }

    static func from(_ rawContext: UnsafeMutableRawPointer?) -> ReadStatImportContext {
        Unmanaged<ReadStatImportContext>.fromOpaque(rawContext!).takeUnretainedValue()
    }

    func enforceShape(rowCount: Int64, columnCount: Int) -> Bool {
        if rowCount >= 0 && rowCount > limits.maxRows {
            error = .maxRowsExceeded
            return false
        }
        if columnCount > limits.maxColumns {
            error = .maxColumnsExceeded
            return false
        }
        if rowCount >= 0 && Int64(columnCount) * rowCount > limits.maxCells {
            error = .maxCellsExceeded
            return false
        }
        return true
    }

    func declaredType(for variable: UnsafeMutablePointer<readstat_variable_t>, format: String) -> String {
        let upperFormat = format.uppercased()
        if upperFormat.contains("DOLLAR") || upperFormat.contains("CURRENCY") {
            return "currency"
        }
        if upperFormat.contains("PCT") || upperFormat.contains("PERCENT") {
            return "percent"
        }
        if upperFormat.first == "E" {
            return "scientific"
        }

        switch readstat_variable_get_measure(variable) {
        case READSTAT_MEASURE_ORDINAL:
            return "ordinal"
        case READSTAT_MEASURE_NOMINAL:
            return "categorical"
        default:
            break
        }

        switch readstat_variable_get_type(variable) {
        case READSTAT_TYPE_STRING, READSTAT_TYPE_STRING_REF:
            return "categorical"
        case READSTAT_TYPE_INT8, READSTAT_TYPE_INT16, READSTAT_TYPE_INT32:
            return "integer"
        default:
            return "float"
        }
    }

    func appendValue(obsIndex: Int, variable: UnsafeMutablePointer<readstat_variable_t>, value: readstat_value_t) throws {
        if Date() > deadline {
            throw ReadStatTabularReader.ReaderError.timeoutExceeded
        }
        try writeHeaderIfNeeded()

        if currentObsIndex == nil {
            try beginRow(obsIndex)
        } else if currentObsIndex != obsIndex {
            try flushCurrentRow()
            try beginRow(obsIndex)
        }

        let index = Int(readstat_variable_get_index(variable))
        if index >= 0 && index < currentRow.count {
            currentRow[index] = string(for: value, variable: variable)
        }
    }

    func finish() throws {
        try writeHeaderIfNeeded()
        if currentObsIndex != nil {
            try flushCurrentRow()
        }
        let metadataColumns = columns.map { column in
            MetadataColumn(
                name: column.name,
                label: column.label,
                declaredType: column.declaredType,
                valueLabels: column.labelSetName.flatMap { valueLabels[$0] } ?? [:]
            )
        }
        let metadataWarnings = warnings.map { MetadataWarning(code: $0.code, message: $0.message) }
        let metadata = Metadata(
            columns: metadataColumns,
            rowCount: rowsWritten,
            encoding: encoding ?? "UTF-8",
            warnings: metadataWarnings
        )
        let data = try JSONEncoder().encode(metadata)
        try metadataOutput.truncate(atOffset: 0)
        try metadataOutput.seek(toOffset: 0)
        try metadataOutput.write(contentsOf: data)
    }

    func result() -> ImportResult {
        ImportResult(
            csvURL: outputURL,
            metadataURL: metadataURL,
            warnings: warnings,
            rowCount: rowsWritten,
            columnCount: columns.count
        )
    }

    func string(for value: readstat_value_t, variable: UnsafeMutablePointer<readstat_variable_t>? = nil) -> String {
        if let variable, readstat_value_is_missing(value, variable) != 0 {
            return ""
        }
        switch readstat_value_type(value) {
        case READSTAT_TYPE_STRING, READSTAT_TYPE_STRING_REF:
            guard let rawString = readstat_string_value(value) else { return "" }
            return String(cString: rawString)
        case READSTAT_TYPE_INT8:
            return String(readstat_int8_value(value))
        case READSTAT_TYPE_INT16:
            return String(readstat_int16_value(value))
        case READSTAT_TYPE_INT32:
            return String(readstat_int32_value(value))
        case READSTAT_TYPE_FLOAT:
            return numberString(Double(readstat_float_value(value)))
        default:
            return numberString(readstat_double_value(value))
        }
    }

    private func beginRow(_ obsIndex: Int) throws {
        if rowsWritten + 1 > limits.maxRows {
            throw ReadStatTabularReader.ReaderError.maxRowsExceeded
        }
        if Int64(columns.count) * (rowsWritten + 1) > limits.maxCells {
            throw ReadStatTabularReader.ReaderError.maxCellsExceeded
        }
        currentObsIndex = obsIndex
        currentRow = Array(repeating: "", count: columns.count)
    }

    private func flushCurrentRow() throws {
        if rowsWritten > 0 {
            try output.write(contentsOf: Data("\n".utf8))
        }
        try output.write(contentsOf: Data(currentRow.map(csvEscaped).joined(separator: ",").utf8))
        rowsWritten += 1
        currentObsIndex = nil
        currentRow = []
    }

    private func writeHeaderIfNeeded() throws {
        guard !wroteHeader else { return }
        try output.write(contentsOf: Data(columns.map(\.name).map(csvEscaped).joined(separator: ",").utf8))
        wroteHeader = true
        if !columns.isEmpty {
            try output.write(contentsOf: Data("\n".utf8))
        }
    }

    private func csvEscaped(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r") {
            return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return value
    }

    private func numberString(_ number: Double) -> String {
        String(format: "%.15g", locale: Locale(identifier: "en_US_POSIX"), number)
    }
}

private extension Result where Failure == ReadStatTabularReader.ReaderError {
    func mapError<E: Swift.Error>(_ transform: (Failure) -> E) throws -> Success {
        switch self {
        case .success(let value):
            return value
        case .failure(let error):
            throw transform(error)
        }
    }
}
