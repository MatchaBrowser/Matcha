import Foundation
import WebKit

/// Passage entre l'état retenu d'une extension et son contexte WebKit (tâche 6.3).
extension ExtensionState {
    /// Décisions actuelles de `context`.
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

    /// Remet ces décisions dans `context` (avant son chargement), sans celles expirées ; un motif illisible est ignoré.
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

    /// Clés en texte ; pour deux clés de même texte, l'expiration la plus lointaine.
    private static func texts<Key>(_ dictionary: [Key: Date], _ text: (Key) -> String) -> [String: Date] {
        Dictionary(dictionary.map { (text($0.key), $0.value) }, uniquingKeysWith: max)
    }

    private static func values<Key: Hashable>(_ dictionary: [String: Date], _ key: (String) -> Key?) -> [Key: Date] {
        Dictionary(dictionary.compactMap { entry in key(entry.key).map { ($0, entry.value) } }, uniquingKeysWith: max)
    }
}
