import AppKit
import XCTest
@testable import CsvCore
@testable import NanumCsvViewerMac

@MainActor
final class PivotBuilderTests: XCTestCase {
    func testChartModelProjectsSimplePivotIntoSeries() {
        let pivot = PivotTableResult(
            rowColumns: [0],
            rowColumnNames: ["site"],
            columnColumns: [1],
            valueColumn: 2,
            function: .sum,
            rowKeys: [["A"], ["B"]],
            columnKeys: [["Control"], ["Treatment"]],
            values: [
                PivotCellKey(row: ["A"], column: ["Control"]): 3,
                PivotCellKey(row: ["A"], column: ["Treatment"]): 7,
                PivotCellKey(row: ["B"], column: ["Control"]): 2,
                PivotCellKey(row: ["B"], column: ["Treatment"]): 5
            ]
        )

        let model = PivotChartModel.make(from: pivot)

        XCTAssertEqual(model.categories, ["A", "B"])
        XCTAssertEqual(model.series.map(\.name), ["Control", "Treatment"])
        XCTAssertEqual(model.series[0].values, [3, 2])
        XCTAssertEqual(model.series[1].values, [7, 5])
        XCTAssertNil(model.unsupportedReason)
    }

    func testDropZoneStoresVisibleFieldNames() {
        let zone = PivotDropZoneView(zone: .rows) { _, _ in }

        zone.setFieldNames(["site", "visit"])

        XCTAssertEqual(zone.fieldNamesForTesting, ["site", "visit"])
    }

    func testChartViewStoresModelForRendering() {
        let chart = PivotChartView()
        let model = PivotChartModel(
            categories: ["A"],
            series: [PivotChartSeries(name: "Treatment", values: [4])],
            unsupportedReason: nil
        )

        chart.update(model: model)

        XCTAssertEqual(chart.modelForTesting, model)
    }

    func testBuilderAssignsFieldsAndBuildsPreview() throws {
        _ = NSApplication.shared
        let (doc, path) = try openIndexed("""
        site,arm,value
        A,Control,3
        A,Treatment,7
        B,Control,2
        B,Treatment,5

        """)
        defer { try? FileManager.default.removeItem(atPath: path) }
        let builder = PivotBuilderWindowController(document: doc, columnNames: doc.header)

        builder.assignFieldForTesting(0, to: .rows)
        builder.assignFieldForTesting(1, to: .columns)
        builder.assignFieldForTesting(2, to: .values)
        builder.setAggregationForTesting(.sum)

        XCTAssertEqual(builder.layoutForTesting.rows, [0])
        XCTAssertEqual(builder.layoutForTesting.columns, [1])
        XCTAssertEqual(builder.layoutForTesting.value, 2)
        XCTAssertEqual(builder.previewHeadersForTesting, ["site", "Control", "Treatment"])
        XCTAssertEqual(builder.previewRowForTesting(0), ["A", "3", "7"])
        XCTAssertEqual(builder.previewRowForTesting(1), ["B", "2", "5"])
        XCTAssertEqual(builder.chartModelForTesting?.categories, ["A", "B"])
    }

    func testBuilderRemovesFieldsFromZones() throws {
        _ = NSApplication.shared
        let (doc, path) = try openIndexed("""
        site,arm,value
        A,Control,3
        A,Treatment,7

        """)
        defer { try? FileManager.default.removeItem(atPath: path) }
        let builder = PivotBuilderWindowController(document: doc, columnNames: doc.header)

        builder.assignFieldForTesting(0, to: .rows)
        builder.assignFieldForTesting(1, to: .columns)
        builder.assignFieldForTesting(2, to: .values)
        builder.removeFieldForTesting(0, from: .rows)

        XCTAssertEqual(builder.layoutForTesting.rows, [])
        XCTAssertEqual(builder.previewHeadersForTesting, [])
        XCTAssertNil(builder.chartModelForTesting)
    }

    func testMainWindowCreatesPivotBuilderForIndexedDocument() throws {
        _ = NSApplication.shared
        let path = try temporaryCsvPath("""
        site,arm,value
        A,Control,3
        A,Treatment,7

        """)
        defer { try? FileManager.default.removeItem(atPath: path) }
        let controller = MainWindowController()
        controller.showWindow(nil)
        defer { controller.close() }

        controller.openFileForTesting(URL(fileURLWithPath: path))
        try waitUntilIndexed(controller)

        let builder = controller.makePivotBuilderForTesting()

        XCTAssertNotNil(builder)
    }

    private func openIndexed(_ content: String) throws -> (VirtualCsvDocument, String) {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let path = directory.appendingPathComponent("nanumcsv_pivot_\(UUID().uuidString).csv").path
        try content.data(using: .utf8)!.write(to: URL(fileURLWithPath: path))
        let doc = try VirtualCsvDocument.open(path: path)
        try doc.runIndexing(progress: { _ in }, cancellation: CancellationFlag())
        return (doc, path)
    }

    private func temporaryCsvPath(_ content: String) throws -> String {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let path = directory.appendingPathComponent("nanumcsv_pivot_main_\(UUID().uuidString).csv").path
        try content.data(using: .utf8)!.write(to: URL(fileURLWithPath: path))
        return path
    }

    private func waitUntilIndexed(_ controller: MainWindowController, file: StaticString = #filePath, line: UInt = #line) throws {
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
            if controller.indexingCompleteForTesting {
                return
            }
        }
        XCTFail("Timed out waiting for indexing", file: file, line: line)
    }
}
