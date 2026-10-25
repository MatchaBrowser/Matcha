import Foundation

/// Requests an extension makes while running (audit E5): a refusal is remembered for `denialDuration`, during which
/// WebKit answers no without asking; an extension has at most one request waiting for the user, the others are refused
/// (not remembered). Pure type.
nonisolated enum ExtensionPromptPolicy {
    static let denialDuration: TimeInterval = 24 * 60 * 60

    static func denialExpiration(from date: Date) -> Date {
        date.addingTimeInterval(denialDuration)
    }
}
