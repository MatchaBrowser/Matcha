import Foundation

/// Horloge hybride de la synchro (tâche 7.4, `SYNC.md` § 2.2) : chaque modification écrite ici est datée après tout ce
/// que ce Mac a déjà écrit ou reçu, même si son horloge retarde. À la milliseconde. Type pur.
nonisolated struct SyncClock: Codable, Equatable, Sendable {
    /// Plus grande date écrite ou reçue, en millisecondes depuis 1970.
    private(set) var latest: Int64 = 0

    /// Date d'une nouvelle modification : l'heure du Mac, ou 1 ms après la plus grande date connue.
    mutating func next(now: Date = .now) -> Date {
        latest = max(SyncCoding.milliseconds(of: now), latest + 1)
        return SyncCoding.date(milliseconds: latest)
    }

    /// Date d'une modification reçue.
    mutating func observe(_ date: Date) {
        latest = max(latest, SyncCoding.milliseconds(of: date))
    }
}
