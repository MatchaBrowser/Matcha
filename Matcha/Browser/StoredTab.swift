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
}
