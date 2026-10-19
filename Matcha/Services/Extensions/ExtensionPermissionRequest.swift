import Foundation

/// Request from a running extension (`permissions.request()`, task 6.3): permissions (“tabs”, “cookies”…), websites
/// (address patterns or addresses) or access to all websites. Pure type, described for the alert of
/// `ExtensionPermissionAlert`; the permissions screen of task 6.4 can use it.
nonisolated struct ExtensionPermissionRequest: Equatable, Sendable {
    /// Name of the extension (its display name, otherwise its identifier).
    var extensionName: String
    /// Requested permissions, sorted.
    var permissions: [String] = []
    /// Requested websites (host or pattern), sorted, without duplicates.
    var websites: [String] = []
    /// The request covers all websites (`<all_urls>`, `*://*/*`).
    var allWebsites = false

    /// Permission request.
    init(extensionName: String, permissions: some Sequence<String>) {
        self.extensionName = extensionName
        self.permissions = Set(permissions).sorted()
    }

    /// Website request: patterns (`string` of each pattern) and whether one of them covers all websites.
    init(extensionName: String, matchPatterns: some Sequence<String>, includesAllWebsites: Bool) {
        self.extensionName = extensionName
        websites = Set(matchPatterns).sorted()
        allWebsites = includesAllWebsites
    }

    /// Request for access to addresses: their hosts (otherwise the whole address, for a local file).
    init(extensionName: String, urls: some Sequence<URL>) {
        self.extensionName = extensionName
        websites = Set(urls.map { $0.host() ?? $0.absoluteString }).sorted()
    }

    /// Nothing to request: the answer is empty, without showing anything.
    var isEmpty: Bool {
        permissions.isEmpty && websites.isEmpty && !allWebsites
    }
}
