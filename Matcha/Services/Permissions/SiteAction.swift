import Foundation

/// Something a website asks to do, which waits for the user's answer in the page's banner: hand a link to another app
/// (audit W2), download files on its own (W7). “Always” is remembered per profile and per website
/// (`SiteActionAllowances`). Pure type.
nonisolated enum SiteAction: Hashable, Sendable {
    /// Hand the links of `scheme` (`zoommtg`, `mailto`, lowercase) to the app that opens them.
    case openApp(scheme: String)
    /// Download files without a click (`DownloadConsentPolicy`).
    case downloadFiles

    /// Saved key: `open:zoommtg`, `downloads`.
    var key: String {
        switch self {
        case let .openApp(scheme): "open:\(scheme)"
        case .downloadFiles: "downloads"
        }
    }

    init?(key: String) {
        if key == "downloads" {
            self = .downloadFiles
            return
        }
        guard key.hasPrefix("open:"), key.count > 5 else {
            return nil
        }
        self = .openApp(scheme: String(key.dropFirst(5)).lowercased())
    }
}

/// The user's answer to a website's request in the banner.
nonisolated enum SiteActionAnswer: Sendable {
    case decline
    /// This time only.
    case allowOnce
    /// Now and from now on, for this website.
    case alwaysAllow
}
