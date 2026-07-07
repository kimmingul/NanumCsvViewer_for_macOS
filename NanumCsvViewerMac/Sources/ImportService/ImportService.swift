import Foundation
import ImportServiceProtocol

final class ImportService: NSObject, ImportServiceProtocol {
    func inspectFile(
        sourceFile: ImportFileReference,
        kind: ImportKind,
        limits: ImportLimits,
        reply: @escaping (ImportInspection?, ImportError?) -> Void
    ) {
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
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        newConnection.exportedInterface = ImportServiceXPCInterface.make()
        newConnection.exportedObject = ImportService()
        newConnection.activate()
        return true
    }
}
