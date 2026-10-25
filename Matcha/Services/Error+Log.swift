import Foundation

nonisolated extension Error {
    /// What the logs show of an error: its domain and code, never its description, which can hold a path (and so the
    /// user's name), a file name or an address (audit W10).
    var logSummary: String {
        let error = self as NSError
        return "\(error.domain) \(error.code)"
    }
}
