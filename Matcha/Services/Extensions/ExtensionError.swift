import Foundation

/// Errors returned to extensions and to callers of `ExtensionManager` (task 6.3). Their text, in English, is read by
/// extension developers (console, rejected promise), like WebKit's messages: it is not translated.
nonisolated enum ExtensionError: Error, Equatable, LocalizedError {
    /// Matcha does not do this (closing a browser window, private window requested by an extension…).
    case unsupported(String)
    /// The targeted tab or window no longer exists.
    case notFound
    /// No browser window open to put a tab in.
    case noBrowserWindow
    /// Invalid extension identifier (`ExtensionInstallDirectory.isValidIdentifier`).
    case invalidIdentifier(String)
    /// An extension with the same identifier is already loaded.
    case alreadyLoaded(String)
    /// No extension installed under this identifier (folder missing, app deleted).
    case notInstalled(String)
    /// Messages to an extension's app (`runtime.sendNativeMessage`, `connectNative`).
    case nativeMessagingUnsupported
    /// An address an extension may not open (`ExtensionURLPolicy`): local file, `data:`, another extension's page…
    case forbiddenURL
    /// An app's Safari extension whose signed identity changed since its installation (audit E7).
    case identityChanged(String)

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
        case .forbiddenURL:
            "Extensions can only open web pages, about:blank and their own pages."
        case let .identityChanged(identifier):
            "The Safari extension \(identifier) is no longer signed by the developer it was installed from."
        }
    }
}
