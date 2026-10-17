import Foundation

/// Source de résultats de la barre de commande. Elle renvoie large : `CommandRanker` fait seul la
/// correspondance avec le texte. Jamais appelée pour un texte vide ni pour l'adresse de ⌘L non modifiée.
/// Une tâche annulée revient vite, éventuellement avec [] (le modèle ignore alors son résultat).
@MainActor
protocol CommandProvider: AnyObject {
    func candidates(for query: CommandQuery, context: CommandContext) async -> [CommandCandidate]
}

/// Adresse de l'historique, toutes visites regroupées.
nonisolated struct HistoryEntry: Equatable, Sendable {
    let url: URL
    /// Dernier titre non vide connu de la page.
    let title: String?
    let visitCount: Int
    let lastVisit: Date
}

/// Historique vu par la barre (tâche 5.5) : adresses regroupées par URL, au plus `limit`,
/// un sur-ensemble de ce qui correspond à `query`. Jamais lu pour une session privée.
@MainActor
protocol HistorySource: AnyObject {
    func entries(matching query: CommandQuery, limit: Int) async -> [HistoryEntry]
}
