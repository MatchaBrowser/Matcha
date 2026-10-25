import Foundation

/// Reading of the event stream (`SYNC.md` § 4.6), one line at a time: `event: changes` followed by its `data:` line
/// means another device had changes applied; `event: expired` means the server closes the stream for an expired
/// token. `: ping` comments and blank lines only keep the connection alive. Pure type (review TS8).
nonisolated struct SyncEventReader {
    enum Action: Equatable {
        case none
        /// Read the changes again.
        case changes
        /// Renew the token, then reconnect.
        case expired
    }

    /// Event named by the last line, until the line after it.
    private var event: String?

    mutating func read(_ line: String) -> Action {
        if line.hasPrefix("event:") {
            event = line.dropFirst(6).trimmingCharacters(in: .whitespaces)
            return event == "expired" ? .expired : .none
        }
        defer { event = nil }
        return line.hasPrefix("data:") && event == "changes" ? .changes : .none
    }
}
