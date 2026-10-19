import Foundation
import SwiftData

/// Saved Space: its pinned and today tabs, its folders, its theme.
@Model
final class SpaceRecord {
    var id = UUID()
    var name = ""
    /// The Space's icon (`SidebarIcon.spaceSymbol`): an SF Symbol name, or “emoji:<emoji>”.
    var symbol = "circle.fill"
    /// Encoded theme (`SpaceTheme`, task 3.4); nil for the default theme.
    var themeData: Data?
    var order = 0
    var profile: ProfileRecord?
    @Relationship(deleteRule: .cascade, inverse: \TabRecord.space) var tabs: [TabRecord]? = []
    @Relationship(deleteRule: .cascade, inverse: \FolderRecord.space) var folders: [FolderRecord]? = []

    init(id: UUID = UUID(), name: String, symbol: String = "circle.fill", order: Int = 0, profile: ProfileRecord? = nil) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.order = order
        self.profile = profile
    }

    /// Icon read from `symbol` (unreadable: the circle); writing it replaces it.
    var icon: SidebarIcon {
        get { SidebarIcon(spaceSymbol: symbol) }
        set { symbol = newValue.spaceSymbol }
    }
}
