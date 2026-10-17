import Foundation

/// Ce que la barre de commande lit dans l'historique (`HistorySource`).
nonisolated extension HistoryIndex {
    /// Adresses qui correspondent à `query` selon `CommandMatcher` (le même que `CommandRanker`), donc un
    /// sur-ensemble de ce que la barre gardera ; au plus `limit`, les meilleures dans l'ordre du classement :
    /// palier, tranche approximative, fréquence et récence, dernière visite, clé. Un masque de caractères écarte
    /// d'abord les adresses qui ne peuvent pas correspondre, sans les comparer une à une. Rien si la tâche en cours
    /// est annulée (une frappe plus récente).
    func entries(matching query: CommandQuery, limit: Int, now: Date) -> [HistoryEntry] {
        guard !query.isEmpty, limit > 0 else {
            return []
        }
        // Tout palier demande les lettres et chiffres de l'adresse tapée sans « https:// » ni « www. » (le plus
        // petit des textes comparés), sauf la même page, qui passe par la clé.
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

    /// Adresse retenue et ce qui sert à la classer.
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
