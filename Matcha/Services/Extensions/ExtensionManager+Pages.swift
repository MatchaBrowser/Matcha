import Foundation
import OSLog
import WebKit

/// Pages of the extensions and requests to the user (task 6.3).
extension ExtensionManager {
    /// Configuration of an extension page (`webkit-extension:`) opened in a tab or a mini window: that of its extension
    /// (otherwise WebKit refuses the navigation), with a per-page content controller (task 6.2); nil for another
    /// address or an extension that is not loaded.
    func pageConfiguration(for url: URL) -> WKWebViewConfiguration? {
        guard Self.isExtensionURL(url), let configuration = context(for: url)?.webViewConfiguration else {
            return nil
        }
        configuration.userContentController = WebConfigurationFactory.makeUserContentController()
        return configuration
    }

    /// Name of the extension for the user.
    func displayName(of context: WKWebExtensionContext) -> String {
        context.webExtension.displayName ?? context.uniqueIdentifier
    }

    /// Asks the user (`permissionPrompter`); an empty request is denied without showing anything.
    func ask(_ request: ExtensionPermissionRequest, for context: WKWebExtensionContext, completion: @escaping @MainActor (Bool) -> Void) {
        let key = ObjectIdentifier(context)
        guard !request.isEmpty, !promptingContexts.contains(key) else {
            completion(false)
            return
        }
        promptingContexts.insert(key)
        permissionPrompter.ask(request) { [weak self] allowed in
            self?.promptingContexts.remove(key)
            Logger.extensions.info("Permission request \(allowed ? "granted" : "denied", privacy: .public)")
            completion(allowed)
        }
    }

    /// The user removes an extension's access to a website (Settings): it may ask again.
    func revokeSite(_ pattern: String, identifier: String) {
        if let context = contexts[identifier], let matchPattern = try? WKWebExtension.MatchPattern(string: pattern) {
            context.setPermissionStatus(.unknown, for: matchPattern)
            saveState(of: context, identifier: identifier)
        } else if var state = store.state(for: identifier) {
            state.grantedMatchPatterns[pattern] = nil
            store.setState(state, for: identifier)
        }
    }
}
