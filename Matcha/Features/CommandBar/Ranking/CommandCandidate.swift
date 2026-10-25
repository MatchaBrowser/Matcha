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
    /// and Mac), `history:<address key>`, `action:<name>`, `suggestion:<folded text>`.
    var id: String {
        switch kind {
        case let .tab(reference, _, _, _): "tab:\(reference.tabID.uuidString)"
        case let .otherMacTab(deviceID, _, _): "otherMac:\(deviceID.uuidString):\(url.map(CommandText.urlKey) ?? "")"
        case .history: "history:\(url.map(CommandText.urlKey) ?? "")"
        case let .action(action, _): "action:\(action.rawValue)"
        case .suggestion: "suggestion:\(CommandText.fold(title))"
        }
    }
}
