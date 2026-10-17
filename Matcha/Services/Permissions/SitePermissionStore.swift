import Foundation
import Observation
import OSLog
import SwiftData

/// Décisions de permission d'une session (tâche 5.2) : la table en mémoire, observée par le panneau des réglages du
/// site et par les Réglages, et ses enregistrements `SitePermissionRecord`. Une fenêtre privée n'a pas de contexte :
/// ses décisions vivent en mémoire, le temps de la fenêtre, et rien n'est écrit.
@MainActor
@Observable
final class SitePermissionStore {
    private(set) var table: SitePermissionTable
    /// Base où retenir les décisions ; nil pour une fenêtre privée.
    @ObservationIgnored private let context: ModelContext?

    init(context: ModelContext?) {
        self.context = context
        table = SitePermissionTable(Self.load(from: context))
    }

    /// Vrai si les décisions sont enregistrées (faux pour une fenêtre privée).
    var isPersistent: Bool {
        context != nil
    }

    /// Décisions retenues, dans l'ordre des Réglages.
    var entries: [SitePermissionEntry] {
        table.sortedEntries
    }

    func decisions(for origin: SiteOrigin, profileID: UUID?) -> [SitePermissionKind: SitePermissionDecision] {
        table.decisions(for: origin, profileID: profileID)
    }

    func decision(_ kind: SitePermissionKind, for origin: SiteOrigin, profileID: UUID?) -> SitePermissionDecision? {
        decisions(for: origin, profileID: profileID)[kind]
    }

    /// Retient `decision` (nil : l'oublie, « Demander »).
    func set(_ decision: SitePermissionDecision?, for kind: SitePermissionKind, origin: SiteOrigin, profileID: UUID?) {
        let date = Date.now
        table.set(decision, for: kind, origin: origin, profileID: profileID, date: date)
        let value = decision?.rawValue ?? "ask"
        Logger.permissions
            .info("\(kind.rawValue, privacy: .public) : \(value, privacy: .public) pour \(origin.displayHost, privacy: .private)")
        guard let context else {
            return
        }
        let records = matchingRecords(profileID: profileID, origin: origin, kind: kind, in: context)
        if let decision, let record = records.first {
            record.decisionValue = decision.rawValue
            record.date = date
            records.dropFirst().forEach(context.delete)
        } else {
            records.forEach(context.delete)
            if let decision {
                context.insert(SitePermissionRecord(
                    profileID: profileID,
                    originKey: origin.key,
                    kind: kind,
                    decision: decision,
                    date: date,
                ))
            }
        }
        save(context)
    }

    func remove(_ entry: SitePermissionEntry) {
        set(nil, for: entry.kind, origin: entry.origin, profileID: entry.profileID)
    }

    /// Oublie les décisions d'un profil supprimé.
    func removeAll(profileID: UUID) {
        table.removeAll(profileID: profileID)
        guard let context else {
            return
        }
        let records = (try? context.fetch(FetchDescriptor<SitePermissionRecord>())) ?? []
        records.filter { $0.profileID == profileID }.forEach(context.delete)
        save(context)
    }

    private func matchingRecords(
        profileID: UUID?,
        origin: SiteOrigin,
        kind: SitePermissionKind,
        in context: ModelContext,
    ) -> [SitePermissionRecord] {
        // Peu de décisions : un filtre en mémoire suffit et évite un prédicat sur un identifiant optionnel.
        let records = (try? context.fetch(FetchDescriptor<SitePermissionRecord>(sortBy: [SortDescriptor(\.date, order: .reverse)]))) ?? []
        return records.filter { $0.profileID == profileID && $0.originKey == origin.key && $0.kindValue == kind.rawValue }
    }

    private func save(_ context: ModelContext) {
        do {
            try context.save()
        } catch {
            Logger.permissions.error("Décision non enregistrée : \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Enregistrements lisibles ; une origine, une permission ou une décision inconnue est ignorée.
    private static func load(from context: ModelContext?) -> [SitePermissionEntry] {
        guard let context else {
            return []
        }
        let records = (try? context.fetch(FetchDescriptor<SitePermissionRecord>())) ?? []
        return records.compactMap { record in
            guard let origin = SiteOrigin(key: record.originKey),
                  let kind = SitePermissionKind(rawValue: record.kindValue),
                  let decision = SitePermissionDecision(rawValue: record.decisionValue)
            else {
                Logger.permissions.notice("Décision enregistrée illisible, ignorée")
                return nil
            }
            return SitePermissionEntry(
                key: .init(profileID: record.profileID, origin: origin, kind: kind),
                decision: decision,
                date: record.date,
            )
        }
    }
}

/// Décisions vues par les pages d'un profil : celles d'un Space, de son aperçu ou d'une mini-fenêtre.
struct SitePermissionScope {
    let store: SitePermissionStore
    let profileID: UUID?

    func decisions(for origin: SiteOrigin) -> [SitePermissionKind: SitePermissionDecision] {
        store.decisions(for: origin, profileID: profileID)
    }

    func decision(_ kind: SitePermissionKind, for origin: SiteOrigin) -> SitePermissionDecision? {
        store.decision(kind, for: origin, profileID: profileID)
    }

    func set(_ decision: SitePermissionDecision?, for kind: SitePermissionKind, origin: SiteOrigin) {
        store.set(decision, for: kind, origin: origin, profileID: profileID)
    }
}
