import Foundation
import ImportServiceProtocol

enum ImportClientError: Error, Equatable {
    case cannotOpenBridgeFiles
    case connectionInterrupted
    case connectionInvalidated
    case invalidReply
    case serviceError(code: String, message: String)
}

final class ImportClient {
    static let serviceName = "com.nanum.csvviewer.ImportService"
    /// Grace period beyond the service's own deadline before the client gives up
    /// on a hung import and tears the connection down.
    private static let watchdogMargin: TimeInterval = 30

    private let injectedService: ImportServiceProtocol?

    init(service: ImportServiceProtocol? = nil) {
        injectedService = service
    }

    func inspectXls(
        sourceURL: URL,
        limits: ImportLimits,
        completion: @escaping (Result<ImportInspection, ImportClientError>) -> Void
    ) {
        inspect(sourceURL: sourceURL, kind: .xls, limits: limits, completion: completion)
    }

    func inspectXlsx(
        sourceURL: URL,
        limits: ImportLimits,
        completion: @escaping (Result<ImportInspection, ImportClientError>) -> Void
    ) {
        inspect(sourceURL: sourceURL, kind: .xlsx, limits: limits, completion: completion)
    }

    func inspectSqlite(
        sourceURL: URL,
        limits: ImportLimits,
        completion: @escaping (Result<ImportInspection, ImportClientError>) -> Void
    ) {
        inspect(sourceURL: sourceURL, kind: .sqlite, limits: limits, completion: completion)
    }

    private func inspect(
        sourceURL: URL,
        kind: ImportKind,
        limits: ImportLimits,
        completion: @escaping (Result<ImportInspection, ImportClientError>) -> Void
    ) {
        let sourceHandle: FileHandle
        do {
            sourceHandle = try FileHandle(forReadingFrom: sourceURL)
        } catch {
            completion(.failure(.cannotOpenBridgeFiles))
            return
        }
        let sourceFile = ImportFileReference(fileHandle: sourceHandle)

        if let injectedService {
            sendInspection(to: injectedService, sourceFile: sourceFile, kind: kind, limits: limits) { result in
                try? sourceHandle.close()
                completion(result)
            }
            return
        }

        let connection = NSXPCConnection(serviceName: Self.serviceName)
        connection.remoteObjectInterface = ImportServiceXPCInterface.make()

        let completionBox = ImportInspectionCompletionBox {
            try? sourceHandle.close()
            connection.invalidate()
            completion($0)
        }
        connection.interruptionHandler = {
            completionBox.complete(.failure(.connectionInterrupted))
        }
        connection.invalidationHandler = {
            completionBox.complete(.failure(.connectionInvalidated))
        }
        connection.activate()

        let service = connection.remoteObjectProxyWithErrorHandler { _ in
            completionBox.complete(.failure(.connectionInvalidated))
        } as? ImportServiceProtocol

        guard let service else {
            completionBox.complete(.failure(.connectionInvalidated))
            return
        }

        sendInspection(
            to: service,
            sourceFile: sourceFile,
            kind: kind,
            limits: limits,
            completion: completionBox.complete
        )
        completionBox.arm(timeout: limits.timeoutSeconds + Self.watchdogMargin)
    }

    func importEcho(
        sourceURL: URL,
        destinationDir: URL,
        limits: ImportLimits,
        completion: @escaping (Result<ImportResult, ImportClientError>) -> Void
    ) {
        importFile(
            sourceURL: sourceURL,
            destinationDir: destinationDir,
            outputFileName: "echo.csv",
            kind: .echo,
            limits: limits,
            completion: completion
        )
    }

    func importXls(
        sourceURL: URL,
        destinationDir: URL,
        sheetName: String? = nil,
        limits: ImportLimits,
        completion: @escaping (Result<ImportResult, ImportClientError>) -> Void
    ) {
        importFile(
            sourceURL: sourceURL,
            destinationDir: destinationDir,
            outputFileName: "import.csv",
            kind: sheetName.map(ImportKind.xlsSheet) ?? .xls,
            limits: limits,
            completion: completion
        )
    }

    func importXlsx(
        sourceURL: URL,
        destinationDir: URL,
        sheetName: String? = nil,
        outputFileName: String = "import.csv",
        limits: ImportLimits,
        completion: @escaping (Result<ImportResult, ImportClientError>) -> Void
    ) {
        importFile(
            sourceURL: sourceURL,
            destinationDir: destinationDir,
            outputFileName: outputFileName,
            kind: sheetName.map(ImportKind.xlsxSheet) ?? .xlsx,
            limits: limits,
            completion: completion
        )
    }

    func importSqlite(
        sourceURL: URL,
        destinationDir: URL,
        tableName: String? = nil,
        outputFileName: String = "import.csv",
        limits: ImportLimits,
        completion: @escaping (Result<ImportResult, ImportClientError>) -> Void
    ) {
        importFile(
            sourceURL: sourceURL,
            destinationDir: destinationDir,
            outputFileName: outputFileName,
            kind: tableName.map(ImportKind.sqliteTable) ?? .sqlite,
            limits: limits,
            completion: completion
        )
    }

