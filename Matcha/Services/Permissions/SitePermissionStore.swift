import Foundation
import Observation
import OSLog
import SwiftData

/// Permission decisions of a session (task 5.2): the in-memory table, observed by the site settings panel and by
/// Settings, and its `SitePermissionRecord` records. A private window has no context: its decisions live in memory for
/// the lifetime of the window, and nothing is written.
@MainActor
@Observable
final class SitePermissionStore {
    private(set) var table: SitePermissionTable
    /// Store in which to remember the decisions; nil for a private window.
    @ObservationIgnored private let context: ModelContext?

    init(context: ModelContext?) {
        self.context = context
        table = SitePermissionTable(Self.load(from: context))
    }

    /// True if the decisions are saved (false for a private window).
    var isPersistent: Bool {
        context != nil
    }

    /// Remembered decisions, in the order of Settings.
    var entries: [SitePermissionEntry] {
        table.sortedEntries
    }

    func decisions(for origin: SiteOrigin, profileID: UUID?) -> [SitePermissionKind: SitePermissionDecision] {
        table.decisions(for: origin, profileID: profileID)
    }

    func decision(_ kind: SitePermissionKind, for origin: SiteOrigin, profileID: UUID?) -> SitePermissionDecision? {
        decisions(for: origin, profileID: profileID)[kind]
    }

    /// Remembers `decision` (nil: forgets it, “Ask”).
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

    /// Forgets the decisions of a deleted profile.
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
        // Few decisions: an in-memory filter is enough and avoids a predicate on an optional identifier.
        let records = (try? context.fetch(FetchDescriptor<SitePermissionRecord>(sortBy: [SortDescriptor(\.date, order: .reverse)]))) ?? []
        return records.filter { $0.profileID == profileID && $0.originKey == origin.key && $0.kindValue == kind.rawValue }
    }

    private func save(_ context: ModelContext) {
        do {
            try context.save()
        } catch {
            Logger.permissions.error("Décision non enregistrée : \(error.logSummary, privacy: .public)")
        }
    }

    /// Readable records; an unknown origin, permission or decision is ignored.
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

/// Decisions seen by the pages of a profile: those of a Space, of its Peek or of a mini window.
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
