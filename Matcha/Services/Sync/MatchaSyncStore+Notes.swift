import Foundation

/// Notes and their folders as sync sees them (task 12.8, `SYNC.md` § 2.10). A note whose fields are too large for the
/// server, or without a profile, stays on this Mac: absent from the snapshot, and its absence isn't a deletion.
extension MatchaSyncStore {
    func addNotes(to result: inout [UUID: SyncFields]) throws {
        for folder in try fetch(NoteFolderRecord.self) {
            if let profileID = folder.profileID {
                result[folder.id] = .noteFolder(SyncNoteFolderFields(
                    name: folder.name,
                    order: Double(folder.order),
                    profileId: profileID,
                    parentId: folder.parent?.id,
                ))
            }
        }
        for note in try fetch(NoteRecord.self) {
            if let fields = Self.travelingFields(of: note) {
                result[note.id] = .note(fields)
            }
        }
    }

    /// Notes that stay on this Mac.
    func localNotes() throws -> Set<UUID> {
        var local = try Set(fetch(NoteRecord.self).filter { Self.travelingFields(of: $0) == nil }.map(\.id))
        try local.formUnion(fetch(NoteFolderRecord.self).filter { $0.profileID == nil }.map(\.id))
        return local
    }

    /// Fields of `note` if it travels: it has a profile, and its fields fit (`NoteSyncLimit`).
    static func travelingFields(of note: NoteRecord) -> SyncNoteFields? {
        guard let profileID = note.profileID, note.content.utf8.count <= NoteSyncLimit.maximumFieldsBytes else {
            return nil
        }
        let fields = SyncNoteFields(
            title: note.title,
            content: note.content,
            profileId: profileID,
            folderId: note.folder?.id,
            link: note.link,
            createdAt: note.createdAt,
            updatedAt: note.modifiedAt,
        )
        guard let size = try? SyncCoding.encoder().encode(fields).count, size <= NoteSyncLimit.maximumFieldsBytes else {
            return nil
        }
        return fields
    }
}
