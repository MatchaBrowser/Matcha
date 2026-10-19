import Foundation
import Observation
import OSLog

/// Websites where the blocker is turned off (task 6.2), for all profiles: a choice about the website (a page broken
/// by blocking), not a profile's data. A website is the registrable domain of the address (`SiteDomain`:
/// “mail.google.com” → “google.com”): the exception applies to it and all its subdomains, on pages whose main
/// document is from that website (frames from other websites included, like `if-domain` in a WebKit list).
/// Saved in the app's settings (`contentBlockerExceptions`); without `defaults` (tests), everything stays in
/// memory. Private windows never write to it (`ContentBlockerScope`).
@MainActor
@Observable
final class ContentBlockerExceptions {
    /// App setting: list of websites.
    static let defaultsKey = "contentBlockerExceptions"

    private(set) var sites: Set<String>
    @ObservationIgnored private let defaults: UserDefaults?

    init(defaults: UserDefaults?) {
        self.defaults = defaults
        let stored = defaults?.stringArray(forKey: Self.defaultsKey) ?? []
        sites = Set(stored.compactMap(Self.normalized))
        if sites.count != stored.count {
            Logger.contentBlocker.notice("Exceptions du bloqueur illisibles ou en double : ignorées")
        }
    }

    /// Websites in alphabetical order (settings).
    var sortedSites: [String] {
        sites.sorted()
    }

    func contains(_ site: String) -> Bool {
        sites.contains(site)
    }

    /// Adds (`isExcepted`) or removes `site`; false if nothing changes.
    @discardableResult
    func set(_ isExcepted: Bool, forSite site: String) -> Bool {
        guard let site = Self.normalized(site), contains(site) != isExcepted else {
            return false
        }
        if isExcepted {
            sites.insert(site)
        } else {
            sites.remove(site)
        }
        save()
        return true
    }

    /// Website of `url` for exceptions; nil outside the web (`file:`, `about:`, an app's scheme).
    nonisolated static func site(for url: URL?) -> String? {
        url.flatMap(SiteDomain.site(of:))
    }

    /// Website read back or received: lowercase, without spaces or trailing dot; nil if it is empty or contains a
    /// slash, a space or a full address.
    nonisolated static func normalized(_ site: String) -> String? {
        var site = site.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if site.hasSuffix(".") {
            site.removeLast()
        }
        let forbidden = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "/?#@"))
        guard !site.isEmpty, site.rangeOfCharacter(from: forbidden) == nil, !site.hasPrefix(".") else {
            return nil
        }
        return site
    }

    private func save() {
        guard let defaults else {
            return
        }
        if sites.isEmpty {
            defaults.removeObject(forKey: Self.defaultsKey)
        } else {
            defaults.set(sortedSites, forKey: Self.defaultsKey)
        }
    }
}
