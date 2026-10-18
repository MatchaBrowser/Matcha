import Foundation

/// Son d'une page (tâche 5.10), d'après les messages de son script (`PageAudioReport`). L'icône haut-parleur s'allume dès
/// qu'un document de la page (cadre principal ou iframe) joue un son, et s'éteint `silenceDelay` (2 s) après le dernier :
/// pas de clignotement entre deux morceaux, une publicité et la vidéo, ou pendant un changement de source (comme Chrome).
/// Elle s'éteint tout de suite (`reset`) quand l'utilisateur met la page en pause, quand la page change (navigation),
/// est mise en veille ou que son processus s'arrête.
nonisolated struct PageAudioState: Equatable, Sendable {
    static let defaultSilenceDelay: TimeInterval = 2

    /// Délai entre la fin du dernier son et l'extinction de l'icône ; changé dans les tests.
    var silenceDelay = defaultSilenceDelay
    /// Documents qui jouent un son.
    private(set) var audibleFrames: Set<String> = []
    /// Icône affichée.
    private(set) var isPlaying = false
    /// Moment où le dernier son s'est arrêté, tant que l'icône reste allumée.
    private(set) var silentSince: Date?

    /// Moment où l'icône doit s'éteindre ; nil si rien n'est prévu.
    var silenceDeadline: Date? {
        silentSince.map { $0.addingTimeInterval(silenceDelay) }
    }

    /// Un document prévient qu'il joue un son, qu'il n'en joue plus ou qu'il s'en va.
    mutating func apply(_ report: PageAudioReport, at date: Date) {
        if report.isAudible, !report.isGone {
            audibleFrames.insert(report.frame)
        } else {
            audibleFrames.remove(report.frame)
        }
        if !audibleFrames.isEmpty {
            isPlaying = true
            silentSince = nil
        } else if isPlaying, silentSince == nil {
            silentSince = date
        }
    }

    /// L'icône s'éteint si plus rien ne joue depuis `silenceDelay` à `date`.
    mutating func expire(at date: Date) {
        guard let silenceDeadline, date >= silenceDeadline else {
            return
        }
        isPlaying = false
        silentSince = nil
    }

    /// Plus aucun son : tout est en pause, ou la page a changé. Un document qui rejoue un son le redit.
    mutating func reset() {
        audibleFrames = []
        isPlaying = false
        silentSince = nil
    }
}
