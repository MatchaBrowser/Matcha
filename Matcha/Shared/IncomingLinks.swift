import Foundation
import OSLog

/// Links opened by other apps (task 8.2): web addresses clicked in Mail or Messages, HTML files opened from the
/// Finder. Received by the app delegate, they wait until the app is ready (`handler`), at launch.
@MainActor
final class IncomingLinks {
    /// Accepted schemes; the others are ignored.
    static let schemes: Set<String> = ["http", "https", "file"]

    /// Opens the links; as long as it is nil, they wait.
    var handler: (([URL]) -> Void)? {
        didSet {
            guard let handler, !waiting.isEmpty else {
                return
            }
            let urls = waiting
            waiting = []
            handler(urls)
        }
    }

    private var waiting: [URL] = []

    func receive(_ urls: [URL]) {
        let accepted = urls.filter { $0.scheme.map { Self.schemes.contains($0.lowercased()) } ?? false }
        guard !accepted.isEmpty else {
            return
        }
        // Never the address: only the count.
        Logger.app.info("Links from another app: \(accepted.count, privacy: .public)")
        if let handler {
            handler(accepted)
        } else {
            waiting += accepted
        }
    }
}
