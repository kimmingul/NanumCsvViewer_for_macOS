import Foundation
import Security

/// Scaffolding for verifying that an XPC peer is our own signed app.
///
/// DISABLED by default: `ImportServiceDelegate.peerRequirement` is `nil`, which
/// accepts any peer — the historical behavior, safe because the service is a
/// bundled `XPCServices/` service scoped to the host app by launchd. Turning it
/// on needs (1) a real Team ID / designated requirement string, and (2) a
/// SIGNED-build CI smoke test that exercises the `auditToken` path (unit tests
/// cannot). Until both exist, do NOT set a non-nil requirement in a release.
///
/// The one hard rule encoded here: when a requirement IS configured, ANY
/// outcome other than a positive match rejects the peer. There is no
/// fail-open-on-error branch.
enum PeerValidator {
    /// A `nil` requirement accepts (current behavior). A non-nil requirement
    /// delegates to `validate`, which must return `true` only on a positive
    /// match; any failure or error returns `false` (fail-closed).
    static func isAcceptable(requirement: String?, validate: () -> Bool) -> Bool {
        guard requirement != nil else { return true }
        return validate()
    }

    /// The real check (only run once a requirement is configured, i.e. never in
    /// the current shipping build). Validates the peer's audit token against a
    /// code-signing requirement; returns `false` on any error.
    static func auditTokenSatisfies(_ auditToken: audit_token_t, requirement: String) -> Bool {
        let tokenData = withUnsafeBytes(of: auditToken) { Data($0) }
        let attributes = [kSecGuestAttributeAudit: tokenData] as CFDictionary

        var code: SecCode?
        guard SecCodeCopyGuestWithAttributes(nil, attributes, [], &code) == errSecSuccess,
              let code else {
            return false
        }
        var requirementRef: SecRequirement?
        guard SecRequirementCreateWithString(requirement as CFString, [], &requirementRef) == errSecSuccess,
              let requirementRef else {
            return false
        }
        return SecCodeCheckValidity(code, [], requirementRef) == errSecSuccess
    }
}
