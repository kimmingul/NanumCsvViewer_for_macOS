import Foundation
import XCTest
@testable import NanumCsvViewerMac

final class ImportMetadataIntegrationTests: XCTestCase {
    @MainActor
    func testImportedMetadataAppliesColumnTypesAndRendersValueLabels() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("import-metadata-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let csvURL = directory.appendingPathComponent("import.csv")
        try Data("status,income\n2,1234.5\n".utf8).write(to: csvURL)
        let metadataURL = csvURL.appendingPathExtension("metadata.json")
        try Data("""
        {
          "columns": [
            { "name": "status", "label": "Employment status", "declaredType": "ordinal", "valueLabels": { "2": "Part time" } },
            { "name": "income", "label": "Annual income", "declaredType": "currency", "valueLabels": {} }
          ],
          "rowCount": 1,
          "encoding": "UTF-8",
          "warnings": []
        }
        """.utf8).write(to: metadataURL)

        let controller = MainWindowController()
        controller.openImportedCsvForTesting(csvURL: csvURL, metadataURL: metadataURL)

        try waitUntil(controller) { $0.renderedRowCountForTesting == 1 }
        XCTAssertEqual(controller.columnTypeOverridesForTesting, [0: "Categorical", 1: "Float"])
        XCTAssertEqual(controller.renderedDataRowForTesting(0), ["Part time", "1234.5"])
    }

    @MainActor
    func testImportedSasWarningBannerPersists() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("import-metadata-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let csvURL = directory.appendingPathComponent("import.csv")
        try Data("x\n1\n".utf8).write(to: csvURL)
        let metadataURL = csvURL.appendingPathExtension("metadata.json")
        try Data("""
        { "columns": [ { "name": "x", "label": null, "declaredType": "float", "valueLabels": {} } ],
          "rowCount": 1, "encoding": "UTF-8",
          "warnings": [ { "code": "sas-best-effort", "message": "SAS import is best-effort; verify critical data against SAS." } ] }
        """.utf8).write(to: metadataURL)

        let controller = MainWindowController()
        controller.openImportedCsvForTesting(
            csvURL: csvURL,
            metadataURL: metadataURL,
            warningText: "SAS import is best-effort; verify critical data against SAS."
        )

        try waitUntil(controller) { $0.renderedRowCountForTesting == 1 }
        XCTAssertEqual(controller.importWarningTextForTesting, "SAS import is best-effort; verify critical data against SAS.")
    }

    @MainActor
    private func waitUntil(
        _ controller: MainWindowController,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ condition: @MainActor (MainWindowController) -> Bool
    ) throws {
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
            if condition(controller) { return }
        }
        XCTFail("Timed out waiting for condition", file: file, line: line)
    }
}
