import Foundation

/// Message of the notes editor's bridge (`NoteEditorScript`), read with caps (TR2): anything else is refused. Pure
/// type.
nonisolated enum NoteEditorMessage: Equatable, Sendable {
    /// The page can take a note.
    case ready
    /// The document of the note given with `token`, as the editor writes it.
    case change(token: String, content: String)
    /// The note given with `token` has blocks this editor doesn't know: it is shown read-only.
    case unreadable(token: String)
    /// The document of the note given with `token` is larger than the store takes: it isn't saved.
    case tooLarge(token: String)

    static let maximumTokenLength = 64

    init?(body: Any?, maximumContentBytes: Int = NoteStore.maximumContentBytes) {
        guard let body = body as? [String: Any], let type = body["type"] as? String else {
            return nil
        }
        if type == "ready" {
            self = .ready
            return
        }
        guard let token = body["token"] as? String, !token.isEmpty, token.utf8.count <= Self.maximumTokenLength else {
            return nil
        }
        switch type {
        case "change":
            guard let content = body["content"] as? String else {
                return nil
            }
            self = content.utf8.count <= maximumContentBytes ? .change(token: token, content: content) : .tooLarge(token: token)
        case "unreadable":
            self = .unreadable(token: token)
        default:
            return nil
        }
    }
}

/// What the app gives the page for a note (`NoteEditorScript.loadBody`), as JSON text.
nonisolated struct NoteEditorPayload: Encodable, Sendable {
    let token: String
    /// Document of the note, as saved (`NoteRecord.content`).
    let content: String
    let editable: Bool
    /// Texts of the menus (`NoteEditorTexts`).
    let texts: [String: String]

    var json: String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .withoutEscapingSlashes
        return (try? encoder.encode(self)).flatMap { String(data: $0, encoding: .utf8) }
    }
}
