import Foundation

/// A history change, applied to the profiles' indexes (`HistoryStore`). Changes made during loading are replayed
/// afterwards: they are idempotent (`HistoryIndex`), whether or not they are already in what was read.
nonisolated enum HistoryChange: Equatable, Sendable {
    case insert(HistoryVisit, profileID: UUID?)
    case setTitle(String?, visitID: UUID, profileID: UUID?)
    case refresh(visitID: UUID, date: Date, title: String?, profileID: UUID?)
    case remove(Set<UUID>, profileID: UUID?)
    /// Visits made since this date; nil: the profile's whole history.
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
