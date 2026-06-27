import AppKit
import XCTest
@testable import NanumCsvViewerMac

@MainActor
final class AppMenuTests: XCTestCase {
    func testFileMenuContainsCloseAction() throws {
        let mainMenu = try buildMainMenu()
        let fileItem = try XCTUnwrap(mainMenu.items.first { $0.title == L.t("File", "파일") })
        let fileMenu = try XCTUnwrap(fileItem.submenu)
        let closeItem = try XCTUnwrap(fileMenu.items.first { $0.title == L.t("Close", "닫기") })

        XCTAssertEqual(closeItem.action, NSSelectorFromString("closeCurrentDocument:"))
        XCTAssertEqual(closeItem.keyEquivalent, "w")
        XCTAssertNotNil(closeItem.image)
    }

    func testPivotMenuIsTopLevelWithTableAndChartActions() throws {
        let mainMenu = try buildMainMenu()
        let pivotItem = try XCTUnwrap(mainMenu.items.first { $0.title == L.t("Pivot", "피벗") })
        let pivotMenu = try XCTUnwrap(pivotItem.submenu)
        let pivotTitles = pivotMenu.items.map(\.title)

        XCTAssertEqual(pivotTitles, [
            L.t("Pivot Table", "피벗 테이블"),
            L.t("Pivot Chart", "피벗 차트")
        ])
        XCTAssertEqual(pivotMenu.items[0].action, #selector(MainWindowController.showPivotTable(_:)))
        XCTAssertEqual(pivotMenu.items[1].action, NSSelectorFromString("showPivotChart:"))

        let analysisItem = try XCTUnwrap(mainMenu.items.first { $0.title == L.t("Analysis", "분석") })
        let analysisTitles = try XCTUnwrap(analysisItem.submenu).items.map(\.title)
        XCTAssertFalse(analysisTitles.contains(L.t("Pivot Table", "피벗 테이블")))
        XCTAssertFalse(analysisTitles.contains(L.t("Pivot Chart", "피벗 차트")))
    }

    func testAnalysisMenuContainsResultCopyAndExportActions() throws {
        let mainMenu = try buildMainMenu()
        let analysisItem = try XCTUnwrap(mainMenu.items.first { $0.title == L.t("Analysis", "분석") })
        let analysisMenu = try XCTUnwrap(analysisItem.submenu)
        let copyItem = try XCTUnwrap(analysisMenu.items.first { $0.title == L.t("Copy Analysis Result", "분석 결과 복사") })
        let exportItem = try XCTUnwrap(analysisMenu.items.first { $0.title == L.t("Export Analysis Result...", "분석 결과 내보내기...") })

        XCTAssertEqual(copyItem.action, NSSelectorFromString("copyAnalysisResult:"))
        XCTAssertEqual(exportItem.action, NSSelectorFromString("exportAnalysisResult:"))
        XCTAssertNotNil(copyItem.image)
        XCTAssertNotNil(exportItem.image)
    }

    func testSettingsMenuContainsIndexCacheManagementActions() throws {
        let mainMenu = try buildMainMenu()
        let settingsItem = try XCTUnwrap(mainMenu.items.first { $0.title == L.t("Settings", "설정") })
        let settingsMenu = try XCTUnwrap(settingsItem.submenu)

        let persistentIndex = try XCTUnwrap(settingsMenu.items.first { $0.title == L.t("Persistent Index", "인덱스 저장") })
        let deleteOnClose = try XCTUnwrap(settingsMenu.items.first { $0.title == L.t("Delete Index Cache on Close", "CSV 닫을 때 인덱스 캐시 삭제") })
        let revealFolder = try XCTUnwrap(settingsMenu.items.first { $0.title == L.t("Show Index Folder", "인덱스 폴더 보기") })
        let clearFolder = try XCTUnwrap(settingsMenu.items.first { $0.title == L.t("Clear Index Folder", "인덱스 폴더 비우기") })

        XCTAssertEqual(persistentIndex.action, NSSelectorFromString("togglePersistentIndex:"))
        XCTAssertEqual(deleteOnClose.action, NSSelectorFromString("toggleDeleteIndexCacheOnClose:"))
        XCTAssertEqual(revealFolder.action, NSSelectorFromString("showIndexFolder:"))
        XCTAssertEqual(clearFolder.action, NSSelectorFromString("clearIndexFolder:"))
        XCTAssertNotNil(persistentIndex.image)
        XCTAssertNotNil(deleteOnClose.image)
        XCTAssertNotNil(revealFolder.image)
        XCTAssertNotNil(clearFolder.image)
    }

    func testEverySubmenuCommandHasIcon() throws {
        let mainMenu = try buildMainMenu()
        let missingIcons = mainMenu.items.flatMap { item -> [String] in
            guard let submenu = item.submenu else { return [] }
            return menuCommandTitlesMissingIcons(in: submenu)
        }

        XCTAssertEqual(missingIcons, [])
    }

    private func buildMainMenu() throws -> NSMenu {
        _ = NSApplication.shared
        let previousMenu = NSApp.mainMenu
        let existingWindows = Set(NSApp.windows.map(ObjectIdentifier.init))

        let delegate = AppDelegate()
        delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification, object: NSApp))
        let mainMenu = try XCTUnwrap(NSApp.mainMenu)

        addTeardownBlock { @MainActor in
            for window in NSApp.windows where !existingWindows.contains(ObjectIdentifier(window)) {
                window.close()
            }
            NSApp.mainMenu = previousMenu
        }

        return mainMenu
    }

    private func menuCommandTitlesMissingIcons(in menu: NSMenu) -> [String] {
        menu.items.flatMap { item -> [String] in
            var missing: [String] = []
            if !item.isSeparatorItem, !item.title.isEmpty, item.image == nil {
                missing.append(item.title)
            }
            if let submenu = item.submenu {
                missing.append(contentsOf: menuCommandTitlesMissingIcons(in: submenu))
            }
            return missing
        }
    }
}
