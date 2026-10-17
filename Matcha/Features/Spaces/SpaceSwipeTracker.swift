import Foundation

/// Suit un glissement à deux doigts et décide quand changer de Space : une fois par geste, dès que le
/// déplacement horizontal dépasse le seuil, sauf si le geste est surtout vertical (défilement).
nonisolated struct SpaceSwipeTracker: Sendable {
    /// Déplacement horizontal, en points, qui déclenche le changement.
    static let threshold = 80.0
    /// Le geste doit être au moins autant de fois plus horizontal que vertical.
    static let horizontalDominance = 1.5

    enum Phase: Sendable {
        case began, changed, ended, cancelled
    }

    enum Direction: Equatable, Sendable {
        /// Doigts vers la gauche : le Space suivant arrive de la droite.
        case next
        case previous
    }

    private var horizontal = 0.0
    private var vertical = 0.0
    private var isTracking = false
    private var hasTriggered = false

    /// Traite un événement de défilement. `fingerDeltaX` suit le mouvement des doigts (positif vers la
    /// droite), quel que soit le réglage du défilement naturel. Renvoie un sens au plus une fois par geste.
    mutating func handle(phase: Phase, fingerDeltaX: Double, deltaY: Double) -> Direction? {
        switch phase {
        case .began:
            (horizontal, vertical, isTracking, hasTriggered) = (fingerDeltaX, abs(deltaY), true, false)
        case .changed:
            guard isTracking else {
                return nil
            }
            horizontal += fingerDeltaX
            vertical += abs(deltaY)
        case .ended, .cancelled:
            isTracking = false
            return nil
        }
        guard !hasTriggered, abs(horizontal) >= Self.threshold, abs(horizontal) >= vertical * Self.horizontalDominance else {
            return nil
        }
        hasTriggered = true
        return horizontal < 0 ? .next : .previous
    }
}
