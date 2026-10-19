import Foundation
import OSLog
import WebKit

/// WebKit data records that belong to a website, without the Public Suffix List.
nonisolated enum WebsiteDataMatcher {
    /// True if record `recordName` (its `displayName`: usually the registrable domain, “google.com”, or a whole host,
    /// “localhost”) covers `host` (“mail.google.com”): same host, or a host under this domain. Another website that
    /// only shares a suffix (“notgoogle.com”) is never targeted.
    static func matches(recordName: String, host: String) -> Bool {
        let name = normalized(recordName)
        let host = normalized(host)
        guard !name.isEmpty, !host.isEmpty else {
            return false
        }
        return host == name || host.hasSuffix(".\(name)")
    }

    private static func normalized(_ value: String) -> String {
        var value = value.trimmingCharacters(in: .whitespaces).lowercased()
        if value.hasSuffix(".") {
            value.removeLast()
        }
        return value.hasPrefix("www.") ? String(value.dropFirst(4)) : value
    }
}

/// “Clear cookies and website data” (site settings, task 5.2): cookies, storage, caches and other data of the website
/// in a profile's data store, without touching other websites.
@MainActor
enum WebsiteDataCleaner {
    /// Erases the data of `host` in `store`; returns the number of records erased.
    @discardableResult
    static func removeData(forHost host: String, in store: WKWebsiteDataStore) async -> Int {
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        let records = await store.dataRecords(ofTypes: types)
        let matching = records.filter { WebsiteDataMatcher.matches(recordName: $0.displayName, host: host) }
        guard !matching.isEmpty else {
            Logger.permissions.info("No data to clear for \(host, privacy: .private)")
            return 0
        }
        await store.removeData(ofTypes: types, for: matching)
        Logger.permissions.info("Data cleared for \(host, privacy: .private) (\(matching.count, privacy: .public) records)")
        return matching.count
    }
}
