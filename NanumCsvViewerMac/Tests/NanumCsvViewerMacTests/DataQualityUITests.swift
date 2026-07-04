import AppKit
@preconcurrency import CsvCore
import XCTest
@testable import NanumCsvViewerMac

@MainActor
final class DataQualityUITests: XCTestCase {
    func testDataQualityMenuHasProfileAndExports() throws {
        _ = NSApplication.shared
        let previousMenu = NSApp.mainMenu
        let existingWindows = Set(NSApp.windows.map(ObjectIdentifier.init))
        let delegate = AppDelegate()
        delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification, object: NSApp))
        addTeardownBlock { @MainActor in
            for window in NSApp.windows where !existingWindows.contains(ObjectIdentifier(window)) {
                window.close()
            }
            NSApp.mainMenu = previousMenu
        }

        let mainMenu = try XCTUnwrap(NSApp.mainMenu)
        let item = try XCTUnwrap(mainMenu.items.first { $0.title == L.t("Data Quality", "데이터 품질") })
        let menu = try XCTUnwrap(item.submenu)

        let profile = try XCTUnwrap(menu.items.first { $0.action == #selector(MainWindowController.runDataQualityProfile(_:)) })
        XCTAssertEqual(profile.keyEquivalent, "P", "Cmd+Shift+Q is the macOS logout chord, so quality uses Cmd+Shift+P")
        XCTAssertEqual(profile.keyEquivalentModifierMask, [.command, .shift])

        XCTAssertNotNil(menu.items.first { $0.action == #selector(MainWindowController.exportDataQualityMarkdown(_:)) })
        XCTAssertNotNil(menu.items.first { $0.action == #selector(MainWindowController.exportDataQualityHtml(_:)) })
        XCTAssertNotNil(menu.items.first { $0.action == #selector(MainWindowController.exportDataQualityJson(_:)) })

        let mainMenuTitles = mainMenu.items.map(\.title)
        let visualizationIndex = try XCTUnwrap(mainMenuTitles.firstIndex(of: L.t("Visualization", "시각화")))
        let qualityIndex = try XCTUnwrap(mainMenuTitles.firstIndex(of: L.t("Data Quality", "데이터 품질")))
        let pivotIndex = try XCTUnwrap(mainMenuTitles.firstIndex(of: L.t("Pivot", "피벗")))
        XCTAssertTrue(visualizationIndex < qualityIndex && qualityIndex < pivotIndex, "Windows twin menu order")
    }

    func testRunProfileRendersReportIntoInspector() throws {
        let controller = try openController(csv: """
        user_id,amount
        u1,10
        u1,NA
        u2,20

        """)
        defer { controller.close() }

        controller.runDataQualityProfile(nil)
        try waitUntilQualityReport(controller)

        let report = try XCTUnwrap(controller.dataQualityReportForTesting)
        XCTAssertEqual(report.scannedRowCount, 3)
        XCTAssertTrue(report.issues.contains { $0.rule == .keyUniqueness })
        XCTAssertTrue(report.issues.contains { $0.rule == .sentinel })

        XCTAssertTrue(controller.detailHeaderTextForTesting.contains(L.t("Data Quality", "데이터 품질")))
        XCTAssertTrue(controller.detailTextForTesting.contains("/ 100"), "score line should render")
    }

    func testMarkdownAndHtmlFormattersContainCoreSections() throws {
        let (doc, path) = try openIndexedDocument(csv: "id,v\na,1\nb,2\na,3\n")
        defer { try? FileManager.default.removeItem(atPath: path) }

        let report = try doc.dataQualityReport(cancellation: CancellationFlag())
        let markdown = DataQualityReportFormatter.markdown(report: report, fileName: "sample.csv")
        let html = DataQualityReportFormatter.html(report: report, fileName: "sample.csv")

        XCTAssertTrue(markdown.contains("sample.csv"))
        XCTAssertTrue(markdown.contains(L.t("Column Profiles", "컬럼 프로필")))
        XCTAssertTrue(markdown.contains("| id |"))
        XCTAssertTrue(html.contains("<table>"))
        XCTAssertTrue(html.contains("sample.csv"))
        XCTAssertTrue(html.hasPrefix("<!DOCTYPE html>"))

        let json = try DataQualityReportFormatter.json(report: report)
        let decoded = try JSONDecoder().decode(DataQualityReport.self, from: json)
        XCTAssertEqual(decoded, report)
    }

    private func openController(csv: String) throws -> MainWindowController {
        let path = try temporaryCsvPath()
        try csv.data(using: .utf8)!.write(to: URL(fileURLWithPath: path))
        addTeardownBlock {
            try? FileManager.default.removeItem(atPath: path)
        }
        let controller = MainWindowController()
        controller.showWindow(nil)
        controller.openFileForTesting(URL(fileURLWithPath: path))
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
            if controller.indexingCompleteForTesting, controller.renderedRowCountForTesting > 0 {
                return controller
            }
        }
        XCTFail("Timed out waiting for indexing")
        return controller
    }

    private func openIndexedDocument(csv: String) throws -> (VirtualCsvDocument, String) {
        let path = try temporaryCsvPath()
        try csv.data(using: .utf8)!.write(to: URL(fileURLWithPath: path))
        let doc = try VirtualCsvDocument.open(path: path)
        try doc.runIndexing(progress: { _ in }, cancellation: CancellationFlag())
        return (doc, path)
    }

    private func waitUntilQualityReport(_ controller: MainWindowController, file: StaticString = #filePath, line: UInt = #line) throws {
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
            if controller.dataQualityReportForTesting != nil, !controller.hasPendingDataQualityScanForTesting {
                return
            }
        }
        XCTFail("Timed out waiting for data quality report", file: file, line: line)
    }

    private func temporaryCsvPath() throws -> String {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return directory.appendingPathComponent("nanumcsv_quality_\(UUID().uuidString).csv").path
    }
}
