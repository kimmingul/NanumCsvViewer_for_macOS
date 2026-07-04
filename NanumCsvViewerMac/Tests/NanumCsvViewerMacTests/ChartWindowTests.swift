import AppKit
@preconcurrency import CsvCore
import XCTest
@testable import NanumCsvViewerMac

@MainActor
final class ChartWindowTests: XCTestCase {
    func testVisualizationMenuListsAllSevenCharts() throws {
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
        let visualizationItem = try XCTUnwrap(mainMenu.items.first { $0.title == L.t("Visualization", "시각화") })
        let titles = try XCTUnwrap(visualizationItem.submenu).items.map(\.title)

        XCTAssertEqual(titles, ChartKind.allCases.map(\.title))
        XCTAssertEqual(ChartKind.allCases.count, 7)
    }

    func testHistogramChartWindowOpensWithComputedModel() throws {
        let values = (0...40).map(String.init).joined(separator: "\n")
        let controller = try openController(csv: "amount\n\(values)\n")
        defer { controller.close() }

        controller.openChartWindowForTesting(.histogram(column: 0, binCount: 8))
        try waitUntilChartWindows(controller, count: 1)

        let chart = try XCTUnwrap(controller.chartWindowsForTesting.first)
        XCTAssertEqual(chart.model.kind, .histogram)
        guard case .histogram(let data, let columnName) = chart.model.render else {
            return XCTFail("expected histogram render model")
        }
        XCTAssertEqual(columnName, "amount")
        XCTAssertEqual(data.distribution.bins.count, 8)
        XCTAssertFalse(data.density.isEmpty)
        XCTAssertNotNil(chart.window)
        XCTAssertTrue(chart.window?.isVisible == true)
    }

    func testChartWindowsAutoCloseWhenDocumentChanges() throws {
        let values = (0...20).map(String.init).joined(separator: "\n")
        let controller = try openController(csv: "amount\n\(values)\n")
        defer { controller.close() }

        controller.openChartWindowForTesting(.qqPlot(column: 0))
        try waitUntilChartWindows(controller, count: 1)

        let secondPath = try temporaryCsvPath()
        try "name\nAlice\n".data(using: .utf8)!.write(to: URL(fileURLWithPath: secondPath))
        addTeardownBlock {
            try? FileManager.default.removeItem(atPath: secondPath)
        }
        controller.openFileForTesting(URL(fileURLWithPath: secondPath))
        try waitUntilIndexed(controller)

        XCTAssertTrue(controller.chartWindowsForTesting.isEmpty, "document switch must close chart snapshots")
    }

    func testChartWindowsAutoCloseWhenDocumentCloses() throws {
        let values = (0...20).map(String.init).joined(separator: "\n")
        let controller = try openController(csv: "amount\n\(values)\n")
        defer { controller.close() }

        controller.openChartWindowForTesting(.pareto(column: 0))
        try waitUntilChartWindows(controller, count: 1)

        controller.closeCurrentDocument(nil)
        XCTAssertTrue(controller.chartWindowsForTesting.isEmpty)
    }

    func testMultipleChartWindowsStayOpenTogether() throws {
        let rows = (0...30).map { "\($0),\($0 * 3)" }.joined(separator: "\n")
        let controller = try openController(csv: "x,y\n\(rows)\n")
        defer { controller.close() }

        controller.openChartWindowForTesting(.scatter(xColumn: 0, yColumn: 1))
        try waitUntilChartWindows(controller, count: 1)
        controller.openChartWindowForTesting(.histogram(column: 0, binCount: 6))
        try waitUntilChartWindows(controller, count: 2)

        XCTAssertEqual(controller.chartWindowsForTesting.count, 2, "charts are modeless and stack up")

        guard case .scatter(let data, _, _) = controller.chartWindowsForTesting[0].model.render else {
            return XCTFail("expected scatter render model")
        }
        XCTAssertEqual(data.regression?.slope ?? .nan, 3, accuracy: 1e-9)
    }

    func testQQReferenceLineTracksQuartilePairs() {
        let points = (1...100).map { index -> QQPoint in
            let p = (Double(index) - 0.375) / 100.25
            return QQPoint(theoretical: p, sample: Double(index))
        }
        let line = StatChartContentView.qqReferenceLine(points)
        XCTAssertNotNil(line)
    }

    func testCorrelationColorIsClampedAndDistinct() {
        XCTAssertNotEqual(
            StatChartContentView.correlationColor(1),
            StatChartContentView.correlationColor(-1),
            "positive and negative correlations need distinct hues"
        )
        XCTAssertEqual(
            StatChartContentView.correlationColor(5),
            StatChartContentView.correlationColor(1),
            "values clamp to [-1, 1]"
        )
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
        try waitUntilIndexed(controller)
        return controller
    }

    private func waitUntilIndexed(_ controller: MainWindowController, file: StaticString = #filePath, line: UInt = #line) throws {
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
            if controller.indexingCompleteForTesting, controller.renderedRowCountForTesting > 0 {
                return
            }
        }
        XCTFail("Timed out waiting for indexing", file: file, line: line)
    }

    private func waitUntilChartWindows(
        _ controller: MainWindowController,
        count: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
            if controller.chartWindowsForTesting.count >= count, !controller.busyForTesting {
                return
            }
        }
        XCTFail("Timed out waiting for chart windows", file: file, line: line)
    }

    private func temporaryCsvPath() throws -> String {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return directory.appendingPathComponent("nanumcsv_chart_\(UUID().uuidString).csv").path
    }
}