    func importSav(
        sourceURL: URL,
        destinationDir: URL,
        limits: ImportLimits,
        completion: @escaping (Result<ImportResult, ImportClientError>) -> Void
    ) {
        importFile(
            sourceURL: sourceURL,
            destinationDir: destinationDir,
            outputFileName: "import.csv",
            kind: .sav,
            limits: limits,
            completion: completion
        )
    }

    func importSas7bdat(
        sourceURL: URL,
        destinationDir: URL,
        limits: ImportLimits,
        completion: @escaping (Result<ImportResult, ImportClientError>) -> Void
    ) {
        importFile(
            sourceURL: sourceURL,
            destinationDir: destinationDir,
            outputFileName: "import.csv",
            kind: .sas7bdat,
            limits: limits,
            completion: completion
        )
    }

    private func importFile(
        sourceURL: URL,
        destinationDir: URL,
        outputFileName: String,
        kind: ImportKind,
        limits: ImportLimits,
        completion: @escaping (Result<ImportResult, ImportClientError>) -> Void
    ) {
        let sourceHandle: FileHandle
        let outputHandle: FileHandle
        let metadataHandle: FileHandle?
        let outputURL = destinationDir.appendingPathComponent(outputFileName, isDirectory: false)
        let metadataURL = outputURL.appendingPathExtension("metadata.json")
        do {
            try FileManager.default.createDirectory(at: destinationDir, withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: outputURL.path, contents: nil)
            sourceHandle = try FileHandle(forReadingFrom: sourceURL)
            outputHandle = try FileHandle(forWritingTo: outputURL)
            if kind.requiresMetadataSidecar {
                FileManager.default.createFile(atPath: metadataURL.path, contents: nil)
                metadataHandle = try FileHandle(forWritingTo: metadataURL)
            } else {
                metadataHandle = nil
            }
        } catch {
            completion(.failure(.cannotOpenBridgeFiles))
            return
        }
        let sourceFile = ImportFileReference(fileHandle: sourceHandle)
        let outputFile = ImportFileReference(fileHandle: outputHandle)
        let metadataFile = metadataHandle.map(ImportFileReference.init(fileHandle:))

        if let injectedService {
            sendImport(
                to: injectedService,
                sourceFile: sourceFile,
                kind: kind,
                outputFile: outputFile,
                metadataFile: metadataFile,
                outputURL: outputURL,
                metadataURL: metadataFile != nil ? metadataURL : nil,
                limits: limits,
                completion: { result in
                    try? sourceHandle.close()
                    try? outputHandle.close()
                    try? metadataHandle?.close()
                    if case .failure = result, kind.requiresMetadataSidecar {
                        try? FileManager.default.removeItem(at: metadataURL)
                    }
                    completion(result)
                }
            )
            return
        }

        let connection = NSXPCConnection(serviceName: Self.serviceName)
        connection.remoteObjectInterface = ImportServiceXPCInterface.make()

        let completionBox = ImportCompletionBox {
            try? sourceHandle.close()
            try? outputHandle.close()
            try? metadataHandle?.close()
            if case .failure = $0, kind.requiresMetadataSidecar {
                try? FileManager.default.removeItem(at: metadataURL)
            }
            connection.invalidate()
            completion($0)
        }
        connection.interruptionHandler = {
            completionBox.complete(.failure(.connectionInterrupted))
        }
        connection.invalidationHandler = {
            completionBox.complete(.failure(.connectionInvalidated))
        }
        connection.activate()

        let service = connection.remoteObjectProxyWithErrorHandler { _ in
            completionBox.complete(.failure(.connectionInvalidated))
        } as? ImportServiceProtocol

        guard let service else {
            completionBox.complete(.failure(.connectionInvalidated))
            return
        }

        sendImport(
            to: service,
            sourceFile: sourceFile,
            kind: kind,
            outputFile: outputFile,
            metadataFile: metadataFile,
            outputURL: outputURL,
            metadataURL: metadataFile != nil ? metadataURL : nil,
            limits: limits,
            completion: completionBox.complete
        )
        completionBox.arm(timeout: limits.timeoutSeconds + Self.watchdogMargin)
    }

    private func sendImport(
        to service: ImportServiceProtocol,
        sourceFile: ImportFileReference,
        kind: ImportKind,
        outputFile: ImportFileReference,
        metadataFile: ImportFileReference?,
        outputURL: URL,
        metadataURL: URL?,
        limits: ImportLimits,
        completion: @escaping (Result<ImportResult, ImportClientError>) -> Void
    ) {
        service.importFile(sourceFile: sourceFile, kind: kind, limits: limits, outputFile: outputFile, metadataFile: metadataFile, outputURL: outputURL) { result, error in
            if let result {
                // Trust only the client-known output paths, never the URLs echoed
                // back in the reply — a compromised service could otherwise point
                // the app at any user-readable file.
                let trusted = ImportResult(
                    csvURL: outputURL,
                    metadataURL: metadataURL,
                    warnings: result.warnings,
                    rowCount: result.rowCount,
                    columnCount: result.columnCount
                )
                completion(.success(trusted))
            } else if let error {
                completion(.failure(.serviceError(code: error.code, message: error.message)))
            } else {
                completion(.failure(.invalidReply))
            }
        }
    }

