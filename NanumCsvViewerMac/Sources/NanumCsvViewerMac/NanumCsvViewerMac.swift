import AppKit
@preconcurrency import CsvCore

@main
struct NanumCsvViewerMacApp {
    static let displayName = "Nanum CSV Viewer"
    @MainActor private static var retainedDelegate: AppDelegate?

    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        retainedDelegate = delegate
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var windowControllers: [MainWindowController] = []
    private var aboutWindowController: AboutWindowController?

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu.title == L.t("Columns", "컬럼") else { return }
        // Bind strictly to the front window's controller — the same one the
        // menu action will target through the responder chain. No arbitrary
        // fallback that could mutate a background document.
        let controller = (NSApp.keyWindow?.windowController as? MainWindowController)
            ?? (NSApp.mainWindow?.windowController as? MainWindowController)
        if let controller {
            controller.populateColumnsMenu(menu)
        } else {
            menu.removeAllItems()
            let empty = NSMenuItem(title: L.t("No document", "문서 없음"), action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu()
        MainWindowController.applyAppearancePreference(
            AppearancePreference.from(rawValue: UserDefaults.standard.string(forKey: "NanumCsvViewerMac.Appearance"))
        )
        // Sweep leftover temp-CSV bridge dirs and clipboard files from prior
        // sessions off the main thread so it never delays launch. The 10-minute
        // age gate protects anything a document opened at launch just created.
        DispatchQueue.global(qos: .utility).async {
            TempFileCleanup.removeStaleTempFiles(
                in: FileManager.default.temporaryDirectory,
                minimumAge: 600,
                now: Date()
            )
        }
        // application(_:openFile:) runs BEFORE this for command-line and
        // Finder-open launches and may already have created a document
        // window; only add the empty window when nothing exists yet.
        if windowControllers.isEmpty {
            let controller = makeWindowController()
            controller.showWindow(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        let url = URL(fileURLWithPath: filename)
        if windowControllers.count == 1,
           let only = windowControllers.first,
           !only.hasOpenDocument {
            only.openFileURL(url)
            return true
        }
        openAdditionalDocuments([url], tabbedTo: NSApp.keyWindow)
        return true
    }

    private func makeWindowController(opening url: URL? = nil) -> MainWindowController {
        let controller = MainWindowController()
        controller.openAdditionalFilesHandler = { [weak self] urls, sourceWindow in
            self?.openAdditionalDocuments(urls, tabbedTo: sourceWindow)
        }
        controller.closeHandler = { [weak self] controller in
            self?.windowControllers.removeAll { $0 === controller }
        }
        windowControllers.append(controller)

        if let url {
            controller.openFileURL(url)
        }
        return controller
    }

    private func openAdditionalDocuments(_ urls: [URL], tabbedTo baseWindow: NSWindow?) {
        for url in urls {
            let controller = makeWindowController(opening: url)
            controller.showWindow(nil)
            if let baseWindow, let window = controller.window, baseWindow !== window {
                baseWindow.addTabbedWindow(window, ordered: .above)
            }
        }
    }

    private func buildMenu() {
        let mainMenu = NSMenu()
        NSApp.mainMenu = mainMenu

        let appMenuItem = NSMenuItem(title: NanumCsvViewerMacApp.displayName, action: nil, keyEquivalent: "")
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu
        let about = NSMenuItem(title: L.t("About Nanum CSV Viewer", "Nanum CSV Viewer 정보"), action: #selector(showAboutWindow(_:)), keyEquivalent: "")
        about.target = self
        appMenu.addItem(about)
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: L.t("Quit Nanum CSV Viewer", "Nanum CSV Viewer 종료"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        let fileItem = NSMenuItem(title: L.t("File", "파일"), action: nil, keyEquivalent: "")
        mainMenu.addItem(fileItem)
        let fileMenu = NSMenu(title: fileItem.title)
        fileItem.submenu = fileMenu
        let open = NSMenuItem(title: L.t("Open...", "열기..."), action: #selector(MainWindowController.openDocument(_:)), keyEquivalent: "o")
        fileMenu.addItem(open)
        let clipboard = NSMenuItem(title: L.t("Open from Clipboard", "클립보드에서 열기"), action: #selector(MainWindowController.openFromClipboard(_:)), keyEquivalent: "v")
        clipboard.keyEquivalentModifierMask = [.command, .shift]
        fileMenu.addItem(clipboard)
        let close = NSMenuItem(title: L.t("Close", "닫기"), action: #selector(MainWindowController.closeCurrentDocument(_:)), keyEquivalent: "w")
        fileMenu.addItem(close)
        fileMenu.addItem(.separator())
        let export = NSMenuItem(title: L.t("Export Current View...", "현재 보기 내보내기..."), action: #selector(MainWindowController.exportCurrentView(_:)), keyEquivalent: "e")
        fileMenu.addItem(export)
        let exportMarkdown = NSMenuItem(title: L.t("Export as Markdown...", "Markdown으로 내보내기..."), action: #selector(MainWindowController.exportCurrentViewAsMarkdown(_:)), keyEquivalent: "")
        fileMenu.addItem(exportMarkdown)
        let exportJson = NSMenuItem(title: L.t("Export as JSON...", "JSON으로 내보내기..."), action: #selector(MainWindowController.exportCurrentViewAsJson(_:)), keyEquivalent: "")
        fileMenu.addItem(exportJson)
        let exportHtml = NSMenuItem(title: L.t("Export as HTML...", "HTML로 내보내기..."), action: #selector(MainWindowController.exportCurrentViewAsHtml(_:)), keyEquivalent: "")
        fileMenu.addItem(exportHtml)

        let editItem = NSMenuItem(title: L.t("Edit", "편집"), action: nil, keyEquivalent: "")
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: editItem.title)
        editItem.submenu = editMenu
        let find = NSMenuItem(title: L.t("Find", "찾기"), action: #selector(MainWindowController.focusFindField(_:)), keyEquivalent: "f")
        editMenu.addItem(find)
        let findNext = NSMenuItem(title: L.t("Find Next", "다음 찾기"), action: #selector(MainWindowController.findNext(_:)), keyEquivalent: "\u{F704}")
        editMenu.addItem(findNext)
        let goToRow = NSMenuItem(title: L.t("Go to Row...", "행으로 이동..."), action: #selector(MainWindowController.goToRow(_:)), keyEquivalent: "g")
        editMenu.addItem(goToRow)
        editMenu.addItem(.separator())
        let copyCell = NSMenuItem(title: L.t("Copy Cell", "셀 복사"), action: #selector(MainWindowController.copySelectedCellToPasteboard(_:)), keyEquivalent: "c")
        editMenu.addItem(copyCell)
        let copyCsv = NSMenuItem(title: L.t("Copy Cell as CSV", "셀을 CSV로 복사"), action: #selector(MainWindowController.copySelectedCellAsCsv(_:)), keyEquivalent: "")
        editMenu.addItem(copyCsv)
        let copyJson = NSMenuItem(title: L.t("Copy Cell as JSON", "셀을 JSON으로 복사"), action: #selector(MainWindowController.copySelectedCellAsJson(_:)), keyEquivalent: "")
        editMenu.addItem(copyJson)
        editMenu.addItem(.separator())
        let applyFilter = NSMenuItem(title: L.t("Apply Filter", "필터 적용"), action: #selector(MainWindowController.applyTextFilter(_:)), keyEquivalent: "")
        editMenu.addItem(applyFilter)
        let filterByCell = NSMenuItem(title: L.t("Filter by Cell", "이 셀 값으로 필터"), action: #selector(MainWindowController.filterBySelectedCell(_:)), keyEquivalent: "b")
        editMenu.addItem(filterByCell)
        let clearFilter = NSMenuItem(title: L.t("Clear Filter", "필터 해제"), action: #selector(MainWindowController.clearFilter(_:)), keyEquivalent: "L")
        clearFilter.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(clearFilter)
        editMenu.addItem(.separator())
        let sortAsc = NSMenuItem(title: L.t("Sort Ascending", "오름차순 정렬"), action: #selector(MainWindowController.sortAscending(_:)), keyEquivalent: "")
        editMenu.addItem(sortAsc)
        let sortDesc = NSMenuItem(title: L.t("Sort Descending", "내림차순 정렬"), action: #selector(MainWindowController.sortDescending(_:)), keyEquivalent: "")
        editMenu.addItem(sortDesc)
        let clearSort = NSMenuItem(title: L.t("Clear Sort", "정렬 해제"), action: #selector(MainWindowController.clearSort(_:)), keyEquivalent: "S")
        clearSort.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(clearSort)

        let viewItem = NSMenuItem(title: L.t("View", "보기"), action: nil, keyEquivalent: "")
        mainMenu.addItem(viewItem)
        let viewMenu = NSMenu(title: viewItem.title)
        viewItem.submenu = viewMenu
        let filterBar = NSMenuItem(title: L.t("Show Filter Bar", "필터 바 보기"), action: #selector(MainWindowController.toggleFilterBar(_:)), keyEquivalent: "F")
        filterBar.keyEquivalentModifierMask = [.command, .option]
        viewMenu.addItem(filterBar)
        let details = NSMenuItem(title: L.t("Toggle Inspector", "인스펙터 토글"), action: #selector(MainWindowController.toggleDetailPanel(_:)), keyEquivalent: "\u{F707}")
        details.keyEquivalentModifierMask = []
        viewMenu.addItem(details)
        let facets = NSMenuItem(title: L.t("Facets Panel", "패싯 패널"), action: #selector(MainWindowController.toggleFacetsPanel(_:)), keyEquivalent: "\u{F709}")
        facets.keyEquivalentModifierMask = []
        viewMenu.addItem(facets)
        let statistics = NSMenuItem(title: L.t("Column Statistics", "컬럼 통계"), action: #selector(MainWindowController.showColumnStatistics(_:)), keyEquivalent: "i")
        statistics.keyEquivalentModifierMask = [.command, .option]
        viewMenu.addItem(statistics)
        let performance = NSMenuItem(title: L.t("Performance Dashboard", "성능 대시보드"), action: #selector(MainWindowController.showPerformanceDashboard(_:)), keyEquivalent: "p")
        performance.keyEquivalentModifierMask = [.command, .option]
        viewMenu.addItem(performance)
        let benchmark = NSMenuItem(title: L.t("Run Benchmark", "벤치마크 실행"), action: #selector(MainWindowController.runBenchmark(_:)), keyEquivalent: "b")
        benchmark.keyEquivalentModifierMask = [.command, .option]
        viewMenu.addItem(benchmark)
        let columnsItem = NSMenuItem(title: L.t("Columns", "컬럼"), action: nil, keyEquivalent: "")
        let columnsMenu = NSMenu(title: columnsItem.title)
        columnsMenu.delegate = self
        columnsMenu.autoenablesItems = false
        columnsItem.submenu = columnsMenu
        viewMenu.addItem(columnsItem)
        let showAllColumns = NSMenuItem(title: L.t("Show All Columns", "모든 컬럼 보기"), action: #selector(MainWindowController.showAllColumns(_:)), keyEquivalent: "")
        viewMenu.addItem(showAllColumns)
        let rowDensityItem = NSMenuItem(title: L.t("Row Density", "행 밀도"), action: nil, keyEquivalent: "")
        let rowDensityMenu = NSMenu(title: rowDensityItem.title)
        rowDensityItem.submenu = rowDensityMenu
        for density in GridRowDensity.allCases {
            let item = NSMenuItem(title: density.title, action: #selector(MainWindowController.changeRowDensity(_:)), keyEquivalent: "")
            item.representedObject = density.rawValue
            rowDensityMenu.addItem(item)
        }
        viewMenu.addItem(rowDensityItem)

        let fontSizeItem = NSMenuItem(title: L.t("Font Size", "글자 크기"), action: nil, keyEquivalent: "")
        let fontSizeMenu = NSMenu(title: fontSizeItem.title)
        fontSizeItem.submenu = fontSizeMenu
        for size in GridFontSize.allCases {
            let item = NSMenuItem(title: size.title, action: #selector(MainWindowController.changeGridFontSize(_:)), keyEquivalent: "")
            item.representedObject = size.rawValue
            fontSizeMenu.addItem(item)
        }
        viewMenu.addItem(fontSizeItem)

        let appearanceItem = NSMenuItem(title: L.t("Appearance", "화면 모드"), action: nil, keyEquivalent: "")
        let appearanceMenu = NSMenu(title: appearanceItem.title)
        appearanceItem.submenu = appearanceMenu
        for preference in AppearancePreference.allCases {
            let item = NSMenuItem(title: preference.title, action: #selector(MainWindowController.changeAppearance(_:)), keyEquivalent: "")
            item.representedObject = preference.rawValue
            appearanceMenu.addItem(item)
        }
        viewMenu.addItem(appearanceItem)

        viewMenu.addItem(.separator())
        let saveView = NSMenuItem(title: L.t("Save View As...", "다른 이름으로 보기 저장..."), action: #selector(MainWindowController.saveCurrentView(_:)), keyEquivalent: "s")
        saveView.keyEquivalentModifierMask = [.command, .option]
        viewMenu.addItem(saveView)
        let restoreView = NSMenuItem(title: L.t("Restore Saved View...", "저장된 보기 복원..."), action: #selector(MainWindowController.restoreSavedView(_:)), keyEquivalent: "r")
        restoreView.keyEquivalentModifierMask = [.command, .option]
        viewMenu.addItem(restoreView)
        let autoRestoreView = NSMenuItem(title: L.t("Restore View on Open", "열 때 보기 복원"), action: #selector(MainWindowController.toggleAutoRestoreView(_:)), keyEquivalent: "")
        viewMenu.addItem(autoRestoreView)
        viewMenu.addItem(.separator())
        let encodingItem = NSMenuItem(title: L.t("Encoding", "인코딩"), action: nil, keyEquivalent: "")
        let encodingMenu = NSMenu(title: encodingItem.title)
        for name in CsvEncodingName.selectable {
            let item = NSMenuItem(title: name, action: #selector(MainWindowController.changeEncodingFromMenu(_:)), keyEquivalent: "")
            item.representedObject = name
            encodingMenu.addItem(item)
        }
        encodingItem.submenu = encodingMenu
        viewMenu.addItem(encodingItem)

        let settingsItem = NSMenuItem(title: L.t("Settings", "설정"), action: nil, keyEquivalent: "")
        mainMenu.addItem(settingsItem)
        let settingsMenu = NSMenu(title: settingsItem.title)
        settingsItem.submenu = settingsMenu
        let persistentIndex = NSMenuItem(title: L.t("Persistent Index", "인덱스 저장"), action: #selector(MainWindowController.togglePersistentIndex(_:)), keyEquivalent: "")
        settingsMenu.addItem(persistentIndex)
        let deleteIndexCacheOnClose = NSMenuItem(title: L.t("Delete Index Cache on Close", "CSV 닫을 때 인덱스 캐시 삭제"), action: #selector(MainWindowController.toggleDeleteIndexCacheOnClose(_:)), keyEquivalent: "")
        settingsMenu.addItem(deleteIndexCacheOnClose)
        settingsMenu.addItem(.separator())
        let showIndexFolder = NSMenuItem(title: L.t("Show Index Folder", "인덱스 폴더 보기"), action: #selector(MainWindowController.showIndexFolder(_:)), keyEquivalent: "")
        settingsMenu.addItem(showIndexFolder)
        let clearIndexFolder = NSMenuItem(title: L.t("Clear Index Folder", "인덱스 폴더 비우기"), action: #selector(MainWindowController.clearIndexFolder(_:)), keyEquivalent: "")
        settingsMenu.addItem(clearIndexFolder)

        let analysisItem = NSMenuItem(title: L.t("Analysis", "분석"), action: nil, keyEquivalent: "")
        mainMenu.addItem(analysisItem)
        let analysisMenu = NSMenu(title: analysisItem.title)
        analysisItem.submenu = analysisMenu
        let numeric = NSMenuItem(title: L.t("Numeric Distribution", "숫자 분포"), action: #selector(MainWindowController.showNumericDistribution(_:)), keyEquivalent: "")
        analysisMenu.addItem(numeric)
        let dateHistogram = NSMenuItem(title: L.t("Date Histogram", "날짜 히스토그램"), action: #selector(MainWindowController.showDateHistogram(_:)), keyEquivalent: "")
        analysisMenu.addItem(dateHistogram)
        let duplicates = NSMenuItem(title: L.t("Find Duplicates", "중복 찾기"), action: #selector(MainWindowController.showDuplicateRows(_:)), keyEquivalent: "")
        analysisMenu.addItem(duplicates)
        let groupBy = NSMenuItem(title: L.t("Group By", "그룹화"), action: #selector(MainWindowController.showGroupBy(_:)), keyEquivalent: "")
        analysisMenu.addItem(groupBy)
        analysisMenu.addItem(.separator())
        let correlation = NSMenuItem(title: L.t("Correlation", "상관분석"), action: #selector(MainWindowController.showCorrelation(_:)), keyEquivalent: "")
        analysisMenu.addItem(correlation)
        let tTest = NSMenuItem(title: L.t("t-test", "t-검정"), action: #selector(MainWindowController.showTTest(_:)), keyEquivalent: "")
        analysisMenu.addItem(tTest)
        let chiSquare = NSMenuItem(title: L.t("Chi-square Test", "카이제곱 검정"), action: #selector(MainWindowController.showChiSquare(_:)), keyEquivalent: "")
        analysisMenu.addItem(chiSquare)
        analysisMenu.addItem(.separator())
        let descriptive = NSMenuItem(title: L.t("Descriptive Statistics", "기술통계"), action: #selector(MainWindowController.showDescriptiveStatistics(_:)), keyEquivalent: "")
        analysisMenu.addItem(descriptive)
        let frequency = NSMenuItem(title: L.t("Frequency Analysis", "빈도분석"), action: #selector(MainWindowController.showFrequencyAnalysis(_:)), keyEquivalent: "")
        analysisMenu.addItem(frequency)
        let anova = NSMenuItem(title: L.t("One-way ANOVA", "일원배치 분산분석"), action: #selector(MainWindowController.showOneWayAnova(_:)), keyEquivalent: "")
        analysisMenu.addItem(anova)
        let normality = NSMenuItem(title: L.t("Normality Test (Shapiro-Wilk)", "정규성 검정 (Shapiro-Wilk)"), action: #selector(MainWindowController.showNormalityTest(_:)), keyEquivalent: "")
        analysisMenu.addItem(normality)
        let quickStats = NSMenuItem(title: L.t("Quick Stats", "빠른 통계"), action: #selector(MainWindowController.showQuickStats(_:)), keyEquivalent: "")
        analysisMenu.addItem(quickStats)
        analysisMenu.addItem(.separator())
        let copyAnalysis = NSMenuItem(title: L.t("Copy Analysis Result", "분석 결과 복사"), action: #selector(MainWindowController.copyAnalysisResult(_:)), keyEquivalent: "C")
        copyAnalysis.keyEquivalentModifierMask = [.command, .option]
        analysisMenu.addItem(copyAnalysis)
        let exportAnalysis = NSMenuItem(title: L.t("Export Analysis Result...", "분석 결과 내보내기..."), action: #selector(MainWindowController.exportAnalysisResult(_:)), keyEquivalent: "")
        analysisMenu.addItem(exportAnalysis)
        let cancelAnalysis = NSMenuItem(title: L.t("Cancel Analysis", "분석 취소"), action: #selector(MainWindowController.cancelAnalysis(_:)), keyEquivalent: ".")
        cancelAnalysis.keyEquivalentModifierMask = [.command]
        analysisMenu.addItem(cancelAnalysis)

        let visualizationItem = NSMenuItem(title: L.t("Visualization", "시각화"), action: nil, keyEquivalent: "")
        mainMenu.addItem(visualizationItem)
        let visualizationMenu = NSMenu(title: visualizationItem.title)
        visualizationItem.submenu = visualizationMenu
        let chartActions: [(ChartKind, Selector)] = [
            (.histogram, #selector(MainWindowController.showHistogramChartWindow(_:))),
            (.boxplot, #selector(MainWindowController.showBoxplotChartWindow(_:))),
            (.scatter, #selector(MainWindowController.showScatterChartWindow(_:))),
            (.correlationHeatmap, #selector(MainWindowController.showCorrelationHeatmapWindow(_:))),
            (.qqPlot, #selector(MainWindowController.showQQPlotChartWindow(_:))),
            (.timeseries, #selector(MainWindowController.showTimeseriesChartWindow(_:))),
            (.pareto, #selector(MainWindowController.showParetoChartWindow(_:)))
        ]
        for (kind, action) in chartActions {
            visualizationMenu.addItem(NSMenuItem(title: kind.title, action: action, keyEquivalent: ""))
        }

        let dataQualityItem = NSMenuItem(title: L.t("Data Quality", "데이터 품질"), action: nil, keyEquivalent: "")
        mainMenu.addItem(dataQualityItem)
        let dataQualityMenu = NSMenu(title: dataQualityItem.title)
        dataQualityItem.submenu = dataQualityMenu
        // The Windows twin uses Ctrl+Shift+Q, but Cmd+Shift+Q is the macOS
        // logout chord, so the profile lives on Cmd+Shift+P instead.
        let qualityProfile = NSMenuItem(title: L.t("Run Quality Profile", "품질 프로파일 실행"), action: #selector(MainWindowController.runDataQualityProfile(_:)), keyEquivalent: "P")
        qualityProfile.keyEquivalentModifierMask = [.command, .shift]
        dataQualityMenu.addItem(qualityProfile)
        dataQualityMenu.addItem(.separator())
        let qualityMarkdown = NSMenuItem(title: L.t("Export Report as Markdown...", "리포트를 Markdown으로 내보내기..."), action: #selector(MainWindowController.exportDataQualityMarkdown(_:)), keyEquivalent: "")
        dataQualityMenu.addItem(qualityMarkdown)
        let qualityHtml = NSMenuItem(title: L.t("Export Report as HTML...", "리포트를 HTML로 내보내기..."), action: #selector(MainWindowController.exportDataQualityHtml(_:)), keyEquivalent: "")
        dataQualityMenu.addItem(qualityHtml)
        let qualityJson = NSMenuItem(title: L.t("Export Report as JSON...", "리포트를 JSON으로 내보내기..."), action: #selector(MainWindowController.exportDataQualityJson(_:)), keyEquivalent: "")
        dataQualityMenu.addItem(qualityJson)

        let pivotItem = NSMenuItem(title: L.t("Pivot", "피벗"), action: nil, keyEquivalent: "")
        mainMenu.addItem(pivotItem)
        let pivotMenu = NSMenu(title: pivotItem.title)
        pivotItem.submenu = pivotMenu
        let pivotTable = NSMenuItem(title: L.t("Pivot Table", "피벗 테이블"), action: #selector(MainWindowController.showPivotTable(_:)), keyEquivalent: "")
        pivotMenu.addItem(pivotTable)
        let pivotChart = NSMenuItem(title: L.t("Pivot Chart", "피벗 차트"), action: #selector(MainWindowController.showPivotChart(_:)), keyEquivalent: "")
        pivotMenu.addItem(pivotChart)

        let helpItem = NSMenuItem(title: L.t("Help", "도움말"), action: nil, keyEquivalent: "")
        mainMenu.addItem(helpItem)
        let helpMenu = NSMenu(title: helpItem.title)
        helpItem.submenu = helpMenu
        let usage = NSMenuItem(title: L.t("How to Use", "사용법"), action: #selector(MainWindowController.showUsage(_:)), keyEquivalent: "?")
        helpMenu.addItem(usage)

        decorateMenuIcons(mainMenu, skippingFirstItem: true)
    }

    private func decorateMenuIcons(_ menu: NSMenu, skippingFirstItem: Bool = false) {
        for (index, item) in menu.items.enumerated() {
            if !(skippingFirstItem && index == 0), !item.isSeparatorItem, !item.title.isEmpty, item.image == nil {
                item.image = menuIcon(symbol: menuIconSymbol(for: item), title: item.title)
            }
            if let submenu = item.submenu {
                decorateMenuIcons(submenu)
            }
        }
    }

    private func menuIcon(symbol: String, title: String) -> NSImage? {
        NSImage(systemSymbolName: symbol, accessibilityDescription: title)
            ?? NSImage(systemSymbolName: "circle", accessibilityDescription: title)
    }

    private func menuIconSymbol(for item: NSMenuItem) -> String {
        switch item.action {
        case #selector(showAboutWindow(_:)):
            return "info.circle"
        case #selector(NSApplication.terminate(_:)):
            return "power"
        case #selector(MainWindowController.openDocument(_:)):
            return "folder"
        case #selector(MainWindowController.openFromClipboard(_:)):
            return "clipboard"
        case #selector(MainWindowController.closeCurrentDocument(_:)):
            return "xmark.circle"
        case #selector(MainWindowController.exportCurrentView(_:)):
            return "square.and.arrow.up"
        case #selector(MainWindowController.exportCurrentViewAsMarkdown(_:)):
            return "doc.plaintext"
        case #selector(MainWindowController.exportCurrentViewAsJson(_:)):
            return "curlybraces"
        case #selector(MainWindowController.exportCurrentViewAsHtml(_:)):
            return "chevron.left.forwardslash.chevron.right"
        case #selector(MainWindowController.focusFindField(_:)):
            return "magnifyingglass"
        case #selector(MainWindowController.findNext(_:)):
            return "arrow.down.circle"
        case #selector(MainWindowController.goToRow(_:)):
            return "number"
        case #selector(MainWindowController.copySelectedCellToPasteboard(_:)),
             #selector(MainWindowController.copySelectedCellAsCsv(_:)),
             #selector(MainWindowController.copySelectedCellAsJson(_:)):
            return "doc.on.doc"
        case #selector(MainWindowController.applyTextFilter(_:)):
            return "checkmark.circle"
        case #selector(MainWindowController.filterBySelectedCell(_:)):
            return "line.3.horizontal.decrease.circle"
        case #selector(MainWindowController.clearFilter(_:)):
            return "xmark.circle"
        case #selector(MainWindowController.sortAscending(_:)):
            return "arrow.up"
        case #selector(MainWindowController.sortDescending(_:)):
            return "arrow.down"
        case #selector(MainWindowController.clearSort(_:)):
            return "arrow.up.arrow.down.circle"
        case #selector(MainWindowController.toggleFilterBar(_:)):
            return "line.3.horizontal.decrease"
        case #selector(MainWindowController.toggleDetailPanel(_:)):
            return "sidebar.right"
        case #selector(MainWindowController.toggleFacetsPanel(_:)):
            return "chart.bar.xaxis"
        case #selector(MainWindowController.showColumnStatistics(_:)):
            return "chart.bar.doc.horizontal"
        case #selector(MainWindowController.showPerformanceDashboard(_:)):
            return "speedometer"
        case #selector(MainWindowController.runBenchmark(_:)):
            return "stopwatch"
        case #selector(MainWindowController.showAllColumns(_:)):
            return "tablecells"
        case #selector(MainWindowController.changeRowDensity(_:)):
            return "arrow.up.and.down.text.horizontal"
        case #selector(MainWindowController.saveCurrentView(_:)):
            return "bookmark"
        case #selector(MainWindowController.restoreSavedView(_:)):
            return "bookmark.fill"
        case #selector(MainWindowController.toggleAutoRestoreView(_:)):
            return "arrow.clockwise.circle"
        case #selector(MainWindowController.togglePersistentIndex(_:)):
            return "internaldrive"
        case #selector(MainWindowController.toggleDeleteIndexCacheOnClose(_:)):
            return "trash"
        case #selector(MainWindowController.showIndexFolder(_:)):
            return "folder"
        case #selector(MainWindowController.clearIndexFolder(_:)):
            return "trash.circle"
        case #selector(MainWindowController.changeEncodingFromMenu(_:)):
            return "textformat"
        case #selector(MainWindowController.showNumericDistribution(_:)):
            return "chart.bar"
        case #selector(MainWindowController.showDateHistogram(_:)):
            return "calendar"
        case #selector(MainWindowController.showDuplicateRows(_:)):
            return "square.on.square"
        case #selector(MainWindowController.showGroupBy(_:)):
            return "rectangle.3.group"
        case #selector(MainWindowController.showCorrelation(_:)):
            return "point.3.connected.trianglepath.dotted"
        case #selector(MainWindowController.showTTest(_:)):
            return "function"
        case #selector(MainWindowController.showChiSquare(_:)):
            return "x.squareroot"
        case #selector(MainWindowController.showQuickStats(_:)):
            return "sum"
        case #selector(MainWindowController.copyAnalysisResult(_:)):
            return "doc.on.doc"
        case #selector(MainWindowController.exportAnalysisResult(_:)):
            return "square.and.arrow.up"
        case #selector(MainWindowController.cancelAnalysis(_:)):
            return "xmark.circle"
        case #selector(MainWindowController.showPivotTable(_:)):
            return "tablecells"
        case #selector(MainWindowController.showPivotChart(_:)):
            return "chart.bar.xaxis"
        case #selector(MainWindowController.showHistogramChartWindow(_:)):
            return "chart.bar"
        case #selector(MainWindowController.showBoxplotChartWindow(_:)):
            return "square.split.2x1"
        case #selector(MainWindowController.showScatterChartWindow(_:)):
            return "chart.dots.scatter"
        case #selector(MainWindowController.showCorrelationHeatmapWindow(_:)):
            return "square.grid.3x3.fill"
        case #selector(MainWindowController.showQQPlotChartWindow(_:)):
            return "line.diagonal"
        case #selector(MainWindowController.showTimeseriesChartWindow(_:)):
            return "chart.xyaxis.line"
        case #selector(MainWindowController.showParetoChartWindow(_:)):
            return "chart.bar.doc.horizontal"
        case #selector(MainWindowController.runDataQualityProfile(_:)):
            return "checkmark.seal"
        case #selector(MainWindowController.exportDataQualityMarkdown(_:)):
            return "doc.plaintext"
        case #selector(MainWindowController.exportDataQualityHtml(_:)):
            return "chevron.left.forwardslash.chevron.right"
        case #selector(MainWindowController.exportDataQualityJson(_:)):
            return "curlybraces"
        case #selector(MainWindowController.showUsage(_:)):
            return "book"
        default:
            return submenuIconSymbol(for: item)
        }
    }

    private func submenuIconSymbol(for item: NSMenuItem) -> String {
        switch item.title {
        case L.t("File", "파일"):
            return "doc"
        case L.t("Edit", "편집"):
            return "pencil"
        case L.t("View", "보기"):
            return "eye"
        case L.t("Settings", "설정"):
            return "gearshape"
        case L.t("Encoding", "인코딩"):
            return "textformat"
        case L.t("Row Density", "행 밀도"):
            return "arrow.up.and.down.text.horizontal"
        case L.t("Font Size", "글자 크기"):
            return "textformat.size"
        case L.t("Appearance", "화면 모드"):
            return "circle.lefthalf.filled"
        case L.t("Columns", "컬럼"):
            return "checklist"
        case L.t("Analysis", "분석"):
            return "chart.xyaxis.line"
        case L.t("Visualization", "시각화"):
            return "chart.bar.xaxis"
        case L.t("Data Quality", "데이터 품질"):
            return "checkmark.seal"
        case L.t("Pivot", "피벗"):
            return "tablecells"
        case L.t("Help", "도움말"):
            return "questionmark.circle"
        default:
            return "circle"
        }
    }

    @objc func showAboutWindow(_ sender: Any?) {
        if aboutWindowController == nil {
            aboutWindowController = AboutWindowController()
        }
        aboutWindowController?.showWindow(sender)
        NSApp.activate(ignoringOtherApps: true)
    }
}
