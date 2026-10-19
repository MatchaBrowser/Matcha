import Foundation
import Observation
import OSLog

/// What websites may do without asking, answered “Always” in the banner (audit W2): per profile, per website and per
/// action (allowing Zoom for zoom.us allows nothing else). Listed in Settings > Privacy and in the site settings, where
/// each can be forgotten. Saved in the app's settings (`siteActionAllowances`), not synced; without `defaults`
/// (private window, test store), in memory only, gone with the session.
@MainActor
@Observable
final class SiteActionAllowances {
    static let defaultsKey = "siteActionAllowances"

    struct Entry: Hashable, Identifiable {
        let profileID: UUID?
        let origin: SiteOrigin
        let action: SiteAction

        var id: Self {
            self
        }
    }

    private(set) var entries: Set<Entry>
    @ObservationIgnored private let defaults: UserDefaults?

    init(defaults: UserDefaults?) {
        self.defaults = defaults
        entries = Self.load(from: defaults)
    }

    /// In the order of Settings: website, then action.
    var sortedEntries: [Entry] {
        entries.sorted { ($0.origin.displayName, $0.action.key) < ($1.origin.displayName, $1.action.key) }
    }

    func isAllowed(_ action: SiteAction, origin: SiteOrigin, profileID: UUID?) -> Bool {
        entries.contains(Entry(profileID: profileID, origin: origin, action: action))
    }

    /// Actions allowed for `origin`.
    func actions(for origin: SiteOrigin, profileID: UUID?) -> [Entry] {
        sortedEntries.filter { $0.origin == origin && $0.profileID == profileID }
    }

    func allow(_ action: SiteAction, origin: SiteOrigin, profileID: UUID?) {
        entries.insert(Entry(profileID: profileID, origin: origin, action: action))
        Logger.permissions.info("\(action.key, privacy: .public) always allowed for \(origin.displayHost, privacy: .private)")
        save()
    }

    func remove(_ entry: Entry) {
        entries.remove(entry)
        save()
    }

    /// Forgets what a deleted profile allowed.
    func removeAll(profileID: UUID) {
        entries = entries.filter { $0.profileID != profileID }
        save()
    }

    private func save() {
        defaults?.set(entries.map { entry in
            ["profile": entry.profileID?.uuidString ?? "", "site": entry.origin.key, "action": entry.action.key]
        }, forKey: Self.defaultsKey)
    }

    /// Readable entries; an unknown website or action is ignored.
    private static func load(from defaults: UserDefaults?) -> Set<Entry> {
        let saved = defaults?.array(forKey: defaultsKey) as? [[String: String]] ?? []
        return Set(saved.compactMap { item in
            guard let origin = item["site"].flatMap(SiteOrigin.init(key:)),
                  let action = item["action"].flatMap(SiteAction.init(key:))
            else {
                return nil
            }
            return Entry(profileID: item["profile"].flatMap(UUID.init(uuidString:)), origin: origin, action: action)
        })
    }
}
