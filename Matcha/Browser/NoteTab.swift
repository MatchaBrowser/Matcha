import Foundation

/// Address of a note shown in a tab (task 12.5): `matcha-note://note/<id>`. Such a tab never makes a web view: its card
/// shows the note's editor, and it can be pinned, put in a folder or a split like any tab. Never served by
/// `NoteEditorSchemeHandler` (another host than the editor's page). Pure type.
nonisolated enum NoteTab {
    static let host = "note"

    static func url(for id: UUID) -> URL? {
        URL(string: "\(NoteEditorResources.scheme)://\(host)/\(id.uuidString.lowercased())")
    }

    /// Note shown at `url`; nil for any other address.
    static func noteID(in url: URL?) -> UUID? {
        guard let url, url.scheme?.lowercased() == NoteEditorResources.scheme, url.host()?.lowercased() == host,
              url.pathComponents.count == 2
        else {
            return nil
        }
        return UUID(uuidString: url.lastPathComponent)
    }
}
