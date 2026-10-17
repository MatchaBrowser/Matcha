import Foundation

/// Fréquence et récence d'une adresse de l'historique, en entiers, à la manière de Firefox.
nonisolated enum Frecency {
    /// Au-delà, les visites ne comptent plus.
    static let maximumVisits = 30

    /// Poids de la dernière visite selon son âge (bornes incluses) : 100 jusqu'à 4 jours, 70 jusqu'à
    /// 14, 50 jusqu'à 31, 30 jusqu'à 90, puis 10. Un âge négatif compte comme nul.
    static func recencyWeight(age: TimeInterval) -> Int {
        let day: TimeInterval = 86400
        switch max(0, age) {
        case ...(4 * day): return 100
        case ...(14 * day): return 70
        case ...(31 * day): return 50
        case ...(90 * day): return 30
        default: return 10
        }
    }

    /// Poids de récence multiplié par le nombre de visites (au moins 1, au plus 30).
    static func score(visitCount: Int, lastVisit: Date, now: Date) -> Int {
        recencyWeight(age: now.timeIntervalSince(lastVisit)) * min(max(visitCount, 1), maximumVisits)
    }
}
