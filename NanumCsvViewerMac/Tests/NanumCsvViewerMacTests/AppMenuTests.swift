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

    func testViewMenuContainsNamedSavedViewCommands() throws {
        let mainMenu = try buildMainMenu()
        let viewItem = try XCTUnwrap(mainMenu.items.first { $0.title == L.t("View", "보기") })
        let viewMenu = try XCTUnwrap(viewItem.submenu)

        let save = try XCTUnwrap(viewMenu.items.first { $0.action == #selector(MainWindowController.saveCurrentView(_:)) })
        XCTAssertEqual(save.title, L.t("Save View As...", "다른 이름으로 보기 저장..."))
        let restore = try XCTUnwrap(viewMenu.items.first { $0.action == #selector(MainWindowController.restoreSavedView(_:)) })
        XCTAssertEqual(restore.title, L.t("Restore Saved View...", "저장된 보기 복원..."))
        XCTAssertNotNil(viewMenu.items.first { $0.action == #selector(MainWindowController.toggleAutoRestoreView(_:)) })
    }

    func testViewMenuContainsFacetsPanelToggle() throws {
        let mainMenu = try buildMainMenu()
        let viewItem = try XCTUnwrap(mainMenu.items.first { $0.title == L.t("View", "보기") })
        let viewMenu = try XCTUnwrap(viewItem.submenu)
        let facetsItem = try XCTUnwrap(viewMenu.items.first { $0.title == L.t("Facets Panel", "패싯 패널") })

        XCTAssertEqual(facetsItem.action, NSSelectorFromString("toggleFacetsPanel:"))
        XCTAssertEqual(facetsItem.keyEquivalent, "\u{F709}", "F6 matches the Windows twin shortcut")
        XCTAssertEqual(facetsItem.keyEquivalentModifierMask, [])
        XCTAssertNotNil(facetsItem.image)
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

    func testApplicationMenuItemDoesNotReceiveIconDecoration() throws {
        let mainMenu = try buildMainMenu()
        let appMenuItem = try XCTUnwrap(mainMenu.items.first)

        XCTAssertEqual(appMenuItem.title, "Nanum CSV Viewer")
        XCTAssertNil(appMenuItem.image)
    }

    func testAppMenuUsesCustomAboutWindowAction() throws {
        let mainMenu = try buildMainMenu()
        let appMenuItem = try XCTUnwrap(mainMenu.items.first)
        let appMenu = try XCTUnwrap(appMenuItem.submenu)
        let aboutItem = try XCTUnwrap(appMenu.items.first { $0.title == L.t("About Nanum CSV Viewer", "Nanum CSV Viewer 정보") })

        XCTAssertEqual(aboutItem.action, NSSelectorFromString("showAboutWindow:"))
    }

    func testAboutWindowContentIncludesDeveloperAffiliations() {
        let content = AboutWindowContent.current()

        XCTAssertEqual(content.developerLabel, "Developed by")
        XCTAssertEqual(content.developerName, "Min-Gul Kim, MD, PhD")
        XCTAssertEqual(content.affiliationLines, [
            "Professor",
            "Department of Pharmacology",
            "Jeonbuk National University Medical School",
            "CEO",
            "Nanum Space Co., Ltd."
        ])
        XCTAssertEqual(content.footerText, "© 2026 김민걸")
    }

    func testAboutWindowUsesCompactTypography() {
        XCTAssertEqual(AboutTypography.appNameSize, 18)
        XCTAssertEqual(AboutTypography.versionSize, 12)
        XCTAssertEqual(AboutTypography.headlineSize, 15)
        XCTAssertEqual(AboutTypography.subheadlineSize, 13)
        XCTAssertEqual(AboutTypography.bodySize, 13)
        XCTAssertEqual(AboutTypography.footerSize, 12)
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
