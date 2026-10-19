import Foundation

/// Local result kept, with what is used to sort it.
private nonisolated struct RankedCandidate {
    enum Group {
        case tab
        case history
        case action
    }

    let candidate: CommandCandidate
    let match: CommandMatch
    let group: Group
    let id: String
    /// Breaks the tie between two history entries with the same key (same identifier).
    let address: String
    let foldedTitle: String
    /// Address key of tabs and history.
    let urlKey: String?
    /// 4: tab of the displayed Space, 3: tab of another Space, 2: action, 1: history.
    let kindPriority: Int
    /// Tab: last activity; history: frecency; action: opposite of its rank.
    let signal: Double
    /// History: last visit; 0 otherwise.
    let secondarySignal: Double

    /// Nil for a suggestion: suggestions are not ranked with the local results.
    init?(_ candidate: CommandCandidate, match: CommandMatch, now: Date) {
        self.candidate = candidate
        self.match = match
        id = candidate.id
        address = candidate.url?.absoluteString ?? ""
        foldedTitle = CommandText.fold(candidate.title)
        urlKey = candidate.url.map(CommandText.urlKey)
        switch candidate.kind {
        case let .tab(_, _, spaceName, lastActivity):
            group = .tab
            kindPriority = spaceName == nil ? 4 : 3
            signal = lastActivity.timeIntervalSinceReferenceDate
            secondarySignal = 0
        case let .history(visitCount, lastVisit):
            group = .history
            kindPriority = 1
            signal = Double(Frecency.score(visitCount: visitCount, lastVisit: lastVisit, now: now))
            secondarySignal = lastVisit.timeIntervalSinceReferenceDate
        case let .action(action, _):
            group = .action
            kindPriority = 2
            signal = -Double(CommandActionID.allCases.firstIndex(of: action) ?? 0)
            secondarySignal = 0
        case .suggestion:
            return nil
        }
    }

    /// Bar order: tier, fuzzy band, kind, activity or frecency, last visit (descending), then folded title and
    /// identifier (ascending). Total, because identifiers are unique.
    static func areInIncreasingOrder(_ lhs: Self, _ rhs: Self) -> Bool {
        if lhs.match.tier != rhs.match.tier {
            return lhs.match.tier > rhs.match.tier
        }
        if lhs.match.fuzzyBucket != rhs.match.fuzzyBucket {
            return lhs.match.fuzzyBucket > rhs.match.fuzzyBucket
        }
        if lhs.kindPriority != rhs.kindPriority {
            return lhs.kindPriority > rhs.kindPriority
        }
        return isBetter(lhs, than: rhs)
    }

    /// Same tier and same kind: activity or frecency, last visit, title, identifier, address.
    static func isBetter(_ lhs: Self, than rhs: Self) -> Bool {
        if lhs.signal != rhs.signal {
            return lhs.signal > rhs.signal
        }
        if lhs.secondarySignal != rhs.secondarySignal {
            return lhs.secondarySignal > rhs.secondarySignal
        }
        if lhs.foldedTitle != rhs.foldedTitle {
            return lhs.foldedTitle < rhs.foldedTitle
        }
        if lhs.id != rhs.id {
            return lhs.id < rhs.id
        }
        return lhs.address < rhs.address
    }
}

nonisolated extension CommandRanker {
    /// Rows of the matching local results: history deduplicated, sorting, caps.
    /// `primaryKey`: key of the typed address, whose history is hidden.
    func localRows(
        _ matches: [(candidate: CommandCandidate, match: CommandMatch)],
        excludingKey primaryKey: String?,
        now: Date,
    ) -> [CommandRow] {
        let ranked = matches.compactMap { RankedCandidate($0.candidate, match: $0.match, now: now) }
        let sorted = Self.deduplicateHistory(ranked, excludingKey: primaryKey).sorted(by: RankedCandidate.areInIncreasingOrder)
        return applyCaps(sorted).compactMap { Self.row(for: $0.candidate) }
    }

    /// Suggestions in the engine's order, without the one equal to the typed text or duplicates, capped.
    func suggestionRows(for query: CommandQuery, candidates: [CommandCandidate]) -> [CommandRow] {
        var seen: Set<String> = [query.folded]
        var rows: [CommandRow] = []
        for candidate in candidates where candidate.kind == .suggestion && rows.count < limits.suggestions {
            let folded = CommandText.fold(candidate.title)
            guard !folded.isEmpty, seen.insert(folded).inserted, let url = query.searchEngine.searchURL(for: candidate.title) else {
                continue
            }
            rows.append(CommandRow(
                id: candidate.id,
                style: .suggestion,
                title: candidate.title,
                subtitle: nil,
                url: url,
                target: .open(url),
            ))
        }
        return rows
    }

    /// Row of a tab, of a history address or of an action; the identifier is that of the result.
    static func row(for candidate: CommandCandidate) -> CommandRow? {
        switch candidate.kind {
        case let .tab(reference, place, spaceName, _):
            return CommandRow(
                id: candidate.id, style: .tab(reference, place: place, spaceName: spaceName), title: candidate.title,
                subtitle: subtitle(AddressDisplay.short(for: candidate.url), title: candidate.title), url: candidate.url,
                target: .switchToTab(reference),
            )
        case .history:
            guard let url = candidate.url else {
                return nil
            }
            return CommandRow(
                id: candidate.id, style: .history, title: candidate.title,
                subtitle: subtitle(CommandText.displayURL(url), title: candidate.title), url: url, target: .open(url),
            )
        case let .action(action, _):
            return CommandRow(
                id: candidate.id,
                style: .action(action),
                title: candidate.title,
                subtitle: nil,
                url: nil,
                target: .perform(action),
            )
        case .suggestion:
            return nil
        }
    }

    // MARK: Steps

    /// Removes the history of an address already open in a kept tab or equal to the typed address, then keeps one
    /// entry per address: the most frequent, the most recent, then the smallest title.
    /// Tabs are never deduplicated by address.
    private static func deduplicateHistory(_ ranked: [RankedCandidate], excludingKey primaryKey: String?) -> [RankedCandidate] {
        var excluded = Set(ranked.filter { $0.group == .tab }.compactMap(\.urlKey))
        if let primaryKey {
            excluded.insert(primaryKey)
        }
        var others: [RankedCandidate] = []
        var bestHistory: [String: RankedCandidate] = [:]
        for item in ranked {
            guard item.group == .history, let key = item.urlKey else {
                others.append(item)
                continue
            }
            if !excluded.contains(key), bestHistory[key].map({ RankedCandidate.isBetter(item, than: $0) }) ?? true {
                bestHistory[key] = item
            }
        }
        return others + bestHistory.values
    }

    /// Walks the sorted list, keeping each result as long as its kind and the total stay under their caps.
    private func applyCaps(_ sorted: [RankedCandidate]) -> [RankedCandidate] {
        var counts: [RankedCandidate.Group: Int] = [:]
        var kept: [RankedCandidate] = []
        for item in sorted where kept.count < limits.local {
            let count = counts[item.group, default: 0]
            guard count < cap(for: item.group) else {
                continue
            }
            counts[item.group] = count + 1
            kept.append(item)
        }
        return kept
    }

    private func cap(for group: RankedCandidate.Group) -> Int {
        switch group {
        case .tab: limits.tabs
        case .history: limits.history
        case .action: limits.actions
        }
    }

    /// `text`, unless it is empty or equal to the title.
    private static func subtitle(_ text: String, title: String) -> String? {
        text.isEmpty || text == title ? nil : text
    }
}
