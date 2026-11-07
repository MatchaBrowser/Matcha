import Foundation

/// The text of a note is never lost in a conflict (task 12.8, `SYNC.md` § 2.10): when the rule of § 2.3 would drop a
/// change of the title or the document, the losing version becomes a copy, a new note. Pure type.
nonisolated enum SyncNoteConflict {
    /// How the winning version replaces the losing one.
    enum Resolution: Sendable {
        /// The winner replaces every field (the server's version wins).
        case replaced
        /// The winner keeps the loser's changes on the fields it didn't change itself (this Mac wins, merged field by
        /// field, `SyncFieldMerge`).
        case merged
        /// The winner is a deletion.
        case deleted
    }

    static let textKeys = ["title", "content"]

    /// Fields of the copy that keeps the loser's title and document, if `resolution` would lose a change of them made
    /// since `baseline` (the last content this Mac accepted); nil otherwise, or if the loser isn't a readable note.
    static func copy(
        of loser: SyncJSON?,
        winner: SyncJSON?,
        baseline: SyncJSON?,
        resolution: Resolution,
        now: Date,
    ) -> SyncNoteFields? {
        guard let loser, case let .note(fields)? = SyncFields(json: loser, type: .note) else {
            return nil
        }
        let mine = loser.objectValue
        let before = baseline?.objectValue ?? [:]
        let theirs = winner?.objectValue ?? [:]
        let isLost = textKeys.contains { key in
            let isChanged = mine[key] != before[key]
            return switch resolution {
            case .deleted: isChanged
            case .replaced: isChanged && mine[key] != theirs[key]
            case .merged: isChanged && theirs[key] != before[key] && theirs[key] != mine[key]
            }
        }
        guard isLost else {
            return nil
        }
        var copy = fields
        let title = fields.title.isEmpty ? String(localized: "Untitled", comment: "Placeholder of a note's empty title") : fields.title
        copy.title = String(
            localized: "\(title) (conflict)",
            comment: "Title of the copy of a note kept after a sync conflict; %@ is the note's title",
        )
        copy.createdAt = SyncCoding.rounded(now)
        copy.updatedAt = SyncCoding.rounded(now)
        return copy
    }
}
