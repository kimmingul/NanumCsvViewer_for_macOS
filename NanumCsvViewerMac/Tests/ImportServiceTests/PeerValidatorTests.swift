import XCTest
@testable import ImportService

final class PeerValidatorTests: XCTestCase {
    func testNilRequirementAcceptsWithoutValidating() {
        var validateCalled = false
        let accepted = PeerValidator.isAcceptable(requirement: nil) {
            validateCalled = true
            return false
        }
        XCTAssertTrue(accepted, "the shipping default (nil) accepts any peer")
        XCTAssertFalse(validateCalled, "nil requirement short-circuits before validating")
    }

    func testConfiguredRequirementAcceptsOnlyOnPositiveMatch() {
        XCTAssertTrue(PeerValidator.isAcceptable(requirement: "anchor apple generic") { true })
    }

    func testConfiguredRequirementFailsClosedOnAnyFailure() {
        XCTAssertFalse(
            PeerValidator.isAcceptable(requirement: "anchor apple generic") { false },
            "a configured requirement never fails open"
        )
    }

    func testShippingDefaultIsDisabled() {
        XCTAssertNil(ImportServiceDelegate.peerRequirement, "enforcement stays off until a signed-build smoke test exists")
    }
}
