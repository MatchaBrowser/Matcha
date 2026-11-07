import Foundation

/// What the sidebar of the notes library shows (task 12.4). Pure type.
nonisolated enum NotesLibrarySection: Hashable, Sendable {
    /// Every note of the profile.
    case all
    /// The notes linked to a page or a site, whatever their folder.
    case pageNotes
    /// The linked notes of one site.
    case site(String)
    /// The standalone notes of a folder.
    case folder(UUID)

    /// Site under which a linked note is listed: the site of a site note, the site of a page note's address.
    static func site(of link: NoteLink) -> String {
        switch link.scope {
        case .site: link.key
        case .page: SiteDomain.site(of: link.url) ?? link.key
        }
    }

    /// Notes of this section, in the order given (the most recent first).
    func notes(in notes: [NoteSummary]) -> [NoteSummary] {
        switch self {
        case .all: notes
        case .pageNotes: notes.filter { $0.link != nil }
        case let .site(site): notes.filter { $0.link.map(Self.site(of:)) == site }
        case let .folder(id): notes.filter { $0.link == nil && $0.folderID == id }
        }
    }

    /// Sites of the linked notes, sorted.
    static func sites(in notes: [NoteSummary]) -> [String] {
        Set(notes.compactMap { $0.link.map(site(of:)) }).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
}
