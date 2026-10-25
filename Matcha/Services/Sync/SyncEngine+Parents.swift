import Foundation

/// A received record whose parent was deleted, by a deletion received or made here (`SYNC.md` § 2.3, review SY32):
/// without a folder, it goes to the root of its Space; without its Space or its profile, it is deleted. This Mac then
/// sends the change, never waiting for a parent that won't come.
extension SyncEngine {
    enum ParentAdjustment {
        case none
        /// Moved to the root; `restoredKeys`: the deleted parent, kept in the reference so the move is sent.
        case reparented(SyncFields, restoredKeys: [String: SyncJSON])
        case deleted
    }

    func parentAdjustment(of fields: SyncFields) -> ParentAdjustment {
        switch fields {
        case let .space(space):
            return isDeleted(space.profileId) ? .deleted : .none
        case let .sitePermission(permission):
            return isDeleted(permission.profileId) ? .deleted : .none
        case var .folder(folder):
            if isDeleted(folder.spaceId) {
                return .deleted
            }
            guard let parent = folder.parentId, isDeleted(parent) else {
                return .none
            }
            folder.parentId = nil
            return .reparented(.folder(folder), restoredKeys: ["parentId": .string(parent.uuidString)])
        case var .tab(tab):
            guard tab.place != .today else {
                return .none
            }
            if isDeleted(tab.place == .favorite ? tab.profileId : tab.spaceId) {
                return .deleted
            }
            guard tab.place == .pinned, let folder = tab.folderId, isDeleted(folder) else {
                return .none
            }
            tab.folderId = nil
            return .reparented(.tab(tab), restoredKeys: ["folderId": .string(folder.uuidString)])
        case .profile, .webExtension, .setting, .siteZoom, .deviceTabs:
            return .none
        }
    }

    /// Deleted here (a deletion waiting to leave) or on the server (a deletion accepted).
    private func isDeleted(_ id: UUID?) -> Bool {
        guard let id else {
            return false
        }
        if let pending = state.pending[id] {
            return pending.content.deleted
        }
        return state.entries[id]?.remote?.deleted == true
    }
}
