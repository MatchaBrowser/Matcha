import Foundation

/// Notes in the command bar (task 12.7): those of the profile of the Space shown whose title or text contains the typed
/// text, opened in a tab. Nothing in a private window.
@MainActor
final class NotesProvider: CommandProvider {
    /// Notes given to the ranking, the most recently changed first.
    static let fetchLimit = 50

    private let windowModel: WindowModel

    init(windowModel: WindowModel) {
        self.windowModel = windowModel
    }

    var answersAtOnce: Bool {
        true
    }

    func candidates(for query: CommandQuery, context: CommandContext) async -> [CommandCandidate] {
        let store = windowModel.session.notes
        guard !context.isPrivate, store.isPersistent else {
            return []
        }
        let profileID = windowModel.space.record.profile?.id
        guard let matches = store.search(query.trimmed, profileID: profileID), !matches.isEmpty else {
            return []
        }
        return store.notes(ofProfile: profileID)
            .filter { matches.contains($0.id) }
            .prefix(Self.fetchLimit)
            .compactMap { note in
                let untitled = String(localized: "Untitled", comment: "Placeholder of a note's empty title")
                return NoteTab.url(for: note.id).map { url in
                    CommandCandidate(
                        // The text was found in the title or the note's text: the ranking sees it among the keywords.
                        kind: .note(modifiedAt: note.modifiedAt, keywords: [query.trimmed]),
                        title: note.title.isEmpty ? untitled : note.title,
                        url: url,
                    )
                }
            }
    }
}
