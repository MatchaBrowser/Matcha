import Foundation
import OSLog
import SwiftData

/// Deletion in the history: chosen visits, a period, a whole profile.
extension HistoryStore {
    /// Identifiers passed to the database in batches: a single predicate with tens of thousands of values would
    /// exceed SQLite's limits.
    private static let deletionBatchSize = 500

    /// Deletes these visits from the profile (rows of the history window).
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

    /// “Clear History…”: the profile's visits made during `period`.
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

    /// Deleted profile: its whole history.
    func removeAll(profileID: UUID?) {
        clear(.allHistory, profileID: profileID)
    }
}
