import Foundation
import SwiftData

/// Notes and their folders received from another Mac (task 12.8, `SYNC.md` § 2.10). A note or a folder waits for its
/// profile and its folder; a folder of another profile is no parent: `profileId` prevails, the note or the folder goes
/// to the root of the library. A deleted folder leaves its notes and subfolders at the root (their own deletions, if
/// any, come with it).
extension SyncRecordWriter {
    /// A note or a folder of notes; false if its profile or its folder is missing.
    func upsertNoteRecord(_ id: UUID, _ fields: SyncFields) -> Bool {
        switch fields {
        case let .noteFolder(folder): upsertNoteFolder(id, folder)
        case let .note(note): upsertNote(id, note)
        default: true
        }
    }

    func upsertNoteFolder(_ id: UUID, _ fields: SyncNoteFolderFields) -> Bool {
        guard profiles[fields.profileId] != nil else {
            return false
        }
        var parent: NoteFolderRecord?
        if let parentID = fields.parentId {
            guard let found = noteFolders[parentID] else {
                return false
            }
            parent = found.profileID == fields.profileId && found.id != id ? found : nil
        }
        let record = noteFolders[id] ?? inserted(NoteFolderRecord(id: id, name: fields.name, profileID: fields.profileId)) {
            noteFolders[id] = $0
        }
        record.name = fields.name
        record.order = Int(fields.order.rounded())
        record.profileID = fields.profileId
        record.parent = parent
        changes.notes = true
        return true
    }

    func upsertNote(_ id: UUID, _ fields: SyncNoteFields) -> Bool {
        guard profiles[fields.profileId] != nil else {
            return false
        }
        var folder: NoteFolderRecord?
        if let folderID = fields.folderId {
            guard let found = noteFolders[folderID] else {
                return false
            }
            folder = found.profileID == fields.profileId ? found : nil
        }
        let record = notes[id] ?? inserted(NoteRecord(id: id, profileID: fields.profileId)) { notes[id] = $0 }
        record.title = String(fields.title.prefix(NoteStore.maximumTitleLength))
        if record.content != fields.content {
            record.content = fields.content
            record.contentSize = fields.content.utf8.count
            record.plainText = NotePlainText.text(of: fields.content) ?? ""
        }
        record.profileID = fields.profileId
        record.folder = folder
        record.link = fields.link?.noteLink
        if let createdAt = fields.createdAt {
            record.createdAt = createdAt
        }
        record.modifiedAt = fields.updatedAt ?? .now
        changes.notes = true
        return true
    }

    func deleteNoteFolder(_ id: UUID) {
        guard let record = noteFolders.removeValue(forKey: id) else {
            return
        }
        // Detached first: the folder's cascade would delete them.
        for child in record.children ?? [] {
            child.parent = nil
        }
        for note in record.notes ?? [] {
            note.folder = nil
        }
        context.delete(record)
        changes.notes = true
    }

    func deleteNote(_ id: UUID) {
        guard let record = notes.removeValue(forKey: id) else {
            return
        }
        context.delete(record)
        changes.notes = true
    }

    /// Cycles of note folders (A in B, B in A) are broken like those of pinned folders: the folder with the greatest
    /// identifier goes back to the root.
    func repairNoteFolderCycles() {
        for folder in noteFolders.values {
            var visited: Set<UUID> = [folder.id]
            var cycle = [folder]
            var parent = folder.parent
            while let current = parent, !visited.contains(current.id) {
                visited.insert(current.id)
                cycle.append(current)
                parent = current.parent
            }
            guard parent?.id == folder.id, let breaker = cycle.max(by: { $0.id.uuidString < $1.id.uuidString }) else {
                continue
            }
            breaker.parent = nil
            changes.notes = true
        }
    }
}
