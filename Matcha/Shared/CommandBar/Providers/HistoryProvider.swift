import Foundation

/// Browsing history in the command bar, read from `HistorySource` (task 5.5). Nothing without a source or in a
/// private window.
@MainActor
final class HistoryProvider: CommandProvider {
    /// Addresses requested from the source: enough to rank, including approximately.
    static let fetchLimit = 300

    private let source: (any HistorySource)?

    init(source: (any HistorySource)?) {
        self.source = source
    }

    func candidates(for query: CommandQuery, context: CommandContext) async -> [CommandCandidate] {
        guard let source, !context.isPrivate else {
            return []
        }
        let entries = await source.entries(matching: query, limit: Self.fetchLimit)
        return entries.map { entry in
            let title = entry.title.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
            return CommandCandidate(
                kind: .history(visitCount: entry.visitCount, lastVisit: entry.lastVisit),
                title: title ?? CommandText.displayURL(entry.url),
                url: entry.url,
            )
        }
    }
}
