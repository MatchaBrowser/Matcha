import Foundation

/// Addresses an extension may open or load in a tab (`tabs.create`, `tabs.update`, `windows.create`, audit E4): web
/// pages, an empty page, and its own pages. Never a local file (the tab would read its whole folder), `data:`,
/// `javascript:`, `blob:`, another extension's pages or the app's own schemes: no permission covers them. Pure type.
nonisolated enum ExtensionURLPolicy {
    static func allows(_ url: URL, from extensionBaseURL: URL?) -> Bool {
        switch url.scheme?.lowercased() {
        case "http", "https":
            true
        case "about":
            url.absoluteString.lowercased() == "about:blank"
        case ExtensionManager.scheme:
            url.host() != nil && url.host() == extensionBaseURL?.host()
        default:
            false
        }
    }
}
