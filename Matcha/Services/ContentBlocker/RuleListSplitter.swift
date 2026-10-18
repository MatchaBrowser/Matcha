import Foundation

/// Découpe d'une liste de règles au format de blocage de WebKit (un tableau JSON) en parts d'au plus `maximumRuleCount`
/// règles, dans l'ordre (tâche 6.2) : WebKit refuse de compiler une liste trop grosse. Chaque part devient une liste à
/// part dans le magasin ; une règle `ignore-previous-rules` n'agit que dans sa propre part (comme dans sa liste,
/// `DECISIONS.md`).
nonisolated enum RuleListSplitter {
    /// Nombre de règles au-delà duquel WebKit refuse une liste (« Too many rules in JSON array. », vérifié sur
    /// macOS 27 : 150 000 règles passent, 150 001 non).
    static let webKitMaximumRuleCount = 150_000

    enum Error: Swift.Error, Equatable {
        /// Le JSON n'est pas un tableau de règles.
        case notAnArray
        /// Une part ne se relit pas en UTF-8 (n'arrive pas : `JSONSerialization` écrit de l'UTF-8).
        case notUTF8
    }

    /// Nombre de règles de la liste et ses parts (JSON) ; une liste assez petite reste telle quelle, en une part.
    struct Parts: Equatable, Sendable {
        let ruleCount: Int
        let parts: [String]
    }

    /// Découpe `rules` (JSON) ; lève une erreur si le JSON est illisible ou n'est pas un tableau.
    static func parts(of rules: Data, maximumRuleCount: Int) throws -> Parts {
        guard let array = try JSONSerialization.jsonObject(with: rules) as? [Any] else {
            throw Error.notAnArray
        }
        let size = max(1, maximumRuleCount)
        // Assez petite et en UTF-8 : telle quelle, sans la réécrire.
        if array.count <= size, let text = String(bytes: rules, encoding: .utf8) {
            return Parts(ruleCount: array.count, parts: [text])
        }
        var parts: [String] = []
        for start in stride(from: 0, to: max(array.count, 1), by: size) {
            try parts.append(json(of: Array(array[start ..< min(start + size, array.count)])))
        }
        return Parts(ruleCount: array.count, parts: parts)
    }

    private static func json(of rules: [Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: rules, options: [.withoutEscapingSlashes])
        guard let text = String(bytes: data, encoding: .utf8) else {
            throw Error.notUTF8
        }
        return text
    }

    /// Même découpe, hors du fil principal (une grosse liste se lit en quelques dixièmes de seconde).
    @concurrent
    static func partsInBackground(of rules: Data, maximumRuleCount: Int) async throws -> Parts {
        try parts(of: rules, maximumRuleCount: maximumRuleCount)
    }
}
