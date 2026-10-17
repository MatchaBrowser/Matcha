import Foundation

/// Historique de navigation dans la barre de commande, lu dans `HistorySource` (tâche 5.5). Rien sans
/// source ni dans une fenêtre privée.
@MainActor
final class HistoryProvider: CommandProvider {
    /// Adresses demandées à la source : de quoi classer, y compris de façon approximative.
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
