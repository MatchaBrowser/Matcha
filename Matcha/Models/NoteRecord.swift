import Foundation
import SwiftData

/// Saved note (task 12.1): standalone, in a folder of the library, or linked to a page (`SYNC.md` § 2.10). Notes belong
/// to a profile, like favorites; a private window has none.
@Model
final class NoteRecord {
    var id = UUID()
    /// Title written by the user; empty: the interface shows a default one.
    var title = ""
    /// Document: OpenBlock's blocks as a JSON array, as the editor writes it. Opaque to the app, which reads it with a
    /// cap (`NoteStore.maximumContentBytes`).
    var content = "[]"
    /// Text of the document, for search, taken from `content` (`NotePlainText`).
    var plainText = ""
    /// Size of `content` in UTF-8 bytes: the lists know a note too large to travel without reading it (task 12.8).
    var contentSize = 2
    var createdAt = Date.now
    /// Last change of the title, the document or the link.
    var modifiedAt = Date.now
    /// Profile the note belongs to.
    var profileID: UUID?
    /// Folder of the library; nil at its root. A linked note shows under “Page Notes” whatever its folder.
    var folder: NoteFolderRecord?
    /// Linked page (`NoteLink`): the address the note was written on, the key that finds it again, the scope (`page`,
    /// `site`) and the page's title then. All nil for a standalone note.
    var linkURL: String?
    var linkKey: String?
    var linkScopeValue: String?
    var linkTitle: String?

    init(
        id: UUID = UUID(),
        title: String = "",
        content: String = "[]",
        profileID: UUID?,
        link: NoteLink? = nil,
        date: Date = .now,
    ) {
        self.id = id
        self.title = title
        self.content = content
        contentSize = content.utf8.count
        self.profileID = profileID
        createdAt = date
        modifiedAt = date
        self.link = link
    }

    /// Link read from the saved fields (unreadable: nil); writing it replaces them.
    var link: NoteLink? {
        get { NoteLink(storedURL: linkURL, key: linkKey, scope: linkScopeValue, title: linkTitle) }
        set {
            linkURL = newValue?.url.absoluteString
            linkKey = newValue?.key
            linkScopeValue = newValue?.scope.rawValue
            linkTitle = newValue?.title
        }
    }
}
