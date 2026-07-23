import CsvCore
import Foundation
import ImportServiceProtocol

final class ImportService: NSObject, ImportServiceProtocol {
    func inspectFile(
        sourceFile: ImportFileReference,
        kind: ImportKind,
        limits: ImportLimits,
        reply: @escaping (ImportInspection?, ImportError?) -> Void
    ) {
        if kind == .xlsx {
            do {
                reply(ImportInspection(sheetNames: try WorkbookImporter.inspectXlsx(source: sourceFile.fileHandle, limits: limits)), nil)
            } catch {
                reply(nil, Self.mapWorkbookError(error))
            }
            return
        }

        if kind == .sqlite {
            do {
                reply(ImportInspection(sheetNames: try WorkbookImporter.inspectSqlite(source: sourceFile.fileHandle, limits: limits)), nil)
            } catch {
                reply(nil, Self.mapWorkbookError(error))
            }
            return
        }

        guard kind == .xls else {
            reply(nil, ImportError(code: "unsupportedKind", message: "Unsupported import kind."))
            return
        }

        do {
            let sheetNames = try XlsBiffReader.sheetNames(source: sourceFile.fileHandle, limits: limits)
            reply(ImportInspection(sheetNames: sheetNames), nil)
        } catch XlsBiffReader.Error.maxBytesExceeded {
            reply(nil, ImportError(code: "maxBytesExceeded", message: "The source file exceeds the import byte limit."))
        } catch XlsBiffReader.Error.timeoutExceeded {
            reply(nil, ImportError(code: "timeoutExceeded", message: "The import timed out."))
        } catch XlsBiffReader.Error.noSheets {
            reply(nil, ImportError(code: "noSheets", message: "The workbook has no readable sheets."))
        } catch XlsBiffReader.Error.parseFailed(let message) {
            reply(nil, ImportError(code: "parseFailed", message: message))
        } catch {
            reply(nil, ImportError(code: "readFailed", message: "The workbook could not be inspected."))
        }
    }

    func importFile(
        sourceFile: ImportFileReference,
        kind: ImportKind,
        limits: ImportLimits,
        outputFile: ImportFileReference,
        metadataFile: ImportFileReference?,
        outputURL: URL,
        reply: @escaping (ImportResult?, ImportError?) -> Void
    ) {
        if kind == .echo {
            importEcho(sourceFile: sourceFile, limits: limits, outputFile: outputFile, outputURL: outputURL, reply: reply)
            return
        }

        if kind == .xls || kind.xlsSheetName != nil {
            importXls(sourceFile: sourceFile, sheetName: kind.xlsSheetName, limits: limits, outputFile: outputFile, outputURL: outputURL, reply: reply)
            return
        }

        if kind == .xlsx || kind.xlsxSheetName != nil {
            do {
                let result = try WorkbookImporter.importXlsx(
                    source: sourceFile.fileHandle,
                    sheetName: kind.xlsxSheetName,
                    output: outputFile.fileHandle,
                    outputURL: outputURL,
                    limits: limits
                )
                reply(result, nil)
            } catch {
                reply(nil, Self.mapWorkbookError(error))
            }
            return
        }

        if kind == .sqlite || kind.sqliteTableName != nil {
            do {
                let result = try WorkbookImporter.importSqlite(
                    source: sourceFile.fileHandle,
                    tableName: kind.sqliteTableName,
                    output: outputFile.fileHandle,
                    outputURL: outputURL,
                    limits: limits
                )
                reply(result, nil)
            } catch {
                reply(nil, Self.mapWorkbookError(error))
            }
            return
        }

        if kind == .sav {
            importSav(sourceFile: sourceFile, limits: limits, outputFile: outputFile, metadataFile: metadataFile, outputURL: outputURL, reply: reply)
            return
        }

        if kind == .sas7bdat {
            importSas(sourceFile: sourceFile, limits: limits, outputFile: outputFile, metadataFile: metadataFile, outputURL: outputURL, reply: reply)
            return
        }

        reply(nil, ImportError(code: "unsupportedKind", message: "Unsupported import kind."))
    }

