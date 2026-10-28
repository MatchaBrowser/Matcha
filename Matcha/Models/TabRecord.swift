import Foundation
import SwiftData

/// Saved tab. A favorite belongs to the profile; a pinned tab or a today tab, to the Space.
@Model
final class TabRecord {
    var id = UUID()
    var url: URL?
    var title: String?
    /// Placement, as text: `favorite`, `pinned`, `today`, or `archived` (archived tab; archiving postponed, see
    /// `FEATURES.md`).
    var placeValue = TabPlace.today.rawValue
    /// Rank in its container (favorites, root of the pinned tabs, folder, today tabs).
    var order = 0
    var lastActivity = Date.now
    /// Original address and title of a pinned tab or a favorite.
    var pinnedURL: URL?
    var pinnedTitle: String?
    /// Name the user gave a pinned tab or a favorite, shown in place of the page's title; nil: the page's title.
    var customTitle: String?
    /// WebKit navigation state (back/forward history), for restoration.
    @Attribute(.externalStorage) var interactionState: Data?
    /// What its local file may read (`BrowserTab.fileReadAccess`, review WB11); kept on this Mac only.
    var fileReadAccess: URL?
    /// Split view (task 4.3) the tab is part of; nil outside a split. Never for a favorite.
    var splitGroupID: UUID?
    /// Width share of its pane in the split; 0: unknown (equal shares).
    var splitFraction = 0.0
    var space: SpaceRecord?
    var profile: ProfileRecord?
    var folder: FolderRecord?

    init(id: UUID = UUID(), url: URL? = nil, title: String? = nil, place: TabPlace = .today, order: Int = 0) {
        self.id = id
        self.url = url
        self.title = title
        placeValue = place.rawValue
        self.order = order
    }

    /// Placement in the sidebar; nil for an archived tab.
    var place: TabPlace? {
        get { TabPlace(rawValue: placeValue) }
        set { placeValue = newValue?.rawValue ?? "archived" }
    }
}
