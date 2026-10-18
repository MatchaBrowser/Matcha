import Foundation

/// Demande d'une extension en cours d'exécution (`permissions.request()`, tâche 6.3) : des permissions (« tabs »,
/// « cookies »…), des sites (motifs d'adresses ou adresses) ou l'accès à tous les sites. Type pur, décrit pour l'alerte
/// de `ExtensionPermissionAlert` ; l'écran des permissions de la tâche 6.4 pourra s'en servir.
nonisolated struct ExtensionPermissionRequest: Equatable, Sendable {
    /// Nom de l'extension (son nom affiché, sinon son identifiant).
    var extensionName: String
    /// Permissions demandées, triées.
    var permissions: [String] = []
    /// Sites demandés (hôte ou motif), triés, sans doublon.
    var websites: [String] = []
    /// La demande couvre tous les sites (`<all_urls>`, `*://*/*`).
    var allWebsites = false

    /// Demande de permissions.
    init(extensionName: String, permissions: some Sequence<String>) {
        self.extensionName = extensionName
        self.permissions = Set(permissions).sorted()
    }

    /// Demande de sites : motifs (`string` de chaque motif) et l'indication que l'un d'eux couvre tous les sites.
    init(extensionName: String, matchPatterns: some Sequence<String>, includesAllWebsites: Bool) {
        self.extensionName = extensionName
        websites = Set(matchPatterns).sorted()
        allWebsites = includesAllWebsites
    }

    /// Demande d'accès à des adresses : leurs hôtes (sinon l'adresse entière, pour un fichier local).
    init(extensionName: String, urls: some Sequence<URL>) {
        self.extensionName = extensionName
        websites = Set(urls.map { $0.host() ?? $0.absoluteString }).sorted()
    }

    /// Rien à demander : la réponse est vide, sans rien montrer.
    var isEmpty: Bool {
        permissions.isEmpty && websites.isEmpty && !allWebsites
    }
}
