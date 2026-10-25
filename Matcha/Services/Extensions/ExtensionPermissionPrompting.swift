import Foundation

/// The user's answer to what an extension requests while running (review EX6): only a refusal seen by the user is
/// remembered; a request that couldn't be shown (another one waiting, no window) asks again next time.
nonisolated enum ExtensionPermissionAnswer: Equatable, Sendable {
    case allowed
    case denied
    case notAsked
}

/// Asks the user what an extension requests while running (task 6.3). A single answer, and `allowed` only if the user
/// accepts: nothing is ever granted automatically. The app's is an alert (`ExtensionPermissionAlert`); replaced in the
/// tests.
@MainActor
protocol ExtensionPermissionPrompting: AnyObject {
    func ask(_ request: ExtensionPermissionRequest, completion: @escaping @MainActor (ExtensionPermissionAnswer) -> Void)
}

/// Nobody to ask (no interface): every request goes unanswered, never remembered as a refusal.
@MainActor
final class RefusingPermissionPrompter: ExtensionPermissionPrompting {
    func ask(_: ExtensionPermissionRequest, completion: @escaping @MainActor (ExtensionPermissionAnswer) -> Void) {
        completion(.notAsked)
    }
}
