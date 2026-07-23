import Foundation
import XCTest
@testable import NanumCsvViewerMac

/// The embedded XPC service is looked up by `NSXPCConnection(serviceName:)`,
/// which must match the service bundle's `CFBundleIdentifier` exactly. The App
/// Store additionally requires a nested bundle's ID to be prefixed by the host
/// app's bundle ID, so the name is derived from the host bundle rather than
/// hardcoded — these tests pin that derivation.
final class ImportClientServiceNameTests: XCTestCase {
    func testServiceNameDerivesFromHostBundleID() {
        XCTAssertEqual(
            ImportClient.resolveServiceName(hostBundleID: "com.nanumspace.mgkim.nanumcsvviewer"),
            "com.nanumspace.mgkim.nanumcsvviewer.ImportService"
        )
        XCTAssertEqual(
            ImportClient.resolveServiceName(hostBundleID: "com.nanum.csvviewer.mac"),
            "com.nanum.csvviewer.mac.ImportService"
        )
    }

    func testServiceNameFallsBackWhenHostBundleIDMissing() {
        let fallback = "com.nanumspace.mgkim.nanumcsvviewer.ImportService"
        XCTAssertEqual(ImportClient.resolveServiceName(hostBundleID: nil), fallback)
        XCTAssertEqual(ImportClient.resolveServiceName(hostBundleID: ""), fallback)
    }

    func testDerivedServiceNameSatisfiesAppStorePrefixRule() {
        let appID = "com.nanumspace.mgkim.nanumcsvviewer"
        let serviceName = ImportClient.resolveServiceName(hostBundleID: appID)
        XCTAssertTrue(
            serviceName.hasPrefix(appID + "."),
            "App Store requires the embedded XPC bundle ID to be prefixed by the host app bundle ID"
        )
    }
}
