import Foundation

/// Reads Arc's `StorableSidebar.json` file (task 7.1). The format is not documented: reading is lenient, based on the
/// file of Arc 1.x. The local sidebar is the container of `sidebar.containers` that has `items` and `spaces`, two lists
/// of pairs (identifier, object):
/// - a Space has a title, `containerIDs` (`"pinned"` and `"unpinned"`, each followed by the identifier of its
///   container), `customInfo.iconType` (icon or emoji), `customInfo.windowTheme` (colors) and `profile`;
/// - an item has a title (for a tab, the name the user gave it, or null), `childrenIds` and `data`: `tab` (`savedURL`,
///   `savedTitle`: the page's title), `list` (folder), `itemContainer` (root of a container), `arcDocument` (Arc note,
///   left out); another kind that has children (split view…) is replaced by its children.
/// - `topAppsContainerIDs` gives, per profile, the container of its favorites.
/// Only `http`, `https` and `file` addresses are kept. A forged file can't exhaust the app (audit E7): folders deeper
/// than `maximumDepth` and items beyond `maximumItems` are skipped. Pure type.
nonisolated enum ArcSidebarParser {
    static let maximumDepth = 32
    /// Most items read: the import is made on the main thread, about 2 s for 10,000 items in Debug (review SV9).
    static let maximumItems = 10000

    enum Failure: Error, Equatable {
        /// Not a JSON object.
        case unreadable
        /// JSON object without a recognized Arc sidebar.
        case notArcSidebar
        /// A file larger than any Arc sidebar: not read.
        case tooLarge
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
        return ArcSidebar(spaces: spaces, favorites: favorites, skippedItems: reader.skipped, itemsBeyondLimit: reader.beyondLimit)
    }

    // MARK: Reading

    private struct Reader {
        let items: [String: [String: Any]]
        var skipped = 0
        var beyondLimit = 0
        private var visited: Set<String> = []
        private var depth = 0
        private var read = 0

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

        /// Content of item `id`, in order.
        mutating func children(of id: String) -> [ImportNode] {
            guard visited.insert(id).inserted, let item = items[id] else {
                return []
            }
            let ids = (item["childrenIds"] as? [Any])?.compactMap { $0 as? String } ?? []
            guard depth < ArcSidebarParser.maximumDepth else {
                skipped += ids.count
                return []
            }
            depth += 1
            defer { depth -= 1 }
            return ids.flatMap { node(for: $0) }
        }

        /// Item `id`: a tab, a folder, or its children for an unknown kind.
        private mutating func node(for id: String) -> [ImportNode] {
            guard let item = items[id] else {
                return []
            }
            read += 1
            guard read <= ArcSidebarParser.maximumItems else {
                beyondLimit += 1
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
                let pageTitle = savedTitle.flatMap { $0.isEmpty ? nil : $0 } ?? url.host() ?? url.absoluteString
                let name = title.flatMap { $0.isEmpty || $0 == pageTitle ? nil : $0 }
                return [.tab(ImportedTab(title: pageTitle, url: url, customTitle: name))]
            }
            if data["list"] != nil {
                return [.folder(name: title ?? "", children: children(of: id))]
            }
            if data["arcDocument"] != nil {
                visited.insert(id)
                skipped += 1
                return []
            }
            // Container root, split view or unknown kind: its children take its place.
            let content = children(of: id)
            if content.isEmpty, data["itemContainer"] == nil {
                skipped += 1
            }
            return content
        }
    }

    // MARK: Values

    /// List of pairs (identifier, object) as a dictionary; a list of objects carrying their `id` is read too.
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

    /// `["pinned", id, "unpinned", id]`, or keys as an object (`{"pinned": {}}`).
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

    /// Pairs (profile, container identifier) of `topAppsContainerIDs`.
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

    /// `{"default": true}` or `{"custom": {"_0": {"directoryBasename": "Profile 1"}}}`.
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

    /// `{"icon": "skull"}`, or an emoji under a key that contains “emoji”.
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

    /// Background colors of the theme (`red`, `green`, `blue` objects), in order, without adjacent duplicates.
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
