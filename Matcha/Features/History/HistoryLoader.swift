import Foundation
import OSLog
import SwiftData

/// Lecture de l'historique enregistré, hors du fil principal : un an de navigation peut compter des dizaines de
/// milliers de visites (≈ 1,5 s pour 100 000 en Debug, mesuré), à ne pas lire pendant une frappe.
nonisolated enum HistoryLoader {
    /// Efface les visites antérieures à `cutoff` (durée de conservation), puis lit les autres, en index par profil.
    /// Un contexte à part, créé et utilisé ici sans point de suspension : il ne change jamais de fil.
    @concurrent
    static func load(from container: ModelContainer, purgingBefore cutoff: Date) async -> [UUID?: HistoryIndex] {
        let context = ModelContext(container)
        do {
            try context.delete(model: HistoryRecord.self, where: #Predicate { $0.visitDate < cutoff })
            try context.save()
        } catch {
            Logger.history.error("Visites anciennes non effacées : \(error.localizedDescription, privacy: .public)")
        }
        let records: [HistoryRecord]
        do {
            records = try context.fetch(FetchDescriptor<HistoryRecord>())
        } catch {
            Logger.history.error("Historique illisible : \(error.localizedDescription, privacy: .public)")
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
