import Foundation

/// Palier de correspondance entre le texte tapé et un résultat, du plus lâche au plus strict.
nonisolated enum MatchTier: Int, Comparable, Sendable {
    case fuzzy = 1
    case substring
    case wordPrefix
    case prefix
    case exact

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Champs d'un résultat comparés au texte tapé, repliés une fois pour toutes : titres, adresse lisible et clé
/// d'adresse. L'historique (tâche 5.5) les prépare à son chargement plutôt qu'à chaque frappe.
nonisolated struct CommandMatchFields: Equatable, Sendable {
    /// Titres repliés.
    let titles: [String]
    /// Adresse lisible repliée.
    let address: String?
    /// Clé de l'adresse (`CommandText.urlKey`).
    let urlKey: String?

    init(titles: [String], url: URL?) {
        self.titles = titles.map(CommandText.fold)
        address = url.map { CommandText.fold(CommandText.displayURL($0)) }
        urlKey = url.map(CommandText.urlKey)
    }

    /// Même page que l'adresse tapée (`CommandText.urlKey`) : une adresse collée telle quelle
    /// (« https://www.apple.com/ », fragment, « %20 ») désigne l'onglet ouvert dessus.
    func isSamePage(as typedKey: String?) -> Bool {
        typedKey != nil && urlKey == typedKey
    }
}

/// Correspondance trouvée par `CommandMatcher`.
nonisolated struct CommandMatch: Equatable, Sendable {
    let tier: MatchTier
    /// 100 hors palier approximatif ; sinon la compacité des lettres trouvées (`fuzzyQuality`).
    let quality: Int

    /// Tranche de qualité d'une correspondance approximative (3 : ≥ 75, 2 : ≥ 50, 1 : en dessous) ;
    /// 0 pour les autres paliers.
    var fuzzyBucket: Int {
        guard tier == .fuzzy else {
            return 0
        }
        switch quality {
        case 75...: return 3
        case 50...: return 2
        default: return 1
        }
    }
}

/// Correspondance du texte tapé avec les titres et l'adresse d'un résultat. Paliers, du plus strict au
/// plus lâche (le premier atteint l'emporte) : exact (un titre, l'adresse lisible ou la même page),
/// préfixe d'un titre ou de l'adresse, début de mot pour chaque mot tapé, sous-chaîne (2 caractères au
/// moins), puis approximatif (3 à 32 caractères, lettres dans l'ordre depuis un début de mot, qualité
/// d'au moins 30). Textes repliés (`CommandText.fold`), adresses sans schéma ni « www. ».
nonisolated enum CommandMatcher {
    /// En dessous, une correspondance approximative est trop dispersée pour être proposée.
    static let minimumFuzzyQuality = 30
    /// Au-delà, le texte n'est plus cherché de façon approximative.
    static let maximumFuzzyLength = 32
    /// Longueur lue dans chaque champ pour la correspondance approximative.
    static let fuzzyFieldLength = 200

    /// Meilleur palier atteint par `query` sur `titles` et `url`, ou nil s'il n'y en a aucun ou
    /// s'il est sous `minimumTier`.
    static func match(_ query: CommandQuery, titles: [String], url: URL?, minimumTier: MatchTier = .fuzzy) -> CommandMatch? {
        match(query, fields: CommandMatchFields(titles: titles, url: url), minimumTier: minimumTier)
    }

    /// Comme `match(_:titles:url:minimumTier:)`, avec des champs déjà repliés (historique, tâche 5.5).
    static func match(_ query: CommandQuery, fields: CommandMatchFields, minimumTier: MatchTier = .fuzzy) -> CommandMatch? {
        guard !query.folded.isEmpty else {
            return nil
        }
        if let tier = strictTier(query, fields) {
            return tier >= minimumTier ? CommandMatch(tier: tier, quality: 100) : nil
        }
        guard minimumTier == .fuzzy, let quality = bestFuzzyQuality(query.compact, fields), quality >= minimumFuzzyQuality else {
            return nil
        }
        return CommandMatch(tier: .fuzzy, quality: quality)
    }

    /// Compacité (0 à 100) des lettres de `needle` trouvées dans l'ordre dans `haystack`, la première
    /// au début d'un mot : longueur de `needle` sur la longueur de la plus courte fenêtre trouvée
    /// en avançant au plus tôt. Nil si aucun début de mot ne permet de tout trouver.
    static func fuzzyQuality(of needle: String, in haystack: String) -> Int? {
        let needle = Array(needle)
        let haystack = Array(haystack)
        guard let first = needle.first else {
            return nil
        }
        var best: Int?
        for start in haystack.indices where haystack[start] == first && startsWord(haystack, at: start) {
            // Si les lettres manquent depuis ce début, elles manquent aussi depuis les suivants.
            guard let end = greedyEnd(of: needle, in: haystack, from: start) else {
                break
            }
            let quality = Int((Double(needle.count) / Double(end - start + 1) * 100).rounded(.down))
            best = max(best ?? 0, quality)
        }
        return best
    }

    // MARK: Paliers

    private static func strictTier(_ query: CommandQuery, _ fields: CommandMatchFields) -> MatchTier? {
        let folded = query.folded
        let urlFolded = query.urlFolded
        let address = urlFolded.isEmpty ? nil : fields.address
        if fields.titles.contains(folded) || address == urlFolded || fields.isSamePage(as: query.addressKey) {
            return .exact
        }
        if fields.titles.contains(where: { $0.hasPrefix(folded) }) || address?.hasPrefix(urlFolded) == true {
            return .prefix
        }
        if isWordPrefixMatch(query, fields) {
            return .wordPrefix
        }
        if folded.count >= 2, fields.titles.contains(where: { $0.contains(folded) }) || address?.contains(urlFolded) == true {
            return .substring
        }
        return nil
    }

    /// Chaque mot tapé commence un mot des titres ou de l'adresse, dans n'importe quel ordre. Un mot
    /// tapé coupé par une ponctuation (« node.js », « 6.4 ») compte pour ses morceaux ; « c++ », d'un
    /// seul morceau, reste entier pour ne pas se réduire à « c » (et ne commence donc aucun mot).
    private static func isWordPrefixMatch(_ query: CommandQuery, _ fields: CommandMatchFields) -> Bool {
        let haystacks = fields.titles + [fields.address].compactMap(\.self)
        return !query.wordParts.isEmpty && query.wordParts.allSatisfy { parts in
            parts.allSatisfy { part in haystacks.contains { hasWord(startingWith: part, in: $0) } }
        }
    }

    /// Vrai si un mot de `text` (suite de lettres et de chiffres, comme `CommandText.words`) commence par `part`,
    /// sans découper le texte : l'historique (tâche 5.5) passe des milliers d'adresses à chaque frappe.
    private static func hasWord(startingWith part: String, in text: String) -> Bool {
        guard let first = part.first, part.allSatisfy(isWordCharacter) else {
            return false
        }
        var previousIsWordCharacter = false
        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            let isWord = isWordCharacter(character)
            if isWord, !previousIsWordCharacter, character == first, text[index...].hasPrefix(part) {
                return true
            }
            previousIsWordCharacter = isWord
            index = text.index(after: index)
        }
        return false
    }

    private static func isWordCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber
    }

    private static func bestFuzzyQuality(_ compact: String, _ fields: CommandMatchFields) -> Int? {
        guard (3 ... maximumFuzzyLength).contains(compact.count) else {
            return nil
        }
        let haystacks = (fields.titles + [fields.address].compactMap(\.self)).map { String($0.prefix(fuzzyFieldLength)) }
        return haystacks.compactMap { fuzzyQuality(of: compact, in: $0) }.max()
    }

    // MARK: Approximatif

    private static func startsWord(_ characters: [Character], at index: Int) -> Bool {
        guard index > 0 else {
            return true
        }
        let previous = characters[index - 1]
        return !previous.isLetter && !previous.isNumber
    }

    /// Indice de la dernière lettre de `needle` trouvée en avançant au plus tôt depuis `start`
    /// (où se trouve sa première lettre), nil s'il en manque.
    private static func greedyEnd(of needle: [Character], in haystack: [Character], from start: Int) -> Int? {
        var position = start
        for character in needle.dropFirst() {
            guard let found = haystack[(position + 1)...].firstIndex(of: character) else {
                return nil
            }
            position = found
        }
        return position
    }
}
