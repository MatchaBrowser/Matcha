import Foundation

/// Changement de l'historique, appliqué aux index des profils (`HistoryStore`). Ceux faits pendant le chargement
/// sont rejoués ensuite : ils sont idempotents (`HistoryIndex`), qu'ils soient déjà dans ce qui a été lu ou non.
nonisolated enum HistoryChange: Equatable, Sendable {
    case insert(HistoryVisit, profileID: UUID?)
    case setTitle(String?, visitID: UUID, profileID: UUID?)
    case refresh(visitID: UUID, date: Date, title: String?, profileID: UUID?)
    case remove(Set<UUID>, profileID: UUID?)
    /// Visites faites depuis cette date ; nil : tout l'historique du profil.
    case removeSince(Date?, profileID: UUID?)

    func apply(to indexes: inout [UUID?: HistoryIndex]) {
        switch self {
        case let .insert(visit, profileID):
            indexes[profileID, default: HistoryIndex()].insert(visit)
        case let .setTitle(title, visitID, profileID):
            indexes[profileID]?.setTitle(title, ofVisit: visitID)
        case let .refresh(visitID, date, title, profileID):
            indexes[profileID]?.refresh(visit: visitID, date: date, title: title)
        case let .remove(ids, profileID):
            indexes[profileID]?.remove(ids)
        case let .removeSince(start, profileID):
            if let start {
                indexes[profileID]?.remove(since: start)
            } else {
                indexes[profileID] = nil
            }
        }
        if let index = indexes[profileID], index.isEmpty {
            indexes[profileID] = nil
        }
    }

    private var profileID: UUID? {
        switch self {
        case let .insert(_, profileID): profileID
        case let .setTitle(_, _, profileID): profileID
        case let .refresh(_, _, _, profileID): profileID
        case let .remove(_, profileID): profileID
        case let .removeSince(_, profileID): profileID
        }
    }
}
