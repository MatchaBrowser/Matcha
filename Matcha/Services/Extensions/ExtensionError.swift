import Foundation

/// Erreurs rendues aux extensions et aux appelants de `ExtensionManager` (tâche 6.3). Leur texte, en anglais, est lu
/// par les développeurs d'extensions (console, promesse rejetée), comme les messages de WebKit : il n'est pas traduit.
nonisolated enum ExtensionError: Error, Equatable, LocalizedError {
    /// Matcha ne fait pas cela (fermer une fenêtre de navigation, fenêtre privée demandée par une extension…).
    case unsupported(String)
    /// L'onglet ou la fenêtre visés n'existent plus.
    case notFound
    /// Aucune fenêtre de navigation ouverte où mettre un onglet.
    case noBrowserWindow
    /// Identifiant d'extension invalide (`ExtensionInstallDirectory.isValidIdentifier`).
    case invalidIdentifier(String)
    /// Une extension de même identifiant est déjà chargée.
    case alreadyLoaded(String)
    /// Aucune extension installée sous cet identifiant (dossier absent, app supprimée).
    case notInstalled(String)
    /// Messages vers l'app d'une extension (`runtime.sendNativeMessage`, `connectNative`).
    case nativeMessagingUnsupported

    var errorDescription: String? {
        switch self {
        case let .unsupported(message):
            message
        case .notFound:
            "The tab or window no longer exists."
        case .noBrowserWindow:
            "No browser window is open."
        case let .invalidIdentifier(identifier):
            "Invalid extension identifier: \(identifier)"
        case let .alreadyLoaded(identifier):
            "An extension with identifier \(identifier) is already loaded."
        case let .notInstalled(identifier):
            "No extension is installed with identifier \(identifier)."
        case .nativeMessagingUnsupported:
            "Native messaging is not supported in Matcha."
        }
    }
}
