import Foundation

/// Spaces out the answers to an extension's native messages (`runtime.sendNativeMessage`, refused by Matcha): one per
/// interval and per extension. An isolated message gets its answer right away; an extension that sends them in a loop
/// (Bitwarden expects a delayed answer to “sleep” from its app, then starts again) is slowed down instead of keeping
/// the processor busy. Pure type.
nonisolated struct NativeMessageThrottle {
    static let interval = Duration.seconds(1)

    private var nextReply: [String: ContinuousClock.Instant] = [:]

    /// Delay before answering the message that extension `identifier` sends at `now`.
    mutating func delay(for identifier: String, at now: ContinuousClock.Instant) -> Duration {
        let reply = max(now, nextReply[identifier] ?? now)
        nextReply[identifier] = reply + Self.interval
        return reply - now
    }
}
