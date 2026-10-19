import Foundation

/// What the command bar reads from the history (`HistorySource`).
nonisolated extension HistoryIndex {
    /// Addresses that match `query` according to `CommandMatcher` (the same as `CommandRanker`), hence a superset of
    /// what the bar will keep; at most `limit`, the best ones in ranking order: tier, approximate band, frequency and
    /// recency, last visit, key. A character mask first rules out the addresses that cannot match, without comparing
    /// them one by one. Nothing if the current task is cancelled (a more recent keystroke).
    func entries(matching query: CommandQuery, limit: Int, now: Date) -> [HistoryEntry] {
        guard !query.isEmpty, limit > 0 else {
            return []
        }
        // Every tier requires the letters and digits of the typed address without “https://” or “www.” (the
        // shortest of the compared texts), except the same page, which goes through the key.
        let required = HistoryCharacterMask([query.urlFolded])
        var matches: [Match] = []
        for (offset, entry) in entries.values.enumerated() {
            if offset.isMultiple(of: 1024), Task.isCancelled {
                return []
            }
            guard entry.characters.contains(required) || entry.fields.isSamePage(as: query.addressKey),
                  let match = CommandMatcher.match(query, fields: entry.fields)
            else {
                continue
            }
            matches.append(Match(entry: entry, match: match, frecency: Frecency.score(
                visitCount: entry.visitCount,
                lastVisit: entry.lastVisit,
                now: now,
            )))
        }
        matches.sort(by: Match.isBetter)
        return matches.prefix(limit).map(\.entry.historyEntry)
    }

    /// A kept address and what is used to rank it.
    private struct Match {
        let entry: HistoryIndexEntry
        let match: CommandMatch
        let frecency: Int

        static func isBetter(_ lhs: Self, _ rhs: Self) -> Bool {
            if lhs.match.tier != rhs.match.tier {
                return lhs.match.tier > rhs.match.tier
            }
            if lhs.match.fuzzyBucket != rhs.match.fuzzyBucket {
                return lhs.match.fuzzyBucket > rhs.match.fuzzyBucket
            }
            if lhs.frecency != rhs.frecency {
                return lhs.frecency > rhs.frecency
            }
            if lhs.entry.lastVisit != rhs.entry.lastVisit {
                return lhs.entry.lastVisit > rhs.entry.lastVisit
            }
            return lhs.entry.urlKey < rhs.entry.urlKey
        }
    }
}
