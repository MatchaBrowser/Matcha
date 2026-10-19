import Foundation
@testable import Matcha
import SwiftData

/// Frozen copy of the folder-related models as they were before their customization (without `iconValue`,
/// `textColorHex`, `backgroundColorHex` on `FolderRecord`), to create an old store in `BrowserSchemaTests`. Same entity
/// names as the app's models (SwiftData names them after the class, without the namespace); the models without
/// relationships, unchanged, are the app's. Do not modify anymore.
enum SchemaBeforeFolderAppearance {
    static let models: [any PersistentModel.Type] = [
        ProfileRecord.self, SpaceRecord.self, FolderRecord.self, TabRecord.self, SitePermissionRecord.self, HistoryRecord.self,
    ]

    @Model
    final class ProfileRecord {
        var id = UUID()
        var name = ""
        var order = 0
        @Relationship(deleteRule: .cascade, inverse: \SpaceRecord.profile) var spaces: [SpaceRecord]? = []
        @Relationship(deleteRule: .cascade, inverse: \TabRecord.profile) var favorites: [TabRecord]? = []

        init(name: String) {
            self.name = name
        }
    }

    @Model
    final class SpaceRecord {
        var id = UUID()
        var name = ""
        var symbol = "circle.fill"
        var themeData: Data?
        var order = 0
        var profile: ProfileRecord?
        @Relationship(deleteRule: .cascade, inverse: \TabRecord.space) var tabs: [TabRecord]? = []
        @Relationship(deleteRule: .cascade, inverse: \FolderRecord.space) var folders: [FolderRecord]? = []

        init(name: String, profile: ProfileRecord?) {
            self.name = name
            self.profile = profile
        }
    }

    @Model
    final class FolderRecord {
        var id = UUID()
        var name = ""
        var order = 0
        var isCollapsed = false
        var space: SpaceRecord?
        var parent: FolderRecord?
        @Relationship(deleteRule: .cascade, inverse: \FolderRecord.parent) var children: [FolderRecord]? = []
        @Relationship(deleteRule: .nullify, inverse: \TabRecord.folder) var tabs: [TabRecord]? = []

        init(name: String, order: Int, isCollapsed: Bool) {
            self.name = name
            self.order = order
            self.isCollapsed = isCollapsed
        }
    }

    @Model
    final class TabRecord {
        var id = UUID()
        var url: URL?
        var title: String?
        var placeValue = "today"
        var order = 0
        var lastActivity = Date.now
        var pinnedURL: URL?
        var pinnedTitle: String?
        @Attribute(.externalStorage) var interactionState: Data?
        var splitGroupID: UUID?
        var splitFraction = 0.0
        var space: SpaceRecord?
        var profile: ProfileRecord?
        var folder: FolderRecord?

        init(url: URL?, title: String?, placeValue: String) {
            self.url = url
            self.title = title
            self.placeValue = placeValue
        }
    }
}
