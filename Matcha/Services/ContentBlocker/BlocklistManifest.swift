import Foundation

/// Manifeste des listes de blocage livrées dans l'app (tâche 6.2) : `Resources/Blocklists/blocklists.json`, que la tâche
/// 6.1 remplit. Pour chaque liste au format de blocage de WebKit : son identifiant (stable d'une version à l'autre), son
/// nom affiché, sa version (une nouvelle version la fait recompiler au lancement suivant), son fichier, et pour les
/// réglages sa licence et son site. Les ressources de l'app sont copiées à plat : chaque fichier doit avoir un nom unique
/// parmi elles (`blocklist-<identifiant>.json`). Une entrée invalide, ou dont l'identifiant est déjà pris, est ignorée.
///
/// ```json
/// { "format" : 1,
///   "lists" : [ { "identifier" : "easylist", "name" : "EasyList", "version" : "2026.10.18",
///                 "file" : "blocklist-easylist.json", "license" : "CC BY-SA 3.0", "homepage" : "https://easylist.to" } ] }
/// ```
nonisolated struct BlocklistManifest: Equatable, Sendable {
    /// Version du format de manifeste comprise par cette version de Matcha.
    static let supportedFormat = 1
    /// Nom du manifeste parmi les ressources de l'app.
    static let resourceName = "blocklists.json"

    enum Error: Swift.Error, Equatable {
        /// Manifeste d'un format plus récent que celui que cette version comprend.
        case unsupportedFormat(Int)
    }

    /// Listes valides, dans l'ordre du manifeste.
    let lists: [BlocklistEntry]

    init(lists: [BlocklistEntry]) {
        var seen: Set<String> = []
        self.lists = lists.filter { $0.isValid && seen.insert($0.identifier).inserted }
    }

    /// Lit un manifeste ; lève une erreur si le JSON est illisible ou d'un format inconnu.
    init(data: Data) throws {
        let raw = try JSONDecoder().decode(Raw.self, from: data)
        guard raw.format == Self.supportedFormat else {
            throw Error.unsupportedFormat(raw.format)
        }
        self.init(lists: raw.lists.compactMap(\.entry))
    }

    private struct Raw: Decodable {
        let format: Int
        let lists: [LenientEntry]
    }

    /// Une entrée illisible (champ manquant, mauvais type) est ignorée sans rejeter tout le manifeste.
    private struct LenientEntry: Decodable {
        let entry: BlocklistEntry?

        init(from decoder: any Decoder) throws {
            entry = try? BlocklistEntry(from: decoder)
        }
    }
}

/// Une liste du manifeste (`BlocklistManifest`).
nonisolated struct BlocklistEntry: Codable, Hashable, Sendable {
    /// Identifiant stable : minuscules, chiffres et tirets (« easylist »).
    let identifier: String
    /// Nom montré dans les réglages (« EasyList »).
    let name: String
    /// Version de la liste (« 2026.10.18 ») : lettres, chiffres, points, tirets et soulignés.
    let version: String
    /// Nom du fichier JSON parmi les ressources, sans dossier.
    let file: String
    /// Licence montrée dans les réglages (« CC BY-SA 3.0 »).
    var license: String?
    /// Site de la liste, montré dans les réglages (https seulement).
    var homepage: String?

    init(identifier: String, name: String, version: String, file: String, license: String? = nil, homepage: String? = nil) {
        self.identifier = identifier
        self.name = name
        self.version = version
        self.file = file
        self.license = license
        self.homepage = homepage
    }

    /// Adresse du site de la liste, si elle est en https.
    var homepageURL: URL? {
        guard let homepage, let url = URL(string: homepage), url.scheme?.lowercased() == "https", url.host() != nil else {
            return nil
        }
        return url
    }

    var isValid: Bool {
        Self.isToken(identifier, extra: "-", maximumLength: 64)
            && identifier.allSatisfy { !$0.isUppercase }
            && Self.isToken(version, extra: ".-_", maximumLength: 64)
            && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && file.hasSuffix(".json") && file.count > 5 && !file.contains("/") && !file.hasPrefix(".")
    }

    /// Vrai si `text` n'est fait que de lettres et chiffres ASCII et de `extra`, commence par une lettre ou un chiffre, et
    /// ne dépasse pas `maximumLength` caractères.
    private static func isToken(_ text: String, extra: String, maximumLength: Int) -> Bool {
        guard let first = text.first, first.isASCII, first.isLetter || first.isNumber, text.count <= maximumLength else {
            return false
        }
        return text.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || extra.contains($0)) }
    }
}
