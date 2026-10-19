import Foundation
import SwiftData

/// Saved folder of pinned tabs. Its order is sorted together with that of the tabs in the same container.
@Model
final class FolderRecord {
    var id = UUID()
    var name = ""
    var order = 0
    var isCollapsed = false
    /// Chosen icon (`SidebarIcon.storedValue`): “symbol:<SF Symbol name>” or “emoji:<emoji>”; nil: the default
    /// icon.
    var iconValue: String?
    /// Colors of the row's name and background, “#RRGGBB” (sRGB); nil: the system's.
    var textColorHex: String?
    var backgroundColorHex: String?
    var space: SpaceRecord?
    /// Parent folder; nil at the root of the pinned tabs.
    var parent: FolderRecord?
    @Relationship(deleteRule: .cascade, inverse: \FolderRecord.parent) var children: [FolderRecord]? = []
    @Relationship(deleteRule: .nullify, inverse: \TabRecord.folder) var tabs: [TabRecord]? = []

    init(id: UUID = UUID(), name: String, order: Int = 0, isCollapsed: Bool = false) {
        self.id = id
        self.name = name
        self.order = order
        self.isCollapsed = isCollapsed
    }

    /// Appearance read from the saved fields (unreadable: default values); writing it replaces them.
    var appearance: FolderAppearance {
        get { FolderAppearance(storedIcon: iconValue, textColorHex: textColorHex, backgroundColorHex: backgroundColorHex) }
        set {
            iconValue = newValue.storedIcon
            textColorHex = newValue.storedTextColor
            backgroundColorHex = newValue.storedBackgroundColor
        }
    }
}
