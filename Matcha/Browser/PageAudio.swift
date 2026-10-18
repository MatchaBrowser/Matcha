import Foundation
import Observation

/// Son d'une page (onglet, aperçu, mini-fenêtre, fenêtre de connexion ; tâche 5.10) : reçoit les messages de son script
/// (`PageAudioMessageHandler`) et tient l'icône haut-parleur de la barre latérale (`isPlaying`), suivant les règles de
/// `PageAudioState`. Seule une page rangée dans la barre montre l'icône ; l'aperçu ouvert en onglet garde son état.
@MainActor
@Observable
final class PageAudio {
    /// Vrai pendant que la page joue un son, et encore `silenceDelay` après.
    private(set) var isPlaying = false
    @ObservationIgnored private var state = PageAudioState()
    /// Extinction prévue de l'icône.
    @ObservationIgnored private var expiry: Task<Void, Never>?

    /// Délai entre la fin du dernier son et l'extinction de l'icône (2 s) ; changé dans les tests.
    var silenceDelay: TimeInterval {
        get { state.silenceDelay }
        set { state.silenceDelay = newValue }
    }

    func receive(_ report: PageAudioReport) {
        state.apply(report, at: .now)
        publish()
    }

    /// Tout le son de la page vient d'être mis en pause, ou la page a changé (navigation, mise en veille, arrêt du
    /// processus, vue web libérée) : l'icône s'éteint tout de suite. Si la page rejoue un son, son script le redit.
    func reset() {
        state.reset()
        publish()
    }

    /// Recopie l'état (la valeur observée n'est écrite que si elle change) et prévoit l'extinction de l'icône.
    private func publish() {
        if isPlaying != state.isPlaying {
            isPlaying = state.isPlaying
        }
        expiry?.cancel()
        expiry = nil
        guard let deadline = state.silenceDeadline else {
            return
        }
        let delay = max(0, deadline.timeIntervalSinceNow)
        expiry = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else {
                return
            }
            // L'échéance n'a pas changé (sinon cette tâche aurait été annulée) : l'horloge ne la manque pas d'un poil.
            state.expire(at: max(.now, deadline))
            publish()
        }
    }
}
