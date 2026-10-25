import Foundation

/// Requests an extension makes while running (audit E5): a refusal shown to the user is remembered for
/// `denialDuration`, during which WebKit answers no without asking; an extension has at most one request waiting for
/// the user, the others (and a request without a window to show it) get “not asked”, never remembered
/// (`ExtensionPermissionAnswer`, review EX6). Pure type.
nonisolated enum ExtensionPromptPolicy {
    static let denialDuration: TimeInterval = 24 * 60 * 60

    static func denialExpiration(from date: Date) -> Date {
        date.addingTimeInterval(denialDuration)
    }
}
