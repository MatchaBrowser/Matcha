import Foundation
import OSLog
import SwiftData

/// Folders of the notes library (task 12.1): one tree per profile, ranked among their siblings.
extension NoteStore {
    /// Folders of the profile under `parentID` (nil: the root), by rank, then by identifier (two Macs can give the same
    /// rank, `SYNC.md` § 2.7).
    func folders(ofProfile profileID: UUID?, parentID: UUID?) -> [NoteFolder] {
        folders
            .filter { $0.profileID == profileID && $0.parentID == parentID }
            .sorted { ($0.order, $0.id.uuidString) < ($1.order, $1.id.uuidString) }
    }

    /// Makes a folder after the others of its parent; nil in a private window, or if the parent doesn't belong to the
    /// profile.
    @discardableResult
    func createFolder(named name: String, parentID: UUID? = nil, profileID: UUID?) -> NoteFolder? {
        guard let context else {
            return nil
        }
        let parent = parentID.flatMap(folderRecord)
        guard parentID == nil || parent?.profileID == profileID else {
            return nil
        }
        let order = (folders(ofProfile: profileID, parentID: parentID).map(\.order).max() ?? -1) + 1
        let record = NoteFolderRecord(name: Self.cleanName(name), order: order, profileID: profileID)
        record.parent = parent
        context.insert(record)
        save(context)
        remember(record)
        return Self.folder(record)
    }

    /// Renames the folder; an empty name keeps the old one.
    func renameFolder(_ id: UUID, to name: String) {
        let name = Self.cleanName(name)
        guard let context, !name.isEmpty, let record = folderRecord(id), record.name != name else {
            return
        }
        record.name = name
        save(context)
        remember(record)
    }

    /// Puts the folder in another folder of its profile, or at the root (nil), after the folders already there. Refused
    /// (false) for a folder of another profile, or one inside the folder itself.
    @discardableResult
    func moveFolder(_ id: UUID, toParent parentID: UUID?) -> Bool {
        guard let context, let record = folderRecord(id) else {
            return false
        }
        let parent = parentID.flatMap(folderRecord)
        guard parentID == nil || parent?.profileID == record.profileID,
              !ancestors(of: parentID).contains(id)
        else {
            return false
        }
        guard record.parent?.id != parentID else {
            return true
        }
        record.order = (folders(ofProfile: record.profileID, parentID: parentID).map(\.order).max() ?? -1) + 1
        record.parent = parent
        save(context)
        remember(record)
        return true
    }

    /// Deletes the folder, its subfolders and all their notes.
    func deleteFolder(_ id: UUID) {
        guard let context, let record = folderRecord(id) else {
            return
        }
        context.delete(record)
        save(context)
        reload()
        Logger.notes.info("Note folder deleted")
    }

    func folderRecord(_ id: UUID) -> NoteFolderRecord? {
        guard let context else {
            return nil
        }
        var descriptor = FetchDescriptor<NoteFolderRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    /// `id` and the folders above it, up to the root; stops on a cycle (received from sync).
    private func ancestors(of id: UUID?) -> Set<UUID> {
        let parents = Dictionary(
            folders.compactMap { folder in folder.parentID.map { (folder.id, $0) } },
            uniquingKeysWith: { first, _ in first },
        )
        var result: Set<UUID> = []
        var current = id
        while let folder = current, result.insert(folder).inserted {
            current = parents[folder]
        }
        return result
    }

    private static func cleanName(_ name: String) -> String {
        String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maximumTitleLength))
    }
}
