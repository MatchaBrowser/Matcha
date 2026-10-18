import Foundation

/// Lit le fichier `StorableSidebar.json` d'Arc (tâche 7.1). Le format n'est pas documenté : la lecture est tolérante,
/// d'après le fichier d'Arc 1.x. La barre locale est le conteneur de `sidebar.containers` qui a `items` et `spaces`,
/// deux listes de paires (identifiant, objet) :
/// - un Space a un titre, `containerIDs` (`"pinned"` et `"unpinned"`, chacun suivi de l'identifiant de son conteneur),
///   `customInfo.iconType` (icône ou emoji), `customInfo.windowTheme` (couleurs) et `profile` ;
/// - un élément a un titre, `childrenIds` et `data` : `tab` (`savedURL`, `savedTitle`), `list` (dossier),
///   `itemContainer` (racine d'un conteneur), `arcDocument` (note d'Arc, laissée de côté) ; un autre genre qui a des
///   enfants (split view…) est remplacé par ses enfants.
/// - `topAppsContainerIDs` donne, par profil, le conteneur de ses favoris.
/// Seules les adresses `http`, `https` et `file` sont gardées. Type pur.
nonisolated enum ArcSidebarParser {
    enum Failure: Error, Equatable {
        /// Pas un objet JSON.
        case unreadable
        /// Objet JSON sans barre d'Arc reconnue.
        case notArcSidebar
    }

    static let keptSchemes: Set<String> = ["http", "https", "file"]

    static func parse(_ data: Data) throws -> ArcSidebar {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw Failure.unreadable
        }
        let containers = (root["sidebar"] as? [String: Any])?["containers"] as? [Any] ?? []
        guard let main = containers.compactMap({ $0 as? [String: Any] }).first(where: { $0["items"] != nil && $0["spaces"] != nil })
        else {
            throw Failure.notArcSidebar
        }
        var reader = Reader(items: pairs(main["items"]))
        let spaces = orderedPairs(main["spaces"]).map { reader.space(from: $0.value) }
        var favorites: [ArcSidebar.Profile: [ImportedTab]] = [:]
        for (key, containerID) in profilePairs(main["topAppsContainerIDs"]) {
            let tabs = ImportNode.flattenedTabs(of: reader.children(of: containerID))
            if !tabs.isEmpty {
                favorites[profile(from: key), default: []].append(contentsOf: tabs)
            }
        }
        return ArcSidebar(spaces: spaces, favorites: favorites, skippedItems: reader.skipped)
    }

    // MARK: Lecture

    private struct Reader {
        let items: [String: [String: Any]]
        var skipped = 0
        private var visited: Set<String> = []

        init(items: [String: [String: Any]]) {
            self.items = items
        }

        mutating func space(from object: [String: Any]) -> ArcSidebar.Space {
            let containers = ArcSidebarParser.containerIDs(object["containerIDs"] ?? object["newContainerIDs"])
            let customInfo = object["customInfo"] as? [String: Any]
            return ArcSidebar.Space(
                name: (object["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                icon: ArcSidebarParser.icon(customInfo?["iconType"]),
                colors: Array(ArcSidebarParser.colors(in: customInfo?["windowTheme"]).prefix(3)),
                profile: ArcSidebarParser.profile(from: object["profile"]),
                pinned: containers["pinned"].map { children(of: $0) } ?? [],
                openTabs: containers["unpinned"].map { children(of: $0) } ?? [],
            )
        }

        /// Contenu de l'élément `id`, dans l'ordre.
        mutating func children(of id: String) -> [ImportNode] {
            guard visited.insert(id).inserted, let item = items[id] else {
                return []
            }
            let ids = (item["childrenIds"] as? [Any])?.compactMap { $0 as? String } ?? []
            return ids.flatMap { node(for: $0) }
        }

        /// L'élément `id` : un onglet, un dossier, ou ses enfants pour un genre inconnu.
        private mutating func node(for id: String) -> [ImportNode] {
            guard let item = items[id] else {
                return []
            }
            let data = item["data"] as? [String: Any] ?? [:]
            let title = (item["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let tab = data["tab"] as? [String: Any] {
                visited.insert(id)
                guard let url = ArcSidebarParser.url(tab["savedURL"]) else {
                    skipped += 1
                    return []
                }
                let savedTitle = (tab["savedTitle"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                let name = [title, savedTitle].compactMap(\.self).first { !$0.isEmpty } ?? url.host() ?? url.absoluteString
                return [.tab(ImportedTab(title: name, url: url))]
            }
            if data["list"] != nil {
                return [.folder(name: title ?? "", children: children(of: id))]
            }
            if data["arcDocument"] != nil {
                visited.insert(id)
                skipped += 1
                return []
            }
            // Racine de conteneur, split view ou genre inconnu : ses enfants prennent sa place.
            let content = children(of: id)
            if content.isEmpty, data["itemContainer"] == nil {
                skipped += 1
            }
            return content
        }
    }

    // MARK: Valeurs

    /// Liste de paires (identifiant, objet) en dictionnaire ; une liste d'objets portant leur `id` est lue aussi.
    static func pairs(_ value: Any?) -> [String: [String: Any]] {
        Dictionary(orderedPairs(value).map { ($0.key, $0.value) }) { first, _ in first }
    }

    static func orderedPairs(_ value: Any?) -> [(key: String, value: [String: Any])] {
        let list = value as? [Any] ?? []
        var result: [(key: String, value: [String: Any])] = []
        var index = 0
        while index < list.count {
            if let key = list[index] as? String, index + 1 < list.count, let object = list[index + 1] as? [String: Any] {
                result.append((key, object))
                index += 2
            } else {
                if let object = list[index] as? [String: Any], let key = object["id"] as? String {
                    result.append((key, object))
                }
                index += 1
            }
        }
        return result
    }

    /// `["pinned", id, "unpinned", id]`, ou des clés en objet (`{"pinned": {}}`).
    static func containerIDs(_ value: Any?) -> [String: String] {
        let list = value as? [Any] ?? []
        var result: [String: String] = [:]
        var index = 0
        while index + 1 < list.count {
            let key = list[index] as? String ?? (list[index] as? [String: Any])?.keys.first
            if let key, let id = list[index + 1] as? String {
                result[key] = result[key] ?? id
                index += 2
            } else {
                index += 1
            }
        }
        return result
    }

    /// Paires (profil, identifiant du conteneur) de `topAppsContainerIDs`.
    static func profilePairs(_ value: Any?) -> [(key: Any, id: String)] {
        let list = value as? [Any] ?? []
        var result: [(key: Any, id: String)] = []
        var index = 0
        while index + 1 < list.count {
            if !(list[index] is String), let id = list[index + 1] as? String {
                result.append((list[index], id))
                index += 2
            } else {
                index += 1
            }
        }
        return result
    }

    /// `{"default": true}` ou `{"custom": {"_0": {"directoryBasename": "Profile 1"}}}`.
    static func profile(from value: Any?) -> ArcSidebar.Profile {
        guard let object = value as? [String: Any], let custom = object["custom"] else {
            return .default
        }
        let details = (custom as? [String: Any])?["_0"] as? [String: Any] ?? custom as? [String: Any]
        guard let name = details?["directoryBasename"] as? String, !name.isEmpty else {
            return .default
        }
        return .custom(name)
    }

    /// `{"icon": "skull"}`, ou un emoji sous une clé qui contient « emoji ».
    static func icon(_ value: Any?) -> ArcSidebar.Icon? {
        guard let object = value as? [String: Any] else {
            return nil
        }
        if let name = object["icon"] as? String, !name.isEmpty {
            return .named(name)
        }
        for (key, value) in object where key.lowercased().contains("emoji") {
            if let emoji = value as? String ?? (value as? [String: Any])?["_0"] as? String, !emoji.isEmpty {
                return .emoji(emoji)
            }
        }
        return nil
    }

    /// Couleurs du fond du thème (objets `red`, `green`, `blue`), dans l'ordre, sans doublon voisin.
    static func colors(in theme: Any?) -> [ThemeColor] {
        let background = (theme as? [String: Any])?["background"] ?? theme
        var result: [ThemeColor] = []
        collectColors(in: background, into: &result)
        return result
    }

    private static func collectColors(in value: Any?, into result: inout [ThemeColor]) {
        if let object = value as? [String: Any] {
            if let red = number(object["red"]), let green = number(object["green"]), let blue = number(object["blue"]) {
                let color = ThemeColor(red: red, green: green, blue: blue)
                if result.last != color {
                    result.append(color)
                }
                return
            }
            for key in object.keys.sorted() {
                collectColors(in: object[key], into: &result)
            }
        } else if let list = value as? [Any] {
            list.forEach { collectColors(in: $0, into: &result) }
        }
    }

    private static func number(_ value: Any?) -> Double? {
        (value as? NSNumber)?.doubleValue
    }

    static func url(_ value: Any?) -> URL? {
        guard let text = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty,
              let url = URL(string: text), let scheme = url.scheme?.lowercased(), keptSchemes.contains(scheme)
        else {
            return nil
        }
        return url
    }
}
