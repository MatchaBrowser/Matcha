import Foundation

/// Premières lignes de la barre, calculées sans attendre les sources : le texte tapé, ouvert comme
/// adresse ou cherché tel quel, et pour un nom de domaine seul, sa recherche en 2e ligne.
nonisolated enum CommandPrimaryRows {
    static let id = "primary"
    static let searchAlternativeID = "primary.search"

    /// Ligne de l'adresse de ⌘L non modifiée : l'URL entière, jamais réinterprétée.
    static func current(_ url: URL) -> CommandRow {
        CommandRow(id: id, style: .openAddress, title: url.absoluteString, subtitle: nil, url: url, target: .open(url))
    }

    /// Aucune ligne pour un texte vide.
    static func make(for query: CommandQuery) -> [CommandRow] {
        switch query.interpretation {
        case nil:
            return []
        case let .search(url):
            return [CommandRow(id: id, style: .search, title: query.trimmed, subtitle: nil, url: url, target: .open(url))]
        case let .address(url):
            // Le sous-titre montre le schéma ajouté (https:// ou http://).
            let subtitle = url.absoluteString == query.trimmed ? nil : url.absoluteString
            let open = CommandRow(id: id, style: .openAddress, title: query.trimmed, subtitle: subtitle, url: url, target: .open(url))
            guard query.isBareDomain, let searchURL = query.searchEngine.searchURL(for: query.trimmed) else {
                return [open]
            }
            let search = CommandRow(
                id: searchAlternativeID, style: .searchAlternative, title: query.trimmed, subtitle: nil, url: searchURL,
                target: .open(searchURL),
            )
            return [open, search]
        }
    }
}
