import Foundation
import OSLog

/// Blocklist compiled in WebKit's store (task 6.2), remembered in the app's settings: at the next launch, the same
/// version is looked up as is (`WKContentRuleListStore.lookUpContentRuleList`) instead of being recompiled. The rule
/// count and the date are used by the settings.
nonisolated struct CompiledBlocklist: Codable, Equatable, Sendable {
    /// App setting: the compiled lists, as JSON.
    static let defaultsKey = "contentBlockerCompiledLists"
    /// Prefix of our lists' identifiers in the store: other identifiers there are never touched.
    static let storePrefix = "matcha-blocklist."

    let identifier: String
    let version: String
    /// Lists in the store: a single one, or one per part if WebKit refused the whole list (too many rules).
    let storeIdentifiers: [String]
    let ruleCount: Int
    let compiledAt: Date

    /// Identifier in the store of the whole `entry` list (“matcha-blocklist.easylist.2026.10.18”) or of its parts
    /// (“….part-1”, “….part-2”…): the version is part of it, so a new version never replaces the old one before it
    /// is ready.
    static func storeIdentifiers(for entry: BlocklistEntry, partCount: Int) -> [String] {
        let base = "\(storePrefix)\(entry.identifier).\(entry.version)"
        guard partCount > 1 else {
            return [base]
        }
        return (1 ... partCount).map { "\(base).part-\($0)" }
    }

    /// True if `self` is the compiled version of `entry` (same identifier, same version, parts named for it): it only
    /// remains to look it up in the store.
    func matches(_ entry: BlocklistEntry) -> Bool {
        identifier == entry.identifier && version == entry.version && !storeIdentifiers.isEmpty
            && storeIdentifiers == Self.storeIdentifiers(for: entry, partCount: storeIdentifiers.count)
    }

    /// Our identifiers in the store that are no longer used (old version, list removed from the app, interrupted
    /// compilation), sorted; those with another prefix are never returned.
    static func staleIdentifiers(available: [String], keeping kept: Set<String>) -> [String] {
        available.filter { $0.hasPrefix(storePrefix) && !kept.contains($0) }.sorted()
    }

    /// Lists remembered in `defaults`; none without settings, or if the value is unreadable.
    static func load(from defaults: UserDefaults?) -> [CompiledBlocklist] {
        guard let data = defaults?.data(forKey: defaultsKey) else {
            return []
        }
        do {
            // Entry by entry: an unreadable one is compiled again alone (audit R4).
            return try JSONDecoder().decode([Lenient<CompiledBlocklist>].self, from: data).compactMap(\.value)
        } catch {
            Logger.contentBlocker.notice("Unreadable compiled lists: they will be compiled again")
            return []
        }
    }

    static func save(_ lists: [CompiledBlocklist], to defaults: UserDefaults?) {
        guard let defaults else {
            return
        }
        if lists.isEmpty {
            defaults.removeObject(forKey: defaultsKey)
        } else if let data = try? JSONEncoder().encode(lists) {
            defaults.set(data, forKey: defaultsKey)
        }
    }
}
