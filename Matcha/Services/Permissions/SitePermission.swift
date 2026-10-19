import Foundation

/// Permission that a page requests and whose decision is remembered per website (task 5.2). Location (public API from
/// macOS 27 only) and notifications (no public API) are postponed: `DECISIONS.md`.
nonisolated enum SitePermissionKind: String, CaseIterable, Identifiable, Sendable {
    case camera
    case microphone

    var id: String {
        rawValue
    }
}

/// Decision remembered for a website.
nonisolated enum SitePermissionDecision: String, CaseIterable, Sendable {
    case allow
    case deny
}

/// The user's answer in the page's banner.
nonisolated enum SitePermissionAnswer: Sendable {
    /// Granted for this request only (WebKit keeps it for the lifetime of the page); nothing is remembered.
    case allowOnce
    case alwaysAllow
    /// Denied, and remembered (“Don't Allow”).
    case deny
}
