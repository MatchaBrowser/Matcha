import Foundation
import OSLog
import SwiftData

/// Suppression dans l'historique : des visites choisies, une période, tout un profil.
extension HistoryStore {
    /// Identifiants passés à la base par lots : un seul prédicat avec des dizaines de milliers de valeurs dépasserait
    /// les limites de SQLite.
    private static let deletionBatchSize = 500

    /// Supprime ces visites du profil (lignes de la fenêtre de l'historique).
    func deleteVisits(_ ids: Set<UUID>, profileID: UUID?) {
        guard !ids.isEmpty else {
            return
        }
        forgetRecentRecords()
        let all = Array(ids)
        for start in stride(from: 0, to: all.count, by: Self.deletionBatchSize) {
            let batch = Array(all[start ..< min(start + Self.deletionBatchSize, all.count)])
            deleteRecords(where: #Predicate { batch.contains($0.id) })
        }
        save()
        apply(.remove(ids, profileID: profileID))
        Logger.history.info("\(ids.count, privacy: .public) visites supprimées")
    }

    /// « Effacer l'historique… » : les visites du profil faites pendant `period`.
    func clear(_ period: HistoryPeriod, profileID: UUID?) {
        forgetRecentRecords()
        let start = period.start(now: now(), calendar: calendar)
        if let start {
            deleteRecords(where: #Predicate { $0.profileID == profileID && $0.visitDate >= start })
        } else {
            deleteRecords(where: #Predicate { $0.profileID == profileID })
        }
        save()
        apply(.removeSince(start, profileID: profileID))
        Logger.history.info("Historique effacé (\(period.rawValue, privacy: .public))")
    }

    /// Profil supprimé : tout son historique.
    func removeAll(profileID: UUID?) {
        clear(.allHistory, profileID: profileID)
    }
}
