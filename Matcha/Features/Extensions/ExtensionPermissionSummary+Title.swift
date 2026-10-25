import Foundation

/// Sentence of each line of what an extension can do: the permissions screen and the alert of a running extension use
/// the same words (review EX27).
extension ExtensionPermissionSummary.Line {
    var title: String {
        switch self {
        case .allWebsites: String(localized: "Read and change your data on all websites")
        case .websites: String(localized: "Read and change your data on these websites:")
        case .browsingHistory: String(localized: "Read your browsing history")
        case .cookies: String(localized: "Read and change website cookies")
        case .clipboardRead: String(localized: "Read data you copy and paste")
        case .clipboardWrite: String(localized: "Change data you copy and paste")
        case .blockContent: String(localized: "Block content on websites")
        case .nativeApps: String(localized: "Communicate with apps on your Mac")
        case .notifications: String(localized: "Show notifications")
        case .downloads: String(localized: "Manage your downloads")
        case .bookmarks: String(localized: "Read and change your bookmarks")
        case .location: String(localized: "Detect your location")
        case .localFiles: String(localized: "Read your local files")
        }
    }
}