    private func importEcho(
        sourceFile: ImportFileReference,
        limits: ImportLimits,
        outputFile: ImportFileReference,
        outputURL: URL,
        reply: @escaping (ImportResult?, ImportError?) -> Void
    ) {
        do {
            let result = try EchoImporter.copy(
                source: sourceFile.fileHandle,
                output: outputFile.fileHandle,
                outputURL: outputURL,
                limits: limits
            )
            reply(result, nil)
        } catch EchoImporter.Error.maxBytesExceeded {
            reply(nil, ImportError(code: "maxBytesExceeded", message: "The source file exceeds the import byte limit."))
        } catch EchoImporter.Error.timeoutExceeded {
            reply(nil, ImportError(code: "timeoutExceeded", message: "The import timed out."))
        } catch {
            reply(nil, ImportError(code: "readFailed", message: "The source file could not be copied."))
        }
    }

    private func importXls(
        sourceFile: ImportFileReference,
        sheetName: String?,
        limits: ImportLimits,
        outputFile: ImportFileReference,
        outputURL: URL,
        reply: @escaping (ImportResult?, ImportError?) -> Void
    ) {
        do {
            let result = try XlsBiffReader.exportSheetToCsv(
                source: sourceFile.fileHandle,
                sheetName: sheetName,
                output: outputFile.fileHandle,
                outputURL: outputURL,
                limits: limits
            )
            reply(result, nil)
        } catch XlsBiffReader.Error.maxBytesExceeded {
            reply(nil, ImportError(code: "maxBytesExceeded", message: "The source file exceeds the import byte limit."))
        } catch XlsBiffReader.Error.maxRowsExceeded {
            reply(nil, ImportError(code: "maxRowsExceeded", message: "The workbook exceeds the import row limit."))
        } catch XlsBiffReader.Error.maxColumnsExceeded {
            reply(nil, ImportError(code: "maxColumnsExceeded", message: "The workbook exceeds the import column limit."))
        } catch XlsBiffReader.Error.maxCellsExceeded {
            reply(nil, ImportError(code: "maxCellsExceeded", message: "The workbook exceeds the import cell limit."))
        } catch XlsBiffReader.Error.timeoutExceeded {
            reply(nil, ImportError(code: "timeoutExceeded", message: "The import timed out."))
        } catch XlsBiffReader.Error.noSheets {
            reply(nil, ImportError(code: "noSheets", message: "The workbook has no readable sheets."))
        } catch XlsBiffReader.Error.parseFailed(let message) {
            reply(nil, ImportError(code: "parseFailed", message: message))
        } catch {
            reply(nil, ImportError(code: "readFailed", message: "The workbook could not be read."))
        }
    }

    static func mapWorkbookError(_ error: Error) -> ImportError {
        switch error {
        case WorkbookImporter.Failure.maxBytesExceeded:
            return ImportError(code: "maxBytesExceeded", message: "The source file exceeds the import byte limit.")
        case WorkbookImporter.Failure.timedOut, WorkbookImportError.timedOut:
            return ImportError(code: "timeoutExceeded", message: "The import timed out.")
        case WorkbookImporter.Failure.noParts:
            return ImportError(code: "noSheets", message: "The file has no readable sheets or tables.")
        case WorkbookImportError.maxRowsExceeded:
            return ImportError(code: "maxRowsExceeded", message: "The file exceeds the import row limit.")
        case WorkbookImportError.maxColumnsExceeded:
            return ImportError(code: "maxColumnsExceeded", message: "The file exceeds the import column limit.")
        case WorkbookImportError.maxCellsExceeded:
            return ImportError(code: "maxCellsExceeded", message: "The file exceeds the import cell limit.")
        case WorkbookImportError.maxCellCharsExceeded:
            return ImportError(code: "maxCellCharsExceeded", message: "A cell in the file is too large to import.")
        case WorkbookImportError.maxUncompressedBytesExceeded:
            return ImportError(code: "maxUncompressedBytesExceeded", message: "The file expands too much to import.")
        case let XlsxWorkbookError.sheetNotFound(name):
            return ImportError(code: "parseFailed", message: "Sheet \"\(name)\" was not found.")
        case let XlsxWorkbookError.invalidWorkbook(message):
            return ImportError(code: "parseFailed", message: message)
        case let XlsxWorkbookError.cannotOpen(message):
            return ImportError(code: "parseFailed", message: message)
        case let SqliteWorkbookError.tableNotFound(name):
            return ImportError(code: "parseFailed", message: "Table \"\(name)\" was not found.")
        case let SqliteWorkbookError.queryFailed(message):
            return ImportError(code: "parseFailed", message: message)
        case let SqliteWorkbookError.cannotOpen(message):
            return ImportError(code: "parseFailed", message: message)
        default:
            return ImportError(code: "readFailed", message: "The file could not be read.")
        }
    }

