import Foundation

/// Tab of a Space of the window, designated by identifiers: the bar keeps no live object.
nonisolated struct TabReference: Hashable, Sendable {
    let tabID: UUID
    let spaceID: UUID
}

/// Actions offered by the command bar, in their display order when tied.
nonisolated enum CommandActionID: String, CaseIterable, Sendable {
    case newSpace
    case copyURL
    case settings
    /// Translates the page in front (task 9.3), or shows its original.
    case translatePage
    case showOriginal
    /// A new standalone note, in a tab (task 12.7).
    case newNote
    /// The notes panel, on the note of the page shown.
    case pageNote
    /// The notes library window.
    case showAllNotes
}

/// Raw result provided by a bar source, before matching and ranking.
nonisolated struct CommandCandidate: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        /// Open tab; `spaceName` is nil for the displayed Space.
        case tab(TabReference, place: TabPlace, spaceName: String?, lastActivity: Date)
        /// Today tab of another Mac of the account (`SYNC.md` § 2.4); `modifiedAt`: when that Mac last wrote its tabs.
        case otherMacTab(deviceID: UUID, deviceName: String, modifiedAt: Date)
        /// History address, all visits grouped.
        case history(visitCount: Int, lastVisit: Date)
        /// Note of the profile (task 12.7), opened in a tab; `keywords`: the text found in its title or its text.
        case note(modifiedAt: Date, keywords: [String])
        /// `keywords`: words searched in addition to the title, never displayed.
        case action(CommandActionID, keywords: [String])
        /// Search engine suggestion; the title is the text to search.
        case suggestion
    }

    let kind: Kind
    let title: String
    /// Nil for actions and suggestions.
    let url: URL?
    /// Stable identifier, reused by the displayed row: `tab:<uuid>`, `otherMac:<uuid>:<address key>` (one per address
    /// and Mac), `history:<address key>`, `note:<address>`, `action:<name>`, `suggestion:<folded text>`.
    let id: String
    /// Folded title (and keywords of an action) and address, compared with the text: made once, when the source gives
    /// the candidate, not at each ranking of the same keystroke (review IU2); nil for a suggestion.
    let fields: CommandMatchFields?

    init(kind: Kind, title: String, url: URL?) {
        self.kind = kind
        self.title = title
        self.url = url
        let urlKey = url.map(CommandText.urlKey)
        id = switch kind {
        case let .tab(reference, _, _, _): "tab:\(reference.tabID.uuidString)"
        case let .otherMacTab(deviceID, _, _): "otherMac:\(deviceID.uuidString):\(urlKey ?? "")"
        case .history: "history:\(urlKey ?? "")"
        case .note: "note:\(url?.absoluteString ?? title)"
        case let .action(action, _): "action:\(action.rawValue)"
        case .suggestion: "suggestion:\(CommandText.fold(title))"
        }
        fields = switch kind {
        case .tab, .otherMacTab, .history: CommandMatchFields(titles: [title], url: url)
        case let .action(_, keywords), let .note(_, keywords): CommandMatchFields(titles: [title] + keywords, url: nil)
        case .suggestion: nil
        }
    }
}
