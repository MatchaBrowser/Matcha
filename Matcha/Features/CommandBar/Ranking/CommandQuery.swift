import Foundation

/// Texte de la barre de commande sous les formes que le classement compare, avec sa lecture
/// (adresse ou recherche) par `AddressResolver`.
nonisolated struct CommandQuery: Equatable, Sendable {
    /// Texte tel que saisi.
    let text: String
    /// Texte sans espaces aux bords : celui qu'on ouvre ou qu'on cherche.
    let trimmed: String
    /// Texte replié (`CommandText.fold`).
    let folded: String
    /// Mots du texte replié, séparés par les espaces.
    let tokens: [String]
    /// Texte replié sans espaces, pour la correspondance approximative.
    let compact: String
    /// Texte replié sans « https:// », « http:// », « www. » ni « / » final, comparé aux adresses.
    let urlFolded: String
    let searchEngine: SearchEngine
    /// Nil pour un texte vide.
    let interpretation: AddressInterpretation?
    /// Clé (`CommandText.urlKey`) de l'adresse tapée ; nil pour une recherche.
    let addressKey: String?

    init(text: String, searchEngine: SearchEngine) {
        self.text = text
        trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        folded = CommandText.fold(text)
        tokens = folded.split(separator: " ").map(String.init)
        compact = tokens.joined()
        let stripped = CommandText.stripURLPrefixes(folded)
        urlFolded = stripped.count > 1 && stripped.hasSuffix("/") ? String(stripped.dropLast()) : stripped
        self.searchEngine = searchEngine
        let interpretation = AddressResolver(searchEngine: searchEngine).interpret(trimmed)
        self.interpretation = interpretation
        addressKey = if case let .address(url) = interpretation {
            CommandText.urlKey(url)
        } else {
            nil
        }
    }

    var isEmpty: Bool {
        trimmed.isEmpty
    }

    /// Vrai si le texte est lu comme une recherche (et non comme une adresse).
    var isSearch: Bool {
        if case .search = interpretation {
            return true
        }
        return false
    }

    /// Nom de domaine tapé seul (« apple.com », « node.js ») : lu comme une adresse `https`, sans
    /// schéma, port, chemin, requête, fragment ni « @ ».
    var isBareDomain: Bool {
        guard case let .address(url) = interpretation, url.scheme == "https" else {
            return false
        }
        return !trimmed.contains { ":/?#@".contains($0) }
    }
}
