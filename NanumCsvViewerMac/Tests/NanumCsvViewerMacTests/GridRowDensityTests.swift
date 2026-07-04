import AppKit
import XCTest
@testable import NanumCsvViewerMac

final class GridRowDensityTests: XCTestCase {
    func testRowHeightsAscendWithDensity() {
        XCTAssertLessThan(GridRowDensity.compact.rowHeight, GridRowDensity.regular.rowHeight)
        XCTAssertLessThan(GridRowDensity.regular.rowHeight, GridRowDensity.comfortable.rowHeight)
    }

    func testRawValueRoundTripAndDefault() {
        for density in GridRowDensity.allCases {
            XCTAssertEqual(GridRowDensity(rawValue: density.rawValue), density)
        }
        XCTAssertEqual(GridRowDensity(rawValue: "nonsense") ?? .regular, .regular)
    }
}

@MainActor
final class GridRowDensityControllerTests: XCTestCase {
    private let key = "NanumCsvViewerMac.RowDensity"
    private var previous: Any?

    override func setUp() {
        super.setUp()
        previous = UserDefaults.standard.object(forKey: key)
        UserDefaults.standard.removeObject(forKey: key)
    }

    override func tearDown() {
        if let previous { UserDefaults.standard.set(previous, forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) }
        super.tearDown()
    }

    func testChangingDensityUpdatesTableRowHeight() {
        let controller = MainWindowController()
        controller.showWindow(nil)
        defer { controller.close() }

        XCTAssertEqual(controller.tableRowHeightForTesting, GridRowDensity.regular.rowHeight, "default is regular")
        controller.setRowDensityForTesting(.compact)
        XCTAssertEqual(controller.tableRowHeightForTesting, GridRowDensity.compact.rowHeight)
        controller.setRowDensityForTesting(.comfortable)
        XCTAssertEqual(controller.tableRowHeightForTesting, GridRowDensity.comfortable.rowHeight)
    }

    func testPerformanceSnapshotIncludesMemoryLine() throws {
        let path = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("density-\(UUID().uuidString).csv")
        try "a,b\n1,2\n3,4\n".data(using: .utf8)!.write(to: path)
        addTeardownBlock { try? FileManager.default.removeItem(at: path) }

        let controller = MainWindowController()
        controller.showWindow(nil)
        defer { controller.close() }
        controller.openFileForTesting(path)

        let snapshot = try XCTUnwrap(controller.performanceSnapshotForTesting())
        XCTAssertNotNil(snapshot.memoryFootprintBytes)
        XCTAssertTrue(snapshot.formattedLines().contains { $0.hasPrefix("Memory:") })
    }
}
