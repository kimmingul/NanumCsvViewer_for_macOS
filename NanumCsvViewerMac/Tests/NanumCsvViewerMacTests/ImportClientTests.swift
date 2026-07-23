import Foundation
import XCTest
@testable import NanumCsvViewerMac
import ImportServiceProtocol

final class ImportClientTests: XCTestCase {
    func testEchoImportReturnsCsvURLFromServiceResult() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("import-client-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let sourceURL = directory.appendingPathComponent("source.txt")
        try Data("a,b\n1,2\n".utf8).write(to: sourceURL)
        let expectedURL = directory.appendingPathComponent("echo.csv")

        let service = FakeImportService { sourceFile, kind, _, outputFile, metadataFile, outputURL, reply in
            XCTAssertGreaterThanOrEqual(sourceFile.fileHandle.fileDescriptor, 0)
            XCTAssertEqual(kind, .echo)
            XCTAssertGreaterThanOrEqual(outputFile.fileHandle.fileDescriptor, 0)
            XCTAssertNil(metadataFile)
            XCTAssertEqual(outputURL, expectedURL)
            reply(ImportResult(csvURL: outputURL, metadataURL: nil, warnings: [], rowCount: 0, columnCount: 0), nil)
        }

        let client = ImportClient(service: service)
        let expectation = expectation(description: "reply")
        client.importEcho(sourceURL: sourceURL, destinationDir: directory, limits: .phase0Default) { result in
            XCTAssertEqual(try? result.get().csvURL, expectedURL)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1)
    }

    func testEchoImportFailsClosedWhenServiceReturnsNoResult() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("import-client-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let sourceURL = directory.appendingPathComponent("source.txt")
        try Data("a,b\n1,2\n".utf8).write(to: sourceURL)

        let client = ImportClient(service: FakeImportService { _, _, _, _, _, _, reply in
            reply(nil, nil)
        })

        let expectation = expectation(description: "reply")
        client.importEcho(sourceURL: sourceURL, destinationDir: directory, limits: .phase0Default) { result in
            XCTAssertEqual(result.failure, .invalidReply)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1)
    }

    func testXlsImportSendsXlsKindAndImportCsvDestination() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("import-client-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let sourceURL = directory.appendingPathComponent("source.xls")
        try Data([0xD0, 0xCF, 0x11, 0xE0, 0x00]).write(to: sourceURL)
        let expectedURL = directory.appendingPathComponent("import.csv")

        let service = FakeImportService { sourceFile, kind, _, outputFile, metadataFile, outputURL, reply in
            XCTAssertGreaterThanOrEqual(sourceFile.fileHandle.fileDescriptor, 0)
            XCTAssertEqual(kind, .xls)
            XCTAssertGreaterThanOrEqual(outputFile.fileHandle.fileDescriptor, 0)
            XCTAssertNil(metadataFile)
            XCTAssertEqual(outputURL, expectedURL)
            reply(ImportResult(csvURL: outputURL, metadataURL: nil, warnings: [], rowCount: 1, columnCount: 1), nil)
        }

        let client = ImportClient(service: service)
        let expectation = expectation(description: "reply")
        client.importXls(sourceURL: sourceURL, destinationDir: directory, limits: .phase1Default) { result in
            XCTAssertEqual(try? result.get().csvURL, expectedURL)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1)
    }

    func testSavImportSendsSavKindAndImportCsvDestination() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("import-client-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let sourceURL = directory.appendingPathComponent("source.sav")
        try Data("$FL2more".utf8).write(to: sourceURL)
        let expectedURL = directory.appendingPathComponent("import.csv")
        let expectedMetadataURL = expectedURL.appendingPathExtension("metadata.json")

        let service = FakeImportService { sourceFile, kind, _, outputFile, metadataFile, outputURL, reply in
            XCTAssertGreaterThanOrEqual(sourceFile.fileHandle.fileDescriptor, 0)
            XCTAssertEqual(kind, .sav)
            XCTAssertGreaterThanOrEqual(outputFile.fileHandle.fileDescriptor, 0)
            XCTAssertGreaterThanOrEqual(metadataFile?.fileHandle.fileDescriptor ?? -1, 0)
            XCTAssertEqual(outputURL, expectedURL)
            reply(ImportResult(csvURL: outputURL, metadataURL: expectedMetadataURL, warnings: [], rowCount: 2, columnCount: 5), nil)
        }

        let client = ImportClient(service: service)
        let expectation = expectation(description: "reply")
        client.importSav(sourceURL: sourceURL, destinationDir: directory, limits: .phase2Default) { result in
            XCTAssertEqual(try? result.get().csvURL, expectedURL)
            XCTAssertEqual(try? result.get().metadataURL, expectedMetadataURL)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1)
    }

    func testSasImportSendsSasKindAndImportCsvDestination() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("import-client-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let sourceURL = directory.appendingPathComponent("source.sas7bdat")
        try Data(repeating: 0, count: 40).write(to: sourceURL)
        let expectedURL = directory.appendingPathComponent("import.csv")
        let expectedMetadataURL = expectedURL.appendingPathExtension("metadata.json")

        let service = FakeImportService { sourceFile, kind, _, outputFile, metadataFile, outputURL, reply in
            XCTAssertGreaterThanOrEqual(sourceFile.fileHandle.fileDescriptor, 0)
            XCTAssertEqual(kind, .sas7bdat)
            XCTAssertGreaterThanOrEqual(outputFile.fileHandle.fileDescriptor, 0)
            XCTAssertGreaterThanOrEqual(metadataFile?.fileHandle.fileDescriptor ?? -1, 0)
            XCTAssertEqual(outputURL, expectedURL)
            reply(ImportResult(csvURL: outputURL, metadataURL: expectedMetadataURL, warnings: [ImportWarning(code: "sas-best-effort", message: "warn")], rowCount: 2, columnCount: 5), nil)
        }

        let client = ImportClient(service: service)
        let expectation = expectation(description: "reply")
        client.importSas7bdat(sourceURL: sourceURL, destinationDir: directory, limits: .phase3Default) { result in
            XCTAssertEqual(try? result.get().csvURL, expectedURL)
            XCTAssertEqual(try? result.get().metadataURL, expectedMetadataURL)
            XCTAssertEqual(try? result.get().warnings.map(\.code), ["sas-best-effort"])
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1)
    }

