import Foundation

/// Downloads a page starts on its own (audit W7), as in Safari: the user is asked before a page downloads a second
/// file, or before a frame inside it (an ad) downloads one, unless the download follows a real click in the page (a
/// script's click doesn't count) or the user allowed downloads for this page or this website. The first download of a
/// page goes without asking (“your download will start shortly”). Pure type.
nonisolated enum DownloadConsentPolicy {
    /// A download this long after a real click counts as asked for: a download link often redirects before the file.
    static let clickValidity: TimeInterval = 5

    static func needsConsent(isAllowed: Bool, lastClick: Date?, now: Date, isSubframe: Bool, earlierDownloads: Int) -> Bool {
        if isAllowed {
            return false
        }
        if let lastClick, now.timeIntervalSince(lastClick) <= clickValidity {
            return false
        }
        return isSubframe || earlierDownloads > 0
    }
}
