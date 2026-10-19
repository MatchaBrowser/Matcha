import Foundation
import WebKit

/// Conversion between the remembered state of an extension and its WebKit context (task 6.3).
extension ExtensionState {
    /// Current decisions of `context`.
    @MainActor
    init(context: WKWebExtensionContext, isEnabled: Bool) {
        self.isEnabled = isEnabled
        grantedPermissions = Self.texts(context.grantedPermissions, \.rawValue)
        deniedPermissions = Self.texts(context.deniedPermissions, \.rawValue)
        grantedMatchPatterns = Self.texts(context.grantedPermissionMatchPatterns, \.string)
        deniedMatchPatterns = Self.texts(context.deniedPermissionMatchPatterns, \.string)
        hasAccessToPrivateData = context.hasAccessToPrivateData
        hasRequestedOptionalAccessToAllHosts = context.hasRequestedOptionalAccessToAllHosts
    }

    /// Puts these decisions back into `context` (before it is loaded), without the expired ones; an unreadable pattern
    /// is ignored.
    @MainActor
    func apply(to context: WKWebExtensionContext, now: Date = .now) {
        let state = removingExpired(at: now)
        context.grantedPermissions = Self.values(state.grantedPermissions) { WKWebExtension.Permission(rawValue: $0) }
        context.deniedPermissions = Self.values(state.deniedPermissions) { WKWebExtension.Permission(rawValue: $0) }
        context.grantedPermissionMatchPatterns = Self.values(state.grantedMatchPatterns) { try? WKWebExtension.MatchPattern(string: $0) }
        context.deniedPermissionMatchPatterns = Self.values(state.deniedMatchPatterns) { try? WKWebExtension.MatchPattern(string: $0) }
        context.hasAccessToPrivateData = state.hasAccessToPrivateData
        context.hasRequestedOptionalAccessToAllHosts = state.hasRequestedOptionalAccessToAllHosts
    }

    /// Keys as text; for two keys with the same text, the most distant expiration.
    private static func texts<Key>(_ dictionary: [Key: Date], _ text: (Key) -> String) -> [String: Date] {
        Dictionary(dictionary.map { (text($0.key), $0.value) }, uniquingKeysWith: max)
    }

    private static func values<Key: Hashable>(_ dictionary: [String: Date], _ key: (String) -> Key?) -> [Key: Date] {
        Dictionary(dictionary.compactMap { entry in key(entry.key).map { ($0, entry.value) } }, uniquingKeysWith: max)
    }
}