    func testImportIgnoresServiceSuppliedPathsAndUsesClientOutput() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("import-client-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let sourceURL = directory.appendingPathComponent("source.xls")
        try Data([0xD0, 0xCF, 0x11, 0xE0, 0x00]).write(to: sourceURL)
        let expectedURL = directory.appendingPathComponent("import.csv")

        // A compromised service tries to redirect the app to arbitrary files.
        let service = FakeImportService { _, _, _, _, _, _, reply in
            reply(
                ImportResult(
                    csvURL: URL(fileURLWithPath: "/etc/passwd"),
                    metadataURL: URL(fileURLWithPath: "/etc/hosts"),
                    warnings: [],
                    rowCount: 1,
                    columnCount: 1
                ),
                nil
            )
        }

        let client = ImportClient(service: service)
        let expectation = expectation(description: "reply")
        client.importXls(sourceURL: sourceURL, destinationDir: directory, limits: .phase1Default) { result in
            let value = try? result.get()
            XCTAssertEqual(value?.csvURL, expectedURL, "must open the client-known output, not the reply's path")
            XCTAssertNil(value?.metadataURL, "xls has no sidecar; the reply's metadataURL is ignored")
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1)
    }

    func testImportWatchdogFailsWhenServiceNeverReplies() {
        let expectation = expectation(description: "watchdog fires")
        var received: Result<ImportResult, ImportClientError>?
        let box = ImportCompletionBox { result in
            received = result
            expectation.fulfill()
        }
        box.arm(timeout: 0.05)
        wait(for: [expectation], timeout: 2)
        XCTAssertEqual(received?.failure, .connectionInterrupted)
    }

    func testImportWatchdogDoesNotOverrideEarlyReply() {
        let done = expectation(description: "reply")
        var completions = 0
        var received: Result<ImportResult, ImportClientError>?
        let box = ImportCompletionBox { result in
            completions += 1
            received = result
            done.fulfill()
        }
        box.arm(timeout: 0.05)
        let url = URL(fileURLWithPath: "/tmp/x.csv")
        box.complete(.success(ImportResult(csvURL: url, metadataURL: nil, warnings: [], rowCount: 0, columnCount: 0)))
        wait(for: [done], timeout: 2)

        // Give the cancelled watchdog a chance to (wrongly) fire a second time.
        let settle = expectation(description: "settle")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { settle.fulfill() }
        wait(for: [settle], timeout: 2)

        XCTAssertEqual(completions, 1, "a delivered reply cancels the watchdog")
        if case .success(let result)? = received {
            XCTAssertEqual(result.csvURL, url)
        } else {
            XCTFail("expected the early success to win")
        }
    }

    func testXlsInspectionReturnsSheetNamesFromService() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("import-client-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let sourceURL = directory.appendingPathComponent("source.xls")
        try Data([0xD0, 0xCF, 0x11, 0xE0, 0x00]).write(to: sourceURL)

        let service = FakeImportService { _, kind, _, _, _, _, reply in
            XCTFail("Unexpected import call for kind \(kind.rawValue)")
            reply(nil, nil)
        } inspectHandler: { sourceFile, kind, _, reply in
            XCTAssertGreaterThanOrEqual(sourceFile.fileHandle.fileDescriptor, 0)
            XCTAssertEqual(kind, .xls)
            reply(ImportInspection(sheetNames: ["µ", "∂"]), nil)
        }

        let client = ImportClient(service: service)
        let expectation = expectation(description: "reply")
        client.inspectXls(sourceURL: sourceURL, limits: .phase1Default) { result in
            XCTAssertEqual(try? result.get().sheetNames, ["µ", "∂"])
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1)
    }
}

private final class FakeImportService: NSObject, ImportServiceProtocol {
    typealias Handler = (ImportFileReference, ImportKind, ImportLimits, ImportFileReference, ImportFileReference?, URL, @escaping (ImportResult?, ImportError?) -> Void) -> Void
    typealias InspectHandler = (ImportFileReference, ImportKind, ImportLimits, @escaping (ImportInspection?, ImportError?) -> Void) -> Void

    private let handler: Handler
    private let inspectHandler: InspectHandler

    init(
        handler: @escaping Handler,
        inspectHandler: @escaping InspectHandler = { _, _, _, reply in reply(nil, nil) }
    ) {
        self.handler = handler
        self.inspectHandler = inspectHandler
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
        handler(sourceFile, kind, limits, outputFile, metadataFile, outputURL, reply)
    }

    func inspectFile(
        sourceFile: ImportFileReference,
        kind: ImportKind,
        limits: ImportLimits,
        reply: @escaping (ImportInspection?, ImportError?) -> Void
    ) {
        inspectHandler(sourceFile, kind, limits, reply)
    }
}

private extension Result where Failure == ImportClientError {
    var failure: ImportClientError? {
        guard case .failure(let error) = self else { return nil }
        return error
    }
}