    private func sendInspection(
        to service: ImportServiceProtocol,
        sourceFile: ImportFileReference,
        kind: ImportKind,
        limits: ImportLimits,
        completion: @escaping (Result<ImportInspection, ImportClientError>) -> Void
    ) {
        service.inspectFile(sourceFile: sourceFile, kind: kind, limits: limits) { result, error in
            if let result {
                completion(.success(result))
            } else if let error {
                completion(.failure(.serviceError(code: error.code, message: error.message)))
            } else {
                completion(.failure(.invalidReply))
            }
        }
    }
}

private extension ImportKind {
    var requiresMetadataSidecar: Bool {
        self == .sav || self == .sas7bdat
    }
}

final class ImportCompletionBox: @unchecked Sendable {
    private let lock = NSLock()
    private var completed = false
    private var watchdog: DispatchWorkItem?
    private let completion: (Result<ImportResult, ImportClientError>) -> Void

    init(completion: @escaping (Result<ImportResult, ImportClientError>) -> Void) {
        self.completion = completion
    }

    /// Fails the request if neither a reply nor a crash arrives within `timeout`
    /// — NSXPC imposes no reply deadline, so a parser that hangs inside a single
    /// C call (rather than crashing) would otherwise wedge the app forever.
    func arm(timeout: TimeInterval) {
        let work = DispatchWorkItem { [weak self] in
            self?.complete(.failure(.connectionInterrupted))
        }
        lock.lock()
        if completed {
            lock.unlock()
            return
        }
        watchdog = work
        lock.unlock()
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: work)
    }

    func complete(_ result: Result<ImportResult, ImportClientError>) {
        lock.lock()
        guard !completed else {
            lock.unlock()
            return
        }
        completed = true
        let pending = watchdog
        watchdog = nil
        lock.unlock()
        pending?.cancel()
        completion(result)
    }
}

/// Thread-safe accumulator for a fan-out of concurrent workbook-part imports.
/// Collects each part's output URL by index and remembers the first failure so
/// the batch can report an ordered result once every import completes.
final class WorkbookPartCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var results: [Int: URL] = [:]
    private var firstError: ImportClientError?

    func record(index: Int, result: Result<URL, ImportClientError>) {
        lock.lock()
        defer { lock.unlock() }
        switch result {
        case .success(let url):
            results[index] = url
        case .failure(let error):
            if firstError == nil { firstError = error }
        }
    }

    func outcome(count: Int) -> Result<[URL], ImportClientError> {
        lock.lock()
        defer { lock.unlock() }
        if let firstError {
            return .failure(firstError)
        }
        return .success((0..<count).compactMap { results[$0] })
    }
}

private final class ImportInspectionCompletionBox: @unchecked Sendable {
    private let lock = NSLock()
    private var completed = false
    private var watchdog: DispatchWorkItem?
    private let completion: (Result<ImportInspection, ImportClientError>) -> Void

    init(completion: @escaping (Result<ImportInspection, ImportClientError>) -> Void) {
        self.completion = completion
    }

    /// See ImportCompletionBox.arm — bounds a hung inspection call.
    func arm(timeout: TimeInterval) {
        let work = DispatchWorkItem { [weak self] in
            self?.complete(.failure(.connectionInterrupted))
        }
        lock.lock()
        if completed {
            lock.unlock()
            return
        }
        watchdog = work
        lock.unlock()
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: work)
    }

    func complete(_ result: Result<ImportInspection, ImportClientError>) {
        lock.lock()
        guard !completed else {
            lock.unlock()
            return
        }
        completed = true
        let pending = watchdog
        watchdog = nil
        lock.unlock()
        pending?.cancel()
        completion(result)
    }
}

extension ImportLimits {
    static let phase0Default = ImportLimits(
        maxBytes: 100 * 1024 * 1024,
        maxRows: 1_000_000,
        maxColumns: 16_384,
        maxCells: 10_000_000,
        timeoutSeconds: 60
    )

    static let phase1Default = ImportLimits(
        maxBytes: 100 * 1024 * 1024,
        maxRows: 1_048_576,
        maxColumns: 16_384,
        maxCells: 10_000_000,
        timeoutSeconds: 60
    )

    static let phase2Default = ImportLimits(
        maxBytes: 100 * 1024 * 1024,
        maxRows: 1_000_000,
        maxColumns: 16_384,
        maxCells: 10_000_000,
        timeoutSeconds: 60
    )

    static let phase3Default = ImportLimits(
        maxBytes: 100 * 1024 * 1024,
        maxRows: 1_000_000,
        maxColumns: 16_384,
        maxCells: 10_000_000,
        timeoutSeconds: 60
    )
}
