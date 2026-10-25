import Foundation

/// Type of a synced record (task 7.4, `SYNC.md` § 2.1), in the application order of a received batch (§ 2.3):
/// profiles, Spaces, folders, tabs, extensions, settings, site decisions, zooms, tabs of the other Macs. Pure type.
nonisolated enum SyncRecordType: String, CaseIterable, Codable, Sendable {
    case profile
    case space
    case folder
    case tab
    case webExtension = "extension"
    case setting
    case sitePermission
    case siteZoom
    case deviceTabs

    /// Version of the field format of this type, written in each content (`schema`).
    var schema: Int {
        1
    }

    /// The fields this version of Matcha knows for this type (`SYNC.md` § 2.1): without a baseline, they all replace
    /// the received ones, absent ones included, and the others are kept (review SY1). Checked against the field types
    /// by `SyncFieldMergeTests`.
    var fieldKeys: Set<String> {
        switch self {
        case .profile: ["name", "order"]
        case .space: ["name", "symbol", "theme", "order", "profileId"]
        case .folder: ["name", "order", "isCollapsed", "spaceId", "parentId", "icon", "textColor", "backgroundColor"]
        case .tab: ["place", "url", "title", "order", "profileId", "spaceId", "folderId"]
        case .webExtension: Self.extensionFieldKeys
        case .setting: ["key", "value"]
        case .sitePermission: ["origin", "kind", "decision", "profileId"]
        case .siteZoom: ["site", "level"]
        case .deviceTabs: ["deviceId", "name", "spaces"]
        }
    }

    private static let extensionFieldKeys: Set<String> = [
        "identifier", "name", "version", "source", "isEnabled", "allowsPrivateWindows", "showsButton", "grantedPermissions",
        "deniedPermissions", "grantedMatchPatterns", "deniedMatchPatterns",
    ]

    /// Rank in the application order: a parent comes before what it contains.
    var applyRank: Int {
        Self.allCases.firstIndex(of: self) ?? Self.allCases.count
    }
}
