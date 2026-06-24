import AppKit
import XCTest
@testable import NanumCsvViewerMac

@MainActor
final class MainWindowControllerGridTests: XCTestCase {
    func testRepeatedSmallFileOpenRendersEveryGridRow() throws {
        _ = NSApplication.shared
        let path = try temporaryCsvPath()
        let expectedRows = (0..<300).map { index in
            [
                String(format: "r%03d", index),
                String(format: "payload-%03d-abcdefghijklmnopqrstuvwxyz", index),
                String(format: "%03d", index)
            ]
        }
        let content = "id,payload,n\n" + expectedRows.map { $0.joined(separator: ",") }.joined(separator: "\n") + "\n"
        try content.data(using: .utf8)!.write(to: URL(fileURLWithPath: path))
        defer { try? FileManager.default.removeItem(atPath: path) }

        for iteration in 0..<40 {
            let controller = MainWindowController()
            defer { controller.close() }

            controller.openFileForTesting(URL(fileURLWithPath: path))
            try waitUntilIndexed(controller)

            XCTAssertEqual(controller.renderedRowCountForTesting, expectedRows.count, "iteration \(iteration)")
            for row in expectedRows.indices {
                let rendered = controller.renderedDataRowForTesting(row)
                XCTAssertEqual(rendered, expectedRows[row], "iteration \(iteration), row \(row)")
            }
        }
    }

    func testRepeatedSmallFileOpenMaterializesEveryGridRow() throws {
        _ = NSApplication.shared
        let path = try temporaryCsvPath()
        let expectedRows = (0..<300).map { index in
            [
                String(format: "r%03d", index),
                String(format: "payload-%03d-abcdefghijklmnopqrstuvwxyz", index),
                String(format: "%03d", index)
            ]
        }
        let content = "id,payload,n\n" + expectedRows.map { $0.joined(separator: ",") }.joined(separator: "\n") + "\n"
        try content.data(using: .utf8)!.write(to: URL(fileURLWithPath: path))
        defer { try? FileManager.default.removeItem(atPath: path) }

        for iteration in 0..<20 {
            let controller = MainWindowController()
            controller.showWindow(nil)
            defer { controller.close() }

            controller.openFileForTesting(URL(fileURLWithPath: path))
            try waitUntilIndexed(controller)

            XCTAssertEqual(controller.renderedRowCountForTesting, expectedRows.count, "iteration \(iteration)")
            for row in expectedRows.indices {
                let rendered = controller.materializedDataRowForTesting(row)
                XCTAssertEqual(rendered, expectedRows[row], "iteration \(iteration), row \(row)")
            }
        }
    }

    func testRepeatedSmallFileOpenInSameWindowMaterializesEveryGridRow() throws {
        _ = NSApplication.shared
        let path = try temporaryCsvPath()
        let expectedRows = (0..<300).map { index in
            [
                String(format: "r%03d", index),
                String(format: "payload-%03d-abcdefghijklmnopqrstuvwxyz", index),
                String(format: "%03d", index)
            ]
        }
        let content = "id,payload,n\n" + expectedRows.map { $0.joined(separator: ",") }.joined(separator: "\n") + "\n"
        try content.data(using: .utf8)!.write(to: URL(fileURLWithPath: path))
        defer { try? FileManager.default.removeItem(atPath: path) }

        let controller = MainWindowController()
        controller.showWindow(nil)
        defer { controller.close() }

        for iteration in 0..<40 {
            controller.openFileForTesting(URL(fileURLWithPath: path))
            try waitUntilIndexed(controller)

            XCTAssertEqual(controller.renderedRowCountForTesting, expectedRows.count, "iteration \(iteration)")
            for row in expectedRows.indices {
                let rendered = controller.materializedDataRowForTesting(row)
                XCTAssertEqual(rendered, expectedRows[row], "iteration \(iteration), row \(row)")
            }
        }
    }

    func testRapidSmallFileReopenInSameWindowMaterializesEveryGridRow() throws {
        _ = NSApplication.shared
        let path = try temporaryCsvPath()
        let expectedRows = (0..<300).map { index in
            [
                String(format: "r%03d", index),
                String(format: "payload-%03d-abcdefghijklmnopqrstuvwxyz", index),
                String(format: "%03d", index)
            ]
        }
        let content = "id,payload,n\n" + expectedRows.map { $0.joined(separator: ",") }.joined(separator: "\n") + "\n"
        try content.data(using: .utf8)!.write(to: URL(fileURLWithPath: path))
        defer { try? FileManager.default.removeItem(atPath: path) }

        let controller = MainWindowController()
        controller.showWindow(nil)
        defer { controller.close() }

        for iteration in 0..<80 {
            controller.openFileForTesting(URL(fileURLWithPath: path))
            if iteration & 1 == 0 {
                RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.001))
            }
        }

        try waitUntilIndexed(controller)
        XCTAssertEqual(controller.renderedRowCountForTesting, expectedRows.count)
        for row in expectedRows.indices {
            let rendered = controller.materializedDataRowForTesting(row)
            XCTAssertEqual(rendered, expectedRows[row], "row \(row)")
        }
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

    private func temporaryCsvPath() throws -> String {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return directory.appendingPathComponent("nanumcsv_grid_\(UUID().uuidString).csv").path
    }
}
