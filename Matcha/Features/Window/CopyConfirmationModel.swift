import Foundation
import Observation

/// Confirmation « URL copiée » d'une fenêtre : visible 1,5 s après chaque copie. Une nouvelle copie
/// pendant l'affichage relance l'attente ; la fermeture de la fenêtre l'annule.
@MainActor
@Observable
final class CopyConfirmationModel {
    typealias Sleep = @MainActor (Duration) async throws -> Void

    /// Durée d'affichage, fondus non compris.
    nonisolated static let displayDuration = Duration.milliseconds(1500)

    private(set) var isVisible = false
    /// Copies confirmées : chacune est annoncée à VoiceOver, même confirmation déjà visible.
    private(set) var presentationCount = 0

    @ObservationIgnored private let sleep: Sleep
    @ObservationIgnored private var hideTask: Task<Void, Never>?

    /// `sleep` est remplacé dans les tests.
    init(sleep: @escaping Sleep = { try await Task.sleep(for: $0) }) {
        self.sleep = sleep
    }

    /// Affiche la confirmation et relance l'attente avant de la masquer.
    func show() {
        hideTask?.cancel()
        isVisible = true
        presentationCount += 1
        let sleep = sleep
        hideTask = Task { [weak self] in
            do {
                try await sleep(Self.displayDuration)
            } catch {
                // Annulée : copie plus récente ou fenêtre fermée.
                return
            }
            // Une attente qui ignore l'annulation ne doit pas masquer la confirmation suivante.
            guard !Task.isCancelled, let self else {
                return
            }
            isVisible = false
            hideTask = nil
        }
    }

    /// Fenêtre fermée : masque aussitôt et arrête l'attente.
    func cancel() {
        hideTask?.cancel()
        hideTask = nil
        isVisible = false
    }
}
