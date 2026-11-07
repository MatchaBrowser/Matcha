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
            isDeleted(space.profileId) ? .deleted : .none
        case let .sitePermission(permission):
            isDeleted(permission.profileId) ? .deleted : .none
        case .folder, .tab:
            sidebarParentAdjustment(of: fields)
        case .noteFolder, .note:
            noteParentAdjustment(of: fields)
        case .profile, .webExtension, .setting, .siteZoom, .deviceTabs:
            .none
        }
    }

    /// A folder or a pinned tab: deleted with its Space (or a favorite with its profile), at the root of its Space when
    /// its folder is deleted.
    private func sidebarParentAdjustment(of fields: SyncFields) -> ParentAdjustment {
        switch fields {
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
        default:
            return .none
        }
    }

    /// A note or a folder of notes: deleted with its profile, at the root when its folder is deleted.
    private func noteParentAdjustment(of fields: SyncFields) -> ParentAdjustment {
        switch fields {
        case var .noteFolder(folder):
            if isDeleted(folder.profileId) {
                return .deleted
            }
            guard let parent = folder.parentId, isDeleted(parent) else {
                return .none
            }
            folder.parentId = nil
            return .reparented(.noteFolder(folder), restoredKeys: ["parentId": .string(parent.uuidString)])
        case var .note(note):
            if isDeleted(note.profileId) {
                return .deleted
            }
            guard let folder = note.folderId, isDeleted(folder) else {
                return .none
            }
            note.folderId = nil
            return .reparented(.note(note), restoredKeys: ["folderId": .string(folder.uuidString)])
        default:
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
