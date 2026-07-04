import AppKit
import XCTest
@testable import NanumCsvViewerMac

@MainActor
final class InspectorDefaultsTests: XCTestCase {
    private let key = "NanumCsvViewerMac.InspectorVisible"
    private var previousValue: Any?

    override func setUp() {
        super.setUp()
        previousValue = UserDefaults.standard.object(forKey: key)
        UserDefaults.standard.removeObject(forKey: key)
    }

    override func tearDown() {
        if let previousValue {
            UserDefaults.standard.set(previousValue, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
        super.tearDown()
    }

    func testInspectorIsVisibleOnFirstLaunch() {
        let controller = MainWindowController()
        controller.showWindow(nil)
        XCTAssertTrue(controller.inspectorVisibleForTesting, "Windows twin shows the detail panel by default")
    }

    func testInspectorVisibilityPersistsAcrossControllers() {
        let first = MainWindowController()
        first.showWindow(nil)
        first.toggleDetailPanel(NSMenuItem())
        XCTAssertFalse(first.inspectorVisibleForTesting)

        let second = MainWindowController()
        second.showWindow(nil)
        XCTAssertFalse(second.inspectorVisibleForTesting, "hidden state should persist like the facets panel")
    }

    func testInspectorMenuUsesF4KeyEquivalent() throws {
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
        let viewItem = try XCTUnwrap(mainMenu.items.first { $0.title == L.t("View", "보기") })
        let inspectorItem = try XCTUnwrap(
            viewItem.submenu?.items.first { $0.title == L.t("Toggle Inspector", "인스펙터 토글") }
        )
        XCTAssertEqual(inspectorItem.keyEquivalent, "\u{F707}", "F4 matches the Windows twin shortcut")
        XCTAssertEqual(inspectorItem.keyEquivalentModifierMask, [])
    }
}