    private func importSav(
        sourceFile: ImportFileReference,
        limits: ImportLimits,
        outputFile: ImportFileReference,
        metadataFile: ImportFileReference?,
        outputURL: URL,
        reply: @escaping (ImportResult?, ImportError?) -> Void
    ) {
        do {
            let result = try SavReader.exportToCsv(
                source: sourceFile.fileHandle,
                output: outputFile.fileHandle,
                metadataOutput: metadataFile?.fileHandle,
                outputURL: outputURL,
                limits: limits
            )
            reply(result, nil)
        } catch SavReader.Error.maxBytesExceeded {
            reply(nil, ImportError(code: "maxBytesExceeded", message: "The source file exceeds the import byte limit."))
        } catch SavReader.Error.maxRowsExceeded {
            reply(nil, ImportError(code: "maxRowsExceeded", message: "The data set exceeds the import row limit."))
        } catch SavReader.Error.maxColumnsExceeded {
            reply(nil, ImportError(code: "maxColumnsExceeded", message: "The data set exceeds the import column limit."))
        } catch SavReader.Error.maxCellsExceeded {
            reply(nil, ImportError(code: "maxCellsExceeded", message: "The data set exceeds the import cell limit."))
        } catch SavReader.Error.timeoutExceeded {
            reply(nil, ImportError(code: "timeoutExceeded", message: "The import timed out."))
        } catch SavReader.Error.parseFailed(let message) {
            reply(nil, ImportError(code: "parseFailed", message: message))
        } catch {
            reply(nil, ImportError(code: "readFailed", message: "The SPSS file could not be read."))
        }
    }

    private func importSas(
        sourceFile: ImportFileReference,
        limits: ImportLimits,
        outputFile: ImportFileReference,
        metadataFile: ImportFileReference?,
        outputURL: URL,
        reply: @escaping (ImportResult?, ImportError?) -> Void
    ) {
        do {
            let result = try Sas7bdatReader.exportToCsv(
                source: sourceFile.fileHandle,
                output: outputFile.fileHandle,
                metadataOutput: metadataFile?.fileHandle,
                outputURL: outputURL,
                limits: limits
            )
            reply(result, nil)
        } catch Sas7bdatReader.Error.maxBytesExceeded {
            reply(nil, ImportError(code: "maxBytesExceeded", message: "The source file exceeds the import byte limit."))
        } catch Sas7bdatReader.Error.maxRowsExceeded {
            reply(nil, ImportError(code: "maxRowsExceeded", message: "The data set exceeds the import row limit."))
        } catch Sas7bdatReader.Error.maxColumnsExceeded {
            reply(nil, ImportError(code: "maxColumnsExceeded", message: "The data set exceeds the import column limit."))
        } catch Sas7bdatReader.Error.maxCellsExceeded {
            reply(nil, ImportError(code: "maxCellsExceeded", message: "The data set exceeds the import cell limit."))
        } catch Sas7bdatReader.Error.timeoutExceeded {
            reply(nil, ImportError(code: "timeoutExceeded", message: "The import timed out."))
        } catch Sas7bdatReader.Error.parseFailed(let message) {
            reply(nil, ImportError(code: "parseFailed", message: message))
        } catch {
            reply(nil, ImportError(code: "readFailed", message: "The SAS file could not be read."))
        }
    }
}

final class ImportServiceDelegate: NSObject, NSXPCListenerDelegate {
    /// Code requirement a connecting peer must satisfy. `nil` accepts any peer
    /// (the shipping default — see PeerValidator). Enabling enforcement is
    /// blocked on a Team ID + a signed-build CI smoke test.
    static let peerRequirement: String? = nil

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        let accepted = PeerValidator.isAcceptable(requirement: Self.peerRequirement) {
            // Placeholder: fail closed until the peer audit-token accessor is
            // wired up (SDK doesn't expose NSXPCConnection.auditToken publicly).
            // The real check is PeerValidator.auditTokenSatisfies; enabling it is
            // part of the signed-build work. Rejecting here can never ship open.
            false
        }
        guard accepted else { return false }

        newConnection.exportedInterface = ImportServiceXPCInterface.make()
        newConnection.exportedObject = ImportService()
        newConnection.activate()
        return true
    }
}
