import Foundation

/// Asks the user what an extension requests while running (task 6.3). A single answer, and true only if the user
/// accepts: nothing is ever granted automatically. The app's is an alert (`ExtensionPermissionAlert`); replaced in the
/// tests.
@MainActor
protocol ExtensionPermissionPrompting: AnyObject {
    func ask(_ request: ExtensionPermissionRequest, completion: @escaping @MainActor (Bool) -> Void)
}

/// Nobody to ask (no interface): every request is denied.
@MainActor
final class RefusingPermissionPrompter: ExtensionPermissionPrompting {
    func ask(_: ExtensionPermissionRequest, completion: @escaping @MainActor (Bool) -> Void) {
        completion(false)
    }
}
