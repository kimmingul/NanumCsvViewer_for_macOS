import AppKit
import XCTest
@testable import NanumCsvViewerMac

@MainActor
final class MainWindowControllerLifecycleTests: XCTestCase {
    func testClosingWindowRunsTeardownHandler() {
        _ = NSApplication.shared
        let controller = MainWindowController()
        controller.showWindow(nil)

        var handlerFired = false
        let torndown = expectation(description: "teardown handler fires")
        controller.closeHandler = { _ in
            handlerFired = true
            torndown.fulfill()
        }

        // Simulate a red-button / window-level close — NOT controller.close().
        // Before the fix this did not run teardown, leaking the controller.
        controller.window?.close()

        wait(for: [torndown], timeout: 2.0)
        XCTAssertTrue(handlerFired, "closing the window must run teardown, not only controller.close()")
    }

    func testTeardownRunsAtMostOnce() {
        _ = NSApplication.shared
        let controller = MainWindowController()
        controller.showWindow(nil)

        var fireCount = 0
        let torndown = expectation(description: "teardown fires exactly once")
        torndown.assertForOverFulfill = true
        controller.closeHandler = { _ in
            fireCount += 1
            torndown.fulfill()
        }

        controller.window?.close() // fires windowWillClose → teardown
        controller.close()         // explicit close afterwards must be a no-op

        wait(for: [torndown], timeout: 2.0)

        let settle = expectation(description: "drain any erroneous second dispatch")
        DispatchQueue.main.async { settle.fulfill() }
        wait(for: [settle], timeout: 2.0)

        XCTAssertEqual(fireCount, 1, "teardown must be idempotent across window-close and close()")
    }
}
