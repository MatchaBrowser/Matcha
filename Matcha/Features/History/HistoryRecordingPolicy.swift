import Foundation

/// History rules (task 5.5), pure: what is kept, in what form, and when a visit extends another rather than
/// creating a new one. See `DECISIONS.md`.
nonisolated enum HistoryRecordingPolicy {
    /// What a page that has just been displayed at an address does, based on the last visit it kept.
    enum Decision: Equatable, Sendable {
        /// New visit.
        case record
        /// Same page, same address, shortly after: the previous visit takes the new date and the new title
        /// (bursts of reloads, a redirect that comes back).
        case refresh
    }

    /// Last visit kept by a page.
    struct PageVisit: Equatable, Sendable {
        let id: UUID
        let urlKey: String
        let date: Date
    }

    /// The same address reloaded by the same page within this delay counts only once.
    static let mergeInterval: TimeInterval = 60
    /// A title that changes within this delay after the visit renames it (title set by the page's script); after
    /// that, only a title that was still missing is taken.
    static let titleUpdateInterval: TimeInterval = 5
    /// Address changed by the page without a new document (History API): kept if it lasts this delay, so as to keep
    /// only the last of a burst of `replaceState` calls.
    static let sameDocumentDelay: Duration = .seconds(1)

    /// The kept address, or nil if the address does not go into the history: only web pages (`http`, `https`, with
    /// a host) and local files; never `about:`, `data:`, `blob:`, `javascript:`, nor the schemes of other apps or
    /// of tests. The fragment and the credentials (`user:password@`) are removed.
    static func storedURL(for url: URL?) -> URL? {
        guard let url, var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        switch components.scheme?.lowercased() {
        case "http", "https":
            guard let host = components.host, !host.isEmpty else {
                return nil
            }
        case "file":
            break
        default:
            return nil
        }
        components.fragment = nil
        components.user = nil
        components.password = nil
        return components.url
    }

    /// Kept title: without surrounding whitespace, nil if it is empty.
    static func normalizedTitle(_ title: String?) -> String? {
        guard let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    /// New visit, or a refresh of `previous` if it is the same address within the merge delay.
    static func decision(previous: PageVisit?, urlKey: String, now: Date) -> Decision {
        guard let previous, previous.urlKey == urlKey else {
            return .record
        }
        return abs(now.timeIntervalSince(previous.date)) <= mergeInterval ? .refresh : .record
    }

    /// True if a new title of the page renames `visit`: same address, and the title arrived within the delay or the
    /// visit still has no title.
    static func acceptsTitle(for visit: PageVisit, visitHasTitle: Bool, pageURLKey: String?, now: Date) -> Bool {
        guard pageURLKey == visit.urlKey else {
            return false
        }
        return !visitHasTitle || abs(now.timeIntervalSince(visit.date)) <= titleUpdateInterval
    }

    /// An address changed by the page counts if it stays on the origin of the last loaded document (the History
    /// API cannot change it): a failed load to another site does not become a visit.
    static func isSameDocumentChange(from loaded: URL?, to url: URL) -> Bool {
        guard let loaded else {
            return false
        }
        return origin(of: loaded) == origin(of: url)
    }

    /// Visits kept: one year (Safari's default setting); the oldest are erased at launch.
    static func retentionCutoff(now: Date, calendar: Calendar) -> Date {
        calendar.date(byAdding: .year, value: -1, to: now) ?? now.addingTimeInterval(-365 * 86400)
    }

    private static func origin(of url: URL) -> String {
        let scheme = url.scheme?.lowercased() ?? ""
        let host = url.host()?.lowercased() ?? ""
        return "\(scheme)://\(host):\(url.port.map(String.init) ?? "")"
    }
}
