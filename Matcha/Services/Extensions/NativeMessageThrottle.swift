import Foundation

/// Espace les réponses aux messages natifs d'une extension (`runtime.sendNativeMessage`, refusés par Matcha) : une par
/// intervalle et par extension. Un message isolé reçoit sa réponse tout de suite ; une extension qui en envoie en
/// boucle (Bitwarden attend de son app une réponse différée à « sleep », puis recommence) est ralentie au lieu
/// d'occuper le processeur. Type pur.
nonisolated struct NativeMessageThrottle {
    static let interval = Duration.seconds(1)

    private var nextReply: [String: ContinuousClock.Instant] = [:]

    /// Délai avant de répondre au message que l'extension `identifier` envoie à `now`.
    mutating func delay(for identifier: String, at now: ContinuousClock.Instant) -> Duration {
        let reply = max(now, nextReply[identifier] ?? now)
        nextReply[identifier] = reply + Self.interval
        return reply - now
    }
}
