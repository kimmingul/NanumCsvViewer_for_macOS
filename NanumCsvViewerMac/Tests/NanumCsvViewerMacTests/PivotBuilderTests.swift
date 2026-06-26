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
}
