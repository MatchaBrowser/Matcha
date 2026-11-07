import Foundation

// Fields of the notes and their folders (task 12.8, `SYNC.md` § 2.1 and § 2.10), read leniently (§ 2.9): an unreadable
// field takes its default value, except the profile and the document, without which the record is ignored.

/// Fields of a folder of the notes library.
nonisolated struct SyncNoteFolderFields: Codable, Equatable, Sendable {
    var name: String
    var order: Double
    var profileId: UUID
    var parentId: UUID?

    init(name: String, order: Double, profileId: UUID, parentId: UUID?) {
        self.name = name
        self.order = order
        self.profileId = profileId
        self.parentId = parentId
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        profileId = try container.required(UUID.self, forKey: .profileId)
        name = container.lenient(String.self, forKey: .name) ?? ""
        order = container.order(forKey: .order)
        parentId = container.lenient(UUID.self, forKey: .parentId)
    }
}

/// Fields of a note: the document as text (`content`, never read by sync), the linked page (`link`), the dates.
nonisolated struct SyncNoteFields: Codable, Equatable, Sendable {
    /// Linked page, as `NoteLink` keeps it: the key is never computed again from the address.
    struct Link: Codable, Equatable, Sendable {
        var url: URL
        var key: String
        var scope: String
        var title: String?

        init(_ link: NoteLink) {
            url = link.url
            key = link.key
            scope = link.scope.rawValue
            title = link.title
        }

        /// The link this Mac can use; nil if a field is unreadable (`NoteLink(storedURL:…)`).
        var noteLink: NoteLink? {
            NoteLink(storedURL: url.absoluteString, key: key, scope: scope, title: title)
        }
    }

    var title: String
    var content: String
    var profileId: UUID
    var folderId: UUID?
    var link: Link?
    var createdAt: Date?
    var updatedAt: Date?

    init(title: String, content: String, profileId: UUID, folderId: UUID?, link: NoteLink?, createdAt: Date?, updatedAt: Date?) {
        self.title = title
        self.content = content
        self.profileId = profileId
        self.folderId = folderId
        self.link = link.map(Link.init)
        self.createdAt = createdAt.map(SyncCoding.rounded)
        self.updatedAt = updatedAt.map(SyncCoding.rounded)
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        profileId = try container.required(UUID.self, forKey: .profileId)
        content = try container.required(String.self, forKey: .content)
        title = container.lenient(String.self, forKey: .title) ?? ""
        folderId = container.lenient(UUID.self, forKey: .folderId)
        // An unreadable link leaves the note standalone on this Mac.
        link = container.lenient(Link.self, forKey: .link).flatMap { $0.noteLink == nil ? nil : $0 }
        createdAt = container.lenient(Date.self, forKey: .createdAt)
        updatedAt = container.lenient(Date.self, forKey: .updatedAt)
    }
}

/// What travels of a note (`SYNC.md` § 2.10).
nonisolated enum NoteSyncLimit {
    /// Largest fields of a note sent, encoded (under the 256 KiB of an encrypted content, `SYNC.md` § 4.1).
    static let maximumFieldsBytes = 200 * 1024
    /// Documents beyond this size are always too large to travel: the warning shows before the exact count.
    static let warningContentBytes = maximumFieldsBytes - 8 * 1024
}
