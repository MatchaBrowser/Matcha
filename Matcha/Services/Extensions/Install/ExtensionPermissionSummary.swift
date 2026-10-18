import Foundation

/// Ce qu'une extension pourra faire, en phrases pour l'écran d'installation (tâche 6.4) : comme les avertissements de
/// Chrome, seules les permissions sensibles sont nommées (« storage », « alarms »… ne disent rien à l'utilisateur), une
/// fois chacune, dans un ordre fixe ; les sites en dernier. Type pur.
nonisolated enum ExtensionPermissionSummary {
    enum Line: Equatable {
        case allWebsites
        /// Hôtes des sites, sans doublon, dans l'ordre alphabétique.
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
    }

    /// Permissions sensibles, dans l'ordre affiché.
    private static let permissionLines: [(Line, Set<String>)] = [
        (.browsingHistory, ["tabs", "webNavigation", "history", "declarativeNetRequestFeedback", "topSites"]),
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

    /// `permissions` : noms des permissions (« tabs ») ; `hosts` : hôte de chaque motif d'adresses, nil pour un motif qui
    /// vise tous les sites (`<all_urls>`, `*://*/*`).
    static func lines(permissions: Set<String>, hosts: [String?]) -> [Line] {
        var lines = permissionLines.filter { !$0.1.isDisjoint(with: permissions) }.map(\.0)
        if hosts.contains(where: { $0 == nil || $0 == "*" }) {
            lines.append(.allWebsites)
        } else {
            let names = Set(hosts.compactMap(\.self).map(displayHost)).sorted()
            if !names.isEmpty {
                lines.append(.websites(names))
            }
        }
        return lines
    }

    /// Hôte affiché : `*.example.com` devient « example.com et ses sous-domaines » côté interface ; ici, sans l'étoile.
    static func displayHost(_ host: String) -> String {
        host.hasPrefix("*.") ? String(host.dropFirst(2)) : host
    }
}
