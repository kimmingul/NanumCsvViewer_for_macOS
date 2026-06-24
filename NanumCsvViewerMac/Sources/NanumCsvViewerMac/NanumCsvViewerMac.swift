import AppKit
@preconcurrency import CsvCore

@main
struct NanumCsvViewerMacApp {
    private static var retainedDelegate: AppDelegate?

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        retainedDelegate = delegate
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var mainWindowController: MainWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = MainWindowController()
        mainWindowController = controller
        buildMenu(target: controller)
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    private func buildMenu(target: MainWindowController) {
        let mainMenu = NSMenu()
        NSApp.mainMenu = mainMenu

        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu
        appMenu.addItem(NSMenuItem(title: L.t("About Nanum CSV Viewer", "Nanum CSV Viewer 정보"), action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: ""))
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: L.t("Quit Nanum CSV Viewer", "Nanum CSV Viewer 종료"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        let fileItem = NSMenuItem(title: L.t("File", "파일"), action: nil, keyEquivalent: "")
        mainMenu.addItem(fileItem)
        let fileMenu = NSMenu(title: fileItem.title)
        fileItem.submenu = fileMenu
        let open = NSMenuItem(title: L.t("Open...", "열기..."), action: #selector(MainWindowController.openDocument(_:)), keyEquivalent: "o")
        open.target = target
        fileMenu.addItem(open)

        let editItem = NSMenuItem(title: L.t("Edit", "편집"), action: nil, keyEquivalent: "")
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: editItem.title)
        editItem.submenu = editMenu
        let find = NSMenuItem(title: L.t("Find", "찾기"), action: #selector(MainWindowController.focusFindField(_:)), keyEquivalent: "f")
        find.target = target
        editMenu.addItem(find)
        let findNext = NSMenuItem(title: L.t("Find Next", "다음 찾기"), action: #selector(MainWindowController.findNext(_:)), keyEquivalent: "\u{F704}")
        findNext.target = target
        editMenu.addItem(findNext)
        let goToRow = NSMenuItem(title: L.t("Go to Row...", "행으로 이동..."), action: #selector(MainWindowController.goToRow(_:)), keyEquivalent: "g")
        goToRow.target = target
        editMenu.addItem(goToRow)
        editMenu.addItem(.separator())
        let copyCell = NSMenuItem(title: L.t("Copy Cell", "셀 복사"), action: #selector(MainWindowController.copySelectedCellToPasteboard(_:)), keyEquivalent: "c")
        copyCell.target = target
        editMenu.addItem(copyCell)
        editMenu.addItem(.separator())
        let applyFilter = NSMenuItem(title: L.t("Apply Filter", "필터 적용"), action: #selector(MainWindowController.applyTextFilter(_:)), keyEquivalent: "")
        applyFilter.target = target
        editMenu.addItem(applyFilter)
        let filterByCell = NSMenuItem(title: L.t("Filter by Cell", "이 셀 값으로 필터"), action: #selector(MainWindowController.filterBySelectedCell(_:)), keyEquivalent: "b")
        filterByCell.target = target
        editMenu.addItem(filterByCell)
        let clearFilter = NSMenuItem(title: L.t("Clear Filter", "필터 해제"), action: #selector(MainWindowController.clearFilter(_:)), keyEquivalent: "L")
        clearFilter.keyEquivalentModifierMask = [.command, .shift]
        clearFilter.target = target
        editMenu.addItem(clearFilter)
        editMenu.addItem(.separator())
        let sortAsc = NSMenuItem(title: L.t("Sort Ascending", "오름차순 정렬"), action: #selector(MainWindowController.sortAscending(_:)), keyEquivalent: "")
        sortAsc.target = target
        editMenu.addItem(sortAsc)
        let sortDesc = NSMenuItem(title: L.t("Sort Descending", "내림차순 정렬"), action: #selector(MainWindowController.sortDescending(_:)), keyEquivalent: "")
        sortDesc.target = target
        editMenu.addItem(sortDesc)
        let clearSort = NSMenuItem(title: L.t("Clear Sort", "정렬 해제"), action: #selector(MainWindowController.clearSort(_:)), keyEquivalent: "S")
        clearSort.keyEquivalentModifierMask = [.command, .shift]
        clearSort.target = target
        editMenu.addItem(clearSort)

        let viewItem = NSMenuItem(title: L.t("View", "보기"), action: nil, keyEquivalent: "")
        mainMenu.addItem(viewItem)
        let viewMenu = NSMenu(title: viewItem.title)
        viewItem.submenu = viewMenu
        let filterBar = NSMenuItem(title: L.t("Show Filter Bar", "필터 바 보기"), action: #selector(MainWindowController.toggleFilterBar(_:)), keyEquivalent: "F")
        filterBar.keyEquivalentModifierMask = [.command, .option]
        filterBar.target = target
        viewMenu.addItem(filterBar)
        let details = NSMenuItem(title: L.t("Toggle Inspector", "인스펙터 토글"), action: #selector(MainWindowController.toggleDetailPanel(_:)), keyEquivalent: "\u{F705}")
        details.target = target
        viewMenu.addItem(details)
        let statistics = NSMenuItem(title: L.t("Column Statistics", "컬럼 통계"), action: #selector(MainWindowController.showColumnStatistics(_:)), keyEquivalent: "i")
        statistics.keyEquivalentModifierMask = [.command, .option]
        statistics.target = target
        viewMenu.addItem(statistics)
        viewMenu.addItem(.separator())
        let encodingItem = NSMenuItem(title: L.t("Encoding", "인코딩"), action: nil, keyEquivalent: "")
        let encodingMenu = NSMenu(title: encodingItem.title)
        for name in CsvEncodingName.selectable {
            let item = NSMenuItem(title: name, action: #selector(MainWindowController.changeEncodingFromMenu(_:)), keyEquivalent: "")
            item.representedObject = name
            item.target = target
            encodingMenu.addItem(item)
        }
        encodingItem.submenu = encodingMenu
        viewMenu.addItem(encodingItem)

        let helpItem = NSMenuItem(title: L.t("Help", "도움말"), action: nil, keyEquivalent: "")
        mainMenu.addItem(helpItem)
        let helpMenu = NSMenu(title: helpItem.title)
        helpItem.submenu = helpMenu
        let usage = NSMenuItem(title: L.t("How to Use", "사용법"), action: #selector(MainWindowController.showUsage(_:)), keyEquivalent: "?")
        usage.target = target
        helpMenu.addItem(usage)
    }
}
