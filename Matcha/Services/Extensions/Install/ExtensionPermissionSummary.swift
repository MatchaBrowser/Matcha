import Foundation

/// What an extension will be able to do, as sentences for the installation screen (task 6.4): like Chrome's warnings,
/// only sensitive permissions are named (“storage”, “alarms”… mean nothing to the user), once each, in a fixed order;
/// websites last. Pure type.
nonisolated enum ExtensionPermissionSummary {
    enum Line: Equatable {
        case allWebsites
        /// Hosts of the websites, without duplicates, in alphabetical order.
        case websites([String])
        case browsingHistory
        case cookies
        case clipboardRead
        case clipboardWrite
        case blockContent
        case nativeApps
        case notifications
        case downloads
        case bookmarks
        case location
        /// `file:` addresses, or every address (`<all_urls>`, audit E7).
        case localFiles
    }

    /// Sensitive permissions, in display order.
    private static let permissionLines: [(Line, Set<String>)] = [
        (.browsingHistory, ["tabs", "webNavigation", "history", "declarativeNetRequestFeedback", "topSites", "webRequest"]),
        (.cookies, ["cookies"]),
        (.clipboardRead, ["clipboardRead"]),
        (.clipboardWrite, ["clipboardWrite"]),
        (.blockContent, ["declarativeNetRequest", "declarativeNetRequestWithHostAccess"]),
        (.nativeApps, ["nativeMessaging"]),
        (.notifications, ["notifications"]),
        (.downloads, ["downloads"]),
        (.bookmarks, ["bookmarks"]),
        (.location, ["geolocation"]),
    ]

    /// `permissions`: names of the permissions (“tabs”); `hosts`: host of each address pattern, nil for a pattern that
    /// targets all websites (`<all_urls>`, `*://*/*`); `readsLocalFiles`: a pattern covers `file:` addresses.
    static func lines(permissions: Set<String>, hosts: [String?], readsLocalFiles: Bool = false) -> [Line] {
        var lines = permissionLines.filter { !$0.1.isDisjoint(with: permissions) }.map(\.0)
        if hosts.contains(where: { $0 == nil || $0 == "*" }) {
            lines.append(.allWebsites)
        } else {
            // A `file:` pattern has no host: never an empty website.
            let names = Set(hosts.compactMap(\.self).filter { !$0.isEmpty }.map(displayHost)).sorted()
            if !names.isEmpty {
                lines.append(.websites(names))
            }
        }
        if readsLocalFiles {
            lines.append(.localFiles)
        }
        return lines
    }

    /// Displayed host: `*.example.com` becomes “example.com and its subdomains” in the interface; here, without the
    /// asterisk.
    static func displayHost(_ host: String) -> String {
        host.hasPrefix("*.") ? String(host.dropFirst(2)) : host
    }
}
