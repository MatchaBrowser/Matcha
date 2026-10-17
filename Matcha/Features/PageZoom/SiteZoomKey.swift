import Foundation

/// Site sous lequel le zoom d'une page est retenu (tâche 5.4) : le domaine enregistrable approché de `SiteDomain`
/// pour une page web (« mail.google.com » et « docs.google.com » partagent « google.com » ; schéma, port et « www. »
/// ne comptent pas), une seule clé pour tous les fichiers locaux, rien pour les autres pages (`about:`, `data:`,
/// `blob:`), qui restent à 100 %.
nonisolated enum SiteZoomKey {
    /// Clé commune aux fichiers locaux : elle ne peut pas être un hôte (`SiteDomain` n'en donne jamais avec « / »).
    static let localFiles = "file://"

    static func key(for url: URL?) -> String? {
        guard let url else {
            return nil
        }
        if url.isFileURL {
            return localFiles
        }
        return SiteDomain.site(of: url)
    }
}
