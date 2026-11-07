import Foundation

/// A note as the interface lists it, without its document (task 12.1): read from a `NoteRecord`.
nonisolated struct NoteSummary: Identifiable, Hashable, Sendable {
    let id: UUID
    var title: String
    var profileID: UUID?
    /// Folder of the library; nil at its root.
    var folderID: UUID?
    /// Linked page; nil for a standalone note.
    var link: NoteLink?
    var createdAt: Date
    var modifiedAt: Date
    /// Size of the document in UTF-8 bytes.
    var contentSize = 2

    /// Too large to go to the other Macs (`SYNC.md` § 2.10): it stays on this one.
    var isTooLargeToSync: Bool {
        contentSize > NoteSyncLimit.warningContentBytes
    }
}

/// A folder of the notes library (task 12.1): read from a `NoteFolderRecord`.
nonisolated struct NoteFolder: Identifiable, Hashable, Sendable {
    let id: UUID
    var name: String
    var order: Int
    var profileID: UUID?
    /// Parent folder; nil at the root of the library.
    var parentID: UUID?
}

/// What became of a document given to the store.
nonisolated enum NoteSaveResult: Equatable, Sendable {
    case saved
    /// Same document as the saved one: nothing written.
    case unchanged
    /// Larger than `NoteStore.maximumContentBytes`: not saved, the editor keeps it and says so.
    case tooLarge
    /// No such note (deleted meanwhile), or no store (private window).
    case notFound
}
