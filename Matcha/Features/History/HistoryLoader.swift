import Foundation
import OSLog
import SwiftData

/// Reads the saved history off the main thread: a year of browsing can amount to tens of thousands of visits
/// (≈ 1.5 s for 100,000 in Debug, measured), not to be read during a keystroke.
nonisolated enum HistoryLoader {
    /// Erases the visits older than `cutoff` (retention period), then reads the others into an index per profile.
    /// A separate context, created and used here with no suspension point: it never changes threads.
    @concurrent
    static func load(from container: ModelContainer, purgingBefore cutoff: Date) async -> [UUID?: HistoryIndex] {
        let context = ModelContext(container)
        do {
            try context.delete(model: HistoryRecord.self, where: #Predicate { $0.visitDate < cutoff })
            try context.save()
        } catch {
            Logger.history.error("Visites anciennes non effacées : \(error.logSummary, privacy: .public)")
        }
        let records: [HistoryRecord]
        do {
            records = try context.fetch(FetchDescriptor<HistoryRecord>())
        } catch {
            Logger.history.error("Historique illisible : \(error.logSummary, privacy: .public)")
            return [:]
        }
        var visits: [UUID?: [HistoryVisit]] = [:]
        for record in records {
            guard let url = record.url else {
                continue
            }
            let key = record.urlKey.isEmpty ? nil : record.urlKey
            visits[record.profileID, default: []].append(
                HistoryVisit(id: record.id, url: url, urlKey: key, title: record.title, date: record.visitDate),
            )
        }
        Logger.history.info("Historique lu : \(records.count, privacy: .public) visites")
        return visits.mapValues { HistoryIndex(visits: $0) }
    }
}
