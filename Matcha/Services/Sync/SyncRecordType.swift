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

    /// Rank in the application order: a parent comes before what it contains.
    var applyRank: Int {
        Self.allCases.firstIndex(of: self) ?? Self.allCases.count
    }
}
