import Foundation
import XCTest
@testable import NanumCsvViewerMac

final class TempFileCleanupTests: XCTestCase {
    private func makeSandbox() throws -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("tempclean-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func testRemovesBridgeDirectoriesAndClipboardFilesButKeepsOthers() throws {
        let sandbox = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: sandbox) }
        let fm = FileManager.default

        let xlsxDir = sandbox.appendingPathComponent("NanumCsvViewerXlsx/abc/sheet.csv")
        let sqliteDir = sandbox.appendingPathComponent("NanumCsvViewerSqlite/def/table.csv")
        try fm.createDirectory(at: xlsxDir.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.createDirectory(at: sqliteDir.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "a\n1\n".write(to: xlsxDir, atomically: true, encoding: .utf8)
        try "b\n2\n".write(to: sqliteDir, atomically: true, encoding: .utf8)
        let clipboardFile = sandbox.appendingPathComponent("nanum-csv-clipboard-\(UUID().uuidString).csv")
        try "c\n3\n".write(to: clipboardFile, atomically: true, encoding: .utf8)
        let unrelated = sandbox.appendingPathComponent("keep-me.txt")
        try "keep".write(to: unrelated, atomically: true, encoding: .utf8)

        let removed = TempFileCleanup.removeStaleTempFiles(in: sandbox, now: Date())

        XCTAssertEqual(removed, 3, "two bridge dirs + one clipboard file")
        XCTAssertFalse(fm.fileExists(atPath: sandbox.appendingPathComponent("NanumCsvViewerXlsx").path))
        XCTAssertFalse(fm.fileExists(atPath: sandbox.appendingPathComponent("NanumCsvViewerSqlite").path))
        XCTAssertFalse(fm.fileExists(atPath: clipboardFile.path))
        XCTAssertTrue(fm.fileExists(atPath: unrelated.path), "unrelated temp files are left alone")
    }

    func testIsNoOpWhenNothingToClean() throws {
        let sandbox = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: sandbox) }
        XCTAssertEqual(TempFileCleanup.removeStaleTempFiles(in: sandbox, now: Date()), 0)
    }

    func testAgeGateKeepsFreshEntries() throws {
        // A bridge dir a launch-time document just created must survive the
        // sweep — only prior-session leftovers are old enough to remove.
        let sandbox = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: sandbox) }
        let fm = FileManager.default
        let freshDir = sandbox.appendingPathComponent("NanumCsvViewerXlsx/current", isDirectory: true)
        try fm.createDirectory(at: freshDir, withIntermediateDirectories: true)
        try "x".write(to: freshDir.appendingPathComponent("sheet.csv"), atomically: true, encoding: .utf8)

        let removed = TempFileCleanup.removeStaleTempFiles(in: sandbox, minimumAge: 600, now: Date())
        XCTAssertEqual(removed, 0, "freshly created bridge dir is younger than the age gate")
        XCTAssertTrue(fm.fileExists(atPath: sandbox.appendingPathComponent("NanumCsvViewerXlsx").path))

        // The same entry, viewed from 20 minutes in the future, is stale.
        let removedLater = TempFileCleanup.removeStaleTempFiles(in: sandbox, minimumAge: 600, now: Date().addingTimeInterval(1200))
        XCTAssertEqual(removedLater, 1)
    }

    func testBridgeDirectoryNamesAreStableConstants() {
        XCTAssertTrue(TempFileCleanup.bridgeDirectoryNames.contains("NanumCsvViewerXlsx"))
        XCTAssertTrue(TempFileCleanup.bridgeDirectoryNames.contains("NanumCsvViewerSqlite"))
        XCTAssertEqual(TempFileCleanup.clipboardFilePrefix, "nanum-csv-clipboard-")
    }
}
