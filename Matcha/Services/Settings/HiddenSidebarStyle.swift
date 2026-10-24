import Foundation

/// What the sidebar leaves when it is hidden (⌃⌘S): nothing, as in Arc (it reappears over the page when hovering the
/// left edge), or a narrow column of the tabs' icons, like Chrome's collapsed vertical tabs. Pure type; not synced (the
/// synced settings are those of `SYNC.md`).
nonisolated enum HiddenSidebarStyle: String, CaseIterable, Identifiable, Sendable {
    case hidden
    case icons

    var id: Self {
        self
    }

    var title: LocalizedStringResource {
        switch self {
        case .hidden: "Hide It Completely"
        case .icons: "Show Tab Icons"
        }
    }
}
