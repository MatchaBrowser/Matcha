import WebKit

/// Fabrique la configuration WebKit commune à toutes les vues web, avec le script de son (tâche 5.10).
/// Plus tard, le bloqueur, les Boosts et les extensions s'y brancheront.
@MainActor
enum WebConfigurationFactory {
    /// Version de Safari annoncée aux sites, pour qu'ils traitent l'app comme Safari.
    /// À tenir à jour avec la version de Safari livrée avec macOS.
    static let safariVersion = "26.6"

    /// Suffixe ajouté par WebKit à son agent utilisateur.
    static var applicationNameForUserAgent: String {
        "Version/\(safariVersion) Safari/605.1.15"
    }

    static func makeConfiguration(websiteDataStore: WKWebsiteDataStore) -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = websiteDataStore
        configuration.preferences.isElementFullscreenEnabled = true
        configuration.applicationNameForUserAgent = applicationNameForUserAgent
        PageAudioScript.install(in: configuration.userContentController)
        return configuration
    }
}
