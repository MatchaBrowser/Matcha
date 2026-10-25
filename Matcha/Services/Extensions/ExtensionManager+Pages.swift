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

    /// Asks the user (`permissionPrompter`); an empty request, or one made while another of the same extension waits,
    /// isn't shown: `notAsked`, never remembered as a refusal (review EX6).
    func ask(
        _ request: ExtensionPermissionRequest,
        for context: WKWebExtensionContext,
        completion: @escaping @MainActor (ExtensionPermissionAnswer) -> Void,
    ) {
        let key = ObjectIdentifier(context)
        guard !request.isEmpty, !promptingContexts.contains(key) else {
            completion(.notAsked)
            return
        }
        promptingContexts.insert(key)
        permissionPrompter.ask(request) { [weak self] answer in
            self?.promptingContexts.remove(key)
            Logger.extensions.info("Permission request: \(String(describing: answer), privacy: .public)")
            completion(answer)
        }
    }

    /// The user removes an extension's access to a website (Settings): it may ask again, and no update grants it back
    /// by itself (review EX3).
    func revokeSite(_ pattern: String, identifier: String) {
        if var state = store.state(for: identifier) {
            state.revokedMatchPatterns.insert(pattern)
            store.setState(state, for: identifier)
        }
        if let context = contexts[identifier], let matchPattern = try? WKWebExtension.MatchPattern(string: pattern) {
            context.setPermissionStatus(.unknown, for: matchPattern)
            saveState(of: context, identifier: identifier)
        } else if var state = store.state(for: identifier) {
            state.grantedMatchPatterns[pattern] = nil
            store.setState(state, for: identifier)
        }
    }
}
