import Foundation

/// Ranking of the command bar rows, pure and lexicographic (see `DECISIONS.md`,
/// “Classement pur et lexicographique”):
/// 1. the rows of the typed text (`CommandPrimaryRows`), always on top;
/// 2. tabs, actions and history matching the text, by match tier, kind, activity or frecency, title then
///    identifier; capped per kind and in total;
/// 3. the engine's suggestions, in its order, only for a search.
nonisolated struct CommandRanker: Sendable {
    /// Number of rows kept.
    struct Limits: Equatable, Sendable {
        var tabs = 4
        var history = 4
        var actions = 2
        /// Tabs, history and actions together.
        var local = 6
        var suggestions = 4
    }

    var limits = Limits()

    /// Rows for the text of `query`; none for an empty text. The result does not depend on the order of
    /// `candidates`, except that of the suggestions (the engine's order) and the choice of the first copy of the
    /// same tab (the source lists the displayed Space first).
    func rank(_ query: CommandQuery, candidates: [CommandCandidate], now: Date) -> [CommandRow] {
        guard !query.isEmpty else {
            return []
        }
        let primary = CommandPrimaryRows.make(for: query)
        let primaryKey = primary.first.flatMap { $0.style == .openAddress ? $0.url.map(CommandText.urlKey) : nil }
        let matches = Self.uniqueLocal(candidates).compactMap { candidate in
            Self.match(candidate, query).map { (candidate: candidate, match: $0) }
        }
        let local = localRows(matches, excludingKey: primaryKey, now: now)
        let suggestions = query.isSearch ? suggestionRows(for: query, candidates: candidates) : []
        return primary + local + suggestions
    }

    /// ⌘L rows before any modification: the current address, then “Copy URL” if it is part of `actions`. No source
    /// is queried.
    func pristineRows(currentURL: URL, actions: [CommandCandidate]) -> [CommandRow] {
        let copy = actions.first { $0.actionID == .copyURL }.flatMap(Self.row(for:))
        return [CommandPrimaryRows.current(currentURL), copy].compactMap(\.self)
    }

    /// Suggestions received for a previous text that still extend `query`, in their order: they stay displayed
    /// until the new ones arrive.
    static func carriedOver(_ suggestions: [CommandCandidate], to query: CommandQuery) -> [CommandCandidate] {
        suggestions.filter { CommandText.fold($0.title).hasPrefix(query.folded) }
    }

    // MARK: Matching

    /// Tabs (a single copy per identifier, the first), actions and history with an address.
    private static func uniqueLocal(_ candidates: [CommandCandidate]) -> [CommandCandidate] {
        var seen: Set<String> = []
        return candidates.filter { candidate in
            switch candidate.kind {
            case .suggestion: false
            case .history: candidate.url != nil
            case .tab, .action: seen.insert(candidate.id).inserted
            }
        }
    }

    /// Tabs and history on their title and address; actions on their title and keywords, from two characters on and
    /// never loosely (word start at least).
    private static func match(_ candidate: CommandCandidate, _ query: CommandQuery) -> CommandMatch? {
        switch candidate.kind {
        case .tab, .history:
            CommandMatcher.match(query, titles: [candidate.title], url: candidate.url)
        case let .action(_, keywords) where query.folded.count >= 2:
            CommandMatcher.match(query, titles: [candidate.title] + keywords, url: nil, minimumTier: .wordPrefix)
        case .action, .suggestion:
            nil
        }
    }
}

private nonisolated extension CommandCandidate {
    var actionID: CommandActionID? {
        if case let .action(action, _) = kind {
            return action
        }
        return nil
    }
}
