import Foundation
import SwiftData

/// Saved folder of the notes library (task 12.1). Deleting it deletes its notes and its subfolders. “Page Notes” is not
/// one: it shows the linked notes, whatever their folder.
@Model
final class NoteFolderRecord {
    var id = UUID()
    var name = ""
    /// Rank among the folders of the same parent.
    var order = 0
    /// Profile the folder belongs to, like its notes.
    var profileID: UUID?
    /// Parent folder; nil at the root of the library.
    var parent: NoteFolderRecord?
    @Relationship(deleteRule: .cascade, inverse: \NoteFolderRecord.parent) var children: [NoteFolderRecord]? = []
    @Relationship(deleteRule: .cascade, inverse: \NoteRecord.folder) var notes: [NoteRecord]? = []

    init(id: UUID = UUID(), name: String, order: Int = 0, profileID: UUID?) {
        self.id = id
        self.name = name
        self.order = order
        self.profileID = profileID
    }
}
