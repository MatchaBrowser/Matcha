import Foundation

/// JSON conventions of sync (task 7.4, `SYNC.md` § 2.2 and § 4.1): ISO 8601 dates in UTC to the millisecond
/// (“2026-10-17T08:30:12.345Z”), sorted keys for stable content. Pure type.
nonisolated enum SyncCoding {
    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(string(from: date))
        }
        return encoder
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            guard let date = date(from: text) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Date illisible")
            }
            return date
        }
        return decoder
    }

    /// Number of milliseconds since 1970 (rounded).
    static func milliseconds(of date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1000).rounded())
    }

    /// Exact date of `milliseconds`.
    static func date(milliseconds: Int64) -> Date {
        Date(timeIntervalSince1970: Double(milliseconds) / 1000)
    }

    /// Date rounded to the millisecond: the one that comes back from a JSON round trip.
    static func rounded(_ date: Date) -> Date {
        self.date(milliseconds: milliseconds(of: date))
    }

    static func string(from date: Date) -> String {
        let milliseconds = milliseconds(of: date)
        let seconds = milliseconds >= 0 ? milliseconds / 1000 : (milliseconds - 999) / 1000
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        let parts = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: Date(timeIntervalSince1970: Double(seconds)),
        )
        let values = [parts.year, parts.month, parts.day, parts.hour, parts.minute, parts.second].map { $0 ?? 0 }
        return String(
            format: "%04ld-%02ld-%02ldT%02ld:%02ld:%02ld.%03lldZ",
            values[0], values[1], values[2], values[3], values[4], values[5], milliseconds - seconds * 1000,
        )
    }

    /// Date read from “2026-10-17T08:30:12.345Z” (optional fraction, counted to the millisecond at most); nil
    /// otherwise.
    static func date(from text: String) -> Date? {
        guard text.hasSuffix("Z") else {
            return try? Date(text, strategy: .iso8601)
        }
        let body = text.dropLast()
        let parts = body.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        guard let whole = try? Date(String(parts[0]) + "Z", strategy: .iso8601) else {
            return nil
        }
        var milliseconds = Int64(whole.timeIntervalSince1970) * 1000
        if parts.count == 2 {
            let digits = parts[1].prefix(3)
            guard !parts[1].isEmpty, parts[1].allSatisfy(\.isASCII), let value = Int64(digits.padding(
                toLength: 3,
                withPad: "0",
                startingAt: 0,
            ))
            else {
                return nil
            }
            milliseconds += value
        }
        return date(milliseconds: milliseconds)
    }
}
