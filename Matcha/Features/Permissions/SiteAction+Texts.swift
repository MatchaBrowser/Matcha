import AppKit

/// Texts and icons of what websites may do without asking (Settings > Privacy, site settings).
extension SiteAction {
    /// “Opens Zoom” (the app of this Mac for this kind of link, otherwise its scheme), “Downloads files”.
    var title: String {
        switch self {
        case let .openApp(scheme):
            let app = URL(string: "\(scheme):")
                .flatMap(NSWorkspace.shared.urlForApplication(toOpen:))
                .map { FileManager.default.displayName(atPath: $0.path) } ?? "\(scheme):"
            return String(localized: "Opens \(app)", comment: "A website may open this app without asking; %@ is the app")
        case .downloadFiles:
            return String(localized: "Downloads files", comment: "A website may download files without asking")
        }
    }

    var symbolName: String {
        switch self {
        case .openApp:
            "arrow.up.forward.app"
        case .downloadFiles:
            "arrow.down.circle"
        }
    }
}
