import Foundation

/// Wait asked by the `Retry-After` header of an error answer (`SYNC.md` § 4.8): a whole number of seconds or an HTTP
/// date, kept between `shortest` and `longest`. The header isn't authenticated: `inf`, `nan` or `1e40` would make
/// `Duration` trap, `0` or a negative number would make the coordinator loop (review SY3). Pure type.
nonisolated enum SyncRetryAfter {
    static let shortest: TimeInterval = 1
    static let longest: TimeInterval = 3600

    /// Seconds to wait; nil without a header, or for one that is neither a number of seconds nor an HTTP date.
    static func seconds(from header: String?, now: Date = .now) -> TimeInterval? {
        guard let header = header?.trimmingCharacters(in: .whitespaces), !header.isEmpty else {
            return nil
        }
        let wait: TimeInterval
        if header.utf8.allSatisfy({ (UInt8(ascii: "0") ... UInt8(ascii: "9")).contains($0) }) {
            // Too many digits for an `Int`: as long as allowed.
            wait = Int(header).map(TimeInterval.init) ?? longest
        } else if let date = httpDate(header) {
            wait = date.timeIntervalSince(now)
        } else {
            return nil
        }
        return min(max(wait, shortest), longest)
    }

    /// IMF-fixdate (“Sun, 06 Nov 1994 08:49:37 GMT”). A formatter per call: an error answer is rare, and
    /// `DateFormatter` can't be shared across threads.
    private static func httpDate(_ text: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter.date(from: text)
    }
}
