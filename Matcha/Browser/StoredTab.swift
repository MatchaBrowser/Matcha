import Foundation

/// What is saved of a tab (apart from its place in the sidebar, described by `SidebarPosition`).
nonisolated struct StoredTab: Hashable, Sendable {
    var id: UUID
    var url: URL?
    var title: String?
    var pinnedURL: URL?
    var pinnedTitle: String?
    var lastActivity: Date
    /// WebKit navigation state (back/forward history, scrolling), opaque.
    var interactionState: Data?
    /// What its local file may read (`BrowserTab.fileReadAccess`, review WB11).
    var fileReadAccess: URL?
}

nonisolated extension StoredTab {
    /// Schemes a restored tab loads again (review WB12): websites, local files and extension pages, plus `about:blank`
    /// and the schemes the app serves itself (`servedSchemes`: the source viewer).
    static let restorableSchemes: Set<String> = ["http", "https", "file", ExtensionManager.scheme]

    /// `url` if a restored tab may load it again; nil for any other address (`data:`, `blob:`, `javascript:`, another
    /// app's scheme): whatever saved it (an older version, a damaged database), a relaunch never runs it.
    static func restorable(_ url: URL?, servedSchemes: Set<String> = []) -> URL? {
        guard let url, let scheme = url.scheme?.lowercased() else {
            return nil
        }
        // `about:blank`, with a fragment that WebKit may give encoded (`about:blank%23b`).
        let isBlank = url.absoluteString.lowercased().hasPrefix("about:blank")
        return restorableSchemes.contains(scheme) || servedSchemes.contains(scheme) || isBlank ? url : nil
    }
}
