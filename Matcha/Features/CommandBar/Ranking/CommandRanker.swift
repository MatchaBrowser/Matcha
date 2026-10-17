import Foundation

/// Classement des lignes de la barre de commande, pur et lexicographique (voir `DECISIONS.md`,
/// « Classement pur et lexicographique ») :
/// 1. les lignes du texte tapé (`CommandPrimaryRows`), toujours en tête ;
/// 2. onglets, actions et historique qui correspondent au texte, par palier de correspondance, nature,
///    activité ou fréquence, titre puis identifiant ; plafonnés par nature et au total ;
/// 3. les suggestions du moteur, dans son ordre, seulement pour une recherche.
nonisolated struct CommandRanker: Sendable {
    /// Nombre de lignes gardées.
    struct Limits: Equatable, Sendable {
        var tabs = 4
        var history = 4
        var actions = 2
        /// Onglets, historique et actions ensemble.
        var local = 6
        var suggestions = 4
    }

    var limits = Limits()

    /// Lignes pour le texte de `query` ; aucune pour un texte vide. Le résultat ne dépend pas de
    /// l'ordre de `candidates`, sauf celui des suggestions (l'ordre du moteur) et le choix du premier
    /// exemplaire d'un même onglet (la source liste le Space affiché d'abord).
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

    /// Lignes de ⌘L avant toute modification : l'adresse actuelle, puis « Copier l'URL » si elle fait
    /// partie de `actions`. Aucune source n'est interrogée.
    func pristineRows(currentURL: URL, actions: [CommandCandidate]) -> [CommandRow] {
        let copy = actions.first { $0.actionID == .copyURL }.flatMap(Self.row(for:))
        return [CommandPrimaryRows.current(currentURL), copy].compactMap(\.self)
    }

    /// Suggestions reçues pour un texte précédent qui prolongent encore `query`, dans leur ordre :
    /// elles restent affichées jusqu'à l'arrivée des nouvelles.
    static func carriedOver(_ suggestions: [CommandCandidate], to query: CommandQuery) -> [CommandCandidate] {
        suggestions.filter { CommandText.fold($0.title).hasPrefix(query.folded) }
    }

    // MARK: Correspondance

    /// Onglets (un seul exemplaire par identifiant, le premier), actions et historique avec adresse.
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

    /// Onglets et historique sur leur titre et leur adresse ; actions sur leur titre et leurs mots-clés,
    /// à partir de deux caractères et jamais de façon lâche (début de mot au moins).
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
